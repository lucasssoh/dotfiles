return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },

    config = function()
        -- Jauge ccslide : "󰐩 4/12 · 18/44" = slide courante / total, puis
        -- hauteur de la slide / hauteur disponible dans le terminal. Le
        -- second nombre suit la taille reelle de la fenetre, resize compris.
        local function ccslide_gauge()
            local ok, ccslide = pcall(require, "ccslide")
            return ok and ccslide.status() or ""
        end

        local function ccslide_color()
            local ok, ccslide = pcall(require, "ccslide")
            if ok and ccslide.over_budget() then
                return "DiagnosticError"
            end
            return "Comment"
        end

        -- Current folder name
        local function get_current_folder()
            local cwd = vim.fn.getcwd()
            return "  " .. vim.fn.fnamemodify(cwd, ":t")
        end

        require("lualine").setup({
            options = {
                theme = "auto",
                globalstatus = true,

                -- Rounded internal separators
                component_separators = {
                    left = "",
                    right = "",
                },

                -- Borders only facing inward
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

                lualine_c = {
                    {
                        ccslide_gauge,
                        color = ccslide_color,
                    },
                },

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

