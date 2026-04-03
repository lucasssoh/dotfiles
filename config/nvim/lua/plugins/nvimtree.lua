return {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        require("nvim-tree").setup({
            -- Surveillance système pour le rafraîchissement auto
            filesystem_watchers = { enable = true },
            
            renderer = {
                icons = {
                    show = {
                        git = true, -- Active les icônes Git
                        file = true,
                        folder = true,
                        folder_arrow = true,
                    },
                    glyphs = {
                        git = {
                            unstaged = "✗",
                            staged = "✓",
                            unmerged = "",
                            renamed = "➜",
                            untracked = "★",
                            deleted = "",
                            ignored = "◌",
                        },
                    },
                },
            },
            git = {
                enable = true,
                ignore = false, -- Pour voir aussi les icônes sur les fichiers ignorés
                show_on_dirs = true, -- Très pratique : l'icône remonte sur les dossiers parents
            },
        })

        -- Le petit hack pour forcer Git à se rafraîchir quand tu reviens sur Neovim
        vim.api.nvim_create_autocmd("FocusGained", {
            callback = function()
                require("nvim-tree.api").git.reload()
            end,
        })
    end,
}
