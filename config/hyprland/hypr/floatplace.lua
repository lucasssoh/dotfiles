-- ============================================================
-- floatplace.lua — new floating windows in context rows
-- ============================================================
-- Hyprland centres every new floating window, so several opened in a row
-- stack exactly on top of each other. This lays them out in "context
-- rows" instead:
--   * a context is a floating window and the floating windows it spawns
--     afterwards (a panel, a dialog from it, a picker from that dialog),
--     left to right on one row, root first. Detected by focus alone:
--     whichever floating window had focus when a new one opened is its
--     parent. No app-specific knowledge.
--   * unrelated floating windows (focus was on nothing, or on a tiled
--     window) start a row of their own.
--   * each row is centred on its own, the rows are stacked, and the block
--     is centred vertically as a group. A lone window lands exactly where
--     Hyprland's own centring would put it.
--   * a row wider than the screen wraps onto another line of the same
--     context.
-- Placement only happens when a tracked window opens, closes or stops
-- floating: dragging one around in between is never fought.
--
-- Left alone, by size rather than by a list:
--   * windows under SMALL_W x SMALL_H (confirm, error, save-as...) stay
--     where windowrules.lua put them, usually centred.
--   * windows taking LARGE_FRACTION or more of the work area (a windowed
--     game, a big main window) are centred once and never tracked, so no
--     dialog's reflow shoves them around later.
--   * pinned and fullscreen windows are never tracked.
--
-- This used to be float-smart-place.py, a Python daemon on Hyprland's
-- event socket. It woke on every event Hyprland sent (each focus change,
-- each title change, about once a second while working), and each window
-- opened ran `hyprctl clients` every 30 ms until the window showed up,
-- then a `hyprctl eval` per window moved. Here it runs inside Hyprland,
-- on the events it subscribes to, with no process, socket or fork.
-- ============================================================

local SMALL_W, SMALL_H = 450, 350
local LARGE_FRACTION = 0.7
local WIN_MARGIN = 12      -- between windows on one line (px)
local LINE_MARGIN = 10     -- between wrapped lines of one context (px)
local CONTEXT_MARGIN = 30  -- between contexts (px)
-- GTK and Qt dialogs often resize right after mapping: wait this long
-- after an open before reading the size, once, instead of polling.
local SETTLE_MS = 60
-- A closing window can still be listed for a moment.
local CLOSE_SETTLE_MS = 50

local M = {}

local rows = {}            -- list of contexts, each a list of addresses, root first
local last_focused = nil   -- address of the window focused before the current event

local function window(addr)
    return hl.get_window("address:" .. addr)
end

local function work_area(mon)
    local r = mon.reserved
    return mon.x + r.left, mon.y + r.top, mon.x + mon.width - r.right, mon.y + mon.height - r.bottom
end

local function trackable(w)
    return w and w.mapped and w.floating and not w.pinned and w.fullscreen == 0
end

local function move(addr, x, y)
    hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), window = "address:" .. addr }))
end

local function row_of(addr)
    if not addr then return nil end
    for _, row in ipairs(rows) do
        for _, a in ipairs(row) do
            if a == addr then return row end
        end
    end
    return nil
end

