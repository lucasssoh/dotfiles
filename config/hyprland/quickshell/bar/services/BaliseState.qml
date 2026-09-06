pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// State + IPC for the QML rewrite of Balise's home page (WiFi/Bluetooth/
// Ethernet control-center panel, Rust backend kept -- see the project
// plan). Same service+render split as NotificationState.qml, except the
// "service" here is a real IPC client rather than an in-process
// Quickshell service binding: `Socket` (Quickshell.Io) connects straight
// to Balise's own existing Unix socket (`$XDG_RUNTIME_DIR/balise.sock`,
// see balise-src/src/paths.rs) and speaks the JSON-lines protocol that
// socket was extended to carry (balise-src/src/ipc.rs's ClientCommand/
// ServerPush) -- no new IPC mechanism invented on the Rust side, no
// D-Bus, just this socket read/written directly.
//
// Panel open/close is mutually exclusive with the notification center
// (asked for explicitly: "les deux ne peuvent pas s'empiler et soit l'un
// soit l'autre s'ouvre") -- both are drawer entries on the same
// toolsIsland now, so opening one closes the other. `import "."` (this
// file's own directory) is what makes `NotificationState` resolvable
// here without a relative `../services` path; NotificationState.qml
// does the same back to this file for the other direction.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/balise.sock"

    property bool wifiEnabled: false
    property bool bluetoothEnabled: false
    property bool nightModeEnabled: false

    // Section lists (second slice, see the project plan) -- plain JS
    // arrays of plain objects straight off the daemon's own JSON, no
    // wrapping QML type: each object's fields are exactly whatever
    // `#[derive(Serialize)]` on the matching Rust struct produced
    // (snake_case keys, e.g. `is_connected`/`device_path`), read directly
    // from row delegates via `modelData.ssid` etc.
    property var wifiNetworks: []
    property var bluetoothDevices: []
    property var wiredProfiles: []
    // Detail page (third slice, see the project plan) -- only WiFi needs
    // its own fetched object; Bluetooth/Ethernet detail pages read
    // straight off their own row in the arrays above (see
    // BaliseHome.qml's detailBtDevice/detailEthProfile). Reset to null on
    // every fetch request so a stale previous SSID's details can't
    // flash before the fresh ones land.
    property var wifiDetail: null

    // ---- credential entry (fourth slice) --------------------------------
    // The SSID a connect attempt is currently in flight for, "" when idle.
    // Set optimistically the moment the command goes out rather than on a
    // daemon push: `connect()` can take up to 15s (see
    // NetworkManager::connect's own poll), and a form that doesn't
    // acknowledge the click for that long reads as broken.
    property string connectingSsid: ""
    // Last failure, as a { ssid, message } pair -- kept per-SSID so a
    // stale error from another network can't surface under this one's
    // form. Cleared on the next attempt and on success.
    property var connectError: null

    // Whether a text field is on screen and expecting keystrokes. The bar
    // is a layer-shell surface with `focusable: false` (shell.qml), which
    // means the compositor never sends it a key event at all -- so this
    // has to flip the window's own keyboard interactivity on before the
    // field can be typed into, and back off afterwards so the bar isn't
    // permanently stealing focus from real windows. Set by whoever shows
    // the field (a Binding in BaliseDetailPage.qml), read by shell.qml.
    property bool textInputActive: false

    property bool panelOpen: false
    property var activeScreen: null

    function togglePanel(screen) {
        if (root.panelOpen && root.activeScreen === screen) {
            root.close();
            return;
        }
        NotificationState.close();
        root.activeScreen = screen;
        root.panelOpen = true;
        // The panel just became visible -- refresh right away rather
        // than waiting for the poll timer's next tick (see
        // refreshState/statusPollTimer below), same "just opened" moment
        // the old GTK app's own ClientCommand::Show used to catch.
        root.refreshState();
    }

    function close() {
        root.panelOpen = false;
        // Belt and braces alongside the Binding that normally owns this
        // (see textInputActive): the drawer can close without the page
        // holding the field ever being unloaded -- an outside click, the
        // notification center taking the island -- and a bar left
        // focusable with nothing on screen to type into would keep
        // swallowing focus from whatever the user clicked next.
        root.textInputActive = false;
    }

    function toggleWifi() { root._send({ cmd: "wifi_toggle" }); }
    function toggleBluetooth() { root._send({ cmd: "bt_toggle" }); }
    function toggleNightMode() { root._send({ cmd: "night_mode_toggle" }); }
    // Re-reads the real radio power state (see ipc.rs's own doc comment
    // on RefreshState for why this exists as its own command rather than
    // reusing ClientCommand::Show) -- fixes wifiEnabled/bluetoothEnabled
    // going stale when the radio is toggled from outside Balise entirely
    // (rfkill hotkey, GNOME quick settings, another app). Polled on an
    // interval below while the panel is open, so an external toggle is
    // reflected within a few seconds without the user having to do
    // anything.
    function refreshState() { root._send({ cmd: "refresh_state" }); }

    Timer {
        interval: 3000
        repeat: true
        running: root.panelOpen
        triggeredOnStart: false
        onTriggered: root.refreshState()
    }
    function triggerScreenshot() { root._send({ cmd: "screenshot" }); }

    // ---- section lists (second slice) -- scan/connect/disconnect.
    // WiFi takes credentials now (fourth slice, see connectWifi below),
    // so "already-existing profile only" no longer applies to it; the
    // Bluetooth half still does, since pairing needs the BlueZ agent
    // bridged to QML and that is its own pass.
    function scanWifi() { root._send({ cmd: "wifi_scan" }); }
    // `security` is the same snake_case token the daemon put in the
    // access-point list ("none"/"wpa2"/"wpa3"/"enterprise"/...), echoed
    // back so the daemon writes the right key-mgmt without re-deriving it
    // (see ClientCommand::WifiConnect). `credentials` is null for an open
    // network or a saved profile being reactivated, and otherwise the
    // object BaliseDetailPage's form built -- its keys match
    // dbus/types.rs's WifiCredentials exactly.
    function connectWifi(ssid, security, credentials) {
        const msg = { cmd: "wifi_connect", ssid: ssid };
        if (security) msg.security = security;
        if (credentials) msg.credentials = credentials;
        if (!root._send(msg)) {
            root.connectError = { ssid: ssid, message: "Balise daemon is not running" };
            return;
        }
        root.connectError = null;
        root.connectingSsid = ssid;
        connectWatchdog.restart();
    }
    function disconnectWifi(ssid) { root._send({ cmd: "wifi_disconnect", ssid: ssid }); }
    function scanBluetooth() { root._send({ cmd: "bt_scan" }); }
    function connectBluetooth(path) { root._send({ cmd: "bt_connect", path: path }); }
    function disconnectBluetooth(path) { root._send({ cmd: "bt_disconnect", path: path }); }
    function connectEthernet(connectionPath, devicePath) {
        root._send({ cmd: "eth_connect", connection_path: connectionPath, device_path: devicePath });
    }
    function disconnectEthernet(devicePath) {
        root._send({ cmd: "eth_disconnect", device_path: devicePath });
    }
    // No radio to scan for wired -- just an instant re-read, called when
    // the Ethernet section is opened (there's no "Scan" affordance for
    // it, see BaliseHome.qml).
    function listEthernet() { root._send({ cmd: "eth_list" }); }

    // ---- detail page (third slice) -- read/toggle/forget for an
    // already-paired/saved endpoint only, no pairing (see the project
    // plan). Same "presentation stays dumb, this is the only place that
    // knows the wire format" split every other action above already
    // follows.
    function fetchWifiDetail(ssid) {
        root.wifiDetail = null;
        root._send({ cmd: "wifi_detail", ssid: ssid });
    }
    function forgetWifi(settingsPath) { root._send({ cmd: "wifi_forget", settings_path: settingsPath }); }
    function setWifiAutoconnect(ssid, settingsPath, autoconnect) {
        root._send({ cmd: "wifi_autoconnect", ssid: ssid, settings_path: settingsPath, autoconnect: autoconnect });
    }
    function forgetBluetooth(path) { root._send({ cmd: "bt_forget", path: path }); }
    function setBluetoothTrust(path, trusted) { root._send({ cmd: "bt_trust", path: path, trusted: trusted }); }
    function setEthernetAutoconnect(connectionPath, autoconnect) {
        root._send({ cmd: "eth_autoconnect", connection_path: connectionPath, autoconnect: autoconnect });
    }

    // Returns whether the command actually went out -- callers that put
    // the UI into a pending state (connectWifi) need to know, otherwise a
    // send dropped because the daemon is down leaves a spinner running
    // against a reply that will never come.
    // Display name for a `security` token (the snake_case value the
    // daemon puts in every access point and, since credential entry
    // landed, in WifiDetails too). Lives on the singleton that already
    // owns the wire vocabulary rather than being written out twice: the
    // row list and the detail page both show it, and `"wpa3_enterprise"
    // .toUpperCase()` -- what the row used to do to whatever arrived --
    // is not a thing to put in front of a person.
    //
    // This is pure formatting, not an action: BaliseNetworkRow.qml stays
    // presentation-only in the sense its own header means (it triggers
    // nothing, it emits a signal and lets the consumer act).
    function securityLabel(token) {
        switch (String(token || "")) {
        case "none": return "Open";
        case "wep": return "WEP";
        case "wpa": return "WPA";
        case "wpa2": return "WPA2";
        case "wpa3": return "WPA3";
        case "enterprise": return "Enterprise";
        case "wpa3_enterprise": return "WPA3-Enterprise";
        default: return "Secured";
        }
    }

    function _send(obj) {
        if (!socket.connected) return false;
        socket.write(JSON.stringify(obj) + "\n");
        socket.flush();
        return true;
    }

    Socket {
        id: socket
        path: root.socketPath
        connected: true

        parser: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._handleLine(line)
        }

        // The daemon may not be up yet (bar starts before balise.service
        // on a cold login, or the service briefly restarts) -- retry on
        // a plain timer rather than failing silently forever. Cheap:
        // `connected = true` on an already-connected socket is a no-op,
        // so this is safe to fire even once a connection has succeeded
        // (interval just keeps ticking, next real disconnect is caught
        // the same way).
        onConnectionStateChanged: {
            if (!connected) reconnectTimer.restart();
        }
    }

    Timer {
        id: reconnectTimer
        interval: 2000
        onTriggered: socket.connected = true
    }

    // Assigns only when the payload actually differs. These three arrays
    // back ListViews whose model is a plain JS array, and reassigning one
    // resets that model wholesale -- every delegate destroyed and rebuilt,
    // scroll position and any running transition with it.
    //
    // That did not matter while the lists only arrived on an explicit
    // scan. It does now: RefreshState re-broadcasts all three, and
    // BaliseState polls it every 3s while the drawer is open, so an
    // unguarded assignment would rebuild the WiFi list under the user
    // twenty times a minute while they are reading it. Comparing first
    // means a poll that finds nothing changed costs one string compare and
    // touches no binding at all -- and it retroactively calms the 12s
    // section rescan too.
    function _assignList(prop, value) {
        const next = value || [];
        if (JSON.stringify(root[prop]) === JSON.stringify(next)) return;
        root[prop] = next;
    }

    function _handleLine(line) {
        const trimmed = line.trim();
        if (trimmed === "") return;
        let msg;
        try {
            msg = JSON.parse(trimmed);
        } catch (e) {
            return;   // a command ack or a line split oddly -- ignore
        }
        if (msg.type === "state") {
            root.wifiEnabled = !!(msg.wifi && msg.wifi.enabled);
            root.bluetoothEnabled = !!(msg.bluetooth && msg.bluetooth.enabled);
            root.nightModeEnabled = !!(msg.night_mode && msg.night_mode.active);
        } else if (msg.type === "wifi_list") {
            root._assignList("wifiNetworks", msg.access_points);
        } else if (msg.type === "bluetooth_list") {
            root._assignList("bluetoothDevices", msg.devices);
        } else if (msg.type === "wired_list") {
            root._assignList("wiredProfiles", msg.profiles);
        } else if (msg.type === "wifi_detail") {
            root.wifiDetail = msg.details || null;
        } else if (msg.type === "wifi_connect_result") {
            // Ignored unless it's the attempt currently on screen: this is
            // a broadcast, so a connect the user started, backed out of,
            // and replaced with another one would otherwise land its late
            // failure under the newer network's form.
            if (root.connectingSsid !== "" && msg.ssid !== root.connectingSsid) return;
            connectWatchdog.stop();
            root.connectingSsid = "";
            root.connectError = msg.ok ? null : { ssid: msg.ssid, message: msg.error || "Connection failed" };
        }
    }

    // A connect attempt can take up to 15s daemon-side (see
    // NetworkManager::connect's own poll), and nothing clears
    // `connectingSsid` if the daemon dies mid-attempt. This is the floor
    // under that, slightly past the daemon's own ceiling. Driven
    // imperatively (restart/stop) rather than by a `running:` binding, so
    // that a second attempt started while the first is still in flight
    // resets the countdown instead of inheriting what's left of it.
    Timer {
        id: connectWatchdog
        interval: 20000
        repeat: false
        onTriggered: {
            root.connectError = { ssid: root.connectingSsid, message: "No response from the daemon" };
            root.connectingSsid = "";
        }
    }
}
