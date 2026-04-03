return {
    "savq/melange-nvim",
    config = function()
        vim.cmd.colorscheme("melange")

        vim.api.nvim_set_hl(0, "Normal",       { bg = "#000000" })
        vim.api.nvim_set_hl(0, "NormalFloat",  { bg = "#000000" })
        vim.api.nvim_set_hl(0, "LineNr",       { fg = "#5e5249", bg = "NONE" })
        vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#35271e" })
        vim.api.nvim_set_hl(0, "CursorLine",   { bg = "#1a1a1a" })
        vim.api.nvim_set_hl(0, "SmoothCursor", { fg = "#d79921" })
    end,
}
