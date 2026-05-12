-- ============================================================
-- HYPRLAND.LUA — Main config
-- ============================================================

-- ============================================================
-- ENVIRONMENT
-- ============================================================
hl.env("XCURSOR_SIZE",          "24")
hl.env("XCURSOR_THEME",         "Bibata-Modern-Classic")
hl.env("QT_QPA_PLATFORM",       "wayland")
hl.env("QT_QPA_PLATFORMTHEME",  "qt6ct")
hl.env("GDK_BACKEND",           "wayland,x11")
hl.env("SDL_VIDEODRIVER",       "wayland")
hl.env("CLUTTER_BACKEND",       "wayland")
hl.env("XDG_CURRENT_DESKTOP",   "Hyprland")
hl.env("XDG_SESSION_TYPE",      "wayland")
hl.env("XDG_SESSION_DESKTOP",   "Hyprland")
hl.env("MOZ_ENABLE_WAYLAND",    "1")

-- ============================================================
-- SOURCES
-- ============================================================
local colors = require("colors")

-- ============================================================
-- AUTOSTART (Nouvelle syntaxe Lua 0.55+)
-- ============================================================

hl.on("hyprland.start", function()
    -- Environnement système (important pour Wayland/Portal)
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    
    -- Services et Daemons
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("waybar")
    hl.exec_cmd("dunst")
    hl.exec_cmd("hypridle")
    
    -- Gestion du presse-papier
    hl.exec_cmd("wl-paste --watch cliphist store")
    
end)-- ============================================================
-- INPUT
-- ============================================================
hl.config({
    input = {
        kb_layout  = "fr",
        kb_variant = "azerty",
        follow_mouse = 1,
        repeat_rate = 45,
        repeat_delay = 200,
        sensitivity  = 0,
        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            disable_while_typing = true,
            scroll_factor        = 0.3,
        },
    },
})

-- ============================================================
-- GENERAL
-- ============================================================
hl.config({
    general = {
        gaps_in          = 5,
        gaps_out         = 10,
        border_size      = 1,
        col = {
            active_border   = colors.accent,
            inactive_border = colors.overlay,
        },
        layout           = "dwindle",
        resize_on_border = true,
    },
})

-- ============================================================
-- DECORATION
-- ============================================================
hl.config({
    decoration = {
        rounding = 6,
        blur = {
            enabled           = false,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            xray              = false,
            ignore_opacity    = false,
        },
        shadow = {
            enabled       = true,
            range         = 20,
            render_power  = 3,
            color         = "rgba(0,0,0,0.4)",
            color_inactive= "rgba(0,0,0,0.2)",
        },
        inactive_opacity = 0.93,
        active_opacity   = 1.0,
        dim_inactive     = true,
        dim_strength     = 0.1,
    },
})

-- ============================================================
-- CURVES
-- ============================================================
hl.curve("smooth", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("linear", { type = "bezier", points = { {0.0, 0.0}, {1.0, 1.0} } })
hl.curve("snap",   { type = "bezier", points = { {0.2, 1.0}, {0.2, 1.0} } })

-- ============================================================
-- ANIMATIONS
-- ============================================================

hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "smooth", style = "slide" })

-- Fade
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "smooth" })

hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "snap", style = "slide" })

-- ============================================================
-- LAYOUT & MISC
-- ============================================================
hl.config({
    dwindle = {
        force_split = 0,

        preserve_split = true,
        smart_split    = true,
        smart_resizing = true,
    },
})

require("monitors")
require("windowrules")
require("keybinds")