-- Recomputes every tracked context from scratch: drops what closed or
-- stopped floating, then lays the rows out per (monitor, workspace).
local function reflow()
    local alive_rows, wins = {}, {}
    for _, row in ipairs(rows) do
        local alive = {}
        for _, a in ipairs(row) do
            local w = window(a)
            if trackable(w) then
                alive[#alive + 1] = a
                wins[a] = w
            end
        end
        if #alive > 0 then alive_rows[#alive_rows + 1] = alive end
    end
    rows = alive_rows
    if #rows == 0 then return end

    -- Grouped by the root's monitor and workspace, in row order.
    local groups, order = {}, {}
    for _, row in ipairs(rows) do
        local w0 = wins[row[1]]
        if w0.monitor and w0.workspace then
            local key = w0.monitor.id .. ":" .. w0.workspace.id
            if not groups[key] then
                groups[key] = { mon = w0.monitor, ws = w0.workspace.id, rows = {} }
                order[#order + 1] = key
            end
            table.insert(groups[key].rows, row)
        end
    end

    for _, key in ipairs(order) do
        local g = groups[key]
        local ax0, ay0, ax1, ay1 = work_area(g.mon)
        local area_w = ax1 - ax0

        local blocks = {}  -- { lines = {...}, h = block height }
        for _, row in ipairs(g.rows) do
            local lines, cur, cur_w = {}, {}, 0
            for _, a in ipairs(row) do
                local w = wins[a]
                if w.monitor.id == g.mon.id and w.workspace.id == g.ws then
                    local add_w = (#cur == 0) and w.size.x or (w.size.x + WIN_MARGIN)
                    if #cur > 0 and cur_w + add_w > area_w then
                        lines[#lines + 1] = cur
                        cur, cur_w, add_w = {}, 0, w.size.x
                    end
                    cur[#cur + 1] = { a = a, w = w.size.x, h = w.size.y }
                    cur_w = cur_w + add_w
                end
            end
            if #cur > 0 then lines[#lines + 1] = cur end
            if #lines > 0 then
                local h = LINE_MARGIN * (#lines - 1)
                for _, line in ipairs(lines) do
                    local lh = 0
                    for _, m in ipairs(line) do lh = math.max(lh, m.h) end
                    line.h = lh
                    h = h + lh
                end
                blocks[#blocks + 1] = { lines = lines, h = h }
            end
        end

        if #blocks > 0 then
            local total = CONTEXT_MARGIN * (#blocks - 1)
            for _, b in ipairs(blocks) do total = total + b.h end
            local y = math.max((ay0 + ay1) / 2 - total / 2, ay0)
            for _, b in ipairs(blocks) do
                for _, line in ipairs(b.lines) do
                    local lw = WIN_MARGIN * (#line - 1)
                    for _, m in ipairs(line) do lw = lw + m.w end
                    local x = math.max((ax0 + ax1) / 2 - lw / 2, ax0)
                    for _, m in ipairs(line) do
                        move(m.a, x, y + (line.h - m.h) / 2)
                        x = x + m.w + WIN_MARGIN
                    end
                    y = y + line.h + LINE_MARGIN
                end
                y = y + CONTEXT_MARGIN
            end
        end
    end
end

local function place(addr, parent)
    local w = window(addr)
    if not trackable(w) then return end
    if w.size.x < SMALL_W and w.size.y < SMALL_H then return end
    if not w.monitor or not w.workspace or w.workspace.id < 0 then return end

    local ax0, ay0, ax1, ay1 = work_area(w.monitor)
    if w.size.x >= LARGE_FRACTION * (ax1 - ax0) or w.size.y >= LARGE_FRACTION * (ay1 - ay0) then
        move(addr, math.max((ax0 + ax1) / 2 - w.size.x / 2, ax0), math.max((ay0 + ay1) / 2 - w.size.y / 2, ay0))
        return
    end

    if row_of(addr) then return end
    local row = row_of(parent)
    if row then
        row[#row + 1] = addr
    else
        rows[#rows + 1] = { addr }
    end
    reflow()
end

-- Held until they fire, so the collector cannot take a timer nothing in
-- Lua refers to any more.
local pending = {}
local function later(ms, fn)
    local t
    t = hl.timer(function()
        pending[t] = nil
        fn()
    end, { timeout = ms, type = "oneshot" })
    pending[t] = true
end

hl.on("window.open", function(w)
    if not w then return end
    -- The parent is read now: by the time the timer fires, the new window
    -- has taken focus itself.
    local addr, parent = w.address, last_focused
    later(SETTLE_MS, function() place(addr, parent) end)
end)

hl.on("window.close", function()
    if #rows == 0 then return end
    later(CLOSE_SETTLE_MS, reflow)
end)

hl.on("window.active", function(w)
    last_focused = w and w.address or nil
end)

-- Hyprland's Lua API has no event for a window changing floating mode, so
-- the float bind calls this after toggling: tiled -> floating joins a row,
-- floating -> tiled leaves its row.
function M.float_toggled()
    local w = hl.get_active_window()
    if not w then return end
    if w.floating then
        -- Its own focus is not a parent: a toggled window starts a context.
        place(w.address, nil)
    elseif #rows > 0 then
        reflow()
    end
end

do
    local w = hl.get_active_window()
    last_focused = w and w.address or nil
end

return M
