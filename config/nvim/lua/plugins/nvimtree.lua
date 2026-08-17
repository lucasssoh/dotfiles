return {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        local function my_on_attach(bufnr)
            local api = require("nvim-tree.api")

            local function opts(desc)
                return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
            end

            -- Apply the default keymaps
            api.config.mappings.default_on_attach(bufnr)

            -- Set TAB to open the file or folder (like Enter)
            -- Overrides the default "Preview" mapping
            vim.keymap.set('n', '<Tab>', api.node.open.edit, opts('Open'))
        end

        require("nvim-tree").setup({
            on_attach = my_on_attach,
            filesystem_watchers = { enable = true },
            
            -- =================================================================
            -- REQUIRED CONFIGURATION FOR CCNOTE ISOLATION
            -- =================================================================
            sync_root_with_cwd = true, -- Aligns the tree root with the terminal's folder
            respect_buf_cwd = true,    -- Forces nvim-tree to respect the launch folder
            update_focused_file = {
                enable = true,
                update_root = true,    -- Changes the root if you navigate elsewhere
            },
            -- =================================================================

            renderer = {
                root_folder_label = false,
                -- No diagnostic icon/sign — just underline the file/folder
                -- name text (not its devicon) in the matching Diagnostic*
                -- colour (see coucou's DiagnosticUnderline* groups). Same
                -- convention as the rest of the setup, zero added width.
                highlight_diagnostics = "name",
                icons = {
                    show = {
                        git = true,
                        file = true,
                        folder = true,
                        folder_arrow = true,
                        diagnostics = false,
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
            -- LSP diagnostics propagated up to parent folders, so an
            -- error/warning is visible in the tree without opening every
            -- file. Needs a language server that has already published
            -- diagnostics for that file — see the jdtls warmup autocmd in
            -- lua/lsp/mason.lua.
            diagnostics = {
                enable = true,
                show_on_dirs = true,
                show_on_open_dirs = true,
                severity = {
                    min = vim.diagnostic.severity.HINT,
                    max = vim.diagnostic.severity.ERROR,
                },
            },
        })
    end,
}
