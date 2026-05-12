-- ============================================================
-- HYPRLAND.LUA — Main config (converti depuis hyprland.conf)
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
-- SOURCES (require = ancien source =)
-- ============================================================
require("colors")       -- colors.conf  → colors.lua
require("monitors")     -- monitors.conf → monitors.lua
require("keybinds")     -- keybinds.conf → keybinds.lua
require("windowrules")  -- windowrules.conf → windowrules.lua

-- ============================================================
-- AUTOSTART
-- ============================================================
hl.exec_once("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
hl.exec_once("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
hl.exec_once("hyprpaper")
hl.exec_once("waybar")
hl.exec_once("dunst")
hl.exec_once("hypridle")
hl.exec_once("wl-paste --watch cliphist store")

-- ============================================================
-- INPUT
-- ============================================================
hl.config({
    input = {
        kb_layout  = "fr",
        kb_variant = "azerty",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll      = true,
            tap_to_click        = true,
            disable_while_typing = true,
            scroll_factor       = 0.3,
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
            active_border   = "$accent",   -- défini dans colors.lua
            inactive_border = "$overlay",
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
-- ANIMATIONS
-- ============================================================
hl.curve("smooth", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("linear", { type = "bezier", points = { {0.0,  0.0}, {1.0, 1.0}  } })
hl.curve("snap",   { type = "bezier", points = { {0.2,  1.0}, {0.2, 1.0}  } })

hl.config({
    animations = {
        enabled = true,
    },
})

hl.animation({ name = "windows",    duration = 4, curve = "smooth", style = "slide"  })
hl.animation({ name = "windowsOut", duration = 3, curve = "snap",   style = "slide"  })
hl.animation({ name = "fade",       duration = 4, curve = "smooth"                   })
hl.animation({ name = "workspaces", duration = 4, curve = "snap",   style = "slide"  })

-- ============================================================
-- LAYOUT
-- ============================================================
hl.config({
    dwindle = {
        pseudotile     = true,
        preserve_split = true,
        smart_split    = true,
    },
})

-- ============================================================
-- MISC
-- ============================================================
hl.config({
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        vfr                      = true,  -- économie d'énergie laptop
        mouse_move_enables_dpms  = true,
        key_press_enables_dpms   = true,
    },
    cursor = {
        no_hardware_cursors = false,
    },
})
