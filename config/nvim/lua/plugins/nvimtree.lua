return {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        require("nvim-tree").setup({
            view = { width = 30 },
            filters = { dotfiles = false, custom = {} },
            git = { ignore = false },
        })

        -- Refresh automatique quand on revient dans nvim
        vim.api.nvim_create_autocmd("FocusGained", {
            callback = function()
                require("nvim-tree.api").tree.reload()
            end,
        })
    end,
}
