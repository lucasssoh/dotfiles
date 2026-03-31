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
	    "savq/melange-nvim",
	    config = function()
		vim.cmd.colorscheme("melange")
		
		-- 1. On force le fond en noir pur (#000000)
		vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })
		vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#000000" })
		
		-- 2. On ajuste les détails pour qu'ils restent visibles sur le noir
		vim.api.nvim_set_hl(0, "LineNr", { fg = "#5e5249", bg = "NONE" }) -- Numéros discrets
		vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#35271e" })        -- Séparateurs visibles
		vim.api.nvim_set_hl(0, "CursorLine", { bg = "#1a1a1a" })          -- Ligne sous le curseur subtile
		
		-- 3. Si tu veux que SmoothCursor soit raccord avec le bois :
		vim.api.nvim_set_hl(0, "SmoothCursor", { fg = "#d79921" })
	    end
	},
    require("colorpicker"),
    require("start"),
    require("cursor"),
    require("commenter"),
    -- Fuzzy Finder (Telescope)
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.5",
        dependencies = { 
            "nvim-lua/plenary.nvim",
            { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' }
        },
        config = function()
            local telescope = require("telescope")
            telescope.setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<C-M-j>"] = "move_selection_next",
                            ["<C-M-k>"] = "move_selection_previous",
                        },
                    },
                },
            })
            -- On charge l'extension de recherche rapide
            telescope.load_extension('fzf')

            -- Mappings pratiques
            local builtin = require('telescope.builtin')
            vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
            vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
            vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
        end,
    },
	-- Project Management (Fork moderne et maintenu)
	    {
		"coffebar/neovim-project",
		opts = {
		    projects = { -- Tes répertoires de projets habituels
			"~/code/*",
		    },
		    -- Utilise les mêmes patterns que tu avais
		    detection_methods = { "lsp", "pattern" },
		    patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" },
		    -- Optionnel : sauvegarde auto de la session (très pratique)
		    last_session_on_startup = false, 
		    dashboard_mode = true,
		},
		init = function()
		    -- Indispensable pour que les sessions fonctionnent
		    vim.opt.sessionoptions:append("globals")
		end,
		dependencies = {
		    { "nvim-lua/plenary.nvim" },
		    { "nvim-telescope/telescope.nvim" },
		    { "Shatur/neovim-session-manager" },
		},
	    },
    -- File Explorer
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("nvim-tree").setup({ 
                view = { 
                    width = 30 
                },
                filters = {
                    dotfiles = false, -- Affiche les fichiers cachés (ex: .env)
                    custom = {},      -- Vide les filtres personnalisés
                },
                git = {
                    ignore = false,   -- TRÈS IMPORTANT : Affiche les fichiers même s'ils sont dans .gitignore
                },
            })
            vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true })
        end,
    },

	-- Statusline
	{
	    "nvim-lualine/lualine.nvim",
	    dependencies = { "nvim-tree/nvim-web-devicons" }, -- Optionnel mais recommandé
	    config = function()
		require("lualine").setup({ 
		    options = { 
			theme = "melange", -- Utilise les couleurs de ton thème actuel
			globalstatus = true, 
		    } 
		})
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
	    -- AJOUTE CECI POUR LA COMPLÉTION
	    local cmp = require('cmp')
	    cmp.setup({
		mapping = cmp.mapping.preset.insert({
		    ['<C-Space>'] = cmp.mapping.complete(), -- Forcer la complétion
		    ['<CR>'] = cmp.mapping.confirm({select = true}), -- Entrée pour valider
		    ['<Tab>'] = cmp.mapping.select_next_item(), -- Tab pour descendre
		    ['<S-Tab>'] = cmp.mapping.select_prev_item(), -- Shift+Tab pour monter
		})
	    })
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
    print("Config reloaded!")
end, {})
