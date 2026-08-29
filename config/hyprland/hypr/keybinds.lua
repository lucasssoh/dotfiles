-- ============================================================
-- keybinds.lua — Keyboard shortcuts (AZERTY layout)
-- ============================================================
-- Loaded last by hyprland.lua. Key symbols (ampersand, eacute, ...)
-- correspond to the characters produced by the number row on AZERTY, not
-- to physical keys 1-10.
-- ============================================================

local mod = "SUPER"

-- ============================================================
-- Keybinds cheatsheet dismissal
-- ============================================================
-- `bind` is used in place of `hl.bind` throughout this file. It registers
-- the bind exactly as hl.bind would, UNCHANGED, and then registers a
-- second, non-consuming bind on the same combo that tells the bar to
-- hide the keybinds cheatsheet (see quickshell/bar/shell.qml).
--
-- Why this exists: the cheatsheet appears on a long SUPER hold and is
-- meant to disappear when SUPER comes back up, but Hyprland deliberately
-- suppresses a modifier's release bind once another key was pressed
-- during the hold -- that suppression is what stops tap-to-launch
-- bindings firing at the end of every SUPER+... combo. So after
-- SUPER+Space or SUPER+H the release never arrives and the sheet just
-- sits there. Watching Hyprland's event stream instead only covers part
-- of it: fuzzel and rofi are layer surfaces and emit no window event at
-- all, and moving a window within its workspace emits nothing either.
-- The binds themselves are the only signal that sees every case.
--
-- Registered as a SEPARATE bind rather than by wrapping the original
-- action on purpose: every existing bind here still reaches Hyprland
-- byte for byte as it did before, so a mistake in this block can leave a
-- stray `qs ipc call` behind but cannot break a shortcut.
--
-- Skipped for: anything not prefixed with SUPER (media keys, submap
-- binds -- they can't follow a SUPER hold), the Super_L binds themselves
-- (they already manage this state), and mouse binds (drag/resize rely on
-- their own press/release handling; not worth perturbing for this).
local hl_bind = hl.bind
local function bind(key, action, opts)
    hl_bind(key, action, opts)

    local eligible = type(key) == "string"
        and key:sub(1, #mod) == mod
        and not key:find("Super_L", 1, true)
        and not (opts ~= nil and opts.mouse)
    if eligible then
        hl_bind(key, hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsHide"),
                { non_consuming = true })
    end
end

-- ============================================================
-- APPLICATIONS
-- ============================================================
bind(mod .. "+ Return",  hl.dsp.exec_cmd("wezterm"))
bind(mod .. "+ E",       hl.dsp.exec_cmd("nemo"))
bind(mod .. "+ B",       hl.dsp.exec_cmd("firefox"))
bind(mod .. "+ Space",   hl.dsp.exec_cmd("fuzzel"))
bind(mod .. "+ V",       hl.dsp.exec_cmd("cliphist list | rofi -dmenu -theme ~/.config/rofi/launcher.rasi | cliphist decode | wl-copy"))
bind(mod .. "+SHIFT+ S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | satty --filename - --fullscreen --output-filename - | wl-copy"))
bind(mod .. "+ S",       hl.dsp.exec_cmd("grim - | satty --filename - --fullscreen --output-filename - | wl-copy"))
-- Absolute path required: processes launched by Hyprland don't inherit
-- ~/.local/bin in their PATH (see commit bbb8f61).
bind(mod .. "+ W",       hl.dsp.exec_cmd("$HOME/.local/bin/prisme"))

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
bind(mod .. "+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue power"))

-- Power profile wheel -- same press/release gesture as above. Before:
-- no keyboard shortcut, only the click on the waybar module
-- custom/performance (see waybar/config.jsonc). Its config is no longer a
-- static file either since the state band was added (see wheel.rs): which
-- profile is currently applied comes from power-profiles-daemon, so
-- `performance.sh roue-gen` regenerates wheels/powerprofile.toml on every
-- press, same principle as the display wheel below.
bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("~/.config/waybar/scripts/performance.sh roue-gen && $HOME/.local/bin/roue powerprofile"))
bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue powerprofile --commit"), { release = true })

