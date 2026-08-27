-- ============================================================
-- hyprland.lua — Entry point of the Hyprland configuration
-- ============================================================
-- Loads the palette, environment variables, autostart, then the
-- submodules (monitors / windowrules / keybinds) at the end of the file.
-- ============================================================

-- ============================================================
-- ENVIRONMENT
-- ============================================================
-- Variables needed for consistent Wayland behavior across toolkits
-- (Qt, GTK, SDL, Clutter) and historically X11 applications.
hl.env("XCURSOR_SIZE",          "48")
hl.env("XCURSOR_THEME",         "ComixCursors-White")
hl.env("QT_QPA_PLATFORM",       "wayland")
hl.env("QT_QPA_PLATFORMTHEME",  "qt6ct")
hl.env("GDK_BACKEND",           "wayland,x11")
hl.env("SDL_VIDEODRIVER",       "wayland")
hl.env("CLUTTER_BACKEND",       "wayland")
hl.env("XDG_CURRENT_DESKTOP",   "Hyprland")
hl.env("XDG_SESSION_TYPE",      "wayland")
hl.env("XDG_SESSION_DESKTOP",   "Hyprland")
hl.env("MOZ_ENABLE_WAYLAND",    "1")

-- ============================================================
-- SOURCES
-- ============================================================
local colors = require("colors")

-- ============================================================
-- AUTOSTART (Lua event syntax, Hyprland 0.55+)
-- ============================================================
hl.on("hyprland.start", function()
    -- Propagates session variables to D-Bus/systemd: required for XDG
    -- portals (screen sharing, file picker...) to work correctly under
    -- Wayland.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Imports the session into systemd --user: required for services
    -- declared WantedBy=graphical-session.target to start.
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- NB: `systemctl --user start graphical-session.target` isn't enough
    -- on this session: the target has RefuseManualStart=yes (see
    -- /usr/lib/systemd/user/graphical-session.target) and loginctl doesn't
    -- classify this session as "graphical" (Type=unspecified /
    -- Class=manager), so the target never activates automatically.
    -- Consequence: every WantedBy=graphical-session.target service (e.g.
    -- balise.service) must be started explicitly below instead of relying
    -- on the target's activation.
    --
    -- xdg-desktop-portal.service is hit even worse: its unit has an
    -- outright `Requisite=graphical-session.target` (not just
    -- WantedBy=), so even an explicit `systemctl --user start` refuses it
    -- as long as the target isn't active (see
    -- /usr/lib/systemd/user/xdg-desktop-portal.service). Observed symptom:
    -- every GTK/GDK call to XDG portals fails with "Could not activate
    -- remote peer 'org.freedesktop.portal.Desktop': startup job failed",
    -- and some GTK4 file pickers (e.g. satty's "Save as") that depend on
    -- it to list some folders fail with a display error. Workaround:
    -- launch the binary directly (like the other daemons in this block),
    -- simply bypassing the blocked systemd service -- it registers itself
    -- on the D-Bus at startup, no need for service activation.
    hl.exec_cmd("/usr/libexec/xdg-desktop-portal")

    -- Session services and daemons
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    -- quickshell replaces waybar as the bar (see quickshell/bar/) --
    -- config.jsonc/style.css stay in the repo as a fallback, same
    -- pattern as dunst below, just not started:
    --   hl.exec_cmd("waybar")
    --   hl.exec_cmd("bash ~/.config/waybar/scripts/watch-reload.sh")
    hl.exec_cmd("quickshell -c bar")
    -- swaync replaces dunst as the notification center (history, toggles,
    -- mpris controls). Both claim the same D-Bus name
    -- org.freedesktop.Notifications and can't coexist -- dunst is
    -- therefore no longer started, but its config stays in the repo as a
    -- fallback.
    hl.exec_cmd("swaync")
    -- hypridle disabled on this machine (config present and valid, see
    -- hypridle.conf, but not enabled). Uncomment to re-enable.
    -- hl.exec_cmd("hypridle")
    -- Restores the previous session's wallpaper, then watches the
    -- thumbnail cache in the background.
    hl.exec_cmd("~/.config/hypr/scripts/restore_wallpaper.sh")
    hl.exec_cmd("bash ~/.config/hypr/scripts/wallpaper-cache-watcher.sh")
    -- Forces the combo jack back to the headset mic port -- wireplumber
    -- otherwise picks the internal mic on every boot (higher static
    -- priority, no jack-sensing on either port). See the script for the
    -- full story.
    hl.exec_cmd("bash ~/.config/hypr/scripts/restore-mic-port.sh")
    -- Clipboard history
    hl.exec_cmd("wl-paste --watch cliphist store")
    -- Nemo D-Bus daemon, for other applications' "Open location"
    -- integration (file manager always available).
    hl.exec_cmd("nemo --no-desktop --gapplication-service")

    -- Arranges new floating windows into per-context rows (a window and
    -- whatever it spawns afterwards, detected by focus) instead of
    -- letting them stack dead center. A lone window still lands exactly
    -- centered. Small dialogs (confirm/cancel, save-as, system prompts
    -- -- typically already `center = true` in windowrules.lua) are left
    -- untouched. See the script header for the full algorithm.
    hl.exec_cmd("python3 ~/.config/hypr/scripts/float-smart-place.py")

    -- Fixed workspaces 1-10, set at runtime via hyprctl eval -- not
    -- persisted in a Lua file, so they must be replayed on every startup
    -- (and on config.reloaded / monitor.added / monitor.removed below).
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")

    -- Native Wayland WiFi/Bluetooth/Ethernet manager (replaces the
    -- gnome-control-center detour), built from the sources in this repo
    -- by install.sh (see
    -- balise-src/). The bar's `balise toggle` shortcut reuses this
    -- daemon instead of relaunching one per click. Started
    -- here via a systemd --user service (see systemd/balise.service,
    -- ExecStartPre sleep 3 + Restart=on-failure) rather than directly:
    -- the GTK4/layer-shell client can fail to initialize too early in the
    -- startup sequence, and the service handles the delay and automatic
    -- restart. Started explicitly here rather than via
    -- WantedBy=graphical-session.target, for the same reason as above
    -- (this target never activates on its own on this session).
    hl.exec_cmd("systemctl --user start balise.service")
    -- Closes Balise on an outside click (like swaync): GTK/gtk4-layer-shell
    -- never notifies a layer-shell surface that it lost focus, so this
    -- behavior relies on Hyprland events instead.
    hl.exec_cmd("bash ~/.config/hypr/scripts/balise-autoclose.sh")
end)

