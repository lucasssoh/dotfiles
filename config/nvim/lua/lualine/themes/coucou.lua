-- ============================================================
-- LUALINE THEME: coucou
-- Picked up automatically by plugins/lualine.lua's `theme = "auto"`
-- when the coucou colorscheme is active (lualine.themes.<colors_name>).
-- ============================================================
local p = require("coucou.palette")

local function mode(accent)
    return { a = { fg = p.bg, bg = accent, gui = "bold" }, b = { fg = p.text, bg = p.overlay }, c = { fg = p.subtle, bg = p.surface } }
end

return {
    normal   = mode(p.cyan),
    insert   = mode(p.green),
    visual   = mode(p.blue),
    replace  = mode(p.red_soft),
    command  = mode(p.yellow),
    inactive = {
        a = { fg = p.muted, bg = p.bg },
        b = { fg = p.muted, bg = p.bg },
        c = { fg = p.muted, bg = p.bg },
    },
}
