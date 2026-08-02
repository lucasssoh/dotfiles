import QtQuick
import Quickshell.Io
import "../theme"

// Native port of waybar's `cpu` module. Still a Timer (there is no
// kernel/DBus event for "usage changed" -- see shell.qml header), but
// zero fork per tick: reads /proc/stat and /proc/cpuinfo directly via
// FileView instead of spawning top/awk/lscpu.
//
// Text matches config.jsonc's format string exactly: "  {usage:>3}
// {max_frequency:.1f}" -- icon, usage right-padded to 3 chars, NO "%"
// (waybar's own format string never had one), space, then the highest
// per-core frequency across /proc/cpuinfo's "cpu MHz" lines, in GHz to
// 1 decimal (also no unit suffix, matching waybar's raw
// {max_frequency:.1f} interpolation).

Item {
    id: root

    property real prevTotal: -1
    property real prevIdle: -1
    property int usage: 0
    property real maxGhz: 0

    // Fixed floor: "  100 9.9" is about the widest this ever gets.
    implicitWidth: Math.max(label.implicitWidth + 20, 76)
    implicitHeight: 24

    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
    }

    FileView {
        id: cpuInfoFile
        path: "/proc/cpuinfo"
        blockLoading: true
    }

    function sample() {
        statFile.reload();
        const line = statFile.text().split("\n")[0];
        const parts = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = parts[3] + parts[4];
        const total = parts.reduce((a, b) => a + b, 0);
        if (root.prevTotal >= 0) {
            const dTotal = total - root.prevTotal;
            const dIdle = idle - root.prevIdle;
            root.usage = dTotal > 0 ? Math.round(100 * (1 - dIdle / dTotal)) : 0;
        }
        root.prevTotal = total;
        root.prevIdle = idle;

        cpuInfoFile.reload();
        const matches = cpuInfoFile.text().match(/cpu MHz\s*:\s*([\d.]+)/g) || [];
        let maxMhz = 0;
        for (let i = 0; i < matches.length; i++) {
            const v = parseFloat(matches[i].split(":")[1]);
            if (v > maxMhz) maxMhz = v;
        }
        root.maxGhz = maxMhz / 1000;
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 4

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""
            color: root.usage >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.icon
            font.pixelSize: 13
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: String(root.usage).padStart(3, " ") + " " + root.maxGhz.toFixed(1)
            color: root.usage >= 90 ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }
}
