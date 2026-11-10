-- ============================================================
-- TREE_SHOWN.LUA
-- ============================================================
-- Among the open buffers nvim-tree already colours (renderer
-- highlight_opened_files, NvimTreeOpenedHL), set apart the ones a
-- window is showing right now: NvimTreeShownHL on every file visible
-- in the current tab, NvimTreeFocusedHL on the one being edited.
--
-- "Being edited" is the current window's file, or, while the cursor
-- sits in the tree itself, the file of the last window it came from:
-- jumping into the tree to pick something must not blank out the
-- marker of what you were on.
--
-- Registered as a decorator after "Open" (lua/plugins/nvimtree.lua),
-- so its groups apply over the opened colour. coucou gives them their
-- colours; any other theme gets the italic alone (see M.defaults).

local M = {}

-- Last editor window entered, per tab: the focus to show while the
-- cursor is in the tree.
local last_win = {}

-- Fingerprint of the state the tree was last rendered with, kept by
-- the decorator itself so a render triggered by anything else counts.
local drawn = nil

local function is_editor_win(win)
    if not vim.api.nvim_win_is_valid(win) then
        return false
    end
    if vim.api.nvim_win_get_config(win).relative ~= "" then
        return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree"
end

-- Paths shown in the current tab, and the focused one.
local function state()
    local tab = vim.api.nvim_get_current_tabpage()
    local shown = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if is_editor_win(win) then
            local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
            if name ~= "" then
                shown[name] = true
            end
        end
    end

    local win = vim.api.nvim_get_current_win()
    if not is_editor_win(win) then
        win = last_win[tab]
        -- Nothing recorded yet (nvim-tree, and this module with it, is
        -- loaded when the tree first opens, after those windows were
        -- entered): fall back on Vim's own previous window.
        if not (win and is_editor_win(win)) then
            win = vim.fn.win_getid(vim.fn.winnr("#"))
        end
    end
    local focused = win and is_editor_win(win) and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) or nil
    return shown, focused
end

-- Order-independent fingerprint, to skip redraws that change nothing
-- (entering the tree, moving between two windows on the same file).
local function signature(shown, focused)
    local paths = vim.tbl_keys(shown)
    table.sort(paths)
    return (focused or "") .. "\0" .. table.concat(paths, "\0")
end

M.Decorator = require("nvim-tree.api").Decorator:extend()

-- Built once per tree render: take the window state at that moment.
function M.Decorator:new()
    self.enabled = true
    self.highlight_range = "name"
    self.icon_placement = "none"
    self.shown, self.focused = state()
    drawn = signature(self.shown, self.focused)
end

function M.Decorator:highlight_group(node)
    local path = node.absolute_path
    if not path or node.type ~= "file" then
        return nil
    end
    if path == self.focused then
        return "NvimTreeFocusedHL"
    end
    if self.shown[path] then
        return "NvimTreeShownHL"
    end
end

-- Fallback for themes that do not style the groups: italic only, so
-- the tree still tells shown from hidden. `default` leaves coucou's
-- own definitions alone.
function M.defaults()
    vim.api.nvim_set_hl(0, "NvimTreeShownHL", { italic = true, default = true })
    vim.api.nvim_set_hl(0, "NvimTreeFocusedHL", { italic = true, bold = true, default = true })
end

function M.setup()
    M.defaults()

    local group = vim.api.nvim_create_augroup("NvimTreeShown", { clear = true })
    local pending = false

    local function redraw()
        if pending then
            return
        end
        pending = true
        -- Scheduled: WinClosed fires before the window is gone, and a
        -- split triggers WinEnter and BufWinEnter back to back.
        vim.schedule(function()
            pending = false
            local explorer = require("nvim-tree.core").get_explorer()
            if not explorer or not require("nvim-tree.api").tree.is_visible() then
                return
            end
            if signature(state()) ~= drawn then
                explorer.renderer:draw()
            end
        end)
    end

    -- BufEnter as well as WinEnter: the first window never gets a
    -- WinEnter, and a file opened from the tree lands through BufEnter.
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
        group = group,
        callback = function()
            local win = vim.api.nvim_get_current_win()
            if is_editor_win(win) then
                last_win[vim.api.nvim_get_current_tabpage()] = win
            end
            redraw()
        end,
    })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinClosed", "TabEnter" }, {
        group = group,
        callback = redraw,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = group,
        callback = function()
            for tab in pairs(last_win) do
                if not vim.api.nvim_tabpage_is_valid(tab) then
                    last_win[tab] = nil
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = M.defaults,
    })
end

return M
