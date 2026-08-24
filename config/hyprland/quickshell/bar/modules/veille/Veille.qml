import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../../theme"

// VEILLE -- a large, non-interactive clock that pulses briefly around
// each round hour at night (see VeillePhase.qml's `inPulse`) to make the
// passage of time hard to ignore during focused work/study, without
// sitting permanently on screen -- escalating through the evening, with
// occasional context-aware messages once it's late enough. Full design
// rationale in the project plan (temporal-drifting-hippo.md); this file
// is purely the wiring: VeilleConfig (hot-reloaded JSON) -> VeillePhase
// (time -> escalation level + pulse timing) + VeilleContext (focused
// window -> app family/token) -> VeilleMessages (what to say, and how
// often) -> the actual PanelWindow.
//
// Deliberately a single instance, not one per screen like `bar` -- a
// big clock repeated on every monitor would be noise, and unlike the bar
// (which needs one real surface per screen it spans), this is describing
// a single thing: how late it's gotten.
// Scope, not Item: this whole tree is a grouping container for logic
// components (VeilleConfig/Phase/Context/Messages) and one real window
// (the PanelWindow below), never itself rendered -- Scope is Quickshell's
// purpose-built non-visual QObject container (see quickshell-core's
// ReloadPropagator/Scope), so nothing here inherits Item's geometry
// properties it would never use.
Scope {
    id: root

    // Bound in from shell.qml -- Zen mode is a shared property on the
    // ShellRoot (`shell.zenMode`), not something this module can see on
    // its own without either a singleton or this kind of pass-through
    // (same idea as ActiveWindow.qml's `monitor` property).
    property bool zenMode: false

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
    function pickScreen() {
        const wanted = config.monitor;
        if (wanted === "") return Quickshell.screens[0] || null;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === wanted) return Quickshell.screens[i];
        }
        return Quickshell.screens[0] || null;
    }

    readonly property bool anchorTop: config.position.indexOf("top") === 0
    readonly property bool anchorBottom: config.position.indexOf("bottom") === 0
    readonly property bool anchorLeftEdge: config.position.indexOf("left") !== -1
    readonly property bool anchorRightEdge: config.position.indexOf("right") !== -1
    // Falls back to bottom-right if `position` is unrecognized, rather
    // than leaving the window unanchored (which would drift to whatever
    // the compositor's own default corner is).
    readonly property bool effTop: anchorTop && !anchorBottom
    readonly property bool effBottom: anchorBottom || (!anchorTop && !anchorBottom)
    readonly property bool effLeft: anchorLeftEdge && !anchorRightEdge
    readonly property bool effRight: anchorRightEdge || (!anchorLeftEdge && !anchorRightEdge)

    PanelWindow {
        id: overlay
        screen: root.pickScreen()

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "veille"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        color: "transparent"
        focusable: false
        exclusiveZone: 0
        // Empty region = accepts input NOWHERE on this surface, so every
        // click/scroll passes straight through to whatever's behind it
        // -- the one hard requirement from the plan ("ne bloque jamais
        // les clics"). First use of PanelWindow.mask in this repo (see
        // the plan's own risk list); an empty Region is the documented
        // Quickshell idiom for full click-through.
        mask: Region {}

        visible: !root.suppressed && (root.pickScreen() !== null)

        anchors {
            top: root.effTop
            bottom: root.effBottom
            left: root.effLeft
            right: root.effRight
        }
        margins {
            top: config.margins.y || 0
            bottom: config.margins.y || 0
            left: config.margins.x || 0
            right: config.margins.x || 0
        }

        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Column {
            id: content
            anchors.centerIn: parent
            spacing: 6

            Text {
                id: clockText
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                // Mono, not Fonts.ui -- the first real use of it (see
                // theme/fonts.css's own header: kept for exactly this
                // case, "fast-changing numeric readouts", previously
                // unused anywhere). Without it, each second's digits
                // subtly reflow the text's width under a proportional
                // font, which undercuts the "make time hard to ignore"
                // point by making the ticking itself look unstable.
                font.family: Fonts.mono
                font.pixelSize: phase.fontSize
                color: "#f2f2f7"
                opacity: phase.targetOpacity
                text: Qt.formatDateTime(root.now, config.showSeconds ? "HH:mm:ss" : "HH:mm")

                // Escalation should be FELT arriving, not snap -- asked
                // for implicitly by the whole "progressive" framing.
                Behavior on font.pixelSize {
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
            }

            Text {
                id: dateText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: config.showDate
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                font.family: Fonts.ui
                font.pixelSize: 16
                color: "#8e8e93"
                opacity: clockText.opacity
                text: Qt.formatDateTime(root.now, "dddd d MMMM")
            }

            Text {
                id: messageText
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(420, implicitWidth)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                font.family: Fonts.ui
                font.pixelSize: 15
                color: "#c7c7cc"
                text: messages.text
                opacity: messages.text !== "" ? 0.9 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                }
            }
        }
    }

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
