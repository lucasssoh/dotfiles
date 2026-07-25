-- ============================================================
-- hyprland.lua — Point d'entrée de la configuration Hyprland
-- ============================================================
-- Charge la palette, les variables d'environnement, l'autostart, puis
-- les sous-modules (monitors / windowrules / keybinds) en fin de fichier.
-- ============================================================

-- ============================================================
-- ENVIRONMENT
-- ============================================================
-- Variables nécessaires pour un fonctionnement Wayland cohérent entre
-- toolkits (Qt, GTK, SDL, Clutter) et applications historiquement X11.
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
-- AUTOSTART (syntaxe événementielle Lua, Hyprland 0.55+)
-- ============================================================
hl.on("hyprland.start", function()
    -- Propage les variables de session vers D-Bus/systemd : requis pour
    -- que les portails XDG (partage d'écran, sélecteur de fichiers...)
    -- fonctionnent correctement sous Wayland.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Importe la session dans systemd --user : requis par les services
    -- déclarés WantedBy=graphical-session.target pour démarrer.
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- NB : `systemctl --user start graphical-session.target` ne suffit pas
    -- sur cette session : la target a RefuseManualStart=yes (cf.
    -- /usr/lib/systemd/user/graphical-session.target) et loginctl ne
    -- classe pas cette session comme "graphique" (Type=unspecified /
    -- Class=manager), donc la target ne s'active jamais automatiquement.
    -- Conséquence : tout service WantedBy=graphical-session.target (ex.
    -- orbit.service) doit être démarré explicitement ci-dessous plutôt
    -- que de compter sur l'activation de la target.

    -- Services et daemons de session
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("waybar")
    -- swaync remplace dunst comme centre de notifications (historique,
    -- toggles, contrôles mpris). Les deux revendiquent le même nom D-Bus
    -- org.freedesktop.Notifications et ne peuvent pas cohabiter — dunst
    -- n'est donc plus lancé, mais sa config reste dans le repo en secours.
    hl.exec_cmd("swaync")
    -- hypridle désactivé sur cette machine (config présente et valide,
    -- cf. hypridle.conf, mais non activée). Décommenter pour réactiver.
    -- hl.exec_cmd("hypridle")
    -- Restaure le fond d'écran de la session précédente puis surveille
    -- le cache de vignettes en arrière-plan.
    hl.exec_cmd("~/.config/hypr/scripts/restore_wallpaper.sh")
    hl.exec_cmd("bash ~/.config/hypr/scripts/wallpaper-cache-watcher.sh")
    -- Historique du presse-papier
    hl.exec_cmd("wl-paste --watch cliphist store")
    -- Démon D-Bus Nemo, pour l'intégration "Ouvrir l'emplacement" des
    -- autres applications (gestionnaire de fichiers toujours disponible).
    hl.exec_cmd("nemo --no-desktop --gapplication-service")

    -- Workspaces fixes 1-10, posés à l'exécution via hyprctl eval — non
    -- persistés dans un fichier Lua, donc à rejouer à chaque démarrage
    -- (et sur config.reloaded / monitor.added / monitor.removed ci-dessous).
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")

    -- Gestionnaire WiFi/Bluetooth/VPN natif Wayland (remplace le détour
    -- par gnome-control-center), compilé depuis les sources vendorisées
    -- par install.sh (cf. orbit-vendor/). Le raccourci waybar `orbit
    -- toggle` réutilise ce daemon plutôt que d'en relancer un par clic.
    -- Démarré ici via un service systemd --user (cf. systemd/orbit.service,
    -- ExecStartPre sleep 3 + Restart=on-failure) plutôt que directement :
    -- le client GTK4/layer-shell peut échouer à s'initialiser trop tôt
    -- dans la séquence de démarrage, et le service gère le délai et le
    -- redémarrage automatique. Démarré explicitement ici et non via
    -- WantedBy=graphical-session.target, pour la même raison que ci-dessus
    -- (cette target ne s'active jamais seule sur cette session).
    hl.exec_cmd("systemctl --user start orbit.service")
    -- Ferme Orbit sur clic extérieur (comme swaync) : GTK/gtk4-layer-shell
    -- ne notifie jamais une surface layer-shell de sa perte de focus, donc
    -- ce comportement s'appuie sur les événements Hyprland à la place.
    hl.exec_cmd("bash ~/.config/hypr/scripts/orbit-autoclose.sh")
end)

-- Un `hyprctl reload` recharge les fichiers Lua statiques et efface les
-- règles posées à l'exécution (workspace_rule, tuning moniteur) — on les
-- rejoue ici pour que les 10 workspaces fixes survivent à un reload.
hl.on("config.reloaded", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

-- Écran externe branché ou débranché : réassigne les workspaces 1-10 par
-- rôle (interne/externe) sans nécessiter de hyprctl reload.
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

-- Swipe horizontal 3 doigts pour naviguer entre workspaces (trackpad)
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
            -- Dégradé animé pour la bordure de la fenêtre active
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
-- CURVES — courbes de Bézier réutilisées par les animations ci-dessous
-- ============================================================
hl.curve("smooth", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("linear", { type = "bezier", points = { {0.0, 0.0}, {1.0, 1.0} } })
hl.curve("snap",   { type = "bezier", points = { {0.2, 1.0}, {0.2, 1.0} } })

-- ============================================================
-- ANIMATIONS
-- ============================================================
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "smooth", style = "slide" })

-- Fondu (ouverture/fermeture, changement d'opacité)
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

-- Sous-modules : moniteurs/HDR, règles par application, raccourcis clavier
require("monitors")
require("windowrules")
require("keybinds")
