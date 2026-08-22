import QtQuick
import Quickshell.Io
import "../theme"

// Native port of waybar's `memory` module. Timer + direct /proc/meminfo
// read via FileView -- no free/awk subprocess.

Item {
    id: root

    property real usedGB: 0
    property int usedPct: 0

    implicitWidth: Math.max(label.implicitWidth + 20, 72)   // 70 -> 72, point 6: 4pt grid
    implicitHeight: 24

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
    }

    function sample() {
        memFile.reload();
        const lines = memFile.text().split("\n");
        let total = 0, avail = 0;
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (l.indexOf("MemTotal:") === 0) total = parseInt(l.split(/\s+/)[1]);
            else if (l.indexOf("MemAvailable:") === 0) avail = parseInt(l.split(/\s+/)[1]);
        }
        const usedKB = total - avail;
        root.usedGB = usedKB / 1024 / 1024;
        root.usedPct = total > 0 ? Math.round(100 * usedKB / total) : 0;
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        // Phosphor vs Inter: box-centering (anchors.verticalCenter) is
        // what measured aligned for Phosphor -- see Temperature.qml's
        // comment for the full reasoning/history.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // ph-memory
            color: root.usedPct >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 14
        }
        Text {
            id: valueLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: root.usedGB.toFixed(1) + "G"
            color: root.usedPct >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 12
        }
    }
}
