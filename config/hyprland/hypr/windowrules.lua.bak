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
    blur    = false,
})

-- ============================================================
-- WEZTERM
-- ============================================================
hl.window_rule({
    match   = { class = "org.wezfurlong.wezterm" },
    opacity = "0.95 override",
})

-- ============================================================
-- THUNAR — dialogues flottants, fenêtre principale en tuile
-- ============================================================
-- Dialogues (tout ce qui n'est PAS la fenêtre principale "— Thunar")
hl.window_rule({
    match  = { class = "thunar", title = "^(?!.*— Thunar)" },
    float  = true,
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
-- PAVUCONTROL — mixeur flottant
-- ============================================================
hl.window_rule({
    match  = { class = "pavucontrol" },
    float  = true,
    size   = "700 450",
    center = true,
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
    match  = { floating = true },
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
