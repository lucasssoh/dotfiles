-- ============================================================
-- keybinds.lua — Keyboard shortcuts
-- ============================================================
-- Loaded last by hyprland.lua. Letters are bound by keysym (they follow
-- the layout: SUPER+H is wherever H is), the workspace row by keycode
-- (it stays the top row whatever that row prints -- see WORKSPACES).
--
-- Every bind that belongs on the keybinds sheet carries a `description`:
-- that string is what the sheet prints on the key, and the list of them
-- is exported at the bottom of this file. This file is the only place a
-- shortcut or its label is written down.
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
-- of it: fuzzel is a layer surface and emits no window event at
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

-- The keybinds sheet's source: every bind given a `description` in its
-- opts, as {mods = {...}, key = "H", description = "Focus ←"}. Written
-- out as JSON at the bottom of this file, where quickshell's
-- KeybindsState.qml picks it up. Not read back from `hyprctl binds -j`:
-- that reports a `code:NN` bind with an empty key and keycode 0 (0.56.2
-- keeps a Lua bind's keycode in its multi-key list, which the JSON does
-- not print), so the whole workspace row would vanish from the sheet.
local cheatsheet = {}

local function bind(key, action, opts)
    hl_bind(key, action, opts)

    if opts ~= nil and opts.description ~= nil then
        local parts = {}
        for part in key:gmatch("[^+]+") do
            parts[#parts + 1] = part:match("^%s*(.-)%s*$")
        end
        local sym = table.remove(parts)
        cheatsheet[#cheatsheet + 1] = { mods = parts, key = sym, description = opts.description }
    end

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
-- Roles, not binaries: the user's terminal, browser and file manager
-- (scripts/coucou-open; WezTerm when no terminal preference is set).
local open = "~/.config/hypr/scripts/coucou-open "
bind(mod .. "+ Return",  hl.dsp.exec_cmd(open .. "terminal"), { description = "Terminal" })
bind(mod .. "+ E",       hl.dsp.exec_cmd(open .. "files"), { description = "Files" })
bind(mod .. "+ B",       hl.dsp.exec_cmd(open .. "browser"), { description = "Browser" })
bind(mod .. "+ Space",   hl.dsp.exec_cmd("fuzzel"), { description = "Launcher" })
-- Clipboard history: fuzzel shows the text column, returns the whole
-- "id<TAB>text" line that cliphist decode expects.
bind(mod .. "+ V",       hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu --with-nth=2 --only-match --prompt='Clipboard  ' | cliphist decode | wl-copy"), { description = "Clipboard" })
bind(mod .. "+SHIFT+ S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | satty --filename - --fullscreen --output-filename - | wl-copy"), { description = "Region" })
bind(mod .. "+ S",       hl.dsp.exec_cmd("grim - | satty --filename - --fullscreen --output-filename - | wl-copy"), { description = "Capture" })
-- Absolute path required: processes launched by Hyprland don't inherit
-- ~/.local/bin in their PATH (see commit bbb8f61).
bind(mod .. "+ W",       hl.dsp.exec_cmd("$HOME/.local/bin/prisme"), { description = "Wallpaper" })

-- Agenda: add an event (or delete one) through fuzzel, stored in khal;
-- the bar's calendar drawer shows it and rings its reminders.
bind(mod .. "+ A",       hl.dsp.exec_cmd("~/.config/hypr/scripts/agenda.py"), { description = "Agenda" })

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
bind(mod .. "+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue power"), { description = "Power" })

-- Power profile wheel -- same press/release gesture as above. Before:
-- no keyboard shortcut, only the click on the waybar module
-- custom/performance (see waybar/config.jsonc). Its config is no longer a
-- static file either since the state band was added (see wheel.rs): which
-- profile is currently applied comes from power-profiles-daemon, so
-- `performance.sh roue-gen` regenerates wheels/powerprofile.toml on every
-- press, same principle as the display wheel below.
bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("~/.config/hypr/scripts/performance.sh roue-gen && $HOME/.local/bin/roue powerprofile"), { description = "Power profile" })
bind(mod .. "+ SHIFT+ Delete", hl.dsp.exec_cmd("$HOME/.local/bin/roue powerprofile --commit"), { release = true })

-- Display layout wheel -- same press/release gesture, config regenerated
-- on every press like powerprofile above (never fixed in the repo, unlike
-- roue/wheels/power.toml): it depends on the hardware currently plugged
-- in (external screen present or not, its brand via EDID...), so
-- `display-layout.sh roue-gen` rewrites it on EVERY press right before
-- `roue display` opens (see its doc and cmd_roue_gen in
-- scripts/display-layout.sh).
bind(mod .. "+ O", hl.dsp.exec_cmd("~/.config/hypr/scripts/display-layout.sh roue-gen && $HOME/.local/bin/roue display"), { description = "Display" })