-- A `hyprctl reload` reloads the static Lua files and clears rules set at
-- runtime (workspace_rule, monitor tuning) -- replayed here so the 10
-- fixed workspaces survive a reload.
hl.on("config.reloaded", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

-- External monitor plugged or unplugged: reassigns workspaces 1-10 by
-- role (internal/external) without needing a hyprctl reload.
hl.on("monitor.added", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

hl.on("monitor.removed", function()
    hl.exec_cmd("bash ~/.config/hypr/scripts/workspace-manager.sh")
end)

-- ============================================================
-- INPUT
-- ============================================================
hl.config({
    input = {
        kb_layout  = "fr",
        kb_variant = "azerty",
        follow_mouse = 1,
        repeat_rate = 45,
        repeat_delay = 200,
        sensitivity  = 0,
        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            disable_while_typing = true,
            scroll_factor        = 0.3,
        },
    },
})

-- 3-finger horizontal swipe to navigate between workspaces (trackpad)
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

-- ============================================================
-- GENERAL
-- ============================================================
hl.config({
    general = {
        gaps_in          = 3,
        -- 0 on right/left so tiled windows sit flush against the screen's
        -- left/right edges, same as the quickshell bar itself (see
        -- quickshell/bar/shell.qml's PanelWindow margins: 0). Top/bottom
        -- unchanged at 6. (css_gap wants a table with top/right/bottom/
        -- left fields on this build, not a CSS-shorthand string -- that
        -- was tried first and rejected: "css_gap type requires an integer
        -- or a table with optional 'top','right','bottom','left' fields".)
        gaps_out         = { top = 10, right = 8, bottom = 6, left = 8 },
        border_size      = 2,
        col = {
            -- Convex/"bombé" bevel, not a flat colored strip: a single
            -- light source top-left, the border reading as a rounded,
            -- slightly domed edge catching that light rather than a flat
            -- ring. No shape change involved (still rounding=10,
            -- border_size=2 below -- squircle geometry was already looked
            -- at and shelved for cost, see git history) -- purely a 5-stop
            -- greyscale ramp doing the work: bright highlight where the
            -- curve is closest to the light, fading through the bar's own
            -- text/subtle/muted/overlay/background tokens (colors.lua) down
            -- to near-invisible where the curve rolls away into shadow.
            -- Deliberately monochrome (no accent hue any more) -- color
            -- would read as decoration, grey/white/transparent alone is
            -- what actually sells "curved surface, lit from one side".
            --
            -- Angle convention verified against Hyprland's own gradient
            -- shader (progress = y*sin(angle) + x*(1-sin(angle)), 0<=angle
            -- <=90 branch), not assumed: at angle=45 progress=0 (first
            -- color below) sits at the top-left corner, progress=1 (last
            -- color) at bottom-right -- confirmed empirically too (grim
            -- crops of all 4 corners before touching this).
            active_border = {
                colors = {
                    "rgba(f5f5fABF)",  -- text, ~75% alpha -- the highlight tip, top-left
                    "rgba(8E8E9373)",  -- subtle, ~45% alpha -- shoulder of the curve
                    "rgba(63636647)",  -- muted,  ~28% alpha -- the curve's terminator/mid-tone
                    "rgba(3A3A3C26)",  -- overlay, ~15% alpha -- entering shadow
                    "rgba(1C1C1E0F)",  -- background, ~6% alpha -- deep shadow, bottom-right
                },
                angle = 45,
            },
            -- Fully transparent, deliberately: the active-window glass
            -- border is the ONLY visual cue for focus -- no dimming, no
            -- opacity drop on inactive windows (inactive_opacity/dim_inactive
            -- below are both off), so an inactive rim would just compete
            -- with that single signal instead of reinforcing it.
            inactive_border = "rgba(3E3E3373)",

        },
        layout           = "dwindle",
        resize_on_border = true,
    },
})

-- ============================================================
-- DECORATION
-- ============================================================
hl.config({
    decoration = {
        -- 3 -> 10: softer, more premium silhouette -- the glass border
        -- gradient above needs generous rounding to read as a curved edge
        -- rather than a thin outline on square corners.
        rounding = 12,
        -- Enabled, unlike this file's history: the earlier "not worth the
        -- regression risk" reasoning was specifically about the BAR --
        -- always on screen, aboveWindows, composited over fullscreen HDR
        -- content continuously for the whole session. This global switch
        -- alone doesn't blur anything by default though (no window/layer
        -- opts in just because this is true) -- actual blur only happens
        -- where explicitly requested:
        --   - layerrule blur for swaync-notification-window/
        --     swaync-control-center (see windowrules.lua) -- small,
        --     on-demand panels, visible for seconds at a time, not the
        --     whole session, so nowhere near the bar's cost profile.
        --   - windows with an opacity override below 1.0 (Thunar, Nemo,
        --     Pavucontrol -- see windowrules.lua) pick up a blurred
        --     backdrop as a side effect of already being translucent.
        --     Minor and arguably a nice bonus, not a new risk on its own.
        -- Layer surfaces need an explicit layerrule to opt in at all, so
        -- the bar (quickshell layer) is safe by simply never getting one,
        -- not by an explicit opt-out. Real windows are the opt-out case:
        -- gamescope and the Rockstar Games Launcher already carry an
        -- explicit no_blur in windowrules.lua, set well before this was
        -- ever turned on, for exactly this kind of situation.
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            xray              = false,
            ignore_opacity    = false,
        },
        shadow = {
            enabled       = true,
            range         = 24,
            render_power  = 4,
            color         = "rgba(0,0,0,0.55)",
            -- Back to none, same reasoning as inactive_border above: no
            -- per-window treatment on unfocused windows at all, so the
            -- active glass border stays the one unambiguous focus cue.
            color_inactive= "rgba(0,0,0,0)",
        },
        inactive_opacity = 1,
        active_opacity   = 1,
        dim_inactive     = false,
        dim_strength     = 0.35,
    },
})

-- ============================================================
-- CURVES — Bézier curves reused by the animations below
-- ============================================================
hl.curve("smooth", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("linear", { type = "bezier", points = { {0.0, 0.0}, {1.0, 1.0} } })
hl.curve("snap",   { type = "bezier", points = { {0.2, 1.0}, {0.2, 1.0} } })

-- ============================================================
-- ANIMATIONS
-- ============================================================
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "smooth", style = "slide" })

-- Fade (open/close, opacity change)
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "smooth" })

hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "snap", style = "slide" })

-- ============================================================
-- LAYOUT & MISC
-- ============================================================
hl.config({
    dwindle = {
        force_split = 0,

        -- smart_split = false: with it enabled, the split axis AND the side
        -- both came from which of the parent's four diagonal triangles the
        -- cursor sat in -- the tile's aspect ratio was never consulted, so on
        -- a 2560x1440 screen two windows would just as easily end up stacked
        -- (2560x720 each, long and thin) as side by side. Disabled, dwindle
        -- falls back to its default: the axis comes from the aspect ratio
        -- (see split_width_multiplier below) and only the SIDE still follows
        -- the mouse, which is the behaviour we actually want.
        smart_split = false,

        -- Split side by side when width * multiplier > height, top/bottom
        -- otherwise. 1.0 is the neutral threshold and the optimum for keeping
        -- tiles close to square: on 2560x1440 the first split gives two
        -- 1280x1440 columns, each of which then splits into 1280x720 rows.
        -- Raising it (1.4+) biases toward narrow vertical columns.
        split_width_multiplier = 1.0,

        -- Axis frozen at creation time: closing or resizing a neighbour never
        -- silently re-orients an existing container. SUPER+T flips one by hand
        -- (see keybinds.lua) -- that override only holds because this is true.
        preserve_split = true,
        smart_resizing = true,
    },
    misc = {
        -- Hyprland paints its own built-in wallpaper (and a small logo
        -- watermark) on whatever isn't yet covered by a real client --
        -- most visibly for a moment on every `hyprctl reload`/monitor
        -- change, before awww (restore_wallpaper.sh) repaints over it.
        -- Both off, background_color set to solid black, so that gap is
        -- just a flat black frame instead of Hyprland's default art.
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = "rgba(000000ff)",
    },
})

-- render:cm_auto_hdr = hdredid: fullscreen HDR apps (e.g. Proton games with
-- PROTON_ENABLE_HDR) get the panel's real EDID gamut, not the full BT.2020
-- primaries "hdr" advertises — the latter desaturates everything on
-- displays (all of them) that don't actually cover BT.2020.
--
-- direct_scanout = auto: exclusive-fullscreen surfaces (games) go straight to
-- the DRM plane instead of through the compositor's shader path, replacing
-- what used to be render:cm_fs_passthrough (removed upstream, folded into
-- direct_scanout — see hyprwm/Hyprland PR #13860).
--
-- debug:invalidate_fp16 = disable: works around the PR #13860 FP16 workbuffer
-- invalidation glitch (dim screen / blur artifacts / oversaturated cursor
-- under HDR). NOT the same knob as render:use_fp16, which controls whether
-- the FP16 buffer is used at all — disabling that instead would remove the
-- precision headroom HDR needs, making banding worse, not better.
hl.config({
    render = {
        cm_auto_hdr    = 2, -- hdredid
        direct_scanout = 2, -- auto
    },
    debug = {
        invalidate_fp16 = 0, -- disable
    },
})

-- Submodules: monitors/HDR, per-app rules, keyboard shortcuts
require("monitors")
require("windowrules")
require("keybinds")
