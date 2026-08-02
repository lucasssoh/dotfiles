import QtQuick
import Quickshell
import Quickshell.Io

// ============================================================
// Generic port of waybar's `custom/*` module contract: waybar's own
// custom modules are already a declarative "run this, expect JSON,
// re-run every N seconds, run this other thing on click" contract —
// Quickshell has no built-in equivalent (everything is QML/JS), so
// this recreates that one contract as a reusable component. Every
// custom/* entry from waybar/config.jsonc becomes one instantiation of
// this component with different `command`/`interval`/click values,
// instead of 10 hand-rolled Process+Timer blocks.
//
// JSON mode expects the same {"text":...,"class":...,"tooltip":...}
// shape the existing waybar/scripts/*.sh scripts already print — those
// scripts are reused unchanged (see shell.qml).
// ============================================================

Item {
    id: root

    property var command: []            // e.g. ["bash", "-c", "...status"]
    property int interval: 5000         // ms, 0 = run once, no polling
    property bool json: true            // parse stdout as {text,class,tooltip} vs raw text
    property var clickCommand: []       // left-click, fire-and-forget
    property var rightClickCommand: []  // right-click, fire-and-forget
    property var classColors: ({})      // {"hdr-on": "#4fefff", ...} -- mirrors
                                         // the #custom-hdr.hdr-on {color: ...}
                                         // class selectors in waybar/style.css
    property var classIcons: ({})       // {"notification": "", ...} -- for
                                         // modules whose JSON "text" is data
                                         // (e.g. swaync's unread count) rather
                                         // than the glyph itself; mirrors
                                         // waybar's "format-icons" keyed by
                                         // class/alt. Empty = show obj.text
                                         // as-is (the common case).

    property string text: ""
    property string tooltip: ""
    property string moduleClass: ""

    property real textOpacity: 1.0      // waybar/style.css per-module opacity (e.g. #custom-apps: 0.8)
    property real letterSpacing: 0      // waybar/style.css per-module letter-spacing (e.g. #custom-apps: 4px)
    property real minWidth: 0           // floor in px -- mirrors waybar's "min-length"/CSS
                                         // min-width, reserves space so a module's own text
                                         // changing length (or briefly being empty before the
                                         // first poll) doesn't shift every module after it
    property real padding: 20           // total horizontal padding (both sides combined,
                                         // since the label is centered) -- per-instance so one
                                         // glued pair (e.g. display+hdr) can sit tighter without
                                         // affecting other ScriptModule instances (apps, etc.)

    implicitWidth: Math.max(label.implicitWidth + root.padding, root.minWidth)
    implicitHeight: 24

    function poll() {
        if (!proc.running) proc.running = true;
    }

    Process {
        id: proc
        command: root.command
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                if (!root.json) {
                    root.text = out;
                    return;
                }
                try {
                    const obj = JSON.parse(out);
                    root.text = obj.text || "";
                    root.tooltip = obj.tooltip || "";
                    root.moduleClass = obj.class || "";
                } catch (e) {
                    // Non-JSON output on a json:true module -- show it raw
                    // rather than going blank, easier to spot while wiring
                    // up a new module.
                    root.text = out;
                }
            }
        }
    }

    Timer {
        interval: root.interval
        running: root.interval > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    Component.onCompleted: if (root.interval === 0) root.poll();

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: root.classIcons[root.moduleClass] !== undefined
            ? root.classIcons[root.moduleClass] : root.text
        color: root.classColors[root.moduleClass] || "#f2f2f7"
        opacity: root.textOpacity
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        font.letterSpacing: root.letterSpacing
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton && root.clickCommand.length > 0)
                Quickshell.execDetached(root.clickCommand);
            else if (mouse.button === Qt.RightButton && root.rightClickCommand.length > 0)
                Quickshell.execDetached(root.rightClickCommand);
        }
    }
}
