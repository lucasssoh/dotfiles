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

        -- Compteur de selection : en mode visuel, affiche le nombre de mots et
        -- de caracteres selectionnes (pratique pour la redaction academique).
        -- Le nombre de lignes s'ajoute en visuel ligne ou bloc. Libelles en
        -- anglais pour rester coherent avec le reste de la statusline.
        -- Reserve au Markdown : inutile dans du code.
        local function in_markdown()
            return vim.bo.filetype == "markdown"
        end

        local function selection_stats()
            local mode = vim.fn.mode(true)
            if not mode:match("^[vV\22]") then
                return ""
            end

            local ok, region = pcall(
                vim.fn.getregion,
                vim.fn.getpos("v"),
                vim.fn.getpos("."),
                { type = mode }
            )
            if not ok then
                return ""
            end

            local chars, words = 0, 0
            for _, line in ipairs(region) do
                chars = chars + vim.fn.strchars(line)
                words = words + #vim.split(line, "%s+", { trimempty = true })
            end

            local function plural(n, word)
                return string.format("%d %s", n, n > 1 and word .. "s" or word)
            end

            if #region > 1 then
                return string.format(
                    "󰏫 %s · %s · %s",
                    plural(#region, "line"),
                    plural(words, "word"),
                    plural(chars, "char")
                )
            end
            return string.format("󰏫 %s · %s", plural(words, "word"), plural(chars, "char"))
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

                    {
                        selection_stats,
                        cond = in_markdown,
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

