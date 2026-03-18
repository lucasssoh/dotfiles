-- --- OPTIONS DE BASE ---
vim.g.mapleader = " " 
vim.opt.number = true 
vim.opt.relativenumber = true 
vim.opt.termguicolors = true 
vim.opt.mouse = 'a'
vim.opt.cursorline = true
vim.opt.clipboard = "unnamedplus" -- Permet d'utiliser le presse-papier système par défaut

-- Sécurité Git
vim.fn.setenv("SSH_ASKPASS", "")

-- --- LAZY.NVIM ---
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- --- PLUGINS ---
require("lazy").setup({
  { "rktjmp/lush.nvim" },
  { "EdenEast/nightfox.nvim", lazy = false, priority = 1000, config = function() vim.cmd("colorscheme carbonfox") end },

  -- L'explorateur (Nvim-Tree)
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({ view = { width = 30 }, renderer = { highlight_opened_files = "all" }, filters = { dotfiles = false } })
      vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { silent = true })
    end
  },

  -- Barre d'état (Lualine)
  { "nvim-lualine/lualine.nvim", dependencies = { "nvim-tree/nvim-web-devicons" }, config = function() require('lualine').setup({ options = { theme = 'carbonfox', globalstatus = true } }) end },

  -- --- LE PACK LSP & AUTO-COMPLÉTION ---
  {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v3.x',
    dependencies = {
      -- Gestionnaire de serveurs (LSP, Linters, Formatters)
      {'williamboman/mason.nvim'},
      {'williamboman/mason-lspconfig.nvim'},

      -- LSP Support
      {'neovim/nvim-lspconfig'},
      -- Auto-complétion
      {'hrsh7th/nvim-cmp'},
      {'hrsh7th/cmp-nvim-lsp'},
      {'L3MON4D3/LuaSnip'},
    },
    config = function()
      local lsp_zero = require('lsp-zero')
      lsp_zero.extend_lspconfig()

      lsp_zero.on_attach(function(client, bufnr)
        -- Raccourcis clavier quand le LSP est actif
        lsp_zero.default_keymaps({buffer = bufnr})
        local opts = {buffer = bufnr}
        vim.keymap.set('n', 'gd', function() vim.lsp.buf.definition() end, opts) -- Go to definition
        vim.keymap.set('n', 'K', function() vim.lsp.buf.hover() end, opts)       -- Documentation
        vim.keymap.set('n', '<leader>ca', function() vim.lsp.buf.code_action() end, opts) -- Fix rapide (ESLint fix)
      end)

      require('mason').setup({})
      require('mason-lspconfig').setup({
        ensure_installed = {
          -- --- WEB & FRONTEND ---
          'ts_ls',                    -- React / JS / TS (Anciennement tsserver)
          'angularls',                -- Angular
          'html',                     -- HTML
          'cssls',                    -- CSS
          'tailwindcss',              -- Tailwind CSS (Si tu l'utilises, c'est un must)
          'eslint',                   -- Le fameux ESLint pour le JS/TS

          -- --- PHP & SYMFONY (Projets L3) ---
          'intelephense',             -- Le plus rapide pour PHP

          -- --- JAVA (Cours de Programmation) ---
          'jdtls',                    -- Eclipse JDT.LS

          -- --- C / C++ (Système & Algo) ---
          'clangd',                   -- C / C++

          -- --- PYTHON (Jeu des Amazones / IA) ---
          'pyright',                  -- Le standard de Microsoft pour Python

          -- --- AUTRES ---
          'lua_ls',                   -- Pour configurer ton Neovim sans erreurs
          'bashls',                   -- Pour tes scripts d'installation dotfiles
          'yamlls',                   -- Pour tes configs Symfony / Docker
        },
        handlers = {
          lsp_zero.default_setup,
        },
      })
      -- Config de l'auto-complétion (Menu déroulant)
      local cmp = require('cmp')
      cmp.setup({
        mapping = cmp.mapping.preset.insert({
          ['<CR>'] = cmp.mapping.confirm({select = true}), -- Entrée pour valider
          ['<Tab>'] = cmp.mapping.select_next_item(),    -- Tab pour descendre
        })
      })
    end
  }
})