-- Actions wheel -- the Copilot key. This machine's firmware sends it as a
-- fixed chord, not as a key of its own (libinput debug-events, Lenovo 83V6):
--
--   +0.000s  KEY_LEFTMETA (125) pressed
--   +0.001s  KEY_LEFTSHIFT (42) pressed
--   +0.001s  KEY_F23 (193) pressed
--   +0.058s  KEY_F23 (193) released
--
-- so the binding target is SUPER+SHIFT+F23, and nothing else in this file
-- touches F13-F24, so it collides with nothing.
--
-- No `release` half here, unlike EVERY other roue bind above, and that is
-- forced by the capture rather than a preference: F23 comes back UP after
-- ~58ms no matter how long the key is physically held down, so there is no
-- hold to aim during and no meaningful release edge to confirm on. The
-- wheel therefore opens and STAYS open; confirming is click / Enter /
-- arrows, which roue already supports on equal footing with the release
-- gesture (see roue-src/src/main.rs, the GestureClick and the
-- "Mouse / <-> aim, Enter / click confirm" hint it draws).
--
-- `--toggle` is what closes it again with the same key. It is a roue flag,
-- not a shell trick around it: a second `roue actions` while the first is
-- open is already routed into the running instance over D-Bus (same path
-- as the `--commit` on the powerprofile bind above), and --toggle makes
-- that arriving press cancel instead of re-presenting the window. Nothing
-- to pgrep, nothing to pkill, no race between a test and a launch -- and
-- the other wheels are untouched, since without the flag a second press
-- still just raises them.
--
-- Side effect worth knowing about, harmless: LEFTMETA going down and back
-- up makes the Super_L release bind at the bottom of this file fire a
-- `keybindsRelease` on every press of this key. The 58ms chord is far too
-- short to have opened the cheatsheet via the long_press bind, and
-- keybindsRelease is idempotent (disarm the timer, hide), so this costs one
-- short-lived process and changes nothing on screen.
bind(mod .. "+ SHIFT+ F23", hl.dsp.exec_cmd("$HOME/.local/bin/roue actions --toggle"), { description = "Actions" })
-- Zen/focus mode: was `pkill -SIGUSR1 waybar` (waybar's built-in
-- "toggle all bars" signal). quickshell has no such signal, so this
-- calls its own IPC handler instead (see quickshell/bar/shell.qml's
-- `zenMode` property / toggleZen()).
bind(mod .. "+ Z",       hl.dsp.exec_cmd("qs -c bar ipc call bar toggleZen"), { description = "Zen" })
bind(mod .. "+ N",       hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-night-mode.sh"), { description = "Night" })
-- Notification center: was `swaync-client -t -sw`. quickshell owns
-- notifications natively now (see quickshell/bar/services/
-- NotificationState.qml) -- same IPC pattern as toggleZen above.
bind(mod .. "+ I",       hl.dsp.exec_cmd("qs -c bar ipc call bar toggleNotificationCenter"), { description = "Alerts" })

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
end, { description = "Close" })

-- SUPER+F was fullscreen and is now Liseuse (config/liseuse/), the
-- reading library: one key to get back into the book you were in, or to
-- pick another. The two fullscreen binds each shift one modifier down to
-- make room -- nothing is lost, and F stays the "fullscreen" letter for
-- the two of them.
--
-- Absolute path, same reason as Prisme and Roue above (commit bbb8f61):
-- Hyprland-launched processes don't inherit ~/.local/bin in their PATH.
bind(mod .. "+ F",           hl.dsp.exec_cmd("$HOME/.local/bin/liseuse"), { description = "Liseuse" })
bind(mod .. "+ SHIFT+ F",    hl.dsp.window.fullscreen({ mode = 0 }), { description = "Fullscreen" })
bind(mod .. "+ CTRL+ F",     hl.dsp.window.fullscreen({ mode = 1 }), { description = "Maximize" })
bind(mod .. "+ P",           hl.dsp.window.pseudo(), { description = "Pseudo" })
-- Flips the active split's axis by hand (raw dwindle layoutmsg "togglesplit"
-- -- there's no hl.dsp.window.toggle_split(), this is the passthrough for
-- layout-specific messages). Needed now that smart_split is off and the axis
-- is picked from aspect ratio + preserve_split (see hyprland.lua): this is
-- the manual escape hatch for the rare case the ratio picks the wrong one.
bind(mod .. "+ T",           hl.dsp.layout("togglesplit"), { description = "Split" })
bind(mod .. "+ SHIFT+ Space", hl.dsp.window.float({ action = "toggle" }), { description = "Float" })

