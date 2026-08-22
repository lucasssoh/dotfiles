import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// ============================================================
// Event-driven counterpart to ScriptModule.qml: no Timer at all. A
// long-running "watch" process is started once and left running --
// each line it prints is a push notification of a real state change,
// not a re-poll on a clock. Two shapes:
//
//   watchIsData: true   the watcher's own stdout lines ARE the fresh
//                        {text,class,tooltip} JSON. e.g. `swaync-client
//                        --subscribe-waybar`, which streams one JSON
//                        line per notification add/close -- it was
//                        already event-driven upstream, waybar's own
//                        "custom/notification" module just consumes it
//                        the same way (no "interval" key in
//                        config.jsonc, on purpose).
//
//   watchIsData: false  the watcher's lines are just a wake-up signal
//                        (e.g. `nmcli monitor` prints a terse line on
//                        any connectivity change); `queryCommand` is a
//                        cheap one-shot re-run to fetch the actual
//                        status JSON, executed only when the watcher
//                        actually says something changed -- never on a
//                        timer.
// ============================================================

Item {
    id: root

    property var watchCommand: []
    property bool watchIsData: true
    property var queryCommand: []       // used when watchIsData is false
    property bool json: true
    property var clickCommand: []
    property var rightClickCommand: []
    property var classColors: ({})
    property var classIcons: ({})

    property string text: ""
    property string tooltip: ""
    property string moduleClass: ""
    property real minWidth: 0

    implicitWidth: Math.max(label.implicitWidth + 20, root.minWidth)
    implicitHeight: 24

    function applyOutput(out) {
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
            root.text = out;
        }
    }

    Process {
        id: watcher
        command: root.watchCommand
        running: true    // started once, left running for the module's lifetime
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim();
                if (trimmed === "") return;
                if (root.watchIsData) root.applyOutput(trimmed);
                else if (!query.running) query.running = true;
            }
        }
    }

    // Only used in watchIsData:false mode -- one-shot, re-triggered by
    // the watcher above, never by a clock.
    Process {
        id: query
        command: root.queryCommand
        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text.trim())
        }
    }

    Component.onCompleted: {
        if (!root.watchIsData && root.queryCommand.length > 0) query.running = true;
    }

    // Fonts.icon: every current instantiation of this component (just the
    // notification module today, see shell.qml) only ever shows an icon
    // glyph here, never mixed with prose -- a future instance that needs
    // real text alongside would need its own Text/Row split, same as e.g.
    // Bluetooth.qml.
    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: parent
        text: root.classIcons[root.moduleClass] !== undefined
            ? root.classIcons[root.moduleClass] : root.text
        color: root.classColors[root.moduleClass] || "#f2f2f7"
        font.family: Fonts.iconPhosphor
        font.pixelSize: 14
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
