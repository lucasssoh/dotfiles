import QtQuick
import Quickshell
import Quickshell.Hyprland

// Focused window -> { family, token }. Reuses ActiveWindow.qml's proven
// facts about this API rather than rediscovering them: `lastIpcObject`
// is the only place `class`/`floating` live (HyprlandToplevel itself
// only exposes `.title`), it goes stale unless something calls
// Hyprland.refreshToplevels() -- already done globally on every raw
// event by shell.qml (see its own header comment), so this file doesn't
// need its own Connections/refresh -- and a floating "dashboard-*"
// window (see hypr/windowrules.lua's DASHBOARD block) isn't a real
// focus target, same exclusion workspace-dashboard.sh and
// ActiveWindow.qml both already apply.
//
// Unlike ActiveWindow.qml, there's no per-monitor gating here: that
// existed there to solve "this BAR shows the wrong monitor's window",
// which doesn't apply to a single global overlay describing "what is
// the user doing right now" -- Hyprland.activeToplevel already answers
// that compositor-wide, with no per-screen ambiguity to resolve.
Scope {
    id: root

    property var config: null   // VeilleConfig instance

    // Injected like VeillePhase's, for the same two reasons: the session
    // signals below are functions of elapsed time, and Veille.qml's debug
    // `setNow` hook has to be able to drive them the way it drives the
    // phases.
    property date now: new Date()

    readonly property var toplevel: Hyprland.activeToplevel
    readonly property var ipc: (root.toplevel && root.toplevel.lastIpcObject) ? root.toplevel.lastIpcObject : null

    readonly property bool hasWindow:
        root.ipc !== null
        && !root.ipc.floating
        && (root.ipc.class || "").toLowerCase().indexOf("dashboard") === -1

    readonly property string windowClass: root.hasWindow ? (root.ipc.class || "") : ""
    readonly property string windowTitle: root.hasWindow ? (root.toplevel.title || "") : ""

    // First family (in JSON key order) whose regex list matches the
    // class -- empty string if nothing matches, which is level 0
    // (generic messages) by construction, never a guess. The class ->
    // family table lives entirely in veille.json's `appFamilies`, not
    // here: only one real class was ever observed on this machine while
    // building this (org.wezfurlong.wezterm), so hardcoding a guessed
    // table for IntelliJ/VS Code/etc. in QML would be exactly the kind
    // of "supposed" class this repo has been burned by twice already
    // (hypr/windowrules.lua's own notes on `net.lutris.Lutris` and the
    // real Steam window class) -- `veille probe` (see Veille.qml) exists
    // to fill this table in from what's actually observed.
    readonly property string family: {
        if (!root.hasWindow || !root.config) return "";
        const families = root.config.appFamilies || {};
        const cls = root.windowClass;
        for (const name in families) {
            const patterns = families[name] || [];
            for (let i = 0; i < patterns.length; i++) {
                try {
                    if (new RegExp(patterns[i]).test(cls)) return name;
                } catch (e) {
                    // Malformed regex in a hand-edited config -- skip it
                    // rather than let one bad pattern break every family
                    // after it in iteration order.
                    continue;
                }
            }
        }
        return "";
    }

    // Families whose window titles routinely contain something private
    // (a page title, a contact name, a URL) never get a token, no matter
    // what `tokenPatterns` says -- a hard rule, not a config option, so
    // it can't be loosened by accident from an edited JSON.
    readonly property var noTokenFamilies: ({ browser: true, chat: true, media: true })

    // Conservative allowlist for what a token is allowed to look like:
    // word chars/space/dot/hyphen only (excludes "/", "@", "://" by
    // construction, not by denylisting them), capped at 40 chars. Applied
    // BEFORE the substring blacklist below, so a token that's the wrong
    // shape never even reaches it.
    readonly property var tokenShape: /^[\w][\w .-]{0,39}$/
    readonly property var tokenBlacklist: ["\\.env", "secret", "token", "password", "passwd", "key"]

    function sanitizeToken(raw) {
        const t = (raw || "").trim();
        if (t === "" || !root.tokenShape.test(t)) return "";
        const lower = t.toLowerCase();
        for (let i = 0; i < root.tokenBlacklist.length; i++) {
            if (new RegExp(root.tokenBlacklist[i]).test(lower)) return "";
        }
        return t;
    }

    // `tokenPatterns[family]` is an array of regex strings, tried in
    // order against the live window title; the token is that pattern's
    // first capture group (or the whole match if the pattern has none).
    // First pattern to produce a token that survives sanitizeToken() wins
    // -- a family with no entry, or whose title never matches, silently
    // has no token, which is level 1 (app-only), never a placeholder.
    readonly property string token: {
        if (root.family === "" || root.noTokenFamilies[root.family] || !root.config) return "";
        const patterns = (root.config.tokenPatterns || {})[root.family] || [];
        for (let i = 0; i < patterns.length; i++) {
            try {
                const re = new RegExp(patterns[i]);
                const match = re.exec(root.windowTitle);
                if (match) {
                    const candidate = match.length > 1 ? match[1] : match[0];
                    const clean = root.sanitizeToken(candidate);
                    if (clean !== "") return clean;
                }
            } catch (e) {
                continue;
            }
        }
        return "";
    }

    readonly property bool hasToken: root.token !== ""

    // 0 = no window / unrecognized class, 1 = family known, 2 = family +
    // usable token. VeilleMessages decides how OFTEN to actually draw
    // from the level-2 pool (asked for: "rester subtil", not every tick)
    // -- this just reports what's AVAILABLE, not how it's used.
    readonly property int level: root.hasToken ? 2 : (root.family !== "" ? 1 : 0)

    // ---- session shape -------------------------------------------------
    // What the focused window is says nothing about how the evening has
    // actually gone. These three do, and they're what let a message say
    // something the user couldn't have predicted from the app name alone
    // -- "ça fait 3 h que la même fenêtre est devant toi" is a different
    // claim from "tu es dans l'IDE", and only one of them can be wrong.
    //
    // Nothing here is exposed to the grammar directly; VeilleMessages
    // folds them into the context object, and a fragment naming
    // {heuresApp} (or carrying `when: { churn: ">=5" }`) is simply
    // ineligible until the fact holds. See i18n/grammar.js.
    property string trackedFamily: ""
    property real familySince: 0
    property var familySwitches: []

    readonly property int churnWindowMs: 15 * 60000

    onFamilyChanged: {
        // An empty family is NOT a switch. `hasWindow` reports "" for a
        // floating window, a dashboard surface, or an empty workspace --
        // treating any of those as a change would reset a three-hour
        // session every time a dialog opened, which is exactly the kind
        // of quietly-wrong number that's worse than no number.
        if (root.family === "") return;
        if (root.family === root.trackedFamily) return;

        const at = root.now.getTime();
        root.trackedFamily = root.family;
        root.familySince = at;

        const kept = [];
        for (let i = 0; i < root.familySwitches.length; i++)
            if (root.familySwitches[i] >= at - root.churnWindowMs)
                kept.push(root.familySwitches[i]);
        kept.push(at);
        root.familySwitches = kept;
    }

    // Minutes spent in the CURRENT family without switching to another
    // one. Unlike VeillePhase's {hours} (which counts from the `late`
    // threshold and so says the same thing whatever you're doing), this
    // is a real session length.
    readonly property int sameFamilyMinutes:
        (root.trackedFamily === "" || root.familySince === 0)
            ? 0
            : Math.max(0, Math.floor((root.now.getTime() - root.familySince) / 60000))

    // Family switches in the last quarter hour -- the difference between
    // being absorbed in something and casting about for something to be
    // absorbed in. Both are reasons to still be up; they aren't the same
    // reason, and the grammar has lines for each.
    readonly property int churn: {
        const cut = root.now.getTime() - root.churnWindowMs;
        let n = 0;
        for (let i = 0; i < root.familySwitches.length; i++)
            if (root.familySwitches[i] >= cut) n++;
        return n;
    }

    // Whether the NIGHT is a weekend one, which is not the same question
    // as whether today is Saturday: at 01:00 on a Saturday the evening
    // being lived is Friday's. Anything before dayStart belongs to the
    // previous day, the same remapping VeillePhase applies to its
    // thresholds.
    readonly property bool weekend: {
        const dayStart = (root.config && root.config.thresholds && root.config.thresholds.dayStart)
            ? root.config.thresholds.dayStart : "05:00";
        const startHour = parseInt(dayStart.split(":")[0], 10) || 0;
        let day = root.now.getDay();
        if (root.now.getHours() < startHour) day = (day + 6) % 7;
        return day === 5 || day === 6;   // vendredi soir / samedi soir
    }
}