-- Move focus between windows (hjkl)
bind(mod .. "+ H",  hl.dsp.focus({ direction = "left" }), { description = "Focus ←" })
bind(mod .. "+ L",  hl.dsp.focus({ direction = "right" }), { description = "Focus →" })
bind(mod .. "+ K",  hl.dsp.focus({ direction = "up" }), { description = "Focus ↑" })
bind(mod .. "+ J",  hl.dsp.focus({ direction = "down" }), { description = "Focus ↓" })

-- Move the active window in the given direction
bind(mod .. "+ SHIFT+ H",  hl.dsp.window.move({ direction = "left" }), { description = "Move ←" })
bind(mod .. "+ SHIFT+ L",  hl.dsp.window.move({ direction = "right" }), { description = "Move →" })
bind(mod .. "+ SHIFT+ K",  hl.dsp.window.move({ direction = "up" }), { description = "Move ↑" })
bind(mod .. "+ SHIFT+ J",  hl.dsp.window.move({ direction = "down" }), { description = "Move ↓" })

-- Resize submap: SUPER+R enters "resize", hjkl resizes in 5px steps,
-- Escape/Enter exits it.
bind(mod .. "+ R", hl.dsp.submap("resize"), { description = "Resize" })
hl.define_submap("resize", function()
    bind("+ H",      hl.dsp.window.resize({ x = -5, y = 0,  relative = true }), { repeating = true })
    bind("+ L",      hl.dsp.window.resize({ x =  5, y = 0,  relative = true }), { repeating = true })
    bind("+ K",      hl.dsp.window.resize({ x = 0,  y = -5, relative = true }), { repeating = true })
    bind("+ J",      hl.dsp.window.resize({ x = 0,  y =  5, relative = true }), { repeating = true })
    bind("+ Escape", hl.dsp.submap("reset"))
    bind("+ Return", hl.dsp.submap("reset"))
end)

-- Wake submap: the first key after the panel went dark (or the machine
-- slept) only wakes, it is not typed anywhere. Hyprland's
-- key_press_enables_dpms turns the panel back on AND still delivers
-- that key to the focused surface -- on the lock screen, hyprlock, which
-- puts it in the password field (verified in both sources: Hyprland
-- 0.56.2 InputManager.cpp, hyprlock 0.9.6 CHyprlock::onKey).
--
-- scripts/idle-action.sh enters this submap on dpms-off and before a
-- suspend; the catchall swallows the next key and leaves. Waking with
-- the mouse instead leaves through hypridle's on-resume (dpms-on).
--   locked      -- binds are skipped while the session is locked
--                  otherwise, and locked is the whole point here.
--   ignore_mods -- a catchall still has to match the modmask, so without
--                  it a Shift+x or Ctrl+x wake would slip through.
hl.define_submap("wake", function()
    bind("catchall", hl.dsp.submap("reset"), { locked = true, ignore_mods = true })
end)

-- ============================================================
-- WORKSPACES — the number row, by keycode
-- ============================================================
-- Bound as `code:10`..`code:19` (xkb keycodes of the row's ten keys,
-- AE01..AE10) rather than by what they print. They used to be keysyms --
-- ampersand, eacute, quotedbl... -- which only exist unshifted on
-- AZERTY: under QWERTY, SUPER+ampersand would have needed Shift+7, and
-- SUPER+SHIFT+ampersand would have collided with it. By keycode, the
-- row is the workspace row in every layout, and the sheet just prints
-- whatever glyph the active layout puts on each key.
for n = 1, 10 do
    local key = "code:" .. (9 + n)

    -- SUPER+key: switches focus to workspace n
    bind(mod .. "+ " .. key, hl.dsp.focus({ workspace = tostring(n) }),
         { description = "WS " .. n })

    -- SUPER+SHIFT+key: moves the active window to workspace n
    bind(mod .. "+ SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(n) }),
         { description = "→ WS " .. n })
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
bind(mod .. "+ C", hl.dsp.exec_cmd("~/.config/hypr/scripts/compact-workspaces.sh"), { description = "Compact" })

-- Scratchpad (special "magic" workspace)
bind(mod .. "+ U",         hl.dsp.workspace.toggle_special("magic"), { description = "Scratch" })
bind(mod .. "+ SHIFT+ U", hl.dsp.window.move({ workspace = "special:magic" }), { description = "→ Scratch" })

