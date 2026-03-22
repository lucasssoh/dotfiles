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
vim.opt.clipboard = "unnamedplus"  -- utiliser le presse-papier système
vim.opt.timeoutlen = 50            -- détecter combos rapidement

-- Sécurité Git
vim.fn.setenv("SSH_ASKPASS", "")

-- =======================
-- MAPPINGS CLAVIER
-- =======================
vim.keymap.set("i", "jk", "<Esc>", { noremap = true, silent = true })

-- Commande pour recharger la config à chaud
vim.api.nvim_create_user_command("ReloadConfig", function()
    dofile(vim.fn.stdpath("config") .. "/init.lua")
end, {})

-- =======================
-- PLUGINS (LAZY.NVIM)
-- =======================
-- Installation lazy.nvim si nécessaire
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Setup plugins
require("lazy").setup({
    -- Theme & couleurs
    { "rktjmp/lush.nvim" },
    {
        "EdenEast/nightfox.nvim",
        lazy = false,
        priority = 1000,
        config = function() vim.cmd("colorscheme carbonfox") end,
    },

    -- Explorateur de fichiers
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("nvim-tree").setup({
                view = { width = 30 },
                renderer = { highlight_opened_files = "all" },
                filters = { dotfiles = false },
            })
            vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true })
        end,
    },

    -- Barre d'état
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("lualine").setup({ options = { theme = "carbonfox", globalstatus = true } })
        end,
    },

    -- LSP & auto-complétion
    {
        "VonHeikemen/lsp-zero.nvim",
        branch = "v3.x",
        dependencies = {
            { "williamboman/mason.nvim" },
            { "williamboman/mason-lspconfig.nvim" },
            { "neovim/nvim-lspconfig" },
            { "hrsh7th/nvim-cmp" },
            { "hrsh7th/cmp-nvim-lsp" },
            { "L3MON4D3/LuaSnip" },
        },
        config = function()
            local lsp_zero = require("lsp-zero")
            lsp_zero.extend_lspconfig()

            lsp_zero.on_attach(function(client, bufnr)
                lsp_zero.default_keymaps({ buffer = bufnr })
                local opts = { buffer = bufnr }
                vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
                vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
                vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
            end)

            -- Installer & configurer LSP
            require("mason").setup({})
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "ts_ls", "angularls", "html", "cssls", "tailwindcss", "eslint",
                    "intelephense", "jdtls", "clangd", "pyright",
                    "lua_ls", "bashls", "yamlls",
                },
                handlers = {
                    lsp_zero.default_setup,
                },
            })

            -- Auto-complétion
            local cmp = require("cmp")
            cmp.setup({
                mapping = cmp.mapping.preset.insert({
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                    ["<Tab>"] = cmp.mapping.select_next_item(),
                }),
            })
        end,
    },
})
