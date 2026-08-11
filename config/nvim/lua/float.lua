-- ============================================================
-- FLOAT.LUA
-- Uniform look/behaviour for all floating windows (LSP hover,
-- signature help, diagnostics float, :checkhealth, etc.)
-- ============================================================

-- Every floating window gets the same rounded border by default.
vim.opt.winborder = "rounded"

-- Every LSP/diagnostic float (hover, signature help, diagnostics)
-- goes through vim.lsp.util.open_floating_preview under the hood,
-- so wrapping it once covers all of them and lets us close with
-- "q" like everywhere else (Telescope, NvimTree, ...).
local open_floating_preview = vim.lsp.util.open_floating_preview
function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
    local bufnr, winnr = open_floating_preview(contents, syntax, opts, ...)

    vim.keymap.set("n", "q", "<Cmd>close<CR>", {
        buffer = bufnr,
        silent = true,
        nowait = true,
    })

    return bufnr, winnr
end
