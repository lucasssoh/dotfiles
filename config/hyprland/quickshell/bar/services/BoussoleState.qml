pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// State + IPC for Boussole, the study planner. The planning, the alarm
// clock and the session tracking are the `boussole` service's
// (config/hyprland/boussole-src); this file connects to its socket
// ($XDG_RUNTIME_DIR/boussole.sock, JSON lines, like Manette's), keeps the
// last status it pushed, and sends back what the drawer and the island's
// alert ask for.
//
// The service never pushes a second-by-second clock: it sends the session's
// effective seconds and the instant they were counted at, and the bar
// counts on from there while `counting` holds.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/boussole.sock"

    property var status: ({})
    readonly property bool fr: root.status.lang === "fr"
    // Fixed labels live here, in both languages; sentences the service
    // builds arrive already written in the chosen one.
    function tr(en, frText) {
        return root.fr ? frText : en;
    }

    readonly property var next: root.status.next || null
    readonly property var tracking: (root.status.suivi && root.status.suivi.tracking) || null
    readonly property var today: root.status.today || []
    readonly property var declare: root.status.declare || []
    readonly property var gap: root.status.gap || null
    readonly property var alert: root.status.alert || null
    readonly property bool paused: root.status.paused === true

    // ---- the drawer ---------------------------------------------------
    property bool panelOpen: false
    property var activeScreen: null

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
        // Ten seconds is plenty for a ring and a minute count.
        interval: 10000
        repeat: true
        running: root.tracking !== null && root.tracking.counting
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
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
    function later(session, at) { root._send({ cmd: "later", session: session, at: at }); }
    function skip(session) { root._send({ cmd: "skip", session: session }); }
    function closeSession(session) { root._send({ cmd: "close", session: session }); }
    function setActivity(idle, media) { root._send({ cmd: "activity", idle: idle, media: media }); }

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
        }
    }
}
