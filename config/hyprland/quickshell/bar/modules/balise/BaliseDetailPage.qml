import QtQuick
import Qt5Compat.GraphicalEffects
import ".."
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
// WiFi credential entry lives here now (fourth slice): a secured network
// with no saved profile gets a form on this page instead of the "no
// Connect button at all" dead end it used to be, and that form covers
// enterprise networks (eduroam and the rest of the 802.1X family) as well
// as ordinary passphrase ones -- username, EAP method and phase-2 auth,
// not just a password box. A saved network can reopen the same form to
// replace credentials that stopped working.
//
// Bluetooth pairing is still out (it needs the BlueZ agent bridged to
// QML, a separate pass). An unpaired Bluetooth device's page stays
// informational only, no action button -- asked for explicitly ("un
// appareil non appairé montre juste ses infos, pas de bouton Pair").
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

    readonly property color accent: Ink.accent
    readonly property color destructive: Ink.danger

    // ---- WiFi credential entry ------------------------------------------
    // The SSID every WiFi action on this page targets. `ap` and `details`
    // are fetched independently and either can be briefly missing (see
    // pageTitle's own header), so this reads whichever is there.
    readonly property string wifiSsid: root.ap ? String(root.ap.ssid || "") : (root.details ? String(root.details.ssid || "") : "")
    // Security kind, preferring the live scan and falling back to what the
    // saved profile stored (WifiDetails.security, added for exactly this
    // -- a saved network out of range has no AccessPoint to read). "" when
    // neither is known yet, which is treated as "don't offer a form".
    readonly property string wifiSecurity: {
        if (root.ap && root.ap.security) return String(root.ap.security);
        if (root.details && root.details.security) return String(root.details.security);
        return "";
    }
    readonly property bool wifiSecured: root.wifiSecurity !== "" && root.wifiSecurity !== "none"
    readonly property bool wifiEnterprise: root.wifiSecurity === "enterprise" || root.wifiSecurity === "wpa3_enterprise"
    readonly property bool wifiSaved: !!(root.details && root.details.settings_path !== "")

    // ---- sharing (fifth slice) ------------------------------------------
    // Offered only for a network whose profile lives on this machine (the
    // key is read back out of it -- there is no reading one off the air)
    // and never for 802.1X: the `WIFI:` format carries no username, no
    // EAP method and no certificate, so an eduroam code would scan and
    // then fail to join. The daemon refuses those too; this is what keeps
    // the button from being offered in the first place.
    readonly property bool wifiShareable: root.kind === "wifi" && root.wifiSaved && !root.wifiEnterprise
    property bool shareOpen: false
    // This network's own code, or null -- BaliseState.wifiShare is a
    // broadcast slot shared by every Share action (see its own header).
    readonly property var shareResult: {
        const r = BaliseState.wifiShare;
        if (!r || root.kind !== "wifi" || r.ssid !== root.wifiSsid) return null;
        return r;
    }
    readonly property var shareMatrix: root.shareResult && !root.shareResult.error ? root.shareResult.qr : null
    readonly property string shareError: root.shareResult ? String(root.shareResult.error || "") : ""

    // The grid is a joinable credential: drop it as soon as it is off
    // screen rather than leaving it in the singleton until something else
    // overwrites it.
    onShareOpenChanged: {
        if (!root.shareOpen) BaliseState.clearWifiShare();
    }
    Component.onDestruction: BaliseState.clearWifiShare()

    readonly property bool connecting: root.kind === "wifi" && root.wifiSsid !== "" && BaliseState.connectingSsid === root.wifiSsid
    // Only this network's own failure -- BaliseState.connectError is a
    // single slot shared by every attempt (it's a broadcast), so it
    // carries the SSID it belongs to and this filters on it.
    readonly property string connectError: {
        const e = BaliseState.connectError;
        if (!e || root.kind !== "wifi" || e.ssid !== root.wifiSsid) return "";
        return String(e.message || "");
    }

    // Opened by the "Change credentials" action on an already-saved
    // network. An unsaved secured one doesn't need it: there is no stored
    // secret to reuse, so the form is the only way in and shows itself.
    property bool credentialsOpen: false
    readonly property bool showCredentials: root.kind === "wifi"
        && root.wifiSecured
        && !root.statusConnected
        // A rejected credential re-opens the form on its own, saved or
        // not: the message is useless without the field it refers to.
        && (!root.wifiSaved || root.credentialsOpen || root.connectError !== "")

    // EAP/phase-2 pickers keep their state here; the three text values
    // live in the fields themselves (`passwordField.text` and friends
    // below) rather than being mirrored into properties, so there is
    // exactly one copy of a typed password in memory and clearing the
    // field clears it. Defaults match the daemon's own fallbacks (see
    // WifiCredentials' field docs): PEAP + MSCHAPv2, what eduroam
    // deployments overwhelmingly use.
    property string credEap: "peap"
    property string credPhase2: "mschapv2"
    property bool credAdvancedOpen: false

    readonly property bool canSubmit: passwordField.text !== ""
        && (!root.wifiEnterprise || identityField.text !== "")
        && !root.connecting

    function submitCredentials() {
        if (!root.canSubmit) return;
        BaliseState.connectWifi(root.wifiSsid, root.wifiSecurity, {
            password: passwordField.text,
            // Enterprise-only fields are sent empty otherwise rather than
            // omitted, so the daemon's own struct fills in identically
            // whichever branch built the object.
            identity: root.wifiEnterprise ? identityField.text : "",
            anonymous_identity: root.wifiEnterprise ? anonymousField.text : "",
            eap_method: root.wifiEnterprise ? root.credEap : "",
            phase2_auth: root.wifiEnterprise ? root.credPhase2 : ""
        });
    }

    // Drop the typed secret the moment it is no longer needed, rather than
    // leaving it in a field until this page happens to be destroyed. Only
    // the password: leaving the username filled in is a convenience, not a
    // secret, and the form may still be needed for a retry.
    onStatusConnectedChanged: {
        if (root.statusConnected) {
            passwordField.text = "";
            root.credentialsOpen = false;
        }
    }

    // The bar is `focusable: false` (shell.qml) -- a layer surface the
    // compositor sends no key events to. This is what lifts that while a
    // field is on screen; the Binding restores the previous value when
    // this page is destroyed or the form closes, so the bar goes back to
    // never taking focus. See BaliseState.textInputActive.
    Binding {
        target: BaliseState
        property: "textInputActive"
        value: true
        when: root.showCredentials
    }

    // Put the caret in the first empty field as the form appears, so the
    // user's click on the bar (which is what actually hands the layer
    // surface its keyboard focus -- see the Binding above) lands them
    // typing rather than hunting for the box. One frame late on purpose:
    // the fields have to exist and be laid out first.
    onShowCredentialsChanged: {
        if (root.showCredentials) focusTimer.restart();
    }
    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (root.wifiEnterprise && identityField.text === "") identityField.forceFieldFocus();
            else passwordField.forceFieldFocus();
        }
    }

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
            // Spelled out rather than the old "Secured"/"Open" pair: on
            // this page the exact kind is what tells the user whether the
            // form below is going to ask for a username.
            if (root.wifiSecurity !== "") rows.push({ label: "Security", value: BaliseState.securityLabel(root.wifiSecurity) });
            if (root.ap) rows.push({ label: "Signal", value: root.ap.signal + "%" });
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
            } else if (root.showCredentials) {
                // The form draws its own Connect (it has to know whether
                // the fields are filled in) -- no duplicate down here.
            } else if (root.wifiConnectable) {
                // The only Connect affordance there is now -- the list
                // rows lost their pills when they became single-action
                // chevron rows (see BaliseNetworkRow.qml's header).
                list.push({ label: root.connecting ? "Connecting…" : "Connect", style: "primary", token: "wifi-connect" });
            }
            // Way back into the form for a network whose stored secret
            // stopped working -- rotated campus password, retyped
            // passphrase after a router reset.
            if (root.wifiSecured && root.wifiSaved && !root.showCredentials && !root.statusConnected) {
                list.push({ label: "Change credentials", style: "normal", token: "wifi-credentials" });
            }
            if (root.wifiShareable) {
                list.push(root.shareOpen
                    ? { label: "Hide the QR code", style: "normal", token: "wifi-share-hide" }
                    : { label: "Share this network", style: "normal", token: "wifi-share" });
            }
            if (root.details && root.details.settings_path !== "") list.push({ label: "Forget this network", style: "destructive", token: "wifi-forget" });
        } else if (root.kind === "bluetooth" && root.device) {
            // Pair is the branch that was missing, and its absence left
            // this list EMPTY for any device not already paired: both
            // entries below are gated on is_paired, so a newly discovered
            // pair of headphones opened a detail page with no button on
            // it at all and no way to adopt it from the panel.
            if (root.device.is_connected) list.push({ label: "Disconnect", style: "normal", token: "bt-disconnect" });
            else if (root.device.is_paired) list.push({ label: "Connect", style: "primary", token: "bt-connect" });
            else list.push({ label: "Pair", style: "primary", token: "bt-pair" });
            if (root.device.is_paired) list.push({ label: "Forget this device", style: "destructive", token: "bt-forget" });
        } else if (root.kind === "ethernet" && root.profile) {
            if (root.profile.is_active) list.push({ label: "Disconnect", style: "normal", token: "eth-disconnect" });
            else if (root.profile.has_carrier) list.push({ label: "Connect", style: "primary", token: "eth-connect" });
        }
        return list;
    }
    function runAction(token) {
        switch (token) {
        // No credentials passed: this branch is only reachable for an
        // open network or a saved profile, both of which connect on what
        // NetworkManager already holds.
        case "wifi-connect": if (!root.connecting) BaliseState.connectWifi(root.wifiSsid, root.wifiSecurity, null); break;
        case "wifi-credentials": root.credentialsOpen = true; break;
        case "wifi-share": root.shareOpen = true; BaliseState.shareWifi(root.wifiSsid); break;
        case "wifi-share-hide": root.shareOpen = false; break;
        case "wifi-disconnect": BaliseState.disconnectWifi(root.wifiSsid); root.backRequested(); break;
        case "wifi-forget": BaliseState.forgetWifi(root.details.settings_path); root.backRequested(); break;
        case "bt-disconnect": BaliseState.disconnectBluetooth(root.device.path); break;
        case "bt-connect": BaliseState.connectBluetooth(root.device.path); break;
        case "bt-pair": BaliseState.pairBluetooth(root.device.path); break;
        case "bt-forget": BaliseState.forgetBluetooth(root.device.path); root.backRequested(); break;
        case "eth-disconnect": BaliseState.disconnectEthernet(root.profile.device_path); break;
        case "eth-connect": BaliseState.connectEthernet(root.profile.connection_path, root.profile.device_path); break;
        }
    }

    // ---- header: pinned, like the section lists' own back row -- only
    // the body below it scrolls, so the way out of the page is always
    // reachable no matter how far down an endpoint's metadata runs.
    // No inset of its own -- see BaliseSectionList.qml's header comment
    // for why (BaliseHome's `pageArea` already pads every page by 20, and
    // levels 2/3 were doubling it to 40 while level 1 stayed at 20).
    Item {
        id: headerRow
        RevealPop { item: headerRow; index: 0 }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 30

        Rectangle {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: 9

            // Same glass edge every other block in this bar now carries --
            // see GlassChip.qml. Only the block itself goes through the lens;
            // any icon tile nested inside it is left plain, or the two
            // rims would sit 4px apart and read as noise.
            // Only while this is HOVERED or ON -- asked for: the glass is a
            // state cue, not decoration, so a zone nobody is touching and
            // nothing has switched on carries no edge at all. It also means
            // the layer is allocated only for the one element in play.
            layer.enabled: backArea.containsMouse
            layer.effect: GlassChip { radius: 9 }
            color: backArea.containsMouse ? Surfaces.cardRaised : Surfaces.card
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "‹"
                color: Ink.primary
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
            color: Ink.primary
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
        contentWidth: body.width
        contentHeight: layout.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3000
        clip: true

        // Soft edges rather than a hard cut -- see ScrollFadeMask.qml.
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: bodyMask }

        // A child of the Flickable for the same reason as BaliseHome's --
        // this page's Flickable is a Component root, and only the mask's
        // size is ever read.
        ScrollFadeMask {
            id: bodyMask
            view: body
            width: body.width
            height: body.height
        }

        // Explicit x/width rather than anchors: inside a Flickable the
        // children's `parent` is the contentItem, which has no width of
        // its own to anchor against. x:0/full width now -- the 20px inset
        // this carried was the horizontal half of the same double padding
        // (see headerRow above).
        Column {
            id: layout
            x: 0
            width: body.width
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
                color: root.statusConnected ? root.accent : Ink.primary
                font.family: Fonts.ui
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }
        }

        // ---- credentials form ----
        // Above the metadata, not below it: on an unsaved secured network
        // this is the only thing on the page the user came here to do,
        // and the address rows underneath are all empty anyway until it
        // succeeds.
        //
        // The fields are instantiated unconditionally (only this Column's
        // `visible` flips) rather than sitting behind a Loader, because
        // `canSubmit` and `submitCredentials` read them by id -- a Loader
        // would make those references resolve to null on every page where
        // the form is hidden.
        Column {
            id: credentialsForm
            width: parent.width
            spacing: 8
            visible: root.showCredentials

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.wifiEnterprise ? "SIGN IN" : "PASSWORD"
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: Fonts.ui
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Rectangle {
                id: formCard
                RevealPop { item: formCard; index: 1 }
                width: parent.width
                height: formColumn.implicitHeight + 28
                radius: 12

                color: Surfaces.card

                Column {
                    id: formColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 14
                    spacing: 10

                    // Enterprise (eduroam & co) asks for a username as
                    // well -- the one thing that made those networks
                    // unreachable from here even once a password box
                    // existed.
                    BaliseTextField {
                        id: identityField
                        visible: root.wifiEnterprise
                        placeholder: "Username"
                        onAccepted: passwordField.forceFieldFocus()
                        onEscaped: root.backRequested()
                    }

                    BaliseTextField {
                        id: passwordField
                        placeholder: "Password"
                        secret: true
                        onAccepted: root.submitCredentials()
                        onEscaped: root.backRequested()
                    }

                    // Everything below is enterprise-only and defaulted --
                    // folded away so the common eduroam case is two
                    // fields and a button, and opened by the handful of
                    // deployments that want TTLS/PAP or an outer identity.
                    Item {
                        visible: root.wifiEnterprise
                        width: parent.width
                        height: 20

                        Text {
                            id: advancedLabel
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: (root.credAdvancedOpen ? "▾  " : "▸  ") + "EAP settings"
                            color: advancedArea.containsMouse ? Ink.primary : Ink.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 11
                            font.bold: true
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: advancedArea
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: advancedLabel.width + 16
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.credAdvancedOpen = !root.credAdvancedOpen
                        }
                    }

                    Column {
                        visible: root.wifiEnterprise && root.credAdvancedOpen
                        width: parent.width
                        spacing: 8

                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: "Method"
                            color: Ink.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 11
                        }
                        BaliseSegmented {
                            options: [
                                { label: "PEAP", value: "peap" },
                                { label: "TTLS", value: "ttls" },
                                { label: "PWD", value: "pwd" }
                            ]
                            value: root.credEap
                            onPicked: (v) => root.credEap = v
                        }

                        Text {
                            // EAP-PWD has no inner phase at all -- the
                            // daemon drops phase2-auth for it (NM rejects
                            // a profile carrying both), so offering the
                            // picker would be offering a no-op.
                            visible: root.credEap !== "pwd"
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: "Phase 2"
                            color: Ink.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 11
                        }
                        BaliseSegmented {
                            visible: root.credEap !== "pwd"
                            options: [
                                { label: "MSCHAPv2", value: "mschapv2" },
                                { label: "PAP", value: "pap" },
                                { label: "GTC", value: "gtc" }
                            ]
                            value: root.credPhase2
                            onPicked: (v) => root.credPhase2 = v
                        }

                        BaliseTextField {
                            id: anonymousField
                            placeholder: "Anonymous identity (optional)"
                            onAccepted: root.submitCredentials()
                            onEscaped: root.backRequested()
                        }
                    }

                    // The daemon's own message, verbatim ("Authentication
                    // failed -- check the credentials", "Connection
                    // timeout", ...). Sits directly above the button that
                    // produced it rather than in a toast, so the field to
                    // fix is still on screen next to the reason.
                    Text {
                        visible: root.connectError !== ""
                        width: parent.width
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.connectError
                        color: root.destructive
                        font.family: Fonts.ui
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 20

                        // Same glass edge every other block in this bar now carries --
                        // see GlassCard.qml. Only the block itself goes through the lens;
                        // any icon tile nested inside it is left plain, or the two
                        // rims would sit 4px apart and read as noise.
                        // Only while this is HOVERED or ON -- asked for: the glass is a
                        // state cue, not decoration, so a zone nobody is touching and
                        // nothing has switched on carries no edge at all. It also means
                        // the layer is allocated only for the one element in play.
                        layer.enabled: root.canSubmit || submitArea.containsMouse
                        layer.effect: GlassCard { radius: 20 }
                        color: {
                            if (!root.canSubmit) return Surfaces.card;
                            return submitArea.containsMouse ? Surfaces.accentStrongest : Surfaces.accentMedium;
                        }
                        border.width: 1
                        border.color: root.canSubmit ? root.accent : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: root.connecting ? "Connecting…" : "Connect"
                            color: root.canSubmit ? root.accent : Ink.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            id: submitArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.canSubmit
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submitCredentials()
                        }
                    }
                }
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
                id: metaCard
                RevealPop { item: metaCard; index: 2 }
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
                                color: Ink.secondary
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
                                color: Ink.primary
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
                id: optionsCard
                RevealPop { item: optionsCard; index: 3 }
                width: parent.width
                height: 54
                radius: 12

                // Same glass edge every other block in this bar now carries --
                // see GlassCard.qml. Only the block itself goes through the lens;
                // any icon tile nested inside it is left plain, or the two
                // rims would sit 4px apart and read as noise.
                // A toggle row, not a text block: it takes a click and
                // carries an on/off state, so it keeps the glass -- lit
                // only while it is actually on.
                layer.enabled: root.optionsValue
                layer.effect: GlassCard { radius: 12 }
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
                        color: Ink.primary
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
                        color: Ink.secondary
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

        // ---- share ----
        // Between the options and the buttons, mirroring ui/detail.rs's
        // own placement: pressing Share shouldn't push what appears off
        // the bottom of the page.
        Column {
            width: parent.width
            spacing: 8
            visible: root.shareOpen

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "SHARE"
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: Fonts.ui
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Rectangle {
                id: shareCard
                RevealPop { item: shareCard; index: 3 }
                width: parent.width
                height: shareColumn.implicitHeight + 28
                radius: 12
                color: Surfaces.card

                Column {
                    id: shareColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    spacing: 10

                    // A QR is read dark-on-light and this panel is dark,
                    // so the code gets its own white plate rather than
                    // being tinted to match the card. The quiet zone (the
                    // light border a scanner needs to find the finder
                    // patterns) is painted by the Canvas itself, inside
                    // this plate -- see onPaint.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 176
                        height: 176
                        radius: 8
                        color: "#ffffff"
                        visible: !!root.shareMatrix

                        Canvas {
                            id: qrCanvas
                            anchors.fill: parent
                            // Repaint whenever a new code lands: the
                            // Canvas caches its last frame and would
                            // otherwise keep showing the previous
                            // network's.
                            property var matrix: root.shareMatrix
                            onMatrixChanged: qrCanvas.requestPaint()
                            onPaint: {
                                const ctx = qrCanvas.getContext("2d");
                                ctx.reset();
                                ctx.fillStyle = "#ffffff";
                                ctx.fillRect(0, 0, qrCanvas.width, qrCanvas.height);

                                const m = qrCanvas.matrix;
                                if (!m || !m.rows || m.rows.length === 0) return;

                                // 4 light modules of border on each side,
                                // and whole pixels per module -- a
                                // fractional scale leaves some modules a
                                // pixel wider than their neighbours and
                                // the code reads as noise.
                                const quiet = 4;
                                const span = m.size + quiet * 2;
                                const scale = Math.max(1, Math.floor(qrCanvas.width / span));
                                const origin = Math.floor((qrCanvas.width - scale * span) / 2) + quiet * scale;

                                ctx.fillStyle = "#000000";
                                for (let y = 0; y < m.rows.length; y++) {
                                    const row = m.rows[y];
                                    for (let x = 0; x < row.length; x++) {
                                        if (row.charCodeAt(x) === 49)   // '1' -- a dark module
                                            ctx.fillRect(origin + x * scale, origin + y * scale, scale, scale);
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        // Three states in one label: the code is on its
                        // way, the daemon said why there isn't one, or
                        // here is how to use it.
                        text: root.shareError !== "" ? root.shareError
                            : (root.shareMatrix ? "Point a phone's camera at this to join" : "Reading the saved key…")
                        color: root.shareError !== "" ? root.destructive : Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
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
                    // Last in the cascade, after the header and the three
                    // cards above -- the buttons are what you came here
                    // to press, so they land once the page is settled.
                    required property int index
                    RevealPop { item: actionBtn; index: actionBtn.index + 4 }
                    width: layout.width
                    height: 44
                    radius: 22
                    readonly property color tint: actionBtn.modelData.style === "destructive" ? root.destructive
                        : (actionBtn.modelData.style === "primary" ? root.accent : Ink.primary)
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
