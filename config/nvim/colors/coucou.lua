-- ============================================================
-- COLORS/COUCOU.LUA
-- Colorscheme entry point (required so :colorscheme coucou and
-- lua/theme.lua's `pcall(vim.cmd.colorscheme, name)` succeed).
-- ============================================================
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
end

-- background is NOT forced here: lua/theme.lua sets vim.o.background to
-- "light"/"dark" before calling :colorscheme, based on --light / saved
-- state, and lua/coucou/init.lua picks palette.lua vs palette_light.lua
-- from it. Neovim's own default ("dark") covers a bare :colorscheme coucou.
vim.g.colors_name = "coucou"

require("coucou").load()