-- Display layout wheel -- same press/release gesture, config regenerated
-- on every press like powerprofile above (never fixed in the repo, unlike
-- roue/wheels/power.toml): it depends on the hardware currently plugged
-- in (external screen present or not, its brand via EDID...), so
-- `display-layout.sh roue-gen` rewrites it on EVERY press right before
-- `roue display` opens (see its doc and cmd_roue_gen in
-- scripts/display-layout.sh). Replaces the old rofi menu
-- (`display-layout.sh menu`, still available if needed).
bind(mod .. "+ O", hl.dsp.exec_cmd("~/.config/hypr/scripts/display-layout.sh roue-gen && $HOME/.local/bin/roue display"))
-- Zen/focus mode: was `pkill -SIGUSR1 waybar` (waybar's built-in
-- "toggle all bars" signal). quickshell has no such signal, so this
-- calls its own IPC handler instead (see quickshell/bar/shell.qml's
-- `zenMode` property / toggleZen()).
bind(mod .. "+ Z",       hl.dsp.exec_cmd("qs -c bar ipc call bar toggleZen"))
bind(mod .. "+ N",       hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-night-mode.sh"))
bind(mod .. "+ I",       hl.dsp.exec_cmd("swaync-client -t -sw"))

-- ============================================================
-- WINDOWS
-- ============================================================
-- close (not kill): closes only the targeted window/tile. kill terminates
-- the whole process -- for a multi-window app (Firefox...), that would
-- close all of its windows instead of just the active one.
bind(mod .. "+ Q", function()
    local w = hl.get_active_window()
    if w ~= nil then
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
    end
end)

bind(mod .. "+ F",           hl.dsp.window.fullscreen({ mode = 0 }))
bind(mod .. "+ SHIFT+ F",    hl.dsp.window.fullscreen({ mode = 1 }))
bind(mod .. "+ P",           hl.dsp.window.pseudo())
-- Flips the active split's axis by hand (raw dwindle layoutmsg "togglesplit"
-- -- there's no hl.dsp.window.toggle_split(), this is the passthrough for
-- layout-specific messages). Needed now that smart_split is off and the axis
-- is picked from aspect ratio + preserve_split (see hyprland.lua): this is
-- the manual escape hatch for the rare case the ratio picks the wrong one.
bind(mod .. "+ T",           hl.dsp.layout("togglesplit"))
bind(mod .. "+ SHIFT+ Space", hl.dsp.window.float({ action = "toggle" }))

-- Move focus between windows (hjkl)
bind(mod .. "+ H",  hl.dsp.focus({ direction = "left" }))
bind(mod .. "+ L",  hl.dsp.focus({ direction = "right" }))
bind(mod .. "+ K",  hl.dsp.focus({ direction = "up" }))
bind(mod .. "+ J",  hl.dsp.focus({ direction = "down" }))

-- Move the active window in the given direction
bind(mod .. "+ SHIFT+ H",  hl.dsp.window.move({ direction = "left" }))
bind(mod .. "+ SHIFT+ L",  hl.dsp.window.move({ direction = "right" }))
bind(mod .. "+ SHIFT+ K",  hl.dsp.window.move({ direction = "up" }))
bind(mod .. "+ SHIFT+ J",  hl.dsp.window.move({ direction = "down" }))

