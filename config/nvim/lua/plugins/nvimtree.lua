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

            -- Pin the cursor's column to the start of the node's icon
            -- (right after the indent guides, the furthest-forward spot
            -- on the line) instead of wherever it was left horizontally.
            -- Without this, moving up/down with j/k keeps Vim's "sticky
            -- column" from a deeper/shallower line, so the cursor lands
            -- mid-icon or mid-name depending on indent depth.
            -- Found via extmarks rather than string search: every
            -- rendered line has an indent-marker extmark (skipped) then
            -- an icon extmark (folder/file/devicon group) — one column
            -- before its start is exactly "just in front of the icon",
            -- not on top of it.
            vim.api.nvim_create_autocmd("CursorMoved", {
                buffer = bufnr,
                callback = function()
                    local cur = vim.api.nvim_win_get_cursor(0)
                    local row = cur[1] - 1
                    local marks = vim.api.nvim_buf_get_extmarks(bufnr, -1, { row, 0 }, { row, -1 }, { details = true })

                    local icon_col
                    for _, m in ipairs(marks) do
                        local col, details = m[3], m[4]
                        if details.hl_group and details.hl_group ~= "NvimTreeIndentMarker" then
                            if not icon_col or col < icon_col then
                                icon_col = col
                            end
                        end
                    end
                    local target_col = icon_col and math.max(icon_col - 1, 0)

                    if target_col and cur[2] ~= target_col then
                        vim.api.nvim_win_set_cursor(0, { cur[1], target_col })
                    end
                end,
            })
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

            -- Dynamic width instead of a fixed one: the window grows to fit
            -- the longest currently-visible line (capped at max) instead of
            -- truncating deeply-nested names off the right edge. This is
            -- what removes the "scroll right to read the filename" problem
            -- entirely — no manual centering/scrolling needed.
            view = {
                width = {
                    min = 30,
                    max = 60,
                    padding = 1,
                },
            },

            renderer = {
                root_folder_label = false,
                -- ├ / └ guide lines between parent and child entries
                -- (like `tree`), coloured NvimTreeIndentMarker (coucou:
                -- p.muted) so they stay discreet.
                -- indent_width stays at the default (2): nvim-tree can
                -- only repeat dashes after the *last*-child corner ("└"),
                -- never after the branch glyph ("├") for non-last
                -- siblings — that filler is hardcoded to blank spaces.
                -- Widening indent_width to fit "└──" just stretches
                -- every "├" row with unused blank space instead (see the
                -- previous attempt). Kept at 2: no dashes anywhere, but
                -- ├/└ still shows branch-vs-last at zero wasted width.
                indent_markers = {
                    enable = true,
                    icons = {
                        corner = "└",
                        edge = "│",
                        item = "├",
                        bottom = "─",
                        none = " ",
                    },
                },
                -- No diagnostic icon/sign — just underline the file/folder
                -- name text (not its devicon) in the matching Diagnostic*
                -- colour (see coucou's DiagnosticUnderline* groups). Same
                -- convention as the rest of the setup, zero added width.
                highlight_diagnostics = "name",
                -- Git status: colour the name text only (not the icon,
                -- not the row background) in the matching NvimTreeGit*
                -- colour — text colour only, no highlight block.
                highlight_git = "name",
                icons = {
                    show = {
                        git = true,
                        file = true,
                        folder = true,
                        -- open/closed state is already carried by the
                        -- folder icon itself (and now the guide lines) —
                        -- the arrow was redundant width.
                        folder_arrow = false,
                        diagnostics = false,
                    },
                    -- Git status is a different "context" than the file
                    -- type icon, so it lives in the sign column (gutter)
                    -- instead of being inlined next to the name — that's
                    -- what naturally groups every status glyph in its own
                    -- column, separated from "icon name" by the gutter's
                    -- own gap, with zero manual spacing logic needed.
                    git_placement = "signcolumn",
                    -- One space between the file/folder icon and the name,
                    -- but nothing else is inline any more to space out.
                    padding = {
                        icon = " ",
                        folder_arrow = "",
                    },
                    -- Plain ASCII signs instead of nerd-font icon shapes —
                    -- the status now reads from the whole row's tinted
                    -- background (see the TreeRendered hook below), so
                    -- the glyph itself only needs to be a compact,
                    -- legible mark, not a distinct pictogram per status.
                    glyphs = {
                        git = {
                            staged = "+",
                            unstaged = "!",
                            untracked = "?",
                            deleted = "-",
                            renamed = "~",
                            unmerged = "=",
                            ignored = "·",
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

        -- Root-level (depth 0) entries never get an indent-marker column
        -- at all — nvim-tree's padding code skips it entirely there, so
        -- their icon sits flush at column 0 with nothing before it for
        -- the cursor-pin autocmd above to land on. Every deeper level
        -- already has that leading column via its indent markers; this
        -- patches depth 0 to match, so "just in front of the icon" is
        -- reachable everywhere, root included.
        do
            local padding = require("nvim-tree.renderer.components.padding")
            local orig_get_indent_markers = padding.get_indent_markers
            padding.get_indent_markers = function(depth, idx, nodes_number, node, markers, early_stop)
                local result = orig_get_indent_markers(depth, idx, nodes_number, node, markers, early_stop)
                if depth == 0 then
                    result.str = " " .. result.str
                end
                return result
            end
        end
    end,
}
