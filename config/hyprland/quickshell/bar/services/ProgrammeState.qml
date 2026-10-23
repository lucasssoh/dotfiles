pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// State + IPC for Programme, the study agenda. The planning, the alarm
// clock and the session under way are the `programme` service's
// (config/hyprland/programme-src); this file connects to its socket
// ($XDG_RUNTIME_DIR/programme.sock, JSON lines, like Manette's), keeps the
// last status it pushed, and sends back what the drawer and the island's
// alert ask for.
//
// The service never pushes a second-by-second clock: it sends the session's
// effective seconds and the instant they were counted at, and the bar
// counts on from there while `counting` holds (Boussole in front).
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/programme.sock"

    property var status: ({})
    readonly property bool fr: root.status.lang === "fr"
    // Fixed labels live here, in both languages; sentences the service
    // builds arrive already written in the chosen one.
    function tr(en, frText) {
        return root.fr ? frText : en;
    }

    readonly property var next: root.status.next || null
    readonly property var tracking: root.status.tracking || null
    readonly property var today: root.status.today || []
    readonly property var gap: root.status.gap || null
    readonly property var alert: root.status.alert || null
    readonly property bool paused: root.status.paused === true
    // The course's window in front during a session: Firefox on Boussole.
    // Notifications keep quiet there, and show anywhere else.
    readonly property bool onCourse: {
        if (!root.tracking || !root.tracking.watched) return false;
        const t = Hyprland.activeToplevel;
        const ipc = t ? (t.lastIpcObject || {}) : {};
        return (ipc.class || "") === "org.mozilla.firefox" && (t.title || "").indexOf("Boussole") !== -1;
    }

    // ---- the drawer ---------------------------------------------------
    property bool panelOpen: false
    property var activeScreen: null
    // "today" | "week" | "plus" | "setup"
    property string page: "today"
    property var week: []
    // The page takes the keyboard (a field of Plus): the bar's window
    // turns focusable for it, like Balise's password field.
    readonly property bool textInput: root.panelOpen && (root.page === "plus" || root.page === "setup" || root.laterTyping)
    // "Later", a time typed rather than picked.
    property bool laterTyping: false
    readonly property bool setupNeeded: root.status.setup_needed === true
    // The first run: 1 courses, 2 timetable, 3 subjects, 4 rhythm, 5 ready.
    property int setupStep: 1
    property var suggestions: ({})
    function openSetup() {
        root.setupStep = 1;
        root.page = "setup";
        root.loadPlus();
        root.request({ cmd: "folders" }, (r) => root.folders = r.data || []);
    }
    // The course folder's subjects, for the first run.
    property var folders: []
    function loadSuggestions() {
        root.request({ cmd: "suggestions" }, (r) => root.suggestions = r.data || ({}));
    }

    function show(page) {
        root.page = page;
        if (page === "week") root.request({ cmd: "week", days: 7 }, (r) => root.week = r.data || []);
        if (page === "plus") {
            root.plusPage = "";
            root.loadPlus();
        }
    }

    // ---- Plus: everything that can be set ----------------------------
    // "" (the menu) or a sub-page: deadlines, projects, campaign,
    // subjects, calendars, rhythm, settings.
    property string plusPage: ""
    property var settings: ({})
    property var deadlines: []
    property var projects: []
    property var campaigns: []
    property var families: []

    function openPlus(sub) {
        root.plusPage = sub;
        root.page = "plus";
        root.loadPlus();
    }
    function loadPlus() {
        root.request({ cmd: "settings" }, (r) => root.settings = r.data || ({}));
        root.request({ cmd: "deadlines" }, (r) => root.deadlines = r.data || []);
        root.request({ cmd: "projects" }, (r) => root.projects = r.data || []);
        root.request({ cmd: "campaigns" }, (r) => root.campaigns = r.data || []);
        root.request({ cmd: "groups" }, (r) => root.families = r.data || []);
    }
    // A merge patch over the settings; `done(reply)` once applied.
    function setSettings(patch, done) {
        root.request({ cmd: "set", patch: patch }, (r) => {
            root.loadPlus();
            if (done) done(r);
        });
    }
    // Quick add: `apply` false only says what was understood.
    function addLine(line, apply, done) {
        root.request({ cmd: "add", line: line, apply: apply }, (r) => {
            if (apply) root.loadPlus();
            if (done) done(r);
        });
    }
    function send(obj, done) {
        root.request(obj, (r) => {
            root.loadPlus();
            if (done) done(r);
        });
    }

    // "18/12", "18/12/2026", "2026-12-18", "today", "demain" → "2026-12-18",
    // or "" when not a date. A day already past this year means next year.
    function parseDate(text) {
        const t = (text || "").trim().toLowerCase();
        const pad = (n) => ("0" + n).slice(-2);
        const iso = (d) => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (t === "today" || t === "auj" || t === "aujourd'hui") return iso(today);
        if (t === "tomorrow" || t === "demain") return iso(new Date(today.getTime() + 86400000));
        let m = t.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
        if (m) return m[1] + "-" + pad(+m[2]) + "-" + pad(+m[3]);
        m = t.match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/);
        if (!m) return "";
        let y = m[3] ? (+m[3] < 100 ? 2000 + +m[3] : +m[3]) : today.getFullYear();
        let d = new Date(y, +m[2] - 1, +m[1]);
        if (d.getMonth() !== +m[2] - 1) return "";
        if (!m[3] && d < today) d = new Date(y + 1, +m[2] - 1, +m[1]);
        return iso(d);
    }

    // "Done": the session under way is over.
    function done(session) {
        root._send({ cmd: "done", session: session });
        root.justClosed = session;
        undoTimer.restart();
    }

    // "Closed · Undo" stays this long under Today.
    property string justClosed: ""
    Timer {
        id: undoTimer
        interval: 10000
        onTriggered: root.justClosed = ""
    }
    // Takes "Done" back: the session is under way again.
    function undoClose() {
        root.justClosed = "";
        undoTimer.stop();
        root._send({ cmd: "undo" });
    }

    function togglePanel(screen) {
        if (root.panelOpen && root.activeScreen === screen) {
            root.close();
            return;
        }
        NotificationState.close();
        BaliseState.close();
        PowerState.close();
        MixerState.close();
        LauncherActionsState.close();
        CalendarState.close();
        root.activeScreen = screen;
        root.page = "today";
        root.panelOpen = true;
    }

    function close() {
        root.panelOpen = false;
    }

    // ---- the session's clock ------------------------------------------
    // Seconds counted, as of now: the service's figure plus what elapsed
    // since, while it counts.
    property real nowMs: Date.now()
    readonly property int effectiveSecs: {
        const t = root.tracking;
        if (!t) return 0;
        const extra = t.counting ? Math.max(0, root.nowMs / 1000 - t.as_of) : 0;
        return Math.floor(t.effective_secs + extra);
    }
    // Pomodoro 25/5 over the effective time: work, then a break.
    readonly property bool onBreak: root.tracking !== null && (root.effectiveSecs % 1800) >= 1500
    readonly property int phaseLeft: root.onBreak ? 1800 - (root.effectiveSecs % 1800) : 1500 - (root.effectiveSecs % 1800)
    readonly property real phaseProgress: root.onBreak ? ((root.effectiveSecs % 1800) - 1500) / 300 : (root.effectiveSecs % 1800) / 1500

    Timer {
        // Every second: the bar and the session panel show seconds.
        interval: 1000
        repeat: true
        running: root.tracking !== null && root.tracking.counting
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    // The countdown before a session ("in 12 min", then "now"): the bar
    // keeps its own clock while it is close. Further off, the service wakes
    // 15 minutes before and says so, and nothing ticks here.
    readonly property bool nextClose: {
        const n = root.next;
        if (!n) return false;
        const p = n.date.split("-"), hm = n.start.split(":"), e = n.end.split(":");
        const start = new Date(+p[0], +p[1] - 1, +p[2], +hm[0], +hm[1]).getTime();
        const end = new Date(+p[0], +p[1] - 1, +p[2], +e[0], +e[1]).getTime();
        return start - root.nowMs < 16 * 60000 && root.nowMs < end;
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.daemonConnected && root.nextClose && root.tracking === null
        onTriggered: root.nowMs = Date.now()
    }

    // "1:04:12", "34:12", "0:45": a count of seconds as the bar shows it.
    function clock(secs) {
        const s = Math.max(0, Math.floor(secs));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60;
        const two = (n) => ("0" + n).slice(-2);
        return h > 0 ? h + ":" + two(m) + ":" + two(r) : m + ":" + two(r);
    }

    readonly property bool sessionActive: root.tracking !== null

    // Veille is quiet during a session, until bedtime.
    readonly property bool holdsVeille: {
        if (!root.sessionActive) return false;
        const b = (root.status.bedtime || "22:30").split(":");
        const now = new Date(root.nowMs);
        return now.getHours() * 60 + now.getMinutes() < (+b[0]) * 60 + (+b[1]);
    }

    // ---- the island's alert -------------------------------------------
    // Bound in from shell.qml; the bar is paused in zen mode anyway.
    property bool zen: false
    // A fullscreen window (a game, most of the time) has the screen: the
    // alert waits for it to go.
    readonly property bool screenTaken: {
        const t = Hyprland.activeToplevel;
        const ipc = t ? (t.lastIpcObject || {}) : {};
        const cls = (ipc.class || ipc.initialClass || "").toLowerCase();
        return (ipc.fullscreen || 0) > 0 || /^steam_app_|gamescope/.test(cls);
    }
    // Closed with its handle: hidden until the next alert.
    property string hiddenKey: ""
    readonly property bool alertShown: root.acked !== null
                                       || (root.alert !== null && !root.zen && !root.screenTaken
                                           && root.alert.key !== root.hiddenKey)
    // After a button: the alert stays a moment to say what was done.
    property var acked: null
    property string ackText: ""
    // What the island shows: the alert, or the one just answered.
    readonly property var shownAlert: root.acked || root.alert

    // The chime, once per alert, when it actually shows.
    property string chimedKey: ""
    onAlertShownChanged: {
        if (!root.alertShown || !root.alert.chime || root.alert.key === root.chimedKey) return;
        root.chimedKey = root.alert.key;
        Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
    }

    function answer(action) {
        if (!root.alert) return;
        if (action === "dismiss") {
            root.hiddenKey = root.alert.key;
        } else {
            root.acked = root.alert;
            root.ackText = "";
            ackTimer.restart();
        }
        root._send({ cmd: "answer", key: root.alert.key, action: action });
    }

    Timer {
        id: ackTimer
        // Long enough to read a line; the reply usually lands well before.
        interval: 2600
        onTriggered: {
            root.acked = null;
            root.ackText = "";
        }
    }

    // ---- commands -----------------------------------------------------
    function start(session) { root._send({ cmd: "start", session: session }); }
    // The session's command again: Boussole on its subject.
    function launch(session) { root._send({ cmd: "launch", session: session }); }
    // "Later, until…": nothing planned, rung or offered before then. `until`
    // is a choice's id (30, 60, tomorrow, a date) or what was typed.
    function later(until) { root._send({ cmd: "later", until: until }); }
    function back() { root._send({ cmd: "back" }); }
    // A session now: that subject, for that long.
    function free(subject, minutes) { root._send({ cmd: "free", subject: subject, minutes: minutes }); }
    function setLevel(domain, level) { root._send({ cmd: "level", domain: domain, level: level }); }

    // "until 21:30" while Later holds, else "".
    readonly property string away: root.status.away || ""
    readonly property var laterChoices: root.status.later || []

    // Commands whose answer is wanted: called back with the reply.
    property var _pending: ({})
    function request(obj, cb) {
        const list = root._pending[obj.cmd] || [];
        list.push(cb);
        root._pending[obj.cmd] = list;
        root._send(obj);
    }

    function _handleLine(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.event === "status") {
            root.status = msg;
            root.nowMs = Date.now();
        } else if (msg.event === "plan") {
            root._send({ cmd: "status" });
        } else if (msg.reply && (root._pending[msg.reply] || []).length > 0) {
            const cb = root._pending[msg.reply].shift();
            cb(msg);
        } else if (msg.reply === "answer") {
            root.ackText = msg.text || "";
            // Nothing to say (a dismissal, a refusal): close at once.
            if (root.ackText === "") {
                ackTimer.stop();
                root.acked = null;
            }
        } else if (msg.reply === "status" && msg.ok && msg.data) {
            root.status = msg.data;
            root.nowMs = Date.now();
        }
    }

    function _send(obj) {
        const sock = socketLoader.item;
        if (!sock || !sock.connected) return false;
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
        return true;
    }

    readonly property bool daemonConnected: socketLoader.item ? socketLoader.item.connected : false

    // Installed (the binary is there), whether or not its service runs: the
    // bar then keeps Programme's place, so a stopped service still shows.
    // Checked at start and at each reconnection attempt, not polled.
    property bool installed: false
    Process {
        id: installedCheck
        command: ["test", "-x", Quickshell.env("HOME") + "/.local/bin/programme"]
        running: true
        onExited: (code) => root.installed = code === 0
    }
    // Saying who it is makes the service send alerts here rather than as
    // notifications.
    onDaemonConnectedChanged: {
        if (root.daemonConnected) root._send({ cmd: "hello", role: "bar" });
        else root.status = ({});
    }

    // Rebuilt rather than reconnected, for the reason BaliseState.qml gives:
    // a Quickshell Socket never comes back once it has failed.
    Loader {
        id: socketLoader
        active: true
        sourceComponent: Component {
            Socket {
                path: root.socketPath
                connected: true
                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => root._handleLine(line)
                }
            }
        }
    }

    // Backs off to a try every 30s, so a machine without the service pays
    // next to nothing for looking.
    Timer {
        id: reconnectTimer
        property int tries: 0
        interval: Math.min(30000, 2000 * Math.pow(2, Math.min(tries, 4)))
        repeat: true
        running: !root.daemonConnected
        onRunningChanged: if (!running) tries = 0
        onTriggered: {
            tries++;
            socketLoader.active = false;
            socketLoader.active = true;
            installedCheck.running = true;
        }
    }
}
