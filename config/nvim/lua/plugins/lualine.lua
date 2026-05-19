return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        -- Fonction pour récupérer uniquement le nom du dossier courant (ex: "cm-deeplearning")
        local function get_current_folder()
            local cwd = vim.fn.getcwd()
            return "  " .. vim.fn.fnamemodify(cwd, ":t")
        end

        require("lualine").setup({
            options = {
                theme = "auto",
                globalstatus = true,
                component_separators = { left = '', right = ''},
                section_separators = { left = '', right = ''},
            },
            sections = {
                -- Le Mode (NORMAL, INSERT, etc.) reste tout à gauche
                lualine_a = { "mode" },
                
                -- =================================================================
                -- BLOC GAUCHE : DOSSIER ACTUEL PUIS BRANCHES & INFOS GIT
                -- =================================================================
                lualine_b = {
                    {
                        get_current_folder,
                        color = "WarningMsg", -- S'adapte dynamiquement à ton thème
                    },
                    "branch",
                    "diff",
                    "diagnostics"
                },
                
                -- Centre vide pour un visuel épuré
                lualine_c = {},
                -- =================================================================

                lualine_x = { "encoding", "fileformat", "filetype" },
                lualine_y = { "progress" },
                lualine_z = { "location" },
            },
        })
    end,
}
