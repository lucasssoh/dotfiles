-- ============================================================
-- monitors.lua — Dynamic multi-monitor & HDR configuration
-- ============================================================
-- No connector name hardcoded here: workspace assignment (1-7 internal
-- / 8-10 external) and the external monitor's scale/HDR tuning are
-- resolved BY ROLE (internal = eDP*/LVDS*/DSI*, external = everything
-- else) by scripts/workspace-manager.sh.
--
-- This module turns on every plugged monitor at its preferred mode;
-- workspace-manager.sh then sets mode, position, scale and HDR per screen
-- through `hyprctl eval`, on startup, hotplug, config.reloaded and, through
-- scripts/display-watch.sh, whenever scale.json, monitor-layout.json,
-- display-layout.json or hdr-state.json is saved.
--
-- Runtime rules are cleared on every reload. So that a reload does not
-- send every screen back to preferred / scale 1 / SDR (a modeset, the
-- black flash of an HDR screen), workspace-manager.sh writes the rules it
-- applied to $XDG_RUNTIME_DIR/coucou-monitors.lua, loaded here on top of
-- the generic rule: Hyprland finds them already applied and leaves the
-- screens alone. loadfile, not require: a file outside this folder, not
-- one of the config's own modules.
-- ============================================================

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

local runtime = os.getenv("XDG_RUNTIME_DIR")
if runtime then
    local applied = loadfile(runtime .. "/coucou-monitors.lua")
    if applied then pcall(applied) end
end
