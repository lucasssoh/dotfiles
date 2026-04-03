return {
    "coffebar/neovim-project",
    opts = {
        projects = { "~/code/*" },
        detection_methods = { "lsp", "pattern" },
        patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" },
        last_session_on_startup = false,
        dashboard_mode = true,
    },
    init = function()
        vim.opt.sessionoptions:append("globals")
    end,
    dependencies = {
        { "nvim-lua/plenary.nvim" },
        { "nvim-telescope/telescope.nvim" },
        { "Shatur/neovim-session-manager" },
    },
}
