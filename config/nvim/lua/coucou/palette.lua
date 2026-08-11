-- ============================================================
-- COUCOU / PALETTE.LUA
-- Greys, cyan, red/red_soft and green are pulled straight from
-- the Hyprland setup (waybar/style.css, hypr/colors.lua, roue).
-- blue/yellow are calibrated against couleurs.jpg (Android
-- screenshot, provided because the desktop monitor's HDR pipeline
-- skews colors — see reference_hdr_hyprland_state) by sampling the
-- rendered "public"/"class" (blue) and "UserService" (yellow)
-- pixels: blue #88d7e8, yellow #e1df95.
-- ============================================================
return {
    bg          = "#0e0e0e", -- waybar/style.css:5 (#141414), darkened a touch for the editor
    surface     = "#17171a", -- waybar/style.css:6 (#1e1e20), darkened to match
    overlay     = "#232326", -- waybar/style.css:7 (#2c2c2e), darkened to match
    border      = "#505050", -- waybar/style.css:8   signature 1-2px border
    muted       = "#48484a", -- waybar/style.css:12  disabled / empty state
    subtle      = "#8e8e93", -- rofi/share.rasi:21   secondary text
    text        = "#f2f2f7", -- waybar/style.css:9   universal foreground

    cyan        = "#4fefff", -- waybar/style.css:11  the system accent
    cyan_light  = "#d0ffff", -- hypr/colors.lua:17   dashboard clock digits
    blue        = "#88d7e8", -- couleurs.jpg: "public"/"class" keyword blue
    green       = "#4ade80", -- roue-src/src/color.rs:43  named accent "green"
    green_dim   = "#237823", -- waybar/style.css:13  media playing / power-saver
    yellow      = "#e1df95", -- couleurs.jpg: "UserService"/"UserRepository" gold, sand-toned

    red_soft    = "#ff6e6e", -- waybar/style.css:14  critical metrics
    red         = "#ff453a", -- hypr/colors.lua:19   urgent
}
