-- ============================================================
-- WINDOWRULES.LUA — Règles par application
-- ============================================================
-- Syntaxe : hl.window_rule({ match = { ... }, effect = value, ... })
-- Les règles sont évaluées de haut en bas — l'ordre compte !
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
-- THUNAR — dialogues flottants, fenêtre principale en tuile
-- ============================================================
-- Dialogues (tout ce qui n'est PAS la fenêtre principale "— Thunar")
hl.window_rule({
    match  = { class = "thunar", title = "^(?!.*— Thunar)" },
    size   = "900 600",
    center = true,
})
-- Opacité sur toutes les fenêtres Thunar
hl.window_rule({
    match   = { class = "thunar" },
    opacity = "0.95 override",
})

-- ============================================================
-- DIALOGUES SYSTÈME — toujours flottants et centrés
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
-- PAVUCONTROL — GUI audio fallback
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
-- DUNST — pas de vol de focus
-- ============================================================
hl.window_rule({
    match            = { class = "dunst" },
    no_initial_focus = true,
})

-- ============================================================
-- TOUTES LES FENÊTRES FLOTTANTES → centrées
-- ============================================================
hl.window_rule({
    match  = { float= true },
    center = true,
})

-- ============================================================
-- CALENDRIER
-- ============================================================
hl.window_rule({
    match        = { class = "calendar" },
    float        = true,
    size         = "820 420",
    center       = true,
    stay_focused = true,
})

-- ============================================================
-- ROFI (Launcher & Powermenu)
-- ============================================================
hl.window_rule({
    match = { class = "Rofi" },
    -- Désactive totalement l'animation pour cette classe
    no_anim = true,
    -- Force le flottement (déjà géré globalement mais on sécurise)
    float = true,
    -- Évite que le flou (blur) ne doive être recalculé à l'ouverture
    no_blur = true,
    -- S'assure que la fenêtre est immédiatement centrée sans "glisser"
    center = true,
    -- Garde le focus pour éviter de devoir recliquer
    stay_focused = true,
})

-- ============================================================
-- NMTUI — WiFi flottant centré
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
-- BLUETUITH — Bluetooth flottant centré
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
-- WIREMIX — Audio TUI
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
-- DASHBOARD
-- ============================================================

-- Dashboard fastfetch (haut-droit)
hl.window_rule({
    match    = { class = "dashboard-fastfetch" },
    float    = true,
    pin      = true,
    size     = "720 440",
    move     = "180 140",
    no_focus = true,
    no_blur  = true,
    no_anim  = false,
    animation= "slide left",
})

-- Dashboard clock (bas-gauche)
hl.window_rule({
    match    = { class = "dashboard-clock" },
    float    = true,
    pin      = true,
    size     = "500 200",
    move     = "1020 820",
    no_focus = true,
    no_blur  = true,
    no_anim  = false,
    animation= "slide right",
})
