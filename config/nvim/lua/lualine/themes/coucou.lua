-- ============================================================
-- LUALINE THEME: coucou
-- Picked up automatically by plugins/lualine.lua's `theme = "auto"`
-- when the coucou colorscheme is active (lualine.themes.<colors_name>).
-- lualine dofile()s this on every ColorScheme, so the palette follows
-- the light/dark switch without a restart.
-- ============================================================
local p = require(vim.o.background == "light" and "coucou.palette_light" or "coucou.palette")

-- `--bg=transparent` removes the surfaces after the fact, but lualine
-- rebuilds its separators from the theme colours cached here. Handing it
-- NONE directly keeps the whole statusline see-through and stops the
-- transition glyphs from repainting an opaque block on every refresh.
local transparent = vim.g.theme_bg == "transparent"

local function bg(color)
    return transparent and "NONE" or color
end

local function mode(accent)
    return {
        a = { fg = p.bg, bg = accent, gui = "bold" },
        b = { fg = p.text, bg = bg(p.overlay) },
        c = { fg = p.subtle, bg = bg(p.surface) },
    }
end

return {
    normal   = mode(p.cyan),
    insert   = mode(p.green),
    visual   = mode(p.blue),
    replace  = mode(p.red_soft),
    command  = mode(p.yellow),
    inactive = {
        a = { fg = p.muted, bg = bg(p.bg) },
        b = { fg = p.muted, bg = bg(p.bg) },
        c = { fg = p.muted, bg = bg(p.bg) },
    },
}
