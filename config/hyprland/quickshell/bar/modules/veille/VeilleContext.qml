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
}
