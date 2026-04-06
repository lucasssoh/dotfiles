-- ============================================================
-- INIT.LUA - CONFIG NEOVIM
-- ============================================================

-- =======================
-- OPTIONS DE BASE
-- =======================
vim.g.mapleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.paste = false
vim.opt.cursorline = true

vim.opt.clipboard = "unnamedplus"

vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 0
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- =======================
-- KEYMAPS
-- =======================
require("keymaps")

-- =======================
-- PLUGINS (LAZY.NVIM)
-- =======================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    spec = {
        require("cursor"),
        require("start"),
        require("lsp.mason"),
        { import = "plugins" },
        require("theme"),
   },
})

-- =======================
-- RELOAD
-- =======================
vim.api.nvim_create_user_command("ReloadConfig", function()
    dofile(vim.fn.stdpath("config") .. "/init.lua")
    print("Config reloaded!")
end, {})
