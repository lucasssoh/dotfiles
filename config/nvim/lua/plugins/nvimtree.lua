return {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        local function my_on_attach(bufnr)
            local api = require("nvim-tree.api")

            local function opts(desc)
                return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
            end

            -- Appliquer les raccourcis par défaut
            api.config.mappings.default_on_attach(bufnr)

            -- Configurer TAB pour ouvrir le fichier ou dossier (comme Entrée)
            -- On écrase le mapping "Preview" par défaut
            vim.keymap.set('n', '<Tab>', api.node.open.edit, opts('Open'))
        end

        require("nvim-tree").setup({
            on_attach = my_on_attach,
            filesystem_watchers = { enable = true },
            renderer = {
                icons = {
                    show = {
                        git = true,
                        file = true,
                        folder = true,
                        folder_arrow = true,
                    },
                    glyphs = {
                        git = {
                            unstaged = "✗",
                            staged = "✓",
                            unmerged = "",
                            renamed = "➜",
                            untracked = "★",
                            deleted = "",
                            ignored = "◌",
                        },
                    },
                },
            },
            git = {
                enable = true,
                ignore = false,
                show_on_dirs = true,
            },
        })
    end,
}
