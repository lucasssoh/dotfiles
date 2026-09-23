return {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        -- Own namespace for the elision extmarks below: nvim-tree clears
        -- its own namespaces on every redraw, and the cursor-pin autocmd
        -- scans every namespace, so ours has to be identifiable.
        local elide_ns = vim.api.nvim_create_namespace("NvimTreeElide")
        local ELLIPSIS = "…"

        -- Pick where to cut `name` so that head .. "…" .. tail fits in
        -- `avail` display cells. The tail keeps the extension plus a few
        -- characters of stem -- "foo.ts" and "foo.test.ts" must not elide
        -- to the same thing -- and the head takes everything left over,
        -- since that is where sibling names diverge most.
        -- Returns byte offsets into `name`, or nil when there is nothing
        -- worth cutting (name already fits, or the budget is so small
        -- that no split stays inside it).
        local function split_name(name, avail)
            local nchars = vim.fn.strchars(name)
            local ext = name:match("%.[%w_%-]+$") or ""
            local tail = math.min(vim.fn.strchars(ext) + 3, math.floor((avail - 1) / 2))
            local head = avail - 1 - tail

            -- Budget is in display cells but the split is in characters;
            -- for a CJK/emoji name those differ, so shrink the head until
            -- the rendered result really fits instead of assuming 1:1.
            while head >= 1 and tail >= 1 and head + tail < nchars do
                local head_b = vim.fn.byteidx(name, head)
                local tail_b = vim.fn.byteidx(name, nchars - tail)
                local shown = name:sub(1, head_b) .. ELLIPSIS .. name:sub(tail_b + 1)
                if vim.fn.strdisplaywidth(shown) <= avail then
                    return head_b, tail_b
                end
                head = head - 1
            end
        end

        -- Conceal the middle of every name that overflows the tree window.
        -- The buffer text itself is never touched -- only its *display* --
        -- which is what makes both halves of the behaviour come for free:
        --   * 'concealcursor' is empty, so Neovim un-conceals the cursor
        --     line on its own: the entry you are sitting on always reads
        --     in full, with no code and no re-render on CursorMoved.
        --   * renderer.full_name (below) floats that full line out over
        --     the editor when even un-concealed it is wider than the
        --     window, so nothing is ever unreachable.
        -- Net effect: the window no longer has to be as wide as its single
        -- longest entry -- everything else stays narrow.
        local function elide_long_names(bufnr, winnr)
            vim.api.nvim_buf_clear_namespace(bufnr, elide_ns, 0, -1)

            local core = require("nvim-tree.core")
            local explorer = core.get_explorer()
            local wininfo = vim.fn.getwininfo(winnr)[1]
            if not explorer or not wininfo then
                return
            end

            -- Columns actually available for text: the window minus its
            -- gutter (the sign column carrying the git glyphs, etc.).
            -- Same figure nvim-tree's own full_name popup compares
            -- against, so the two hand over to each other exactly.
            local budget = vim.api.nvim_win_get_width(winnr) - wininfo.textoff

            for lnum, node in pairs(explorer:get_nodes_by_line(core.get_nodes_starting_line())) do
                local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
                -- Grouped folders render as "a/b/c", so ask the node for
                -- the string that was actually drawn rather than using
                -- node.name. The name is the tail of the line; if it is
                -- not (a decorator drew an icon after it), skip the line
                -- rather than cut the wrong bytes.
                local name = line and node:highlighted_name().str
                if name and #name > 0 and line:sub(-#name) == name then
                    local prefix = line:sub(1, #line - #name)
                    local avail = budget - vim.fn.strdisplaywidth(prefix)
                    if avail >= 6 and vim.fn.strdisplaywidth(name) > avail then
                        local head_b, tail_b = split_name(name, avail)
                        if head_b then
                            -- No hl_group: on a conceal extmark it colours
                            -- the "…" AND the hidden text under it, so the
                            -- middle of the name came back grey (and lost
                            -- its git/diagnostic colour) as soon as the
                            -- cursor line un-concealed it. Without one, the
                            -- "…" takes `Conceal`, remapped per window below.
                            vim.api.nvim_buf_set_extmark(bufnr, elide_ns, lnum - 1, #prefix + head_b, {
                                end_col = #prefix + tail_b,
                                conceal = ELLIPSIS,
                            })
                        end
                    end
                end
            end
        end

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
                        -- The elision marks carry no hl_group, so they are
                        -- already out of the running; the ns check keeps it
                        -- that way if one is ever given back to them.
                        if details.hl_group and details.hl_group ~= "NvimTreeIndentMarker" and details.ns_id ~= elide_ns then
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

            -- Dynamic width, but capped tight. The window still shrinks to
            -- fit a shallow tree; what it no longer does is stretch to the
            -- width of its single longest entry, because past `max` the
            -- overflow is handled by eliding the middle of the name
            -- (elide_long_names above) instead of by widening the window.
            -- Set width to a plain number here for a fixed-width tree —
            -- nothing else in this file depends on it being dynamic.
            view = {
                width = {
                    min = 30,
                    max = 40,
                    padding = 1,
                },
            },

            renderer = {
                root_folder_label = false,
                -- Float the whole line over the editor when the cursor is
                -- on an entry too wide for the window. This is what makes
                -- the elision lossless: 'concealcursor' already expands
                -- the cursor line in place, and this catches the case
                -- where even expanded it runs off the right edge.
                full_name = true,
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
                    -- It also keeps the status out of the text, so the
                    -- elision above never has to budget around it.
                    git_placement = "signcolumn",
                    -- One space between the file/folder icon and the name,
                    -- but nothing else is inline any more to space out.
                    padding = {
                        icon = " ",
                        folder_arrow = "",
                    },
                    -- Plain ASCII signs instead of nerd-font icon shapes —
                    -- the glyph only needs to be a compact, legible mark
                    -- in the gutter, not a distinct pictogram per status.
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

        -- Re-elide after every draw: nvim-tree has already resized the
        -- window by the time TreeRendered fires (renderer/init.lua calls
        -- view.grow_from_content() just before dispatching), so the width
        -- we budget against is the final one.
        do
            local api = require("nvim-tree.api")
            api.events.subscribe(api.events.Event.TreeRendered, function(data)
                if not data.bufnr or not data.winnr or not vim.api.nvim_win_is_valid(data.winnr) then
                    return
                end
                -- conceallevel 2: a concealed block collapses to its
                -- replacement character. concealcursor empty: never
                -- conceal the line the cursor is on — that single option
                -- is the whole "selected entry shows in full" behaviour.
                vim.wo[data.winnr].conceallevel = 2
                vim.wo[data.winnr].concealcursor = ""
                -- The "…" in the discreet guide-line grey, in this window
                -- only. Appended to nvim-tree's own winhighlight, once.
                local winhl = vim.wo[data.winnr].winhighlight
                if not winhl:find("Conceal:", 1, true) then
                    vim.wo[data.winnr].winhighlight = (winhl ~= "" and winhl .. "," or "") .. "Conceal:NvimTreeIndentMarker"
                end
                elide_long_names(data.bufnr, data.winnr)
            end)

            -- TreeRendered only fires when the tree redraws, not when its
            -- window is resized by hand (mouse drag, <C-w>>): a widened
            -- tree kept eliding names that now fit, a narrowed one let them
            -- overflow. Re-budget on the new width instead.
            vim.api.nvim_create_autocmd("WinResized", {
                group = vim.api.nvim_create_augroup("NvimTreeElideResize", { clear = true }),
                -- Every tree window rather than v:event.windows: there is
                -- rarely more than one, and a resized neighbour shrinks it
                -- just as well.
                callback = function()
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        local buf = vim.api.nvim_win_get_buf(win)
                        if vim.bo[buf].filetype == "NvimTree" then
                            elide_long_names(buf, win)
                        end
                    end
                end,
            })
        end

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
