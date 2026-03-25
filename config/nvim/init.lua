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
vim.opt.cursorline = true
vim.opt.clipboard = "unnamedplus"
vim.opt.timeoutlen = 50 

-- =======================
-- MAPPINGS CLAVIER
-- =======================
local key = vim.keymap
key.set("i", "jk", "<Esc>", { silent = true })
key.set("i", "kj", "<Esc>", { silent = true })

-- SOLUTIONS POUR ALT+V / ALT+S DANS TMUX
-- On dit à Neovim de ne rien faire pour laisser Tmux intercepter
key.set({'n', 'i', 'v'}, '<A-v>', '<Nop>', { silent = true })
key.set({'n', 'i', 'v'}, '<A-s>', '<Nop>', { silent = true })

-- =======================
-- PLUGINS (LAZY.NVIM)
-- =======================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- Thème
    {
        "EdenEast/nightfox.nvim",
        lazy = false,
        priority = 1000,
        config = function() vim.cmd("colorscheme carbonfox") end,
    },

    -- File Explorer
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("nvim-tree").setup({ view = { width = 30 } })
            key.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true })
        end,
    },

    -- Statusline
    {
        "nvim-lualine/lualine.nvim",
        config = function()
            require("lualine").setup({ options = { theme = "carbonfox", globalstatus = true } })
        end,
    },

    -- LSP & Completion
    {
        "VonHeikemen/lsp-zero.nvim",
        branch = "v3.x",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "neovim/nvim-lspconfig",
            "hrsh7th/nvim-cmp",
            "hrsh7th/cmp-nvim-lsp",
            "L3MON4D3/LuaSnip",
        },
        config = function()
            local lsp_zero = require("lsp-zero")
            lsp_zero.on_attach(function(client, bufnr)
                lsp_zero.default_keymaps({ buffer = bufnr })
            end)
            require("mason").setup({})
            require("mason-lspconfig").setup({
                ensure_installed = { "ts_ls", "pyright", "lua_ls", "clangd" },
                handlers = { lsp_zero.default_setup },
            })
        end,
    },

    -- TMUX Navigation
    {
        "christoomey/vim-tmux-navigator",
        lazy = false,
        keys = {
            { "<A-h>", "<cmd>TmuxNavigateLeft<cr>" },
            { "<A-j>", "<cmd>TmuxNavigateDown<cr>" },
            { "<A-k>", "<cmd>TmuxNavigateUp<cr>" },
            { "<A-l>", "<cmd>TmuxNavigateRight<cr>" },
        },
    },
})

-- Commande de reload
vim.api.nvim_create_user_command("ReloadConfig", function()
    dofile(vim.fn.stdpath("config") .. "/init.lua")
    print("Config rechargée !")
end, {})
