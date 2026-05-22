-- ~/.config/nvim/lua/start.lua
local M = {
    "goolord/alpha-nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
}

M.config = function()
    local alpha = require("alpha")
    local dashboard = require("alpha.themes.dashboard")

    -- =========================================================
    -- HEADER (ASCII ART)
    -- =========================================================
    dashboard.section.header.val = {
        [[      ___           ___                    ___           ___           ___     ]],
        [[     /\  \         /\  \                  /\  \         /\  \         /\__\    ]],
        [[    /::\  \       /::\  \                /::\  \        \:\  \       /:/ _/_   ]],
        [[   /:/\:\  \     /:/\:\  \              /:/\:\  \        \:\  \     /:/ /\__\  ]],
        [[  /:/  \:\  \   /:/  \:\  \            /::\~\:\__\       /::\  \   /:/ /:/ _/_ ]],
        [[ /:/__/ \:\__\ /:/__/ \:\__\          /:/\:\ \:|__|     /:/\:\__\ /:/_/:/ /\__\]],
        [[ \:\  \  \/__/ \:\  \  \/__/          \:\~\:\/:/  /    /:/  \/__/ \:\/:/ /:/  /]],
        [[  \:\  \        \:\  \                 \:\ \::/  /    /:/  /       \::/_/:/  / ]],
        [[   \:\  \        \:\  \                 \:\/:/  /     \/__/         \:\/:/  /  ]],
        [[    \:\__\        \:\__\                 \::/  /                     \::/  /   ]],
        [[     \/__/         \/__/                  \/__/                       \/__/    ]],
    }

    -- =========================================================
    -- BUTTONS
    -- =========================================================
    dashboard.section.buttons.val = {
        dashboard.button("p", "󱔗  Projects", ":Telescope projects<CR>"),
        dashboard.button("f", "󰈞  Find File", ":Telescope find_files<CR>"),
        dashboard.button("n", "  New File", ":ene | startinsert<CR>"),
        dashboard.button("r", "󰄉  Recent Files", ":Telescope oldfiles<CR>"),
        dashboard.button("c", "  Configuration", ":e $MYVIMRC<CR>"),
        dashboard.button("q", "󰅙  Quit", ":qa<CR>"),
    }

    -- =========================================================
    -- FOOTER
    -- =========================================================
    local stats = require("lazy").stats()
    local ms = math.floor(stats.startuptime * 100 + 0.5) / 100

    dashboard.section.footer.val =
        "⚡ " .. stats.count .. " plugins loaded in " .. ms .. "ms"

    -- =========================================================
    -- SETUP
    -- =========================================================
    alpha.setup(dashboard.config)
end

return M
