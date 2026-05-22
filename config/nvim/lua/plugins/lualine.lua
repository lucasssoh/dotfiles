return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },

    config = function()
        -- Nom du dossier courant
        local function get_current_folder()
            local cwd = vim.fn.getcwd()
            return "  " .. vim.fn.fnamemodify(cwd, ":t")
        end

        require("lualine").setup({
            options = {
                theme = "auto",
                globalstatus = true,

                -- Séparateurs internes arrondis
                component_separators = {
                    left = "",
                    right = "",
                },

                -- Bordures uniquement vers l’intérieur
                section_separators = {
                    left = "",
                    right = "",
                },
            },

            sections = {
                lualine_a = {
                    {
                        "mode",
                        separator = { right = "" },
                    }
                },

                lualine_b = {
                    {
                        get_current_folder,
                        color = "WarningMsg",
                    },

                    {
                        "branch",
                        separator = { right = "" },
                    },

                    "diff",
                    "diagnostics",
                },

                lualine_c = {},

                lualine_x = {
                    "encoding",
                    "fileformat",
                    "filetype",
                },

                lualine_y = {
                    {
                        "progress",
                        separator = { left = "" },
                    }
                },

                lualine_z = {
                    {
                        "location",
                        separator = { left = "" },
                    }
                },
            },
        })
    end,
}

