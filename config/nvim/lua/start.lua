-- ~/.config/nvim/lua/start.lua
local M = {
    "goolord/alpha-nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
}

M.config = function()
    local alpha = require("alpha")
    local dashboard = require("alpha.themes.dashboard")

    -- COUCOU ! Header (Keep your ASCII art here)
    dashboard.section.header.val = {
        [[  ██████╗  ██████╗ ██╗   ██╗  ██████╗  ██████╗ ██╗   ██╗    ██╗ ]],
        [[ ██╔════╝ ██╔═══██╗██║   ██║ ██╔════╝ ██╔═══██╗██║   ██║    ██║ ]],
        [[ ██║      ██║   ██║██║   ██║ ██║      ██║   ██║██║   ██║    ██║ ]],
        [[ ██║      ██║   ██║██║   ██║ ██║      ██║   ██║██║   ██║    ╚═╝ ]],
        [[ ╚██████╗ ╚██████╔╝╚██████╔╝ ╚██████╗ ╚██████╔╝╚██████╔╝    ██╗ ]],
        [[  ╚═════╝  ╚═════╝  ╚═════╝   ╚═════╝  ╚═════╝  ╚═════╝     ╚═╝ ]],
    }

    -- Updated Buttons
    dashboard.section.buttons.val = {
        dashboard.button("p", "󱔗  Projects", ":Telescope projects<CR>"), -- NEW: Open recent projects
        dashboard.button("f", "󰈞  Find File", ":Telescope find_files <CR>"),
        dashboard.button("n", "  New File", ":ene <BAR> startinsert <CR>"),
        dashboard.button("r", "󰄉  Recent Files", ":Telescope oldfiles <CR>"),
        dashboard.button("c", "  Configuration", ":e $MYVIMRC <CR>"),
        dashboard.button("q", "󰅙  Quit", ":qa<CR>"),
    }

    -- Footer
    local stats = require("lazy").stats()
    local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
    dashboard.section.footer.val = "⚡ " .. stats.count .. " plugins loaded in " .. ms .. "ms"

    alpha.setup(dashboard.config)
end

return M
