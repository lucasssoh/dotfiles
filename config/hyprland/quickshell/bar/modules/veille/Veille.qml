import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// VEILLE -- logic only. Computes WHEN the sleep-awareness clock should
// be showing and WHAT it should say (see VeillePhase.qml's `inPulse` for
// the hourly-pulse timing, VeilleMessages.qml for the message content),
// escalating through the evening. Full design rationale in the project
// plan (temporal-drifting-hippo.md).
//
// Used to own its own PanelWindow/rendering too -- moved into shell.qml
// instead (VeilleDrawerContent.qml renders the actual clock/message),
// asked for explicitly: "combiner veille dans l'island central" --
// the drawer now lives INSIDE the bar's own per-screen central island
// (ActiveWindow/Workspaces/Media), not as a separate floating panel.
// That's also *why* this stays a single Scope instance shared by every
// screen's bar (unchanged from before: "a big clock repeated on every
// monitor would be noise") while exposing plain read-only properties
// (clockString/dateString/messageString/suppressed/activeScreen/config)
// instead of a window of its own -- each per-screen `bar` in shell.qml
// reads these and only actually opens its own drawer on whichever
// screen `activeScreen` picked.
Scope {
    id: root

    // Bound in from shell.qml -- Zen mode is a shared property on the
    // ShellRoot (`shell.zenMode`), not something this module can see on
    // its own without either a singleton or this kind of pass-through
    // (same idea as ActiveWindow.qml's `monitor` property).
    property bool zenMode: false

    // Exposed so shell.qml's drawer can read config values (showSeconds/
    // showDate) without this file re-exposing each one individually.
    property alias config: config
    VeilleConfig { id: config }

    SystemClock {
        id: sysClock
        precision: config.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Debug time override (see the IpcHandler below) -- a fixed offset
    // applied to the real clock rather than a frozen fake Date, so
    // seconds/phases keep advancing naturally from wherever `setNow`
    // pointed them, instead of a still image. Only reachable when
    // veille.json has "debug": true.
    property real debugOffsetMs: 0
    readonly property date now: new Date(sysClock.date.getTime() + root.debugOffsetMs)

    VeillePhase {
        id: phase
        config: config
        now: root.now
    }

    VeilleContext {
        id: context
        config: config
    }

    VeilleMessages {
        id: messages
        config: config
        phase: phase
        context: context
        now: root.now
    }

    // What the drawer should actually display -- formatted here, once,
    // rather than in VeilleDrawerContent, so every consumer (were there
    // ever more than one) reads the identical string.
    readonly property string clockString:
        Qt.formatDateTime(root.now, config.showSeconds ? "HH:mm:ss" : "HH:mm")
    readonly property string dateString: Qt.formatDateTime(root.now, "dddd d MMMM")
    readonly property string messageString: messages.text

    // Mode gaming: profile Performance OR the focused window is
    // fullscreen (see the plan's own rationale -- both signals already
    // exist elsewhere in this bar/repo, nothing new to read). By explicit
    // choice this changes NOTHING by default -- it only feeds
    // `muteWhileGaming` below, which stays false unless set in
    // veille.json.
    readonly property bool gaming:
        PowerProfiles.profile === PowerProfile.Performance
        || (context.ipc !== null && context.ipc.fullscreen !== 0)

    readonly property bool suppressed:
        !config.enabled
        || !phase.phaseVisible
        || !phase.inPulse
        || (config.respectZenMode && root.zenMode)
        || (config.muteWhileGaming && root.gaming)

    // ---- placement ----------------------------------------------------
    // Which single screen's bar gets to open its drawer -- unaffected by
    // moving the rendering into shell.qml, still "a big clock repeated
    // on every monitor would be noise".
    function pickScreen() {
        const wanted = config.monitor;
        if (wanted === "") return Quickshell.screens[0] || null;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === wanted) return Quickshell.screens[i];
        }
        return Quickshell.screens[0] || null;
    }

    readonly property var activeScreen: root.pickScreen()

    // ---- debug / development hooks -------------------------------------
    // Everything here is a no-op unless veille.json has "debug": true --
    // asked for explicitly (the plan's own verification section): there
    // is no input-injection tool in this environment, so exercising the
    // five phases / midnight event / cooldown without waiting for the
    // real clock needs a way to fast-forward it, and filling in
    // appFamilies/tokenPatterns needs a way to see the REAL class/title
    // of whatever's focused, rather than guessing.
    IpcHandler {
        target: "veille"

        // `qs -c bar ipc call veille setNow "01:12"` -- jumps the
        // effective clock to that time today, then lets it keep ticking
        // forward normally from there (see root.debugOffsetMs above).
        function setNow(hhmm: string): void {
            if (!config.debug) {
                console.warn("[veille] setNow ignored -- set \"debug\": true in veille.json first");
                return;
            }
            const parts = hhmm.split(":");
            const h = parseInt(parts[0], 10) || 0;
            const m = parseInt(parts[1], 10) || 0;
            const target = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate(), h, m, 0);
            root.debugOffsetMs = target.getTime() - sysClock.date.getTime();
        }

        // Clears the debug offset, back to the real clock.
        function resetNow(): void {
            root.debugOffsetMs = 0;
        }

        // `qs -c bar ipc call veille probe` -- prints the REAL class and
        // title Hyprland reports for whatever's focused right now, so
        // veille.json's appFamilies/tokenPatterns can be filled in from
        // fact instead of guesswork (see VeilleContext.qml's header
        // comment on why the table starts mostly empty).
        function probe(): string {
            if (!config.debug) return "veille debug disabled -- set \"debug\": true in veille.json";
            return "class=[" + context.windowClass + "] title=[" + context.windowTitle
                + "] family=[" + context.family + "] token=[" + context.token
                + "] level=" + context.level;
        }
    }
}
