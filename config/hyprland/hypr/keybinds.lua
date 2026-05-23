-- ============================================================
-- KEYBINDS.LUA — Raccourcis clavier (layout AZERTY)
-- ============================================================

local mod = "SUPER"

-- ============================================================
-- APPLICATIONS
-- ============================================================
hl.bind(mod .. "+ Return",  hl.dsp.exec_cmd("wezterm"))
hl.bind(mod .. "+ E",       hl.dsp.exec_cmd("thunar"))
hl.bind(mod .. "+ B",       hl.dsp.exec_cmd("firefox"))
hl.bind(mod .. "+ Space",   hl.dsp.exec_cmd("fuzzel"))
hl.bind(mod .. "+ V",       hl.dsp.exec_cmd("cliphist list | rofi -dmenu -theme ~/.config/rofi/launcher.rasi | cliphist decode | wl-copy"))
hl.bind(mod .. "+SHIFT+ S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | satty --filename - --fullscreen --output-filename - | wl-copy"))
hl.bind(mod .. "+ S",       hl.dsp.exec_cmd("grim - | satty --filename - --fullscreen --output-filename - | wl-copy"))hl.bind(mod .. "+ W",       hl.dsp.exec_cmd("dex $HOME/.local/share/applications/set_wallpaper.desktop || gtk-launch set_wallpaper"))

hl.bind(mod .. "+ Delete",  hl.dsp.exec_cmd("~/.config/waybar/scripts/rofi-power.sh"))
hl.bind(mod .. "+ Z",       hl.dsp.exec_cmd("pkill -SIGUSR1 waybar"))
hl.bind(mod .. "+ N",       hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-night-mode.sh"))
-- ============================================================
-- FENÊTRES
-- ============================================================
hl.bind(mod .. "+ Q",           hl.dsp.window.kill())
hl.bind(mod .. "+ F",           hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. "+ SHIFT+ F",    hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(mod .. "+ P",           hl.dsp.window.pseudo())
--[[ hl.bind(mod .. "+ T",           hl.dsp.window.toggle_split()) ]]
hl.bind(mod .. "+ SHIFT+ Space", hl.dsp.window.float({ action = "toggle" }))

-- Focus (hjkl)
hl.bind(mod .. "+ H",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. "+ L",  hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. "+ K",  hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. "+ J",  hl.dsp.focus({ direction = "down" }))

-- Déplacer fenêtre
hl.bind(mod .. "+ SHIFT+ H",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. "+ SHIFT+ L",  hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. "+ SHIFT+ K",  hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. "+ SHIFT+ J",  hl.dsp.window.move({ direction = "down" }))

-- Submap resize corrigée
hl.bind(mod .. "+ R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    -- On utilise hl.dsp.window.resize
    hl.bind("+ H",      hl.dsp.window.resize({ x = -5, y = 0,  relative = true }), { repeating = true })
    hl.bind("+ L",      hl.dsp.window.resize({ x =  5, y = 0,  relative = true }), { repeating = true })
    hl.bind("+ K",      hl.dsp.window.resize({ x = 0,  y = -5, relative = true }), { repeating = true })
    hl.bind("+ J",      hl.dsp.window.resize({ x = 0,  y =  5, relative = true }), { repeating = true })
    hl.bind("+ Escape", hl.dsp.submap("reset"))
    hl.bind("+ Return", hl.dsp.submap("reset"))
end)

-- ============================================================
-- WORKSPACES — rangée de chiffres AZERTY
-- ============================================================
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
    -- Pour changer de workspace (focus)
    hl.bind(mod .. "+ " .. ws.key, hl.dsp.focus({ workspace = tostring(ws.n) }))

    -- Pour déplacer la fenêtre active vers un workspace
    hl.bind(mod .. "+ SHIFT + " .. ws.key, hl.dsp.window.move({ workspace = tostring(ws.n) }))
end

-- Scroll souris pour les workspaces relatifs
hl.bind(mod .. "+ mouse_down", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. "+ mouse_up",   hl.dsp.focus({ workspace = "e+1" }))

-- Scratchpad
hl.bind(mod .. "+ U",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. "+ SHIFT+ U", hl.dsp.window.move({ workspace = "special:magic" }))

-- Souris (grab)
hl.bind(mod .. "+ mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. "+ mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- ============================================================
-- SYSTÈME & MÉDIA
-- ============================================================
hl.bind(mod .. "+ Escape",         hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. "+ SHIFT+ M",   hl.dsp.exit())
hl.bind(mod .. "+ SHIFT+ R",   hl.dsp.exec_cmd("hyprctl reload"))

hl.bind("+ XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("+ XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { repeating = true })
hl.bind("+ XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("+ XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })

hl.bind("+ XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { repeating = true })
hl.bind("+ XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { repeating = true })

hl.bind("+ XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("+ XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("+ XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })
