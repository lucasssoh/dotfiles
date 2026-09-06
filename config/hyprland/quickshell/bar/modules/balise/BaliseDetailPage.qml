import QtQuick
import "../../theme"
import "../../services"

// Endpoint detail page -- third slice of the Balise QML rewrite (see the
// project plan), reached by tapping a WiFi/Bluetooth/Ethernet row
// outside its own Connect/Disconnect pill. One shared file for all
// three kinds, same as balise-src's own ui/detail.rs (its own header:
// "a real Stack page... works identically for WiFi/Bluetooth/
// Ethernet") -- ported here as one Item computing per-kind display data
// rather than three build_wifi/build_bluetooth/build_ethernet
// functions building separate widget trees, since QML's declarative
// layout doesn't need the imperative construction ui/detail.rs does.
//
// Read/toggle/forget for an already-paired/saved endpoint only -- no
// password entry for a new secured WiFi network, no Bluetooth pairing
// (needs the BlueZ agent bridged to QML, a separate pass). An unpaired
// Bluetooth device's page is informational only, no action button --
// asked for explicitly ("un appareil non appairé montre juste ses
// infos, pas de bouton Pair").
//
// Calls BaliseState directly rather than emitting per-action signals
// like BaliseNetworkRow/BaliseDeviceRow/BaliseWiredRow do -- unlike
// those reusable row delegates, this page's every action is already
// uniquely tied to the one endpoint it's currently showing (ap/device/
// profile), so a signal→BaliseHome→BaliseState relay would just add
// indirection with no real decoupling benefit.
Item {
    id: root

    property bool drawerOpen: false
    property string kind: ""   // "wifi" | "bluetooth" | "ethernet"
    property var ap: null              // AccessPoint (wifi)
    property var details: null         // WifiDetails (wifi)
    property var device: null          // BluetoothDevice (bluetooth)
    property var profile: null         // WiredProfile (ethernet)
    signal backRequested()

    readonly property color accent: "#a8b4c4"
    readonly property color destructive: "#ff6e6e"

    // Sized by whichever page layer holds it (BaliseHome.qml's own two
    // sliding Loaders, at its fixed `pageHeight`) -- this page no longer
    // drives the island's height, so there's no `Behavior on height`
    // here any more either: an endpoint with a lot of metadata scrolls
    // inside the box below instead of growing it.
    implicitHeight: layout.implicitHeight

    // WiFi's title/status fall back to `details` (its own `ssid`/
    // `is_connected`) when `ap` isn't around -- the two are fetched
    // independently (ap comes from the list's own live push, details
    // from its own one-shot fetch), so a scan landing between opening
    // the page and either arriving shouldn't blank the whole page out.
    readonly property string pageTitle: {
        if (root.kind === "wifi") return root.ap ? root.ap.ssid : (root.details ? root.details.ssid : "");
        if (root.kind === "bluetooth") return root.device ? root.device.name : "";
        if (root.kind === "ethernet") return root.profile ? root.profile.name : "";
        return "";
    }

    readonly property bool statusConnected: {
        if (root.kind === "wifi") return root.ap ? !!root.ap.is_connected : !!(root.details && root.details.is_connected);
        if (root.kind === "bluetooth") return !!(root.device && root.device.is_connected);
        if (root.kind === "ethernet") return !!(root.profile && root.profile.is_active);
        return false;
    }

    readonly property string statusText: {
        if (root.kind === "wifi" && (root.ap || root.details)) {
            if (root.statusConnected) {
                const speed = root.details && root.details.speed ? " · " + root.details.speed : "";
                return root.ap ? "Connected · " + root.ap.signal + "% signal" : "Connected" + speed;
            }
            const saved = root.details && root.details.settings_path !== "";
            return root.ap ? (root.ap.signal + "% signal · " + (saved ? "saved" : "not saved")) : (saved ? "Saved · not connected" : "Not connected");
        }
        if (root.kind === "bluetooth" && root.device) {
            if (root.device.is_connected) {
                const pct = root.device.battery_percentage;
                if (pct !== null && pct !== undefined) return "Connected · " + pct + "%" + (root.device.is_charging ? " (charging)" : "");
                return "Connected";
            }
            return root.device.is_paired ? "Paired · not connected" : "Available · not paired";
        }
        if (root.kind === "ethernet" && root.profile) {
            if (root.profile.is_active) return "Connected" + (root.profile.speed > 0 ? " · " + root.profile.speed + " Mb/s" : "");
            return root.profile.has_carrier ? "Cable connected · not active" : "No cable";
        }
        return "";
    }

    readonly property string metaSectionLabel: root.kind === "wifi" ? "NETWORK" : (root.kind === "bluetooth" ? "DEVICE" : "INTERFACE")

    readonly property var metaRows: {
        const rows = [];
        if (root.kind === "wifi" && (root.ap || root.details)) {
            // ap-derived and details-derived rows are independent (see
            // pageTitle/statusText's own header) -- either can be
            // missing without blanking the other's rows out.
            if (root.ap) {
                rows.push({ label: "Security", value: root.ap.security !== "none" ? "Secured" : "Open" });
                rows.push({ label: "Signal", value: root.ap.signal + "%" });
            }
            const d = root.details;
            if (d) {
                if (d.speed) rows.push({ label: "Link speed", value: d.speed });
                if (d.ip4_address) rows.push({ label: "IPv4", value: d.ip4_address });
                if (d.gateway) rows.push({ label: "Gateway", value: d.gateway });
                if (d.dns_servers && d.dns_servers.length > 0) rows.push({ label: "DNS", value: d.dns_servers.join(", ") });
                if (d.ip6_address) rows.push({ label: "IPv6", value: d.ip6_address });
                if (d.mac_address) rows.push({ label: "MAC", value: d.mac_address });
            }
        } else if (root.kind === "bluetooth" && root.device) {
            const kindLabel = { audio: "Audio", keyboard: "Keyboard", mouse: "Mouse", phone: "Phone", other: "Other" }[root.device.device_type] || "Other";
            rows.push({ label: "Type", value: kindLabel });
            if (root.device.address) rows.push({ label: "Address", value: root.device.address });
            const pct = root.device.battery_percentage;
            if (pct !== null && pct !== undefined) rows.push({ label: "Battery", value: pct + "%" + (root.device.is_charging ? " (charging)" : "") });
            if (root.device.rssi) rows.push({ label: "Signal", value: root.device.rssi + " dBm" });
            rows.push({ label: "Paired", value: root.device.is_paired ? "Yes" : "No" });
        } else if (root.kind === "ethernet" && root.profile) {
            const p = root.profile;
            if (p.device_name) rows.push({ label: "Device", value: p.device_name });
            if (p.speed > 0) rows.push({ label: "Link speed", value: p.speed + " Mb/s" });
            if (p.ip4_address) rows.push({ label: "IPv4", value: p.ip4_address });
            if (p.gateway) rows.push({ label: "Gateway", value: p.gateway });
            if (p.dns_servers && p.dns_servers.length > 0) rows.push({ label: "DNS", value: p.dns_servers.join(", ") });
            if (p.mac_address) rows.push({ label: "MAC", value: p.mac_address });
        }
        return rows;
    }

    // Autoconnect (WiFi/Ethernet, only for a stored profile) / Trusted
    // (Bluetooth, only for an already-paired device) -- same "only means
    // something for a stored/paired endpoint" gate ui/detail.rs applies.
    readonly property bool hasOptions: {
        if (root.kind === "wifi") return !!(root.details && root.details.settings_path !== "");
        if (root.kind === "bluetooth") return !!(root.device && root.device.is_paired);
        if (root.kind === "ethernet") return !!(root.profile && root.profile.connection_path !== "");
        return false;
    }
    readonly property string optionsLabel: root.kind === "bluetooth" ? "Trusted device" : "Connect automatically"
    readonly property string optionsSubtitle: root.kind === "bluetooth"
        ? "Allow connecting without confirmation"
        : "Reconnect whenever it is in range"
    readonly property bool optionsValue: {
        if (root.kind === "wifi") return !!(root.details && root.details.autoconnect);
        if (root.kind === "bluetooth") return !!(root.device && root.device.is_trusted);
        if (root.kind === "ethernet") return !!(root.profile && root.profile.autoconnect);
        return false;
    }
    function onOptionsToggled(on) {
        if (root.kind === "wifi" && root.details) {
            BaliseState.setWifiAutoconnect(root.ap ? root.ap.ssid : root.details.ssid, root.details.settings_path, on);
        } else if (root.kind === "bluetooth" && root.device) {
            BaliseState.setBluetoothTrust(root.device.path, on);
        } else if (root.kind === "ethernet" && root.profile) {
            BaliseState.setEthernetAutoconnect(root.profile.connection_path, on);
        }
    }

    // An open network, or a secured one that already has a saved
    // profile -- the same gate BaliseNetworkRow's own pill used to
    // apply before connect/disconnect moved onto this page.
    readonly property bool wifiConnectable: {
        if (!root.ap) return !!(root.details && root.details.settings_path !== "");
        if (root.ap.security === "none") return true;
        return !!root.ap.is_saved || !!(root.details && root.details.settings_path !== "");
    }

    // { label, style: "primary"|"normal"|"destructive", token } -- one
    // dispatch function below rather than a JS function reference per
    // entry, simpler to reason about from a plain data array.
    readonly property var actions: {
        const list = [];
        if (root.kind === "wifi" && (root.ap || root.details)) {
            if (root.statusConnected) {
                list.push({ label: "Disconnect", style: "normal", token: "wifi-disconnect" });
            } else if (root.wifiConnectable) {
                // The only Connect affordance there is now -- the list
                // rows lost their pills when they became single-action
                // chevron rows (see BaliseNetworkRow.qml's header). A
                // secured network with no saved profile still gets none,
                // since there's no password form in this pass.
                list.push({ label: "Connect", style: "primary", token: "wifi-connect" });
            }
            if (root.details && root.details.settings_path !== "") list.push({ label: "Forget this network", style: "destructive", token: "wifi-forget" });
        } else if (root.kind === "bluetooth" && root.device) {
            if (root.device.is_connected) list.push({ label: "Disconnect", style: "normal", token: "bt-disconnect" });
            else if (root.device.is_paired) list.push({ label: "Connect", style: "primary", token: "bt-connect" });
            if (root.device.is_paired) list.push({ label: "Forget this device", style: "destructive", token: "bt-forget" });
        } else if (root.kind === "ethernet" && root.profile) {
            if (root.profile.is_active) list.push({ label: "Disconnect", style: "normal", token: "eth-disconnect" });
            else if (root.profile.has_carrier) list.push({ label: "Connect", style: "primary", token: "eth-connect" });
        }
        return list;
    }
    function runAction(token) {
        switch (token) {
        case "wifi-connect": BaliseState.connectWifi(root.ap ? root.ap.ssid : root.details.ssid); break;
        case "wifi-disconnect": BaliseState.disconnectWifi(root.ap ? root.ap.ssid : root.details.ssid); root.backRequested(); break;
        case "wifi-forget": BaliseState.forgetWifi(root.details.settings_path); root.backRequested(); break;
        case "bt-disconnect": BaliseState.disconnectBluetooth(root.device.path); break;
        case "bt-connect": BaliseState.connectBluetooth(root.device.path); break;
        case "bt-forget": BaliseState.forgetBluetooth(root.device.path); root.backRequested(); break;
        case "eth-disconnect": BaliseState.disconnectEthernet(root.profile.device_path); break;
        case "eth-connect": BaliseState.connectEthernet(root.profile.connection_path, root.profile.device_path); break;
        }
    }

    // ---- header: pinned, like the section lists' own back row -- only
    // the body below it scrolls, so the way out of the page is always
    // reachable no matter how far down an endpoint's metadata runs.
    Item {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        height: 30

        Rectangle {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: 9
            color: backArea.containsMouse ? Surfaces.cardRaised : Surfaces.card
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "‹"
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 17
                font.bold: true
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.backRequested()
            }
        }

        Text {
            anchors.left: backBtn.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.pageTitle
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 17
            font.bold: true
            elide: Text.ElideRight
        }
    }

    // Same Flickable shell (and same StopAtBounds feel) the home grid
    // and the section lists' ListView use -- one scroll behaviour across
    // every page.
    Flickable {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerRow.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 14
        anchors.bottomMargin: 20
        contentWidth: body.width
        contentHeight: layout.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3000
        clip: true

        // Explicit x/width rather than anchors: inside a Flickable the
        // children's `parent` is the contentItem, which has no width of
        // its own to anchor against.
        Column {
            id: layout
            x: 20
            width: body.width - 40
            spacing: 16

        // ---- status card ----
        Rectangle {
            width: parent.width
            height: 44
            radius: 12
            color: root.statusConnected ? Surfaces.accentMedium : "#14161d"
            border.width: 1
            border.color: root.statusConnected ? root.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.statusText
                color: root.statusConnected ? root.accent : "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }
        }

        // ---- meta section ----
        Column {
            width: parent.width
            spacing: 8
            visible: root.metaRows.length > 0

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.metaSectionLabel
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: Fonts.ui
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Rectangle {
                width: parent.width
                height: metaColumn.implicitHeight + 16
                radius: 12
                color: Surfaces.card

                Column {
                    id: metaColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Repeater {
                        model: root.metaRows
                        delegate: Item {
                            required property var modelData
                            width: metaColumn.width
                            height: 18
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferNoHinting
                                text: modelData.label
                                color: "#8e8e93"
                                font.family: Fonts.ui
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.left: parent.left
                                anchors.leftMargin: 90
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferNoHinting
                                text: modelData.value
                                color: "#f2f2f7"
                                font.family: Fonts.ui
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // ---- options section (autoconnect / trusted) ----
        Column {
            width: parent.width
            spacing: 8
            visible: root.hasOptions

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "OPTIONS"
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: Fonts.ui
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Rectangle {
                width: parent.width
                height: 54
                radius: 12
                color: Surfaces.card

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: optToggle.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.optionsLabel
                        color: "#f2f2f7"
                        font.family: Fonts.ui
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.optionsSubtitle
                        color: "#8e8e93"
                        font.family: Fonts.ui
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                // Same track+thumb switch recipe as NotificationCenter.qml's
                // own DND toggle.
                Rectangle {
                    id: optToggle
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 22
                    radius: 11
                    color: root.optionsValue ? root.accent : Qt.rgba(1, 1, 1, 0.18)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: "#0c0c0e"
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.optionsValue ? parent.width - width - 2 : 2
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.onOptionsToggled(!root.optionsValue)
                }
            }
        }

        // ---- actions ----
        Column {
            width: parent.width
            spacing: 8
            visible: root.actions.length > 0

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "ACTIONS"
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: Fonts.ui
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Repeater {
                model: root.actions
                delegate: Rectangle {
                    id: actionBtn
                    required property var modelData
                    width: layout.width
                    height: 44
                    radius: 22
                    readonly property color tint: actionBtn.modelData.style === "destructive" ? root.destructive
                        : (actionBtn.modelData.style === "primary" ? root.accent : "#f2f2f7")
                    // Destructive gets a faintly red-tinted fill of its
                    // own (the mockup's "Oublier ce réseau"), primary the
                    // accent tint, everything else the plain bordered
                    // card the rest of this page uses.
                    color: {
                        const hovered = actionArea.containsMouse;
                        if (actionBtn.modelData.style === "destructive")
                            return hovered ? Surfaces.destructiveSoftHover : Surfaces.destructiveSoft;
                        if (actionBtn.modelData.style === "primary")
                            return hovered ? Surfaces.accentStrongest : Surfaces.accentMedium;
                        return hovered ? Surfaces.cardHover : Surfaces.card;
                    }
                    border.width: 1
                    border.color: {
                        if (actionBtn.modelData.style === "destructive")
                            return Qt.rgba(0xff / 255, 0x6e / 255, 0x6e / 255, 0.35);
                        if (actionBtn.modelData.style === "primary") return root.accent;
                        return "transparent";
                    }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: actionBtn.modelData.label
                        color: actionBtn.tint
                        font.family: Fonts.ui
                        font.pixelSize: 14
                        font.bold: true
                    }
                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction(actionBtn.modelData.token)
                    }
                }
            }
        }
        }
    }
}
