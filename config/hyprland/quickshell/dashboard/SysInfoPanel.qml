import QtQuick
import Quickshell
import Quickshell.Io

// Top-left system info panel. Replaces BOTH dashboard-fastfetch.sh (the
// wezterm-pinned terminal) and the original hand-rolled bash one-liner
// this file used to run itself: `fastfetch --format json` gives the
// exact same fields (and detection logic -- GPU vendor/model, display
// manager, WM, ...) as the real fastfetch, as plain structured data
// instead of an ANSI-art terminal frame, so there's no wezterm process
// (or any terminal at all) involved anymore. The wheel/hex logo chafa
// used to draw is reproduced natively too -- see `logo` below -- by
// deliberately downsampling the same source image (rayponce.jpg) before
// scaling it back up with smooth:false, the QML equivalent of chafa's
// blocky ascii-block rendering.

PanelWindow {
    id: root

    focusable: false
    exclusiveZone: 0
    aboveWindows: true

    anchors { top: true; left: true }
    margins { top: 64; left: 64 }

    implicitWidth: 640
    implicitHeight: 260
    color: "transparent"

    // [key, value] pairs, filled in from fastfetch's own JSON modules --
    // see config.jsonc's `modules` list, which this deliberately mirrors
    // (same fields fastfetch itself would show, minus Colors/Custom
    // separators and Terminal, which has no meaning without one).
    property var infoLines: [["Loading", "…"]]

    Process {
        id: infoProc
        command: ["fastfetch", "--format", "json", "-c",
            Quickshell.env("HOME") + "/.config/fastfetch/config.jsonc"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = [];
                try {
                    const data = JSON.parse(this.text);
                    const get = t => data.find(m => m.type === t && !m.error);
                    const cpu = get("CPU")?.result;
                    const gpus = (get("GPU") || {}).result || [];
                    const mem = get("Memory")?.result;
                    const os = get("OS")?.result;
                    const kernel = get("Kernel")?.result;
                    const lm = get("LM")?.result;
                    const wm = get("WM")?.result;

                    if (cpu) lines.push(["CPU", cpu.cpu + " (" + cpu.cores.logical + ") @ "
                        + (cpu.frequency.max / 1000).toFixed(2) + " GHz"]);
                    for (const g of gpus)
                        lines.push(["GPU", [g.vendor, g.name].filter(Boolean).join(" ")
                            + (g.type ? " [" + g.type + "]" : "")]);
                    if (mem) {
                        const used = mem.used / 1073741824, total = mem.total / 1073741824;
                        lines.push(["Memory", used.toFixed(2) + " GiB / " + total.toFixed(2)
                            + " GiB (" + Math.round(used / total * 100) + "%)"]);
                    }
                    if (os) lines.push(["OS", os.prettyName + (kernel ? " " + kernel.architecture : "")]);
                    if (kernel) lines.push(["Kernel", kernel.name + " " + kernel.release]);
                    if (lm) lines.push(["DM", lm.service + (lm.type ? " (" + lm.type + ")" : "")]);
                    if (wm) lines.push(["WM", wm.prettyName + " " + wm.version
                        + (wm.protocolName ? " (" + wm.protocolName + ")" : "")]);
                } catch (e) {
                    lines = [["Error", "fastfetch output couldn't be parsed"]];
                }
                if (lines.length > 0) root.infoLines = lines;
            }
        }
    }

    // Re-runs every 5s while shown (uptime/memory/frequency drift); no
    // timer at all runs while hidden, same principle as before.
    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!infoProc.running) infoProc.running = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#1c1c1e"    // colors.lua: background
        opacity: 0.85
        border.width: 1
        border.color: "#2c2c2e"  // colors.lua: surface

        Row {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            // Pixelated logo: the Image loader is told to decode at a
            // tiny resolution (sourceSize), so every "pixel" it hands
            // the GPU is already a big flat-colored block -- then it's
            // scaled back up with smooth:false (no bilinear filtering),
            // which keeps those blocks hard-edged instead of blurring
            // them back into a smooth image. Same visual idea as chafa's
            // ascii-block rendering, without needing chafa or a terminal
            // to produce it.
            Image {
                id: logo
                anchors.verticalCenter: parent.verticalCenter
                source: "file://" + Quickshell.env("HOME") + "/.config/fastfetch/rayponce.jpg"
                sourceSize.width: 26
                sourceSize.height: Math.round(26 * 463 / 360)
                smooth: false
                mipmap: false
                fillMode: Image.PreserveAspectFit
                width: 150
                height: Math.round(150 * 463 / 360)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Repeater {
                    model: root.infoLines
                    delegate: Row {
                        required property var modelData
                        spacing: 10

                        Text {
                            width: 60
                            text: modelData[0]
                            color: "#4fefff"  // colors.lua: accent2 -- same accent used across the bar
                            font.family: "SF Pro Text"
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Text {
                            text: modelData[1]
                            color: "#e5e5ea"  // colors.lua: text
                            font.family: "SF Pro Text"
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }
    }
}
