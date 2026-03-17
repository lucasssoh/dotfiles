-- --- OPTIONS DE BASE ---
vim.g.mapleader = " " 
vim.opt.number = true 
vim.opt.relativenumber = true 
vim.opt.termguicolors = true 
vim.opt.mouse = 'a'
vim.opt.cursorline = true -- Souligne la ligne actuelle pour le look "IDE"

-- --- SÉCURITÉ GIT (Évite l'erreur ksshaskpass) ---
vim.fn.setenv("SSH_ASKPASS", "")

-- --- INSTALLATION DU GESTIONNAIRE DE PLUGINS (LAZY) ---
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- --- CONFIGURATION DES PLUGINS ---
require("lazy").setup({
  -- 1. Le Thème Hyper-style (Version stable et accessible)
  { 
    "rktjmp/lush.nvim" -- Moteur de rendu de couleurs nécessaire pour les thèmes modernes
  },
  { 
    "EdenEast/nightfox.nvim", -- La variante 'carbonfox' est le clone parfait du style Hyper
    lazy = false, 
    priority = 1000, 
    config = function() 
      vim.cmd("colorscheme carbonfox") 
    end 
  },
  
  -- 2. L'explorateur de fichiers (Nvim-Tree)
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = { 
          width = 30, 
          side = "left" 
        },
        renderer = { 
          icons = { show = { file = true, folder = true } },
          highlight_opened_files = "all",
          add_trailing = true, -- Ajoute un slash aux dossiers
        },
        filters = { dotfiles = false } -- Affiche les fichiers cachés (important pour tes dotfiles)
      })
      -- Raccourci Espace + e
      vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { silent = true })
    end
  },

  -- 3. La barre d'état (Lualine) stylisée
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require('lualine').setup({
        options = { 
          theme = 'carbonfox',
          section_separators = { left = '', right = '' },
          component_separators = { left = '', right = '' },
          globalstatus = true, -- Une seule barre en bas, même avec plusieurs splits
        }
      })
    end
  }
})
