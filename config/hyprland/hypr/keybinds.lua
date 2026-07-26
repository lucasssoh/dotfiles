-- ============================================================
-- keybinds.lua — Raccourcis clavier (disposition AZERTY)
-- ============================================================
-- Chargé en dernier par hyprland.lua. Les symboles de touches (ampersand,
-- eacute, ...) correspondent aux caractères produits par la rangée de
-- chiffres en AZERTY, pas aux touches physiques 1-10.
-- ============================================================

local mod = "SUPER"

-- ============================================================
-- APPLICATIONS
-- ============================================================
hl.bind(mod .. "+ Return",  hl.dsp.exec_cmd("wezterm"))
hl.bind(mod .. "+ E",       hl.dsp.exec_cmd("nemo"))
hl.bind(mod .. "+ B",       hl.dsp.exec_cmd("firefox"))
hl.bind(mod .. "+ Space",   hl.dsp.exec_cmd("fuzzel"))
hl.bind(mod .. "+ V",       hl.dsp.exec_cmd("cliphist list | rofi -dmenu -theme ~/.config/rofi/launcher.rasi | cliphist decode | wl-copy"))
hl.bind(mod .. "+SHIFT+ S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | satty --filename - --fullscreen --output-filename - | wl-copy"))
hl.bind(mod .. "+ S",       hl.dsp.exec_cmd("grim - | satty --filename - --fullscreen --output-filename - | wl-copy"))
-- Chemin absolu obligatoire : les processus lancés par Hyprland n'héritent
-- pas de ~/.local/bin dans leur PATH (cf. commit bbb8f61).
hl.bind(mod .. "+ W",       hl.dsp.exec_cmd("$HOME/.local/bin/prisme"))
hl.bind(mod .. "+ O",       hl.dsp.exec_cmd("~/.config/hypr/scripts/display-layout.sh menu"))

-- Roue d'alimentation, façon menu d'arme RPG (LB/L1) : l'appui ouvre et
-- arme la sélection sur le secteur survolé, le relâchement (option
-- `release`, équivalent du `bindr` hyprlang) valide immédiatement --
-- maintenir + viser à la souris/aux flèches avant de relâcher permet un
-- choix délibéré. Un tap rapide (relâchement avant d'avoir visé quoi que ce
-- soit) N'exécute PAS le secteur par défaut : la roue l'interprète comme une
-- annulation (cf. roue-src/src/wheel.rs::activate_hovered) -- sans ce
-- garde-fou côté appli, tout appui bref déclenchait Verrouiller (premier
-- secteur) au lieu de simplement (ne rien) afficher. Chemin absolu
-- obligatoire, même raison que Prisme ci-dessus (commit bbb8f61).
hl.bind(mod .. "+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue power"))
hl.bind(mod .. "+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue power --commit"), { release = true })

