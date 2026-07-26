-- ============================================================
-- windowrules.lua — Règles par application
-- ============================================================
-- Syntaxe : hl.window_rule({ match = { ... }, effet = valeur, ... })
-- Les règles sont évaluées de haut en bas — l'ordre compte ! Une règle
-- plus spécifique placée après une règle générale peut la surcharger
-- (cf. Steam et Lutris plus bas).
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
-- PAVUCONTROL — GUI audio de secours
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
-- TOUTES LES FENÊTRES FLOTTANTES → centrées par défaut
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
-- ROFI (launcher & powermenu)
-- ============================================================
hl.window_rule({
    match = { class = "Rofi" },
    -- Désactive l'animation pour cette classe (rendu instantané)
    no_anim = true,
    -- Force le flottement (déjà géré globalement, redondance volontaire)
    float = true,
    -- Évite un recalcul du flou à l'ouverture
    no_blur = true,
    -- Centre immédiatement la fenêtre sans effet de glissement
    center = true,
    -- Conserve le focus pour permettre la saisie sans reclic
    stay_focused = true,
})

-- ============================================================
-- NMTUI — WiFi (TUI dans un terminal flottant) centré
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
-- BLUETUITH — Bluetooth (TUI) centré
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
-- DASHBOARD — widgets flottants non focusables
-- ============================================================

-- Fastfetch (haut-droit)
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

-- Horloge (bas-gauche)
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
-- SCREENSHOT — outil de retouche Satty
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
-- -- MPV — lecteur vidéo flottant
-- -- ============================================================
-- hl.window_rule({
--     match  = { class = "mpv" },
--     float  = true,
--     size   = "1280 720",
--     center = true,
-- })

-- ============================================================
-- NEMO — fenêtre principale en tuile, tout le reste flotte
-- ============================================================
-- 1. Fenêtre principale : titre se terminant par " — Gestionnaire de
--    fichiers" (FR) ou " — File Manager" (EN)
hl.window_rule({
    match  = { class = "nemo", title = " — Gestionnaire de fichiers$" },
    tile   = true,
})
hl.window_rule({
    match  = { class = "nemo", title = " — File Manager$" },
    tile   = true,
})

-- 2. Tout le reste (dialogues, propriétés, transferts, extraction
--    File-Roller) : match inversé de la règle ci-dessus
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

-- Opacité globale pour Nemo
hl.window_rule({
    match   = { class = "nemo" },
    opacity = "0.95 override",
})

-- ============================================================
-- FIREFOX — téléchargements, paramètres et popups
-- ============================================================
-- Fenêtre principale en tuile sur le workspace 2
hl.window_rule({
    match     = { class = "firefox", title = " — Mozilla Firefox$" },
    workspace = "2",
    tile      = true,
})

-- Flottement pour les fenêtres de préférences et de login.
-- Note : la classe réellement rapportée par hyprctl clients sur ce
-- système est "org.mozilla.firefox", pas "firefox" — cette règle est
-- donc inactive en l'état. Les titres visés n'ont pas été vérifiés en
-- conditions réelles ; à corriger si le besoin se confirme. La fenêtre
-- Bibliothèque est déjà couverte séparément ci-dessous.
hl.window_rule({
    match = { class = "firefox", title = "^(Password Required|Page Info|S'identifier|Préférences|Preferences|Paramètres|Settings)" },
    float = true,
    center = true,
    stay_focused = true,
})

-- Bibliothèque (historique/marque-pages/téléchargements) — popup
-- confirmée via hyprctl clients : class="org.mozilla.firefox",
-- title="Bibliothèque" (locale FR). "Library" couvre le nom officiel
-- Mozilla en anglais pour la même fenêtre. Flottante, centrée, taille
-- fixe, garde le focus à l'ouverture. Pas de pin : elle doit suivre le
-- workspace courant plutôt que rester épinglée à l'écran.
hl.window_rule({
    match        = { class = "org.mozilla.firefox", title = "^(Bibliothèque|Library)$" },
    float        = true,
    center       = true,
    size         = "900 650",
    stay_focused = true,
})

-- ============================================================
-- STEAM & LAUNCHERS DE JEUX (Lutris, Heroic, Rockstar)
-- ============================================================
-- Force le flottement sur tous les popups des launchers de jeux : ces
-- fenêtres n'ont pas de titre fixe exploitable (ex. le dialogue de
-- config de jeu Steam prend le nom du jeu, ex. "Assetto Corsa
-- Competizione"), donc pas de liste de titres figée possible.
--
-- Le lookahead négatif "^(?!Steam$)" (pour exclure uniquement la
-- fenêtre principale de cette règle) ne fonctionne pas ici : le moteur
-- de regex utilisé par Hyprland ne supporte pas les lookaheads de façon
-- fiable. Solution retenue : flotter TOUT ce qui a class=steam, puis
-- une règle plus bas (donc prioritaire, cf. l'en-tête du fichier) repasse
-- la fenêtre principale "Steam" en tuile via un match exact sans lookahead.
--
-- no_follow_mouse : sans cette option, le focus-follows-mouse
-- (input.follow_mouse=1 dans hyprland.lua) reprend la main dès que le
-- curseur n'est pas au-dessus de la popup fraîchement ouverte —
-- stay_focused seul ne suffit pas à empêcher ce vol de focus.
hl.window_rule({
    match          = { class = "steam" },
    float          = true,
    center         = true,
    stay_focused   = true,
    no_follow_mouse = true,
})
-- stay_focused/no_follow_mouse remis explicitement à false pour la
-- fenêtre principale : sans ça, ces propriétés restent héritées de la
-- règle du dessus (les propriétés non redéfinies par une règle plus
-- spécifique ne sont pas réinitialisées), ce qui perturbe la capture
-- d'input des menus contextuels de cette fenêtre.
hl.window_rule({
    match           = { class = "steam", title = "^Steam$" },
    tile            = true,
    stay_focused    = false,
    no_follow_mouse = false,
})

-- Lutris : même limitation de lookahead que Steam ci-dessus. La classe
-- réellement rapportée par hyprctl clients est "net.lutris.Lutris", pas
-- "lutris" — la règle cible donc directement le nom exact.
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

-- Fenêtres d'amis, de chat ou de propriétés Steam
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
-- BOÎTES DE DIALOGUE UNIVERSELLES (XDG Portals, GTK, QT)
-- ============================================================
-- Filet de sécurité générique : cible tout dialogue d'ouverture/
-- sauvegarde lancé par Nemo ou un navigateur, quel que soit le toolkit.
hl.window_rule({ match = { title = "^(Ouvrir|Open|Enregistrer|Save|Choix|Select)" }, float = true, center = true, stay_focused = true })
hl.window_rule({ match = { title = "(Fichier|File|Dossier|Folder)$" }, float = true, center = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true, center = true, stay_focused = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-kde" }, float = true, center = true, stay_focused = true })

-- ============================================================
-- GAMESCOPE — jeux lancés via gamescope (ex. CS2 en 4:3)
-- ============================================================
-- tile + fullscreen : force l'affichage plein écran, condition nécessaire
-- à la capture correcte du curseur relatif (cf. bug connu de gamescope
-- imbriqué qui laisse échapper le curseur si la fenêtre reste flottante).
-- no_follow_mouse : même raison que pour Steam/Lutris ci-dessus — sans
-- ça, le focus-follows-mouse peut faire perdre l'input au jeu si le
-- curseur système sort de la zone au moment du lancement.
-- no_blur/no_anim : évite tout recalcul de flou ou animation sur une
-- fenêtre plein écran qui tourne déjà à pleine charge GPU.
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
