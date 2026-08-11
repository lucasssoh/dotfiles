-- ============================================================
-- COUCOU / PALETTE_LIGHT.LUA
-- Light variant of palette.lua — same token names and same hue
-- family (nothing warmer than yellow, red reserved for errors),
-- but bg/fg flipped and accents darkened/saturated enough to stay
-- readable on a light background (the desktop setup is dark-only,
-- so there's no dotfiles source to pull these from directly).
-- ============================================================
return {
    bg          = "#f0f1f3", -- soft cool off-white
    surface     = "#e5e6ea", -- elevated capsules
    overlay     = "#d7d9de", -- second-tier surface
    border      = "#b3b6bd", -- signature border
    muted       = "#9799a1", -- disabled / empty state
    subtle      = "#63656d", -- secondary text
    text        = "#1b1c20", -- primary text

    cyan        = "#0e8a97", -- darkened take on the dark theme's cyan accent
    cyan_light  = "#1c9dab", -- lighter secondary teal
    blue        = "#1f6fd6", -- darkened take on the dark theme's blue accent
    green       = "#1f9d57", -- darkened take on the dark theme's green
    green_dim   = "#1a7a44", -- media/power-saver equivalent
    yellow      = "#8a7328", -- dark khaki/sand instead of pale sand

    red_soft    = "#d1483f", -- critical metrics, darkened for contrast
    red         = "#c22f26", -- urgent, darkened for contrast
}
