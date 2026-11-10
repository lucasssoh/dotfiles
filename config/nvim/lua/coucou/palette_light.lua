-- ============================================================
-- COUCOU / PALETTE_LIGHT.LUA
-- Light variant of palette.lua: same token names, same roles (blue
-- keywords, sand types and numbers, green strings, red only for
-- errors). The values are the shell's light inks
-- (quickshell/bar/theme/DrawerTheme.qml): the neutral greys, the
-- cream panel, and its dark teal/blue/green/red, so nvim reads like
-- the drawers around it rather than like a stock light theme.
--
-- Picked for a translucent WezTerm too: the light terminal is a cream
-- veil over the blurred wallpaper (wezterm.lua), so every ink here
-- holds against a veil that is not pure cream.
-- ============================================================
return {
    bg          = "#f5f3ee", -- DrawerTheme panelTop (light)
    surface     = "#ebe8e1", -- one step darker: floats, cursor line
    overlay     = "#dedad2", -- second step: selection, prompts
    border      = "#c4c3be", -- DrawerTheme faint
    muted       = "#7a7a80", -- comments, line numbers: DrawerTheme muted, darkened to hold on glass
    subtle      = "#56565b", -- DrawerTheme secondary
    text        = "#1c1c1e", -- DrawerTheme primary

    cyan        = "#006b75", -- DrawerTheme hdr: the accent
    cyan_light  = "#2b7a82", -- a lighter step of the same teal
    blue        = "#1d6386", -- DrawerTheme conserve: keywords
    -- Kept apart from `blue`, as in palette.lua: a saturated blue for git
    -- status, which must not read as a keyword.
    azure       = "#1f56b8",
    green       = "#24692a", -- DrawerTheme positive
    green_dim   = "#3d7a41",
    yellow      = "#6e5c0f", -- dark sand: the dark theme's #e1df95, never amber

    red_soft    = "#b3261e", -- DrawerTheme danger
    red         = "#9c1f18",
}
