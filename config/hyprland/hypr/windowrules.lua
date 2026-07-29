-- ============================================================
-- windowrules.lua — Per-application rules
-- ============================================================
-- Syntax: hl.window_rule({ match = { ... }, effect = value, ... })
-- Rules are evaluated top to bottom — order matters! A more specific rule
-- placed after a general one can override it (see Steam and Lutris below).
-- ============================================================

-- ============================================================
-- FIREFOX
-- ============================================================
hl.window_rule({
    match   = { class = "firefox" },
    opacity = "1.0 override",
    workspace = "2",
})

-- ============================================================
-- WEZTERM
-- ============================================================
-- hl.window_rule({
--     match   = { class = "org.wezfurlong.wezterm" },
--     opacity = "0.95 override",
-- })

-- ============================================================
-- THUNAR — floating dialogs, main window tiled
-- ============================================================
-- Dialogs (everything that is NOT the main "— Thunar" window)
hl.window_rule({
    match  = { class = "thunar", title = "^(?!.*— Thunar)" },
    size   = "900 600",
    center = true,
})
-- Opacity on all Thunar windows
hl.window_rule({
    match   = { class = "thunar" },
    opacity = "0.95 override",
})

-- ============================================================
-- SYSTEM DIALOGS — always floating and centered
-- ============================================================
hl.window_rule({
    match  = { class = "polkit-gnome-authentication-agent-1" },
    float  = true,
    center = true,
})
hl.window_rule({ match = { title = "^Open File$"   }, float = true })
hl.window_rule({ match = { title = "^Open Folder$" }, float = true })
hl.window_rule({ match = { title = "^Save As$"     }, float = true })
hl.window_rule({ match = { title = "^Preferences$" }, float = true })
hl.window_rule({ match = { title = "^Settings$"    }, float = true })

-- ============================================================
-- PAVUCONTROL — audio fallback GUI
-- ============================================================
hl.window_rule({
    match        = { class = "org.pulseaudio.pavucontrol" },
    float        = true,
    size         = "900 550",
    center       = true,
    stay_focused = true,
    opacity      = "0.97 override",
})

-- ============================================================
-- DUNST — no focus stealing
-- ============================================================
hl.window_rule({
    match            = { class = "dunst" },
    no_initial_focus = true,
})

-- ============================================================
-- ALL FLOATING WINDOWS → centered by default
-- ============================================================
hl.window_rule({
    match  = { float= true },
    center = true,
})

-- ============================================================
-- CALENDAR
-- ============================================================
hl.window_rule({
    match        = { class = "calendar" },
    float        = true,
    size         = "820 420",
    center       = true,
    stay_focused = true,
})

-- ============================================================
-- ROFI (launcher & powermenu)
-- ============================================================
hl.window_rule({
    match = { class = "Rofi" },
    -- Disables the animation for this class (instant render)
    no_anim = true,
    -- Forces floating (already handled globally, intentional redundancy)
    float = true,
    -- Avoids a blur recalculation on open
    no_blur = true,
    -- Centers the window immediately with no sliding effect
    center = true,
    -- Keeps focus so typing works without re-clicking
    stay_focused = true,
})

-- ============================================================
-- NMTUI — WiFi (TUI in a floating terminal) centered
-- ============================================================
hl.window_rule({
    match        = { class = "nm-tui-float" },
    float        = true,
    size         = "600 400",
    center       = true,
    stay_focused = true,
    no_anim      = false,
})

-- ============================================================
-- BLUETUITH — Bluetooth (TUI) centered
-- ============================================================
hl.window_rule({
    match        = { class = "bt-tui-float" },
    float        = true,
    size         = "700 480",
    center       = true,
    stay_focused = true,
    no_anim      = false,
})

-- ============================================================
-- WIREMIX — Audio (TUI)
-- ============================================================
hl.window_rule({
    match        = { class = "audio-tui-float" },
    float        = true,
    size         = "900 550",
    center       = true,
    stay_focused = true,
    no_anim      = false,
})

-- ============================================================
-- DASHBOARD — floating, non-focusable widgets
-- ============================================================

-- Fastfetch (top-right)
hl.window_rule({
    match    = { class = "dashboard-fastfetch" },
    float    = true,
    pin      = true,
    size     = "720 440",
    move     = "180 140",
    no_focus = true,
    no_blur  = true,
    no_anim  = false,
    animation= "fade",
})

