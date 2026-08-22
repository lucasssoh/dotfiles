import QtQuick
import Quickshell.Io
import "../theme"

// Native port of waybar/scripts/fan.sh. The hwmon path needs a glob
// (fan1_input under hwmon0, hwmon1, ... -- the number isn't stable
// across machines), which FileView can't do -- so it's resolved ONCE at
// startup via a one-shot Process (not periodic), then every tick after
// that is a direct FileView read of that resolved path, no subprocess.

Item {
    id: root

    property string fanPath: ""
    property string rpm: "N/A"

    // rpm is already padStart(4)'d, this floor just also covers "N/A"
    // during the one-time hwmon discovery at startup.
    implicitWidth: Math.max(label.implicitWidth + 20, 60)
    implicitHeight: 24
    visible: root.fanPath !== ""

    Process {
        id: discover
        command: ["bash", "-c", "find /sys/class/hwmon/hwmon*/fan1_input 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.fanPath = this.text.trim();
                if (root.fanPath !== "") {
                    fanFile.path = root.fanPath;
                    root.sample();
                }
            }
        }
    }

    FileView {
        id: fanFile
        blockLoading: true
    }

    function sample() {
        if (root.fanPath === "") return;
        fanFile.reload();
        const v = parseInt(fanFile.text().trim());
        root.rpm = isNaN(v) ? "N/A" : String(v).padStart(4, " ");
    }

    Timer {
        interval: 10000
        running: root.fanPath !== ""
        repeat: true
        onTriggered: root.sample()
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        // Box-centering (anchors.verticalCenter) -- see Temperature.qml's
        // comment for the full history of why the right anchor mode
        // depends on the specific icon font, not a fixed rule.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // ph-fan
            color: "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 14
        }
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: root.rpm
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 12
        }
    }
}
