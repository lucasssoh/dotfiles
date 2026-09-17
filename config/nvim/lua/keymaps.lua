-- ============================================================
-- KEYMAPS.LUA
-- ============================================================
local key = vim.keymap
local buffers = require("buffers")

vim.g.mapleader = " "

-- Insert mode → Normal
key.set("i", "jk", "<Esc>", { silent = true })
key.set("i", "kj", "<Esc>", { silent = true })

-- Window navigation
key.set("n", "<leader>h", "<C-w>h", { desc = "Go to left window" })
key.set("n", "<leader>l", "<C-w>l", { desc = "Go to right window" })
key.set("n", "<leader>j", "<C-w>j", { desc = "Go to bottom window" })
key.set("n", "<leader>k", "<C-w>k", { desc = "Go to top window" })

-- NvimTree
key.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true, desc = "Toggle file explorer" })

-- Navigate between tabs (buffers)
-- BufferLineCycle* plutot que :bnext/:bprevious : Tab suit alors
-- l'ordre affiche dans la bufferline (y compris apres un
-- BufferLineMove*), la ou :bnext suit l'ordre des numeros de buffer.
key.set("n", "<Tab>", "<Cmd>BufferLineCycleNext<CR>", { silent = true, desc = "Next buffer" })
key.set("n", "<S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { silent = true, desc = "Previous buffer" })

-- Close current tab -- voir lua/buffers.lua : ferme le buffer (donc
-- l'onglet) sans emporter la fenetre avec lui, comme le X de bufferline.
key.set("n", "<leader>x", function() buffers.close() end, { silent = true, desc = "Close buffer" })
key.set("n", "<leader>X", function() buffers.close(nil, true) end, { silent = true, desc = "Close buffer (discard changes)" })

-- Navigate by position (Optional: Alt + number
key.set("n", "<A-1>", "<Cmd>BufferLineGoToBuffer 1<CR>", { silent = true })
key.set("n", "<A-2>", "<Cmd>BufferLineGoToBuffer 2<CR>", { silent = true })
key.set("n", "<A-3>", "<Cmd>BufferLineGoToBuffer 3<CR>", { silent = true })

-- LSP diagnostic
key.set("n", "gz", vim.diagnostic.open_float, { desc = "Diagnostics float" })

key.set("n", "<leader>q", function()
    -- close all floating windows (LSP, plugins, menus)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= "" then
            vim.api.nvim_win_close(win, false)
        end
    end
end, { desc = "Close floating windows" })

-- Alias historique de <leader>x, meme comportement.
key.set("n", "<leader>Q", function() buffers.close() end, { desc = "Smart quit buffer" })

-- ============================================================
-- MOUSE: Block drag in Normal mode to avoid entering Visual mode
-- ============================================================
key.set("n", "<LeftDrag>", "<Nop>", { silent = true })
key.set("n", "<2-LeftDrag>", "<Nop>", { silent = true })
key.set("n", "<3-LeftDrag>", "<Nop>", { silent = true })
key.set("n", "<4-LeftDrag>", "<Nop>", { silent = true })