-- Clock (bottom-left)
hl.window_rule({
    match    = { class = "dashboard-clock" },
    float    = true,
    pin      = true,
    size     = "500 200",
    move     = "1020 820",
    no_focus = true,
    no_blur  = true,
    no_anim  = false,
    animation= "fade",
})

-- ============================================================
-- SCREENSHOT — Satty annotation tool
-- ============================================================
hl.window_rule({
    match        = { class = "com.gabm.satty" },
    float        = true,
    size         = "1200 780",
    center       = true,
    stay_focused = true,
    no_anim      = true,
})

-- -- ============================================================
-- -- MPV — floating video player
-- -- ============================================================
-- hl.window_rule({
--     match  = { class = "mpv" },
--     float  = true,
--     size   = "1280 720",
--     center = true,
-- })

-- ============================================================
-- HDR TONE MAPPING — Brave & mpv already do their own HDR tone
-- mapping/passthrough (Brave via wp_color_manager_v1, mpv via
-- gpu-next + target-colorspace-hint-mode=source in mpv.conf), so
-- Hyprland's own compositor-side tonemap only needs to step in for
-- content whose mastering peak exceeds the panel's real peak
-- (1037 cd/m^2 on DP-9, see hdr.sh's MAX_LUMINANCE/MAX_AVG_LUMINANCE).
--
-- Values (src/desktop/rule/windowRule/WindowRule.cpp): "off" = no
-- compositor tonemap at all (full passthrough — highlights above the
-- panel's peak just clip on the panel itself, closest to what a plain
-- fullscreen present on Windows does); "on" (default when unset) =
-- Hyprland's own knee-based tonemap, which on this panel compresses
-- everything above ~518 cd/m^2 (see the HDR plan doc) — this is the
-- most likely reason HDR looked "correct but not as punchy" as
-- Windows; "clamp" = hard-clip at the panel's peak instead of a soft
-- knee. Starting with "off" as the first A/B step; if highlights blow
-- out or clip ugly instead of rolling off, try "clamp" next.
hl.window_rule({
    match   = { class = "brave-browser" },
    tonemap = "off",
})
hl.window_rule({
    match   = { class = "mpv" },
    tonemap = "off",
})

-- ============================================================
-- NEMO — main window tiled, everything else floats
-- ============================================================
-- 1. Main window: title ending in " — Gestionnaire de fichiers" (FR)
--    or " — File Manager" (EN)
hl.window_rule({
    match  = { class = "nemo", title = " — Gestionnaire de fichiers$" },
    tile   = true,
})
hl.window_rule({
    match  = { class = "nemo", title = " — File Manager$" },
    tile   = true,
})

-- 2. Everything else (dialogs, properties, transfers, File-Roller
--    extraction): inverse match of the rule above
hl.window_rule({
    match  = { class = "nemo", title = "^(?!.* — (Gestionnaire de fichiers|File Manager))" },
    float  = true,
    center = true,
    size   = "850 550",
})
hl.window_rule({
    match  = { class = "file-roller" },
    float  = true,
    center = true,
})

-- Global opacity for Nemo
hl.window_rule({
    match   = { class = "nemo" },
    opacity = "0.95 override",
})

-- ============================================================
-- FIREFOX — downloads, preferences, and popups
-- ============================================================
-- Main window tiled on workspace 2
hl.window_rule({
    match     = { class = "firefox", title = " — Mozilla Firefox$" },
    workspace = "2",
    tile      = true,
})

-- Floating for preferences and login windows.
-- Note: the class actually reported by hyprctl clients on this system is
-- "org.mozilla.firefox", not "firefox" — so this rule is inactive as-is.
-- The targeted titles haven't been verified under real conditions; fix if
-- the need is confirmed. The Library window is already covered separately
-- below.
hl.window_rule({
    match = { class = "firefox", title = "^(Password Required|Page Info|S'identifier|Préférences|Preferences|Paramètres|Settings)" },
    float = true,
    center = true,
    stay_focused = true,
})

-- Library (history/bookmarks/downloads) — popup confirmed via hyprctl
-- clients: class="org.mozilla.firefox", title="Bibliothèque" (FR locale).
-- "Library" covers the official Mozilla English name for the same
-- window. Floating, centered, fixed size, keeps focus on open. No pin: it
-- should follow the current workspace rather than stay pinned to the
-- screen.
hl.window_rule({
    match        = { class = "org.mozilla.firefox", title = "^(Bibliothèque|Library)$" },
    float        = true,
    center       = true,
    size         = "900 650",
    stay_focused = true,
})

-- ============================================================
-- STEAM & GAME LAUNCHERS (Lutris, Heroic, Rockstar)
-- ============================================================
-- Forces floating on all game launcher popups: these windows don't have a
-- usable fixed title (e.g. Steam's game config dialog takes the game's
-- name, e.g. "Assetto Corsa Competizione"), so no fixed title list is
-- possible.
--
-- The negative lookahead "^(?!Steam$)" (to exclude only the main window
-- from this rule) doesn't work here: the regex engine used by Hyprland
-- doesn't support lookaheads reliably. Solution used: float EVERYTHING
-- with class=steam, then a rule further down (so higher priority, see the
-- file header) puts the main "Steam" window back into tile via an exact
-- match with no lookahead.
--
-- no_follow_mouse: without this option, focus-follows-mouse
-- (input.follow_mouse=1 in hyprland.lua) takes back focus as soon as the
-- cursor isn't over the freshly opened popup — stay_focused alone isn't
-- enough to prevent this focus stealing.
hl.window_rule({
    match          = { class = "steam" },
    float          = true,
    center         = true,
    stay_focused   = true,
    no_follow_mouse = true,
})
-- stay_focused/no_follow_mouse explicitly reset to false for the main
-- window: without this, these properties stay inherited from the rule
-- above (properties not redefined by a more specific rule aren't reset),
-- which disrupts input capture for this window's context menus.
hl.window_rule({
    match           = { class = "steam", title = "^Steam$" },
    tile            = true,
    stay_focused    = false,
    no_follow_mouse = false,
})

-- Lutris: same lookahead limitation as Steam above. The class actually
-- reported by hyprctl clients is "net.lutris.Lutris", not "lutris" — so
-- the rule targets the exact name directly.
hl.window_rule({
    match          = { class = "net.lutris.Lutris" },
    float          = true,
    center         = true,
    stay_focused   = true,
    no_follow_mouse = true,
})
hl.window_rule({
    match           = { class = "net.lutris.Lutris", title = "^Lutris$" },
    tile            = true,
    stay_focused    = false,
    no_follow_mouse = false,
})

-- Steam friends, chat, or properties windows
hl.window_rule({ match = { class = "steam", title = "^(Amis|Friends|Lancement|Configuring|Properties|Steam - Self Updater)" }, float = true })

-- Rockstar Games Launcher
hl.window_rule({
    match        = { class = "steam_proton", title = "^Rockstar Games Launcher" },
    float        = true,
    size         = "1200 800",
    center       = true,
    stay_focused = true,
    no_blur      = true,
    no_anim      = true,
    opacity      = "1.0 override",
})

-- ============================================================
-- UNIVERSAL DIALOG BOXES (XDG Portals, GTK, QT)
-- ============================================================
-- Generic safety net: targets any open/save dialog launched by Nemo or a
-- browser, whatever the toolkit.
hl.window_rule({ match = { title = "^(Ouvrir|Open|Enregistrer|Save|Choix|Select)" }, float = true, center = true, stay_focused = true })
hl.window_rule({ match = { title = "(Fichier|File|Dossier|Folder)$" }, float = true, center = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true, center = true, stay_focused = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-kde" }, float = true, center = true, stay_focused = true })

-- ============================================================
-- GAMESCOPE — games launched via gamescope (e.g. CS2 in 4:3)
-- ============================================================
-- tile + fullscreen: forces fullscreen display, a condition needed for
-- correct relative cursor capture (see the known nested-gamescope bug
-- that lets the cursor escape if the window stays floating).
-- no_follow_mouse: same reason as for Steam/Lutris above — without it,
-- focus-follows-mouse can make the game lose input if the system cursor
-- leaves the area at launch time.
-- no_blur/no_anim: avoids any blur or animation recalculation on a
-- fullscreen window that's already running at full GPU load.
hl.window_rule({
    match           = { class = "gamescope" },
    tile            = true,
    fullscreen      = true,
    stay_focused    = true,
    center          = true,
    no_follow_mouse = true,
    no_blur         = true,
    no_anim         = true,
    opacity         = "1.0 override",
})
