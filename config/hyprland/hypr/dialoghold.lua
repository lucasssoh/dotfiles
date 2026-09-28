-- ============================================================
-- dialoghold.lua — a dialog keeps focus until you act on it
-- ============================================================
-- The two failure modes this sits between:
--   * stay_focused as a static rule pins EVERY input to the dialog for
--     as long as it is open: with Firefox's "Enregistrer sous" up, the
--     screenshot bind's satty could not take focus and the Quickshell
--     bar stopped taking clicks.
--   * no rule at all lets a freshly opened dialog lose focus before you
--     have even looked at it.
-- So the hold is temporary: a dialog opens held (stay_focused), and the
-- hold is released by the first sign you are dealing with it --
--   * a key pressed while it is focused (typing a name, Tab, Enter, or a
--     bind such as Super+S for satty), or
--   * the pointer MOVING inside it -- you are about to click. A cursor
--     that merely happens to sit where the dialog opened does not count.
-- After release, the dialog rules' no_follow_mouse still keeps focus from
-- drifting off; only a deliberate click elsewhere takes it.
--
-- Which windows: those the rules in windowrules.lua tag "dialog". The
-- hold itself is the tag "dlg-hold", added here on open and removed on
-- release; the rule below turns it into stay_focused. Checked with
-- `hyprctl getprop address:... stay_focused`: true while tagged, false
-- once the tag is gone. (A `focus` dispatch bypasses stay_focused, so it
-- cannot be used to test this.)
--
-- Why a timer: Hyprland's Lua API has a keyboard event but no pointer
-- one, so pointer movement is sampled -- every 100 ms, and ONLY while at
-- least one dialog is held; the timer is disabled the rest of the time.
-- ============================================================

hl.window_rule({ match = { tag = "dlg-hold" }, stay_focused = true })

local TICK_MS = 100
-- Ticks before a key counts: the combo that OPENED the dialog (Ctrl+S in
-- Firefox) is often released after the dialog maps, and that release must
-- not count as acting on it.
local GRACE_TICKS = 3
-- Pixels the pointer must travel inside the dialog to count as movement.
local MOVE_PX = 6

local held = {} -- address -> { age = ticks, x0, y0 = cursor at open }
local timer

local function count()
    local n = 0
    for _ in pairs(held) do n = n + 1 end
    return n
end

local function release(addr)
    if not held[addr] then return end
    held[addr] = nil
    if hl.get_window("address:" .. addr) then
        hl.dispatch(hl.dsp.window.tag({ tag = "-dlg-hold", window = "address:" .. addr }))
    end
    if timer and count() == 0 then timer:set_enabled(false) end
end

local function has_tag(w, name)
    local t = w.tags
    if type(t) == "table" then t = table.concat(t, ",") end
    return (t or ""):find(name, 1, true) ~= nil
end

local function tick()
    local c = hl.get_cursor_pos()
    for addr, h in pairs(held) do
        h.age = h.age + 1
        local w = hl.get_window("address:" .. addr)
        if not w then
            held[addr] = nil
        elseif c and h.age >= GRACE_TICKS then
            local inside = c.x >= w.at.x and c.x < w.at.x + w.size.x
                       and c.y >= w.at.y and c.y < w.at.y + w.size.y
            local moved = math.abs(c.x - h.x0) + math.abs(c.y - h.y0) >= MOVE_PX
            if inside and moved then
                release(addr)
            elseif not inside then
                -- Rebase while outside, so entering the dialog is itself
                -- the movement that counts.
                h.x0, h.y0 = -1e9, -1e9
            end
        end
    end
    if count() == 0 then timer:set_enabled(false) end
end

hl.on("window.open", function(w)
    if not has_tag(w, "dialog") then return end
    local c = hl.get_cursor_pos() or { x = 0, y = 0 }
    held[w.address] = { age = 0, x0 = c.x, y0 = c.y }
    hl.dispatch(hl.dsp.window.tag({ tag = "+dlg-hold", window = "address:" .. w.address }))
    if not timer then
        timer = hl.timer(tick, { timeout = TICK_MS, type = "repeat" })
    end
    timer:set_enabled(true)
end)

hl.on("input.keyboard.key", function()
    local a = hl.get_active_window()
    if a and held[a.address] and held[a.address].age >= GRACE_TICKS then
        release(a.address)
    end
end)

hl.on("window.close", function(w)
    if w and held[w.address] then held[w.address] = nil end
end)