-- Resize submap: SUPER+R enters "resize", hjkl resizes in 5px steps,
-- Escape/Enter exits it.
bind(mod .. "+ R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    bind("+ H",      hl.dsp.window.resize({ x = -5, y = 0,  relative = true }), { repeating = true })
    bind("+ L",      hl.dsp.window.resize({ x =  5, y = 0,  relative = true }), { repeating = true })
    bind("+ K",      hl.dsp.window.resize({ x = 0,  y = -5, relative = true }), { repeating = true })
    bind("+ J",      hl.dsp.window.resize({ x = 0,  y =  5, relative = true }), { repeating = true })
    bind("+ Escape", hl.dsp.submap("reset"))
    bind("+ Return", hl.dsp.submap("reset"))
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
    bind(mod .. "+ " .. ws.key, hl.dsp.focus({ workspace = tostring(ws.n) }))

    -- SUPER+SHIFT+key: moves the active window to workspace n
    bind(mod .. "+ SHIFT + " .. ws.key, hl.dsp.window.move({ workspace = tostring(ws.n) }))
end

-- Mouse wheel: navigates between workspaces on the monitor under the
-- cursor, never jumping to the neighboring screen. Routed through a
-- script (not the raw "m-1"/"m+1" selector) so it stays strictly bounded
-- to this monitor's own assigned range (1-5 or 6-10 -- see
-- workspace-manager.sh) instead of spilling into an unbound, unreachable
-- workspace 11+ once it runs past the last one that already exists here
-- (see scroll-workspace.sh's own header comment for the bug this fixes).
bind(mod .. "+ mouse_down", hl.dsp.exec_cmd("~/.config/hypr/scripts/scroll-workspace.sh prev"))
bind(mod .. "+ mouse_up",   hl.dsp.exec_cmd("~/.config/hypr/scripts/scroll-workspace.sh next"))

-- Compacts occupied workspaces toward the start of their range, per monitor
bind(mod .. "+ C", hl.dsp.exec_cmd("~/.config/hypr/scripts/compact-workspaces.sh"))

-- Scratchpad (special "magic" workspace)
bind(mod .. "+ U",         hl.dsp.workspace.toggle_special("magic"))
bind(mod .. "+ SHIFT+ U", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move/resize window with the mouse (buttons 8/9)
bind(mod .. "+ mouse:272",  hl.dsp.window.drag(),   { mouse = true })
bind(mod .. "+ mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- ============================================================
-- SYSTEM & MEDIA
-- ============================================================
bind(mod .. "+ Escape",         hl.dsp.exec_cmd("hyprlock"))
bind(mod .. "+ SHIFT+ M",   hl.dsp.exit())
bind(mod .. "+ SHIFT+ R",   hl.dsp.exec_cmd("hyprctl reload"))

-- Volume, mic and backlight: media keys, no modifier
-- -l 1.0: hard-capped at 100%, never boosts past it -- the previous 1.5
-- (150%) headroom went unused and asked to come out.
bind("+ XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
bind("+ XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { repeating = true })
bind("+ XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
bind("+ XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })

-- brightnessctl has no DBus/kernel push the bar's OSD can react to on its
-- own (unlike volume/mic, pure Pipewire push -- see
-- quickshell/bar/services/OsdState.qml's header for why), so the bind
-- itself pokes the bar over IPC right after setting the level.
bind("+ XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+ && quickshell ipc -c bar call bar pokeBrightness"), { repeating = true })
bind("+ XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%- && quickshell ipc -c bar call bar pokeBrightness"), { repeating = true })

bind("+ XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("+ XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
bind("+ XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })

-- ============================================================
-- HELP
-- ============================================================
-- Keybinds cheatsheet: HOLDING SUPER ("Super_L" is the bare left-Super
-- keysym, not `mod` used as a modifier prefix) drops it into the bar's
-- central island in place of the clock, releasing hides it again (see
-- quickshell/bar/shell.qml's keybindsVisible / KeybindsDrawerContent.qml).
-- Same press/release gesture pairing as the power/profile/display wheels
-- above (the `release` option, hyprlang's `bindr`).
--
-- `long_press` (verified against `hyprctl binds -j`, which reports the
-- flag back as longPress: true -- NOT the camelCase spelling, which is
-- silently ignored) is what makes this a HOLD rather than a press: on a
-- quick tap Hyprland emits NO event here at all. That matters twice
-- over. First, Super_L goes down at the start of EVERY other SUPER+...
-- bind in this file, so a plain press bind would fire the sheet on all
-- of them. Second, these two binds are two INDEPENDENT process spawns
-- (`qs ... ipc call`, ~100ms each) with no ordering guarantee between
-- them: on a tap, both fire at once and the release can easily land
-- BEFORE the press, leaving the sheet stuck open with the key already
-- up. Not emitting the press at all on a tap removes that race at the
-- source (shell.qml keeps a small guard for the remaining case -- a
-- release immediately after the threshold). Hyprland's long-press
-- threshold is fixed (there is no binds:long_press_delay option in
-- 0.56.2), so the rest of the delay lives on the quickshell side where
-- it can actually be tuned: shell.qml's keybindsHoldDelay.
--
-- `non_consuming` on both so binding the bare Super key changes nothing
-- about Super's normal job as the modifier prefix for everything else
-- here -- the key events still reach the focused client as usual.
bind("+ Super_L", hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsPress"),
        { long_press = true, non_consuming = true })

-- The release is registered under BOTH modmasks, and that is not
-- redundant. A bind matches on the modifier state at the moment the
-- event fires, and for the modifier key itself that state differs
-- between its own two edges: SUPER is not yet applied when it goes
-- DOWN (modmask 0, what the long-press bind above matches), but is
-- still applied while it comes back UP -- so a release bind registered
-- at modmask 0 alone never matches, which is exactly the "it opens but
-- letting go doesn't close it" symptom. Which of the two Hyprland
-- actually delivers is a compositor-internal ordering detail, so both
-- are registered rather than betting on one; firing both is harmless,
-- keybindsRelease is idempotent (disarm the timer, hide).
bind("+ Super_L", hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsRelease"),
        { release = true, non_consuming = true })
bind(mod .. "+ Super_L", hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsRelease"),
        { release = true, non_consuming = true })


