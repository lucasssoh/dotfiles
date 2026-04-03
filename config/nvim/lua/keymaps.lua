-- ============================================================
-- KEYMAPS.LUA
-- ============================================================
local key = vim.keymap

vim.g.mapleader = " "

-- Mode insertion → Normal
key.set("i", "jk", "<Esc>", { silent = true })
key.set("i", "kj", "<Esc>", { silent = true })

-- Navigation fenêtres
key.set("n", "<leader>h", "<C-w>h", { desc = "Go to left window" })
key.set("n", "<leader>l", "<C-w>l", { desc = "Go to right window" })
key.set("n", "<leader>j", "<C-w>j", { desc = "Go to bottom window" })
key.set("n", "<leader>k", "<C-w>k", { desc = "Go to top window" })

-- Tmux (laisser passer Alt+V / Alt+S)
key.set({ "n", "i", "v" }, "<A-v>", "<Nop>", { silent = true })
key.set({ "n", "i", "v" }, "<A-s>", "<Nop>", { silent = true })

-- NvimTree
key.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true, desc = "Toggle file explorer" })
