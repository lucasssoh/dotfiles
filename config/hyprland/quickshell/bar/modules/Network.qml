import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Native-ish port of waybar's `network` module -- connection-type icon
// only now (ethernet/wifi/none). Used to also show the download rate in
// the same pill; that half moved to Traffic.qml in METRICS (asked for),
// leaving this "simple and stable" like Bluetooth.qml's own icon-only
// module became once its battery % was dropped.
//
// WHICH interface is active: event-driven, a persistent `nmcli monitor`
// watcher triggers a cheap one-shot re-query only when connectivity
// actually changes -- same pattern as the old network StreamModule.
// Own detect Process, not shared with Traffic.qml's -- see that file's
// header comment for why.

Item {
    id: root

    property string iface: ""
    property string kind: "none"   // "wifi" | "ethernet" | "none"
    property int wifiSignal: 0     // 0-100, only meaningful when kind === "wifi"

    // Icon-only, same narrow floor as Bluetooth.qml/Performance.qml's
    // own icon-only modules.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

    Process {
        id: watcher
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line.trim() !== "" && !detect.running) detect.running = true; }
        }
    }

    Process {
        id: detect
        command: ["bash", "-c", `
e=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected" {print $1; exit}')
w=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}')
if [ -n "$e" ]; then
    printf '{"kind":"ethernet","iface":"%s","signal":0}' "$e"
elif [ -n "$w" ]; then
    sig=$(nmcli -t -f IN-USE,SIGNAL dev wifi list ifname "$w" 2>/dev/null | awk -F: '$1=="*" {print $2; exit}')
    [ -z "$sig" ] && sig=0
    printf '{"kind":"wifi","iface":"%s","signal":%s}' "$w" "$sig"
else
    printf '{"kind":"none","iface":"","signal":0}'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(this.text.trim());
                    root.kind = obj.kind;
                    root.iface = obj.iface;
                    root.wifiSignal = obj.signal || 0;
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: detect.running = true

    // Signal strength drifts (moving around, interference) without
    // `nmcli monitor` necessarily firing a connectivity-change line --
    // this is a deliberate light poll (like cpu/temp/etc.), not free,
    // kept slow and only while actually on wifi.
    Timer {
        interval: 10000
        running: root.kind === "wifi"
        repeat: true
        onTriggered: if (!detect.running) detect.running = true
    }

    // ph-plugs-connected (no dedicated "ethernet" glyph in Phosphor,
    // this is the closest -- a physically plugged-in connection) / ph-
    // wifi-low/medium/high / ph-wifi-slash. Phosphor only ships 3 wifi-
    // strength tiers, not waybar's original 5 -- same kind of coarsening
    // already accepted on Battery's 10 -> 5 tiers earlier.
    function icon() {
        if (root.kind === "ethernet") return "";
        if (root.kind === "wifi") {
            const s = root.wifiSignal;
            if (s < 33) return "";
            if (s < 66) return "";
            return "";
        }
        return "";
    }

    // Point 4 (HIG "clarity": color carries state, not decoration) --
    // "none" is a real inactive state (no interface at all), same muted
    // token ActiveWindow/Media/Hdr already use for their own "nothing
    // here" placeholders. Single centered Text, no paired value any
    // more -- no Row/alignment fix needed.
    Text {
        id: iconText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.centerIn: parent
        text: root.icon()
        color: root.kind === "none" ? "#636366" : "#f2f2f7"
        font.family: Fonts.iconPhosphor
        font.pixelSize: 15
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["bash", "-c", "$HOME/.config/waybar/scripts/orbit-toggle.sh wifi"]);
            else
                Quickshell.execDetached(["wezterm", "start", "--class", "nm-tui-float", "--", "nmtui"]);
        }
    }
}
