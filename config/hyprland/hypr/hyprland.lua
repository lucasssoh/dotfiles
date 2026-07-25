-- ============================================================
-- HYPRLAND.LUA — Main config
-- ============================================================

-- ============================================================
-- ENVIRONMENT
-- ============================================================
hl.env("XCURSOR_SIZE",          "24")
hl.env("XCURSOR_THEME",         "breeze_cursors")
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
    
    -- FORCE SYSTEMD À RECONNAÎTRE LA SESSION HYPRLAND
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- NB : `systemctl --user start graphical-session.target` ne sert à rien ici
    -- -- cette target système a RefuseManualStart=yes (cf. /usr/lib/systemd/
    -- user/graphical-session.target) et loginctl ne marque pas cette session
    -- comme "graphique" (Type=unspecified/Class=manager), donc elle ne
    -- s'active jamais toute seule non plus. Résultat : tout service
    -- WantedBy=graphical-session.target (ex. orbit.service) ne démarre
    -- jamais tout seul au login -- démarrage explicite ci-dessous à la place.
    
    -- Services et Daemons
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("waybar")
    -- swaync remplace dunst (centre de contrôle avec historique/toggles/mpris ;
    -- les deux se disputeraient le nom D-Bus org.freedesktop.Notifications,
    -- donc dunst n'est plus lancé -- config gardée dans le repo en fallback).
    hl.exec_cmd("swaync")
    -- Désactivé sur cette machine (config restée en place et corrigée, cf.
    -- hypridle.conf ci-dessus, mais pas activée -- problème connu non traité
    -- ici). À réactiver en décommentant la ligne ci-dessous.
    -- hl.exec_cmd("hypridle")
    -- RESTAURATION DU WALLPAPER (On lance notre aiguillage)
    hl.exec_cmd("~/.config/hypr/scripts/restore_wallpaper.sh")
    hl.exec_cmd("bash ~/.config/hypr/scripts/wallpaper-cache-watcher.sh")
    -- Gestion du presse-papier
    hl.exec_cmd("wl-paste --watch cliphist store")
    -- Démon D-Bus Nemo (permet l'intégration universelle "Ouvrir l'emplacement")
    hl.exec_cmd("nemo --no-desktop --gapplication-service")

    -- Workspaces fixes 1-10 (posés à l'exécution via hyprctl eval, donc pas
    -- persistés dans un fichier — à rejouer à chaque démarrage, cf. aussi
    -- config.reloaded ci-dessous pour le cas `hyprctl reload`)
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")

    -- Gestionnaire WiFi/Bluetooth/VPN natif Wayland (remplace le détour par
    -- gnome-control-center) -- compilé depuis les sources vendorisées par
    -- install.sh, cf. config/hyprland/orbit-vendor/. `orbit toggle` (waybar)
    -- réutilise ce daemon caché plutôt que d'en relancer un par clic.
    -- Plus lancé ici directement : client layer-shell GTK4 démarré trop tôt,
    -- il pouvait échouer à démarrer sans que rien ne le relance (essayé un
    -- sleep bloquant, puis un lancement en fin de séquence -- toujours pas
    -- fiable au reboot réel). Géré par un service systemd --user à la place
    -- (cf. config/hyprland/systemd/orbit.service, ExecStartPre sleep 3 +
    -- Restart=on-failure), démarré explicitement ici -- PAS via
    -- WantedBy=graphical-session.target (cf. note plus haut : cette target
    -- ne s'active jamais tout seule sur cette session, donc le service ne
    -- démarrait jamais sans restart manuel au login).
    hl.exec_cmd("systemctl --user start orbit.service")
    -- Ferme Orbit au clic en dehors (comme swaync) -- GTK/gtk4-layer-shell
    -- ne prévient jamais Orbit d'une perte de focus (surface layer-shell),
    -- donc on s'appuie sur les événements Hyprland à la place.
    hl.exec_cmd("bash ~/.config/hypr/scripts/orbit-autoclose.sh")
end)

-- Un `hyprctl reload` recharge les fichiers Lua statiques et efface les
-- règles posées en runtime (workspace_rule, monitor tuning) — on les rejoue
-- ici pour que les 10 workspaces fixes survivent à un reload.
hl.on("config.reloaded", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

-- Écran externe branché/débranché : reconsolide 1-10 par rôle sans hyprctl reload.
hl.on("monitor.added", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

hl.on("monitor.removed", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

-- ============================================================
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

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})
-- ============================================================
-- GENERAL
-- ============================================================
hl.config({
    general = {
        gaps_in          = 4,
        gaps_out         = 8,
        border_size      = 2,
        col = {
            active_border = {
                colors = {
                    "rgba(89DCEBFF)",
                    "rgba(336699FF)",
                    "rgba(89DCEBFF)",
                },
                angle = 45,
            },
            inactive_border = "rgba(595959aa)",

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
        rounding = 4,
        blur = {
            enabled           = false,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            xray              = false,
            ignore_opacity    = false,
        },
        shadow = {
            enabled       = false,
            range         = 24,
            render_power  = 4,
            color         = "rgba(0,0,0,0.55)",
            color_inactive= "rgba(0,0,0,0)",
        },
        inactive_opacity = 0.98,
        active_opacity   = 1,
        dim_inactive     = true,
        dim_strength     = 0.35,
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