-- Roue de profil d'énergie -- même geste appui/relâchement que ci-dessus.
-- Avant : aucun raccourci clavier, uniquement le clic sur le module waybar
-- custom/performance (cf. waybar/config.jsonc).
hl.bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue powerprofile"))
hl.bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue powerprofile --commit"), { release = true })
hl.bind(mod .. "+ Z",       hl.dsp.exec_cmd("pkill -SIGUSR1 waybar"))
hl.bind(mod .. "+ N",       hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-night-mode.sh"))
hl.bind(mod .. "+ I",       hl.dsp.exec_cmd("swaync-client -t -sw"))

-- ============================================================
-- FENÊTRES
-- ============================================================
-- close (et non kill) : ferme uniquement la fenêtre/tuile visée. kill
-- tue le processus entier — pour une appli multi-fenêtres (Firefox...),
-- ça fermerait toutes ses fenêtres au lieu de la seule fenêtre active.
hl.bind(mod .. "+ Q", function()
    local w = hl.get_active_window()
    if w ~= nil then
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
    end
end)

hl.bind(mod .. "+ F",           hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. "+ SHIFT+ F",    hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(mod .. "+ P",           hl.dsp.window.pseudo())
--[[ hl.bind(mod .. "+ T",           hl.dsp.window.toggle_split()) ]]
hl.bind(mod .. "+ SHIFT+ Space", hl.dsp.window.float({ action = "toggle" }))

-- Déplacement du focus entre fenêtres (hjkl)
hl.bind(mod .. "+ H",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. "+ L",  hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. "+ K",  hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. "+ J",  hl.dsp.focus({ direction = "down" }))

-- Déplacement de la fenêtre active dans la direction indiquée
hl.bind(mod .. "+ SHIFT+ H",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. "+ SHIFT+ L",  hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. "+ SHIFT+ K",  hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. "+ SHIFT+ J",  hl.dsp.window.move({ direction = "down" }))

-- Submap de redimensionnement : SUPER+R entre dans "resize", hjkl
-- redimensionne par pas de 5px, Escape/Entrée en sort.
hl.bind(mod .. "+ R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("+ H",      hl.dsp.window.resize({ x = -5, y = 0,  relative = true }), { repeating = true })
    hl.bind("+ L",      hl.dsp.window.resize({ x =  5, y = 0,  relative = true }), { repeating = true })
    hl.bind("+ K",      hl.dsp.window.resize({ x = 0,  y = -5, relative = true }), { repeating = true })
    hl.bind("+ J",      hl.dsp.window.resize({ x = 0,  y =  5, relative = true }), { repeating = true })
    hl.bind("+ Escape", hl.dsp.submap("reset"))
    hl.bind("+ Return", hl.dsp.submap("reset"))
end)

-- ============================================================
-- WORKSPACES — rangée de chiffres en disposition AZERTY
-- ============================================================
-- Table de correspondance touche AZERTY → numéro de workspace (1-10),
-- car les touches physiques 1-10 produisent des symboles non numériques
-- en AZERTY (&, é, ", ', etc.).
local ws_keys = {
    { key = "ampersand",  n = 1  },
    { key = "eacute",     n = 2  },
    { key = "quotedbl",   n = 3  },
    { key = "apostrophe", n = 4  },
    { key = "parenleft",  n = 5  },
    { key = "minus",      n = 6  },
    { key = "egrave",     n = 7  },
    { key = "underscore", n = 8  },
    { key = "ccedilla",   n = 9  },
    { key = "agrave",     n = 10 },
}

for _, ws in ipairs(ws_keys) do
    -- SUPER+touche : bascule le focus vers le workspace n
    hl.bind(mod .. "+ " .. ws.key, hl.dsp.focus({ workspace = tostring(ws.n) }))

    -- SUPER+SHIFT+touche : déplace la fenêtre active vers le workspace n
    hl.bind(mod .. "+ SHIFT + " .. ws.key, hl.dsp.window.move({ workspace = tostring(ws.n) }))
end

-- Molette souris : navigue entre workspaces relatifs au moniteur sous le
-- curseur (m-1/m+1), sans jamais sauter sur l'écran voisin contrairement
-- à un simple offset global (e-1/e+1).
hl.bind(mod .. "+ mouse_down", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mod .. "+ mouse_up",   hl.dsp.focus({ workspace = "m+1" }))

-- Compacte les workspaces occupés vers le début de leur plage, par moniteur
hl.bind(mod .. "+ C", hl.dsp.exec_cmd("~/.config/hypr/scripts/compact-workspaces.sh"))

-- Scratchpad (workspace spécial "magic")
hl.bind(mod .. "+ U",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. "+ SHIFT+ U", hl.dsp.window.move({ workspace = "special:magic" }))

-- Déplacement/redimensionnement de fenêtre à la souris (boutons 8/9)
hl.bind(mod .. "+ mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. "+ mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- ============================================================
-- SYSTÈME & MÉDIA
-- ============================================================
hl.bind(mod .. "+ Escape",         hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. "+ SHIFT+ M",   hl.dsp.exit())
hl.bind(mod .. "+ SHIFT+ R",   hl.dsp.exec_cmd("hyprctl reload"))

-- Volume, micro et rétroéclairage : touches multimédia, sans modificateur
hl.bind("+ XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("+ XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { repeating = true })
hl.bind("+ XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("+ XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })

hl.bind("+ XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { repeating = true })
hl.bind("+ XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { repeating = true })

hl.bind("+ XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("+ XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("+ XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })
