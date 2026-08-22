-- ============================================================
-- keybinds.lua — Keyboard shortcuts (AZERTY layout)
-- ============================================================
-- Loaded last by hyprland.lua. Key symbols (ampersand, eacute, ...)
-- correspond to the characters produced by the number row on AZERTY, not
-- to physical keys 1-10.
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
-- Absolute path required: processes launched by Hyprland don't inherit
-- ~/.local/bin in their PATH (see commit bbb8f61).
hl.bind(mod .. "+ W",       hl.dsp.exec_cmd("$HOME/.local/bin/prisme"))

-- Power wheel, RPG weapon-menu style (LB/L1): pressing opens it and arms
-- the selection on the hovered sector, releasing (the `release` option,
-- equivalent to hyprlang's `bindr`) confirms immediately -- holding +
-- aiming with the mouse/arrows before releasing allows a deliberate
-- choice. A quick tap (release before aiming at anything) does NOT
-- execute the default sector: the wheel treats it as a cancel (see
-- roue-src/src/wheel.rs::activate_hovered) -- without this app-side
-- guard, any brief press would trigger Lock (first sector) instead of
-- just showing the wheel. Absolute path required, same reason as Prisme
-- above (commit bbb8f61).
hl.bind(mod .. "+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue power"))

-- Power profile wheel -- same press/release gesture as above. Before:
-- no keyboard shortcut, only the click on the waybar module
-- custom/performance (see waybar/config.jsonc). Its config is no longer a
-- static file either since the state band was added (see wheel.rs): which
-- profile is currently applied comes from power-profiles-daemon, so
-- `performance.sh roue-gen` regenerates wheels/powerprofile.toml on every
-- press, same principle as the display wheel below.
hl.bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("~/.config/waybar/scripts/performance.sh roue-gen && $HOME/.local/bin/roue powerprofile"))
hl.bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue powerprofile --commit"), { release = true })

-- Display layout wheel -- same press/release gesture, config regenerated
-- on every press like powerprofile above (never fixed in the repo, unlike
-- roue/wheels/power.toml): it depends on the hardware currently plugged
-- in (external screen present or not, its brand via EDID...), so
-- `display-layout.sh roue-gen` rewrites it on EVERY press right before
-- `roue display` opens (see its doc and cmd_roue_gen in
-- scripts/display-layout.sh). Replaces the old rofi menu
-- (`display-layout.sh menu`, still available if needed).
hl.bind(mod .. "+ O", hl.dsp.exec_cmd("~/.config/hypr/scripts/display-layout.sh roue-gen && $HOME/.local/bin/roue display"))
-- Zen/focus mode: was `pkill -SIGUSR1 waybar` (waybar's built-in
-- "toggle all bars" signal). quickshell has no such signal, so this
-- calls its own IPC handler instead (see quickshell/bar/shell.qml's
-- `zenMode` property / toggleZen()).
hl.bind(mod .. "+ Z",       hl.dsp.exec_cmd("qs -c bar ipc call bar toggleZen"))
hl.bind(mod .. "+ N",       hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-night-mode.sh"))
hl.bind(mod .. "+ I",       hl.dsp.exec_cmd("swaync-client -t -sw"))

-- ============================================================
-- WINDOWS
-- ============================================================
-- close (not kill): closes only the targeted window/tile. kill terminates
-- the whole process -- for a multi-window app (Firefox...), that would
-- close all of its windows instead of just the active one.
hl.bind(mod .. "+ Q", function()
    local w = hl.get_active_window()
    if w ~= nil then
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
    end
end)

hl.bind(mod .. "+ F",           hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. "+ SHIFT+ F",    hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(mod .. "+ P",           hl.dsp.window.pseudo())
-- Flips the active split's axis by hand (raw dwindle layoutmsg "togglesplit"
-- -- there's no hl.dsp.window.toggle_split(), this is the passthrough for
-- layout-specific messages). Needed now that smart_split is off and the axis
-- is picked from aspect ratio + preserve_split (see hyprland.lua): this is
-- the manual escape hatch for the rare case the ratio picks the wrong one.
hl.bind(mod .. "+ T",           hl.dsp.layout("togglesplit"))
hl.bind(mod .. "+ SHIFT+ Space", hl.dsp.window.float({ action = "toggle" }))

-- Move focus between windows (hjkl)
hl.bind(mod .. "+ H",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. "+ L",  hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. "+ K",  hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. "+ J",  hl.dsp.focus({ direction = "down" }))

-- Move the active window in the given direction
hl.bind(mod .. "+ SHIFT+ H",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. "+ SHIFT+ L",  hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. "+ SHIFT+ K",  hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. "+ SHIFT+ J",  hl.dsp.window.move({ direction = "down" }))

-- Resize submap: SUPER+R enters "resize", hjkl resizes in 5px steps,
-- Escape/Enter exits it.
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
-- WORKSPACES — number row in AZERTY layout
-- ============================================================
-- AZERTY key -> workspace number (1-10) mapping table, since physical
-- keys 1-10 produce non-numeric symbols on AZERTY (&, é, ", ', etc.).
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
    -- SUPER+key: switches focus to workspace n
    hl.bind(mod .. "+ " .. ws.key, hl.dsp.focus({ workspace = tostring(ws.n) }))

    -- SUPER+SHIFT+key: moves the active window to workspace n
    hl.bind(mod .. "+ SHIFT + " .. ws.key, hl.dsp.window.move({ workspace = tostring(ws.n) }))
end

-- Mouse wheel: navigates between workspaces on the monitor under the
-- cursor, never jumping to the neighboring screen. Routed through a
-- script (not the raw "m-1"/"m+1" selector) so it stays strictly bounded
-- to this monitor's own assigned range (1-5 or 6-10 -- see
-- workspace-manager.sh) instead of spilling into an unbound, unreachable
-- workspace 11+ once it runs past the last one that already exists here
-- (see scroll-workspace.sh's own header comment for the bug this fixes).
hl.bind(mod .. "+ mouse_down", hl.dsp.exec_cmd("~/.config/hypr/scripts/scroll-workspace.sh prev"))
hl.bind(mod .. "+ mouse_up",   hl.dsp.exec_cmd("~/.config/hypr/scripts/scroll-workspace.sh next"))

-- Compacts occupied workspaces toward the start of their range, per monitor
hl.bind(mod .. "+ C", hl.dsp.exec_cmd("~/.config/hypr/scripts/compact-workspaces.sh"))

-- Scratchpad (special "magic" workspace)
hl.bind(mod .. "+ U",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. "+ SHIFT+ U", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move/resize window with the mouse (buttons 8/9)
hl.bind(mod .. "+ mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. "+ mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- ============================================================
-- SYSTEM & MEDIA
-- ============================================================
hl.bind(mod .. "+ Escape",         hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. "+ SHIFT+ M",   hl.dsp.exit())
hl.bind(mod .. "+ SHIFT+ R",   hl.dsp.exec_cmd("hyprctl reload"))

-- Volume, mic and backlight: media keys, no modifier
hl.bind("+ XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("+ XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { repeating = true })
hl.bind("+ XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("+ XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })

hl.bind("+ XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { repeating = true })
hl.bind("+ XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { repeating = true })

hl.bind("+ XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("+ XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("+ XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })
