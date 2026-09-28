-- ============================================================
-- readinghold.lua — a book on screen keeps the screen on
-- ============================================================
-- Reading is the one activity that produces NO input for minutes at a
-- time, so a book left to hypridle alone gets locked out from under you
-- (5 min on battery, 15 on mains). Idle must be held off while you read,
-- and only while you read.
--
-- That second half is what the previous mechanism got wrong. Liseuse
-- used to launch zathura under `systemd-inhibit --what=idle`: a session-
-- wide block for as long as the process lived. A book left open on
-- workspace 4 while you worked on 1 held the whole ladder -- lock,
-- screen off, suspend -- for the rest of the afternoon (two PDFs, opened
-- at 13:16 and 17:53, kept an unattended laptop lit).
--
-- "Reading" is decided here instead, as "a zathura window is on a
-- workspace that is on screen right now". Hyprland's own idle_inhibit
-- modes do not say that: `always` ignores visibility, `focus` drops the
-- moment you click into the editor beside the handout you are copying
-- from, `fullscreen` misses a tiled book. So visibility is recomputed on
-- every event that can change it, and turned into the tag "reading-on";
-- the rule below turns the tag into idle_inhibit. Checked with
-- `hyprctl getprop address:... idle_inhibit`: 1 while tagged, 0 once the
-- tag is gone. hypridle honours it (ext-idle-notify is inhibited), and
-- its timers restart from the moment the book leaves the screen.
--
-- Every zathura window, not just Liseuse's: a PDF opened from nemo and
-- left on screen is being read just the same, and Liseuse already treats
-- every zathura window as its own (ZATHURA_CLASS).
-- ============================================================

local CLASS = "org.pwmt.zathura"
local TAG = "reading-on"

hl.window_rule({ match = { tag = TAG }, idle_inhibit = "always" })

local function has_tag(w, name)
    local t = w.tags
    if type(t) == "table" then t = table.concat(t, ",") end
    return (t or ""):find(name, 1, true) ~= nil
end

local function sync()
    for _, w in ipairs(hl.get_windows()) do
        if w.class == CLASS then
            local ws = w.workspace
            local want = ws ~= nil and ws.visible == true and w.hidden ~= true
            if want ~= has_tag(w, TAG) then
                hl.dispatch(hl.dsp.window.tag({
                    tag = (want and "+" or "-") .. TAG,
                    window = "address:" .. w.address,
                }))
            end
        end
    end
end

-- Deferred by one tick: some of these fire before the state they
-- announce is visible through get_windows (a closing window is still
-- listed, a switched-to workspace not yet visible). At most one pass in
-- flight, so a burst of events costs a single sync.
local pending = false
local function schedule()
    if pending then return end
    pending = true
    hl.timer(function() pending = false; sync() end,
             { timeout = 50, type = "oneshot" })
end

for _, ev in ipairs({
    "window.open", "window.close", "window.class",
    "window.move_to_workspace",
    "workspace.active", "workspace.special_active",
    "workspace.move_to_monitor",
    "monitor.added", "monitor.removed",
}) do
    hl.on(ev, schedule)
end

-- A config reload re-runs this file with zathura windows already open.
sync()