-- Move/resize window with the mouse (buttons 8/9)
bind(mod .. "+ mouse:272",  hl.dsp.window.drag(),   { mouse = true })
bind(mod .. "+ mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- ============================================================
-- SYSTEM & MEDIA
-- ============================================================
bind(mod .. "+ Escape",         hl.dsp.exec_cmd("hyprlock"), { description = "Lock" })
bind(mod .. "+ SHIFT+ M",   hl.dsp.exit(), { description = "Exit" })
bind(mod .. "+ SHIFT+ R",   hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload" })

-- Volume, mic and backlight: media keys, no modifier
-- -l 1.0: hard-capped at 100%, never boosts past it -- the previous 1.5
-- (150%) headroom went unused and asked to come out.
bind("+ XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
bind("+ XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { repeating = true })
bind("+ XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
bind("+ XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })

-- Backlight goes through a script rather than an inline brightnessctl:
-- the Down key needs a floor computed from the panel's max (a bare
-- `5%-` bottoms out at a literal 0, and max is per-host), and the bar's
-- OSD needs an IPC poke because brightnessctl has no DBus/kernel push it
-- can react to on its own -- unlike volume/mic, pure Pipewire push, see
-- quickshell/bar/services/OsdState.qml's header. Both live in
-- hypr/scripts/brightness.sh, which documents the brightnessctl traps.
bind("+ XF86MonBrightnessUp",   hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/brightness.sh up"),   { repeating = true })
bind("+ XF86MonBrightnessDown", hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/brightness.sh down"), { repeating = true })

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
--
-- A function rather than a bare exec_cmd because it also ARMS the Shift
-- watcher below: the sheet only needs to hear about Shift while it may
-- be on screen.
local sheet = { armed = false, shift = false }

bind("+ Super_L", function()
    sheet.armed = true
    sheet.shift = false
    hl.dispatch(hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsPress"))
end, { long_press = true, non_consuming = true })

-- No release BIND: letting SUPER go is caught by the raw key watcher
-- below. There used to be two (under modmask 0 and SUPER, since the
-- modifier's own state differs between its two edges), and they missed
-- exactly the case the Shift layer created: a modifier's release bind is
-- suppressed once another key went down during the hold, and Shift is a
-- key -- so after flipping to the Shift layer, letting go left the sheet
-- up. The raw event sees SUPER's release whatever was pressed meanwhile.

-- Shift layer of the sheet: while SUPER is held for it, adding Shift
-- flips every key to its SUPER+SHIFT action (H "Focus ←" -> "Move
-- left"), and letting Shift go flips it back. SUPER's own release closes
-- the sheet from here too (see above for why not a release bind).
--
-- Not a pair of binds: SUPER+Shift_L press/release binds would each go
-- through `bind` above and pick up a keybindsHide companion, closing
-- the sheet the moment Shift went down -- and a modifier's release bind
-- is exactly the kind Hyprland suppresses once another key was pressed.
-- The raw key event sees every edge instead. Its callback gets the xkb
-- keycode (libinput's + 8), a timestamp and the wl_keyboard state
-- (1 down, 0 up) -- LuaEventHandler.cpp in 0.56.2.
--
-- Cost: one Lua call per key event, returning on the first comparison
-- unless the sheet is armed, and a `qs ipc` spawn only when Shift
-- actually changes state under a held SUPER, or SUPER comes up after a
-- hold long enough to arm the sheet.
local SUPER_L, SHIFT_L, SHIFT_R = 133, 50, 62

hl.on("input.keyboard.key", function(code, _, state)
    if not sheet.armed then return end
    if code == SUPER_L and state == 0 then
        sheet.armed = false
        hl.dispatch(hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsRelease"))
    elseif (code == SHIFT_L or code == SHIFT_R) and (state == 0 or state == 1) then
        local down = state == 1
        if down ~= sheet.shift then
            sheet.shift = down
            hl.dispatch(hl.dsp.exec_cmd("qs -c bar ipc call bar keybindsShift " .. tostring(down)))
        end
    end
end)

-- ============================================================
-- SHEET EXPORT
-- ============================================================
-- Every described bind above, as JSON, rewritten on each config load --
-- so a reload is all it takes for the sheet to follow an edit here.
-- $XDG_RUNTIME_DIR because it is per-session state, not config; written
-- to a temp file and renamed so the watcher never reads half a file.
local function json_string(str)
    return '"' .. (str:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) .. '"'
end

do
    local entries = {}
    for _, e in ipairs(cheatsheet) do
        local mods = {}
        for _, m in ipairs(e.mods) do mods[#mods + 1] = json_string(m) end
        entries[#entries + 1] = string.format('{"mods":[%s],"key":%s,"description":%s}',
            table.concat(mods, ","), json_string(e.key), json_string(e.description))
    end

    local path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-keybinds.json"
    local file = io.open(path .. ".tmp", "w")
    if file ~= nil then
        file:write("[" .. table.concat(entries, ",") .. "]\n")
        file:close()
        os.rename(path .. ".tmp", path)
    end
end
