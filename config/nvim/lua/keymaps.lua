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

-- Navigation entre les onglets (buffers)
key.set("n", "<Tab>", ":bnext<CR>", { silent = true, desc = "Next buffer" })
key.set("n", "<S-Tab>", ":bprevious<CR>", { silent = true, desc = "Previous buffer" })

-- Fermer l'onglet actuel
key.set("n", "<leader>x", ":bdelete<CR>", { silent = true, desc = "Close buffer" })

-- Naviguer par position (Optionnel : Alt + numéro
key.set("n", "<A-1>", "<Cmd>BufferLineGoToBuffer 1<CR>", { silent = true })
key.set("n", "<A-2>", "<Cmd>BufferLineGoToBuffer 2<CR>", { silent = true })
key.set("n", "<A-3>", "<Cmd>BufferLineGoToBuffer 3<CR>", { silent = true })

-- LSP diagnostic
key.set("n", "gz", vim.diagnostic.open_float, { desc = "Diagnostics float" })

key.set("n", "<leader>q", function()
    -- ferme toutes les fenêtres flottantes (LSP, plugins, menus)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= "" then
            vim.api.nvim_win_close(win, false)
        end
    end
end, { desc = "Close floating windows" })

key.set("n", "<leader>Q", function()
    local bufname = vim.api.nvim_buf_get_name(0)

    if bufname == "" then
        vim.cmd("q")
        return
    end

    -- fallback normal buffer close
    vim.cmd("bd")
end, { desc = "Smart quit buffer" })

-- ============================================================
-- SOURIS : Bloquer le glissé en mode Normal pour éviter le mode Visuel
-- ============================================================
key.set("n", "<LeftDrag>", "<Nop>", { silent = true })
key.set("n", "<2-LeftDrag>", "<Nop>", { silent = true })
key.set("n", "<3-LeftDrag>", "<Nop>", { silent = true })
key.set("n", "<4-LeftDrag>", "<Nop>", { silent = true })

