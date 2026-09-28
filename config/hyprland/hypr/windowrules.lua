-- ============================================================
-- windowrules.lua — Per-application rules
-- ============================================================
-- Syntax: hl.window_rule({ match = { ... }, effect = value, ... })
-- Rules are evaluated top to bottom — order matters! A more specific rule
-- placed after a general one can override it (see Steam and Lutris below).
-- ============================================================

-- ============================================================
-- WEZTERM
-- ============================================================
-- hl.window_rule({
--     match   = { class = "org.wezfurlong.wezterm" },
--     opacity = "0.95 override",
-- })

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
-- SCREENSHOT — Satty annotation tool
-- ============================================================
-- stay_focused removed: it doesn't just protect satty from losing focus,
-- it actively blocks any other window (including satty's own "Save As"
-- portal dialog, class=xdg-desktop-portal-gtk, see below) from acquiring
-- focus while satty is focused. That's why the save dialog opened but
-- input kept going back to satty instead of the dialog. A window takes
-- focus when it opens; the portal dialog rule's no_follow_mouse is what
-- keeps it there while the cursor wanders.
hl.window_rule({
    match   = { class = "com.gabm.satty" },
    float   = true,
    size    = "1200 780",
    center  = true,
    no_anim = true,
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
-- NEMO — main windows tile, secondary windows float
-- ============================================================
-- Why these are listed by name. The previous version split the two with
-- a negative lookahead, `^(?!.* — (Gestionnaire de fichiers|File
-- Manager))`, and Hyprland matches with RE2, which has no lookahead: the
-- rule never matched anything, so Properties, bookmarks and preferences
-- opened tiled, taking half the screen from the file view. Its
-- counterpart, "tile anything titled '… — Gestionnaire de fichiers'", was
-- dead too: Nemo titles a main window with the bare folder name.
--
-- Nothing else tells them apart from here: HL.Window exposes no parent
-- and no role, and a main window's title can be any folder name. What
-- Hyprland DOES do on its own is float every window that has a parent
-- (xdg_toplevel.set_parent) -- delete confirmations, copy conflicts,
-- "open with" -- and every fixed-size window, which covers the
-- file-operations progress window (Nemo makes it non-resizable; checked
-- on a real 100 000-file copy: floating with no rule at all, and just as
-- well, since its title at map time is already "36,5 Mo de 201,2 Mo", not
-- "Opérations de fichiers" -- no title rule could have caught it). So the
-- only ones left to name are Nemo's independent, resizable toplevels,
-- below. Titles are Nemo 6.6's own strings (src/*.c, gresources/*.glade)
-- in English and in its fr translation.
--
-- The patterns must cover the WHOLE title: Hyprland full-matches window
-- rule regexes (checked: "^Enregistrer" does not match "Enregistrer sous
-- - x", "^Enregistrer.*" does), so a bare prefix or suffix never fires.
--
-- initial_title, not title: a rule is evaluated when the window opens,
-- and Properties can retitle itself afterwards (a rename from inside it).
--
-- Main windows need no rule: tiling is the default.

-- Properties ("Propriétés de X" / "X Properties", or bare for several
-- files), bookmarks, preferences, connect-to-server, actions editor.
-- no_follow_mouse and no stay_focused: same reasoning as the universal
-- dialog rules further down.
local nemo_dialogs = {
    "^Propriétés( de .*)?$", "^(.* )?Properties$",
    "^Modifier les signets$", "^Edit Bookmarks$",
    "^Préférences du gestionnaire de fichiers$", "^File Management Preferences$",
    "^Se connecter au serveur$", "^Connect to Server$",
    "^Éditeur de disposition des actions de Nemo$", "^Nemo Actions Layout Editor$",
}
for _, t in ipairs(nemo_dialogs) do
    hl.window_rule({
        match           = { class = "nemo", initial_title = t },
        float           = true,
        center          = true,
        size            = "850 550",
        no_follow_mouse = true,
    })
end

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
-- Class is "org.mozilla.firefox" here (hyprctl clients), not "firefox".
-- Three rules keyed on "firefox" never matched anything: a forced
-- workspace 2 for every Firefox window, the main window tiled, and the
-- popups below. The first two were dropped rather than revived -- Firefox
-- goes wherever it is opened, as it always has in practice.
--
-- Popups: floating, centred. The pattern ends in ".*" because Hyprland
-- full-matches the title ("Informations sur la page – https://..."). No
-- stay_focused: see UNIVERSAL DIALOG BOXES at the end of this file.
hl.window_rule({
    match           = { class = "org.mozilla.firefox", title = "^(Password Required|Mot de passe requis|Page Info|Informations sur la page|S'identifier|Préférences|Preferences|Paramètres|Settings).*" },
    float           = true,
    center          = true,
    no_follow_mouse = true,
})

-- Library (history/bookmarks/downloads) — popup confirmed via hyprctl
-- clients: class="org.mozilla.firefox", title="Bibliothèque" (FR locale).
-- "Library" covers the official Mozilla English name for the same
-- window. Floating, centered, fixed size. No pin: it should follow the
-- current workspace rather than stay pinned to the screen. No
-- stay_focused: the downloads list stays open for a while, and pinning
-- focus to it locked out every other window (see UNIVERSAL DIALOG BOXES).
hl.window_rule({
    match           = { class = "org.mozilla.firefox", title = "^(Bibliothèque|Library)$" },
    float           = true,
    center          = true,
    size            = "900 650",
    no_follow_mouse = true,
})

-- ============================================================
-- STEAM & GAME LAUNCHERS (Lutris, Heroic)
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

-- ============================================================
-- UNIVERSAL DIALOG BOXES (XDG Portals, GTK, QT)
-- ============================================================
-- Generic safety net: targets any open/save dialog launched by Nemo or a
-- browser, whatever the toolkit.
-- no_follow_mouse on every rule here: without it, focus-follows-mouse
-- (input.follow_mouse = 1) hands focus back to the window under the
-- cursor as soon as it drifts off this dialog's tracked geometry
-- (dropdowns/breadcrumb popups, or just navigating near the edge) --
-- that was what made these dialogs lose focus while navigating and on
-- confirm/cancel. It is the whole fix; nothing else is needed.
--
-- No stay_focused, on purpose. It used to be here too, and it does not
-- "protect" a dialog, it PINS every input to it: with a save dialog open,
-- the screenshot bind's satty could not take focus and the Quickshell bar
-- stopped taking clicks. A new window is focused on open anyway, and
-- satty -- the one app that fought for it -- no longer has stay_focused
-- itself (see its rule above).
-- ".*" at the end is load-bearing: Hyprland full-matches the regex, and
-- without it this rule matched only a title that was exactly "Ouvrir",
-- "Save"... -- never "Enregistrer sous - Projet.pdf". Portal dialogs
-- still floated through the class rule below; toolkit-native ones
-- (a GTK app's own chooser) tiled.
hl.window_rule({ match = { title = "^(Ouvrir|Open|Enregistrer|Save|Choix|Select).*" }, float = true, center = true, no_follow_mouse = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true, center = true, no_follow_mouse = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-kde" }, float = true, center = true, no_follow_mouse = true })

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

-- ============================================================
-- ZATHURA — Liseuse's reading surface
-- ============================================================
-- The renderer behind Liseuse (SUPER+F, see config/liseuse/). Everything
-- here is in service of one thing: a page and nothing else.
--
-- opacity 1.0 override is not cosmetic. Global window opacity means the
-- desktop shows through the page, and a document recolored to near-pure
-- #1c1c1e/#e5e5ea (zathurarc's recolor) is precisely the content where a
-- few percent of a wallpaper bleeding through destroys the contrast the
-- recolor exists to create. Same reason Firefox has this rule.
--
-- No `fullscreen` here any more, and that is deliberate. It used to be
-- forced on every zathura window, which is right for a deck of slides
-- and wrong for most of what gets read here -- a reference PDF beside an
-- editor, a handout being copied from, two documents compared -- and it
-- covers the bar, so nothing on screen could say which document had
-- focus or what page it was on. Liseuse briefly took the decision over
-- (fullscreen the first book, tile the second); it now takes no decision
-- at all. A book opens as an ordinary window and SUPER+SHIFT+F is the
-- one thing that changes that, which is what a mode should be.
--
-- no_blur: the window is opaque, so there is nothing to blur behind it
-- -- the pass would cost GPU time per frame for a result no one can see,
-- which matters on battery for something held open for an hour.
hl.window_rule({
    match      = { class = "org.pwmt.zathura" },
    opacity = "1.0 override",
    no_blur = true,
})

-- ============================================================
-- LAYER BLUR — Roue
-- ============================================================
-- Real compositor blur behind this specific layer-shell surface, not a
-- global effect (see hyprland.lua's decoration.blur.enabled comment for
-- the full reasoning): a small, on-demand panel, visible for seconds at a
-- time, unlike the always-on bar (quickshell layer, deliberately left
-- with no rule here -- opts out simply by omission, layers don't get
-- blur unless a rule says so). Balise (the WiFi/BT/Ethernet panel) cycled
-- through a blur rule here more than once and settled on NOT having one
-- -- its "glass" read is built entirely from color/gradient in
-- balise/style.css (a gradient fill on .balise-panel-inner instead of a
-- flat one, alongside the border/button treatment already there), not
-- compositor blur.
--
-- swaync's control-center used to have a rule here too (namespace
-- swaync-control-center, xray + ignore_alpha to confine blur to its
-- actually-opaque panel despite an oversized full-screen click-catching
-- surface behind it) -- gone along with swaync itself. Its quickshell
-- replacement (NotificationCenter.qml) closes via a HyprlandFocusGrab
-- instead of that oversized surface, so its layer is already sized to
-- its real visible bounds and never needed this hack.
--
-- Roue: anchored to all 4 edges (see roue-src/src/main.rs), so it's in
-- the same "oversized surface" situation swaync's control-center used to
-- be in (see above), unlike Balise (an anchored corner panel) -- same
-- xray + ignore_alpha treatment, needed for the exact same reason
-- (confirmed live: without it the whole screen blurs, not just the wheel
-- + sidebar). On-demand, shown for seconds at a time -- see
-- hyprland.lua's decoration.blur.enabled comment.
hl.layer_rule({ match = { namespace = "roue" },                 blur = true, xray = true, ignore_alpha = 0.5 })

-- ============================================================
-- LAYER FADE — awww wallpaper
-- ============================================================
-- The `layers` animation (hyprland.lua) has no explicit style, so every
-- layer slides in from its nearest edge -- right for rofi or the bar,
-- wrong for a full-screen wallpaper, which should never look like it's
-- moving. Only this layer is switched to a plain fade: at session start
-- the wallpaper rises out of the black misc:background_color instead of
-- popping or sliding in. Speed and curve stay those of the `layers` leaf.
hl.layer_rule({ match = { namespace = "^awww-daemon$" },        animation = "fade" })
