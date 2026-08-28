import QtQuick
import Quickshell
import Quickshell.Networking
import "../theme"

// Native-ish port of waybar's `network` module -- connection-type icon
// only now (ethernet/wifi/none). Used to also show the download rate in
// the same pill; that half moved to Traffic.qml in METRICS (asked for),
// leaving this "simple and stable" like Bluetooth.qml's own icon-only
// module became once its battery % was dropped.
//
// WHICH interface is active, and wifi's signal strength: both plain
// reactive bindings over Quickshell.Networking now (NetworkManager's own
// DBus objects, same family as Bluetooth.qml/Battery.qml) -- no more
// `nmcli monitor` watcher, no more re-run `nmcli`/awk script on every
// change or on a 10s poll for signal drift. signalStrength is already a
// live double on WifiNetwork, no parsing needed. Own detect logic here,
// not shared with SystemStats.qml's (same shape, different consumer) --
// harmless now: Networking itself is the single shared native source
// both read from, there's no process left to duplicate.

Item {
    id: root

    // Ethernet beats wifi if both happen to be connected, same priority
    // the old nmcli script used.
    readonly property var activeDevice: {
        const devices = Networking.devices.values;
        let wifi = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d.connected) continue;
            if (d.type === DeviceType.Wired) return d;
            if (d.type === DeviceType.Wifi) wifi = d;
        }
        return wifi;
    }
    readonly property string kind: !activeDevice ? "none" : (activeDevice.type === DeviceType.Wired ? "ethernet" : "wifi")   // "wifi" | "ethernet" | "none"
    readonly property int wifiSignal: {   // 0-100, only meaningful when kind === "wifi"
        if (kind !== "wifi" || !activeDevice) return 0;
        const nets = activeDevice.networks.values;
        for (let i = 0; i < nets.length; i++) {
            if (nets[i].connected) return Math.round(nets[i].signalStrength);
        }
        return 0;
    }

    // Icon-only, same narrow floor as Bluetooth.qml/Performance.qml's
    // own icon-only modules.
    implicitWidth: Math.max(iconText.implicitWidth + 12, 24)
    implicitHeight: 24

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
        font.pixelSize: 16
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["bash", "-c", "$HOME/.config/waybar/scripts/balise-toggle.sh wifi"]);
            else
                Quickshell.execDetached(["wezterm", "start", "--class", "nm-tui-float", "--", "nmtui"]);
        }
    }
}
