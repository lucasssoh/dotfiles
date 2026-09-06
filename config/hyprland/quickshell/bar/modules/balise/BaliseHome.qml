import QtQuick
import Qt5Compat.GraphicalEffects
import ".."
import "../../theme"
import "../../services"

// Balise's home page (Control-Center-style tile grid), first slice of
// the QML rewrite -- see the project plan. Backend stays the Rust
// daemon (balise-src/), reached over its own existing Unix socket via
// BaliseState.qml; this file only renders whatever that holds.
//
// A DrawerIsland entry on `toolsIsland` (shell.qml), same contract as
// NotificationCenter.qml right next to it: `drawerOpen` bound from
// outside, `implicitHeight`, this file's own `Behavior on height` --
// width/height/opacity are otherwise owned by DrawerIsland, hence no
// own background/radius/GlassRim here either (same "no more border"
// reasoning NotificationCenter.qml's header already covers). The two
// are mutually exclusive (see BaliseState.togglePanel/
// NotificationState.toggleNotificationCenter), so only one of them is
// ever actually open at a time despite sharing the same drawer column.
//
// 2x2 grid (WiFi/Bluetooth/Ethernet/Airplane) + 2 full-width rows (Night
// mode/Capture), porting ui/home.rs's own layout. Icons only where this
// bar already has a VERIFIED Phosphor codepoint to reuse (WiFi/
// Bluetooth/Ethernet, copied from BaliseButton.qml/Network.qml/
// Ethernet.qml's own icon() functions) -- Airplane/Night mode/Capture
// stay text-only rather than guessing a codepoint (same rule this bar's
// buttons-grid already follows elsewhere, see NotificationCenter.qml).
//
// Second slice (see the project plan): right-click on WiFi/Bluetooth (a
// plain click on Ethernet, which has no radio to toggle) opens that
// section's list -- scan + connect/disconnect for an already-existing
// profile only, no password entry, no pairing, no detail page (all
// explicitly deferred). Navigation stays inside this same file rather
// than a new top-level drawer entry: `currentPage` switches a `Loader`
// between the tile grid below and BaliseSectionList.qml, and
// `implicitHeight` follows whichever page is actually loaded so
// DrawerIsland's own height Binding (it reads this property live)
// animates the grid <-> list transition the same way it already animates
// open/close.
Item {
    id: root

    property bool drawerOpen: false
    // "home" | "wifi" | "bluetooth" | "ethernet" | "wifi-detail" |
    // "bt-detail" | "eth-detail" (third slice, see the project plan).
    property string currentPage: "home"
    // Kick off the read that populates each section's list right as it
    // opens -- WiFi/Bluetooth get an actual radio scan (also reachable
    // again from the section's own "Scan" button), Ethernet just an
    // instant re-read (see BaliseState.listEthernet).
    function goTo(page) {
        root.currentPage = page;
        if (page === "wifi") BaliseState.scanWifi();
        else if (page === "bluetooth") BaliseState.scanBluetooth();
        else if (page === "ethernet") BaliseState.listEthernet();
    }
    function goHome() { root.currentPage = "home"; }

    // Every open starts at the top level -- asked for explicitly ("si je
    // me trouve dans un contexte ou sous-contexte dans balise, et que je
    // quitte, je reviens à l'interface principale, toujours"). Nothing
    // else resets this: closing the drawer (the Balise button, an
    // outside click via shell.qml's own onRawEvent, or the notification
    // center opening and pushing this one out) all go through
    // BaliseState.close(), which only touches `panelOpen` -- so without
    // this, reopening landed straight back on whatever list or detail
    // page had been left behind.
    //
    // Done on OPEN rather than on close on purpose: the drawer still
    // takes this file's own `Behavior on height` to retract, and
    // resetting during that would swap the Loader back to the home grid
    // mid-collapse (a visible content jump). Here the reset happens
    // while the height is still 0, DrawerIsland's own height Binding
    // re-reads `implicitHeight` in the same pass, and the page being
    // left stays on screen for the whole close.
    // `_instantSwap` keeps THIS page change out of the horizontal slide:
    // the drawer is opening at the same moment, and playing a sideways
    // push underneath a reveal would run the two animations that were
    // deliberately separated (drawer for open/close, slide for
    // navigation) on top of each other. The swap happens while the
    // island is still collapsing/expanding, so nothing is visible
    // anyway.
    property bool _instantSwap: false
    onDrawerOpenChanged: {
        if (root.drawerOpen) {
            root._instantSwap = true;
            root.currentPage = "home";
            root.detailId = "";
            root._instantSwap = false;
        }
    }

    // Detail page (third slice) -- `detailId` is whatever uniquely
    // identifies the row (ssid / bluetooth device path / wired device
    // path), looked up LIVE against the matching array below rather than
    // snapshotting the row object once, so a push that updates it (e.g.
    // a toggled autoconnect/trust reflecting back) is picked up without
    // re-opening the page. WiFi additionally needs an explicit fetch for
    // the half an AccessPoint alone doesn't carry (see BaliseState.
    // fetchWifiDetail) -- Bluetooth/Ethernet read straight off their own
    // list, no round trip needed.
    property string detailId: ""
    function openWifiDetail(ssid) {
        root.detailId = ssid;
        BaliseState.fetchWifiDetail(ssid);
        root.currentPage = "wifi-detail";
    }
    function openBluetoothDetail(path) {
        root.detailId = path;
        root.currentPage = "bt-detail";
    }
    function openEthernetDetail(devicePath) {
        root.detailId = devicePath;
        root.currentPage = "eth-detail";
    }
    // Back from a detail page returns to the section it came from, not
    // home -- derived from the page name itself rather than a separate
    // "previous page" stack, since a detail page is only ever reachable
    // from exactly one section.
    function backFromDetail() {
        if (root.currentPage === "wifi-detail") root.currentPage = "wifi";
        else if (root.currentPage === "bt-detail") root.currentPage = "bluetooth";
        else if (root.currentPage === "eth-detail") root.currentPage = "ethernet";
        else root.goHome();
    }

    readonly property var detailWifiAp: {
        const nets = BaliseState.wifiNetworks;
        for (let i = 0; i < nets.length; i++) if (nets[i].ssid === root.detailId) return nets[i];
        return null;
    }
    readonly property var detailBtDevice: {
        const devs = BaliseState.bluetoothDevices;
        for (let i = 0; i < devs.length; i++) if (devs[i].path === root.detailId) return devs[i];
        return null;
    }
    readonly property var detailEthProfile: {
        const profiles = BaliseState.wiredProfiles;
        for (let i = 0; i < profiles.length; i++) if (profiles[i].device_path === root.detailId) return profiles[i];
        return null;
    }

    // Keeps a WiFi/Bluetooth section's list fresh while it's actually
    // being looked at, on top of the one-shot scan goTo() already fires
    // and the section's own manual "Scan" button (asked for explicitly:
    // "scanner automatiquement lorsque la connectique est active") --
    // gated on the matching radio actually being on, so leaving a
    // section open with its radio off doesn't fire pointless scans.
    // 12s: longer than BtScan's own fixed 5s discovery window and
    // comfortably above NetworkManager's own scan-throttling floor
    // (repeated request_scan() calls under ~10s apart are silently
    // ignored NM-side), so this never fights either backend.
    Timer {
        interval: 12000
        repeat: true
        running: root.drawerOpen && (root.currentPage === "wifi" || root.currentPage === "bluetooth")
        triggeredOnStart: false
        onTriggered: {
            if (root.currentPage === "wifi" && BaliseState.wifiEnabled) BaliseState.scanWifi();
            else if (root.currentPage === "bluetooth" && BaliseState.bluetoothEnabled) BaliseState.scanBluetooth();
        }
    }

    // WiFi/Bluetooth section lists split into three groups -- connected,
    // then saved/paired-but-idle, then everything else merely visible
    // (asked for explicitly: "separer en deux groupes les appareils
    // connectes et les appareils non connectes mais enregistres, puis
    // les reseaux disponibles"). A stable partition (three passes,
    // Array.push in encounter order) rather than a real sort, so
    // whatever secondary order the daemon already applies within each
    // bucket (signal strength for WiFi, connected > paired > alphabetical
    // for Bluetooth -- see dbus/bluez.rs's own get_devices) survives
    // untouched. `_group` is BaliseSectionList's own section.property
    // key (see that file), spelled out per-item since these are plain
    // JS objects straight off the daemon's JSON, not a QML type with a
    // real property to bind against.
    readonly property var groupedWifiNetworks: {
        const nets = BaliseState.wifiNetworks;
        const connected = [], saved = [], available = [];
        for (let i = 0; i < nets.length; i++) {
            const n = nets[i];
            const bucket = n.is_connected ? connected : (n.is_saved ? saved : available);
            const tagged = Object.assign({}, n, {
                _group: n.is_connected ? "Connected" : (n.is_saved ? "Saved" : "Available")
            });
            bucket.push(tagged);
        }
        return connected.concat(saved, available);
    }
    readonly property var groupedBluetoothDevices: {
        const devs = BaliseState.bluetoothDevices;
        const connected = [], paired = [], available = [];
        for (let i = 0; i < devs.length; i++) {
            const d = devs[i];
            const bucket = d.is_connected ? connected : (d.is_paired ? paired : available);
            const tagged = Object.assign({}, d, {
                _group: d.is_connected ? "Connected" : (d.is_paired ? "Paired" : "Available")
            });
            bucket.push(tagged);
        }
        return connected.concat(paired, available);
    }

    // FIXED, not content-driven any more -- asked for explicitly ("garde
    // la taille (hauteur fixe) mais ajouter un scroll coherent
    // interne"). Every page now lays out inside this same box and
    // scrolls internally when it needs more room (the section lists via
    // their own ListView, the grid and the detail page via a Flickable
    // each), so navigating no longer resizes the island: the only height
    // change left is the drawer opening and closing, which is exactly
    // the split that was asked for.
    // Measured from the home grid itself rather than guessed, so the
    // main UI fits EXACTLY with no scrollbar of its own and only the
    // pages that genuinely overflow it scroll (asked for: "adapter la
    // hauteur de base (ui principale de balise) pour qu'il n'y ait pas
    // de scroll que si c'est plus que ça"). Reported up by the home
    // page's own Column (see `homePage`'s Binding) and kept afterwards,
    // so the height stays put when that page is unloaded during a slide.
    // The floor covers the first frames, before it has ever been
    // measured.
    property int homeContentHeight: 0
    readonly property int pageHeight: Math.max(360, root.homeContentHeight + 40)
    implicitHeight: root.pageHeight
    // Still here, and still only ever exercised by DrawerIsland driving
    // this Item's height between 0 and `pageHeight` -- i.e. the drawer
    // reveal for Balise itself, the notification center's own entry
    // being the other one on the same island.
    // Kept equal to DrawerIsland's `revealDuration` -- see the comment there.
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    // Airplane mode has no single backend flag -- computed the same way
    // ui/home.rs's own refresh_airplane does: both radios off.
    readonly property bool airplaneActive: !BaliseState.wifiEnabled && !BaliseState.bluetoothEnabled

    function toggleAirplane() {
        const target = !root.airplaneActive;
        if (BaliseState.wifiEnabled !== target) BaliseState.toggleWifi();
        if (BaliseState.bluetoothEnabled !== target) BaliseState.toggleBluetooth();
    }

    // ---- hero card + tile subtitles (mockup-derived layout, see this
    // file's header) ------------------------------------------------------
    // The WiFi network currently connected, straight off the same list
    // the WiFi section renders -- null until a scan has populated it.
    readonly property var connectedWifiAp: {
        const nets = BaliseState.wifiNetworks;
        for (let i = 0; i < nets.length; i++) if (nets[i].is_connected) return nets[i];
        return null;
    }
    // Coarse wording for a signal percentage, the way the mockup's own
    // "Excellent · 5 GHz" line reads -- no band info in AccessPoint, so
    // the percentage takes that second slot instead of inventing one.
    function signalWord(pct) {
        if (pct >= 75) return "Excellent";
        if (pct >= 50) return "Good";
        if (pct >= 25) return "Fair";
        return "Weak";
    }
    // Ethernet wins over WiFi, same priority Network.qml's own activeDevice
    // already applies ("Ethernet beats wifi if both happen to be
    // connected").
    readonly property string heroName: {
        if (root.activeWiredProfile) return root.activeWiredProfile.name || root.activeWiredProfile.device_name;
        if (root.connectedWifiAp) return root.connectedWifiAp.ssid;
        return "Not connected";
    }
    readonly property string heroStatus: {
        if (root.activeWiredProfile) {
            const p = root.activeWiredProfile;
            return "Connected" + (p.speed > 0 ? " · " + p.speed + " Mb/s" : "");
        }
        if (root.connectedWifiAp) {
            const s = root.connectedWifiAp.signal;
            return root.signalWord(s) + " · " + s + "%";
        }
        return BaliseState.wifiEnabled ? "No network" : "WiFi off";
    }
    // Written as codepoints rather than as the literal PUA characters the
    // tiles below use: same glyphs (ph-plugs-connected / ph-wifi-low /
    // -medium / -high / -slash, all already verified in Network.qml and
    // Ethernet.qml), just spelled in a form that survives every editor
    // and diff tool unambiguously.
    readonly property string heroGlyph: {
        if (root.activeWiredProfile) return String.fromCharCode(0xeb5a);   // ph-plugs-connected
        if (root.connectedWifiAp) {
            const s = root.connectedWifiAp.signal;
            if (s < 33) return String.fromCharCode(0xe4ec);   // ph-wifi-low
            if (s < 66) return String.fromCharCode(0xe4ee);   // ph-wifi-medium
            return String.fromCharCode(0xe4ea);               // ph-wifi-high
        }
        return String.fromCharCode(0xe4f2);   // ph-wifi-slash
    }
    readonly property bool heroConnected: root.activeWiredProfile !== null || root.connectedWifiAp !== null

    readonly property int connectedBtCount: {
        const devs = BaliseState.bluetoothDevices;
        let n = 0;
        for (let i = 0; i < devs.length; i++) if (devs[i].is_connected) n++;
        return n;
    }
    // Second line under each tile's own title -- the live endpoint where
    // there is one, the plain radio state otherwise (mockup: "Freebox-
    // C7C628" / "2 appareils" / "Connecté · 1 Gb/s" / "Désactivé").
    readonly property string wifiTileStatus: {
        if (!BaliseState.wifiEnabled) return "Off";
        return root.connectedWifiAp ? root.connectedWifiAp.ssid : "On";
    }
    readonly property string bluetoothTileStatus: {
        if (!BaliseState.bluetoothEnabled) return "Off";
        const n = root.connectedBtCount;
        if (n === 0) return "On";
        return n === 1 ? "1 device" : n + " devices";
    }
    readonly property string ethernetTileStatus: {
        if (!root.activeWiredProfile) return "—";
        const p = root.activeWiredProfile;
        return "Connected" + (p.speed > 0 ? " · " + p.speed + " Mb/s" : "");
    }

    // Ethernet's own live state, once BaliseState.wiredProfiles has
    // actually been populated (see goTo("ethernet")/listEthernet) --
    // stays the placeholder "—" until then.
    readonly property var activeWiredProfile: {
        const profiles = BaliseState.wiredProfiles;
        for (let i = 0; i < profiles.length; i++) if (profiles[i].is_active) return profiles[i];
        return null;
    }

    // Button style + colors ported from BatteryAlert.qml's own
    // primaryButton/secondaryButton (asked for explicitly: "utilise le
    // meme que le style des boutons et couleurs que le module d'alert
    // battery") -- transparent at rest, the same `#14161d` dark hover
    // fill, a constant thin `rgba(1,1,1,0.18)` border regardless of
    // hover, `accent` (`#a8b4c4`) doing the only "this is active" work
    // instead of BaliseHome's old GTK-ported light-background inversion
    // (`.balise-tile.active`) -- same "accent tints the glyph/badge, the
    // pill itself never fills solid" idea BatteryAlert's own checkBadge
    // ring uses, not a new recipe.
    readonly property color accent: "#a8b4c4"

    component Tile: Rectangle {
        id: tile
        required property string title
        property string status: ""
        property string glyph: ""
        property bool active: false
        signal activated()
        // Right-click opens this tile's section list (WiFi/Bluetooth);
        // Ethernet has no radio to toggle so it routes both to the same
        // place (see below).
        signal activatedSecondary()

        radius: 20
        // "On" needed real contrast at rest, not just a tinted icon/status
        // (asked for explicitly: "il faut un contraste lorsque les
        // boutons sont en on") -- a faint accent-tinted fill + an
        // accent-colored border, same idea as NotificationCenter.qml's
        // own DND toggle track (`#a8b4c4` when on, a plain neutral ring
        // when off), just subtle enough here to still read as a card
        // rather than a solid switch. Hover still darkens/brightens
        // slightly from whichever base it's already in.
        color: tile.active
            ? mouseArea.containsMouse ? Surfaces.accentStrongest : Surfaces.accentMedium
            : (mouseArea.containsMouse ? Surfaces.cardHover : Surfaces.card)
        border.width: 1
        border.color: tile.active ? root.accent : Qt.rgba(1, 1, 1, 0.18)
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        readonly property color fg: tile.active ? root.accent : "#f2f2f7"

        // Vertically centered rather than anchored to `top` with a fixed
        // margin -- the icon row is only present on 3 of the 4 grid
        // tiles (Airplane has none, see the `glyph !== ""` gate), so a
        // fixed top-anchor + guessed tile height either cramped the
        // 3-line tiles' status text against the bottom edge (asked for:
        // "le texte interieur n'est pas ajuster bien") or left the
        // 2-line ones looking top-heavy -- centering makes both cases
        // sit correctly without hand-tuning height per tile.
        // Anchored on BOTH sides, not just the left: `elide` needs a real
        // width to work against, and without one a long value (a WiFi
        // tile showing a 30-character SSID as its status line) simply ran
        // past the tile's own edge instead of ellipsizing.
        Column {
            id: tileText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // The glyph now sits in its own rounded-square badge (the
            // mockup's own tile anatomy) rather than floating bare above
            // the label -- accent-tinted while the tile is active, the
            // same `#1a1d2a` neutral NotificationCard.qml's own iconTile
            // uses otherwise. Tiles with no VERIFIED Phosphor codepoint
            // (Airplane) keep dropping the badge entirely instead of
            // showing an empty square or a guessed icon.
            Rectangle {
                visible: tile.glyph !== ""
                width: 30
                height: 30
                radius: 9
                color: tile.active
                    ? Surfaces.accentStrong
                    : Surfaces.cardHover
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: tile.glyph
                    color: tile.fg
                    font.family: Fonts.iconPhosphor
                    font.pixelSize: 17
                }
            }
            Text {
                width: tileText.width
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: tile.title
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: tileText.width
                visible: tile.status !== ""
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: tile.status
                color: tile.active ? tile.fg : "#8e8e93"
                font.family: Fonts.ui
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) tile.activatedSecondary();
                else tile.activated();
            }
        }
    }

    // Small-caps group label above a block of tiles/rows -- the mockup's
    // own "CONNECTIVITÉ"/"OPTIONS" rhythm, same typography
    // BaliseSectionList.qml's own section headers already use.
    component GroupLabel: Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        color: Qt.rgba(1, 1, 1, 0.4)
        font.family: Fonts.ui
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1
    }

    // Full-width settings row (Night mode) -- a filled card with a real
    // track+thumb switch on the right rather than the bordered pill
    // button this used before, matching the mockup (and reusing
    // NotificationCenter.qml's own DND toggle recipe verbatim so the two
    // drawers' switches are literally the same control).
    component ToggleRow: Rectangle {
        id: trow
        required property string title
        property string subtitle: ""
        property bool checked: false
        signal toggled(bool value)

        height: trow.subtitle !== "" ? 54 : 46
        radius: 12
        color: mouseArea.containsMouse ? Surfaces.cardHover : Surfaces.card
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: track.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: trow.title
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: trow.subtitle !== ""
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: trow.subtitle
                color: "#8e8e93"
                font.family: Fonts.ui
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: track
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 22
            radius: 11
            color: trow.checked ? root.accent : Qt.rgba(1, 1, 1, 0.18)
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: "#0c0c0e"
                anchors.verticalCenter: parent.verticalCenter
                x: trow.checked ? parent.width - width - 2 : 2
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: trow.toggled(!trow.checked)
        }
    }

    // Same card shape as ToggleRow, but for a one-shot action (Capture)
    // -- no switch, the whole row is the button.
    component ActionRow: Rectangle {
        id: arow
        required property string title
        signal activated()

        height: 46
        radius: 12
        color: mouseArea.containsMouse ? Surfaces.cardHover : Surfaces.card
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: arow.title
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 14
            font.bold: true
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arow.activated()
        }
    }

    // The tile grid + wide buttons -- now one of several pages a Loader
    // switches between (see `pageLoader` below) instead of the file's
    // only content. 16px everywhere a gap separates one tile/button from
    // the next (row-to-row here, tile-to-tile inside each Row below) --
    // regularized against NotificationCenter.qml's own topSection
    // spacing (16), the other drawer entry sharing this same toolsIsland.
    Component {
        id: homePage

        // Same Flickable shell BaliseDetailPage.qml uses, and the same
        // StopAtBounds feel the section lists' own ListView has -- one
        // scroll behaviour across all three page kinds ("un scroll
        // coherent interne"). The grid usually fits, so this only ever
        // engages on a short island or a long-ish content run.
        Flickable {
            id: homeFlick
            anchors.fill: parent
            contentHeight: homeColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 3000
            clip: true

            // Soft edges rather than a hard cut, same as the section
            // lists' and the notification history's. The grid usually
            // fits, and ScrollFadeMask draws nothing at an end it cannot
            // scroll toward, so on a tall island this costs a layer and
            // shows no fade at all.
            layer.enabled: true
            layer.effect: OpacityMask { maskSource: homeMask }

            // Declared as a CHILD of the Flickable (so it lands in its
            // contentItem) purely because this page's root IS the
            // Flickable -- a Component has no sibling slot. Harmless:
            // only the mask's size is read, it is never drawn in the
            // scene, and it is outside homeColumn so it adds nothing to
            // the content height either.
            ScrollFadeMask {
                id: homeMask
                view: homeFlick
                width: homeFlick.width
                height: homeFlick.height
            }

            // What sizes the whole panel -- see root.homeContentHeight.
            Binding {
                target: root
                property: "homeContentHeight"
                value: homeColumn.implicitHeight
            }

            Column {
                id: homeColumn
                width: homeFlick.width
                spacing: 12

            // ---- hero: whatever is actually carrying traffic right now
            // (the mockup's own "RÉSEAU ACTUEL" card). Ethernet wins over
            // WiFi, see heroName's own comment.
            GroupLabel { text: "CURRENT NETWORK" }

            Rectangle {
                width: parent.width
                height: 66
                radius: 14
                color: Surfaces.card
                border.width: 1
                border.color: root.heroConnected ? Qt.rgba(0xa8 / 255, 0xb4 / 255, 0xc4 / 255, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                Behavior on border.color { ColorAnimation { duration: 160 } }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: heroBadge.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.heroName
                        color: "#f2f2f7"
                        font.family: Fonts.ui
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.heroStatus
                        color: root.heroConnected ? root.accent : "#8e8e93"
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                // Circular badge, unlike the tiles' rounded squares --
                // the mockup uses the same distinction to mark this as
                // the status summary rather than another toggle.
                Rectangle {
                    id: heroBadge
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    color: root.heroConnected
                        ? Surfaces.accentStrong
                        : Surfaces.cardHover
                    Behavior on color { ColorAnimation { duration: 160 } }

                    Text {
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.heroGlyph
                        color: root.heroConnected ? root.accent : "#8e8e93"
                        font.family: Fonts.iconPhosphor
                        font.pixelSize: 18
                    }
                }
            }

            Item { width: 1; height: 4 }

            GroupLabel { text: "CONNECTIVITY" }

            Row {
                width: parent.width
                spacing: 16
                Tile {
                    width: (parent.width - 16) / 2
                    height: 92
                    title: "WiFi"
                    status: root.wifiTileStatus
                    glyph: BaliseState.wifiEnabled ? "" : ""   // ph-wifi-high / ph-wifi-slash
                    active: BaliseState.wifiEnabled
                    onActivated: BaliseState.toggleWifi()
                    onActivatedSecondary: root.goTo("wifi")
                }
                Tile {
                    width: (parent.width - 16) / 2
                    height: 92
                    title: "Bluetooth"
                    status: root.bluetoothTileStatus
                    glyph: BaliseState.bluetoothEnabled ? "" : ""   // ph-bluetooth / ph-bluetooth-slash
                    active: BaliseState.bluetoothEnabled
                    onActivated: BaliseState.toggleBluetooth()
                    onActivatedSecondary: root.goTo("bluetooth")
                }
            }
            Row {
                width: parent.width
                spacing: 16
                Tile {
                    width: (parent.width - 16) / 2
                    height: 92
                    title: "Ethernet"
                    status: root.ethernetTileStatus
                    glyph: root.activeWiredProfile ? "" : ""   // ph-plugs-connected / ph-plugs
                    active: root.activeWiredProfile !== null
                    // No radio to toggle -- both buttons open the section.
                    onActivated: root.goTo("ethernet")
                    onActivatedSecondary: root.goTo("ethernet")
                }
                Tile {
                    width: (parent.width - 16) / 2
                    height: 92
                    title: "Airplane mode"
                    status: root.airplaneActive ? "On" : "Off"
                    active: root.airplaneActive
                    onActivated: root.toggleAirplane()
                }
            }
            Item { width: 1; height: 4 }

            GroupLabel { text: "SYSTEM" }

            ToggleRow {
                width: parent.width
                title: "Night mode"
                subtitle: "Warmer screen temperature"
                checked: BaliseState.nightModeEnabled
                onToggled: BaliseState.toggleNightMode()
            }
                ActionRow {
                    width: parent.width
                    title: "Screenshot"
                    onActivated: BaliseState.triggerScreenshot()
                }
            }
        }
    }

    // Row delegate `Component`s, one per section -- assigned to
    // BaliseSectionList.rowDelegate below. Signals wire straight to
    // BaliseState here (the row files themselves, like NotificationCard,
    // stay presentation-only).
    Component {
        id: networkRowDelegate
        BaliseNetworkRow {
            onRowActivated: root.openWifiDetail(modelData.ssid)
        }
    }
    Component {
        id: deviceRowDelegate
        BaliseDeviceRow {
            onRowActivated: root.openBluetoothDetail(modelData.path)
        }
    }
    Component {
        id: wiredRowDelegate
        BaliseWiredRow {
            onRowActivated: root.openEthernetDetail(modelData.device_path)
        }
    }

    Component {
        id: wifiPage
        BaliseSectionList {
            title: "WiFi"
            model: root.groupedWifiNetworks
            grouped: true
            rowDelegate: networkRowDelegate
            showScan: true
            emptyText: BaliseState.wifiEnabled ? "No networks found" : "WiFi is off"
            showMaster: true
            masterTitle: "WiFi"
            masterSubtitle: "Search for networks automatically"
            masterChecked: BaliseState.wifiEnabled
            onMasterToggled: BaliseState.toggleWifi()
            onBackRequested: root.goHome()
            onScanRequested: BaliseState.scanWifi()
        }
    }
    Component {
        id: bluetoothPage
        BaliseSectionList {
            title: "Bluetooth"
            model: root.groupedBluetoothDevices
            grouped: true
            rowDelegate: deviceRowDelegate
            showScan: true
            emptyText: BaliseState.bluetoothEnabled ? "No devices found" : "Bluetooth is off"
            showMaster: true
            masterTitle: "Bluetooth"
            masterSubtitle: "Discoverable and ready to connect"
            masterChecked: BaliseState.bluetoothEnabled
            onMasterToggled: BaliseState.toggleBluetooth()
            onBackRequested: root.goHome()
            onScanRequested: BaliseState.scanBluetooth()
        }
    }
    Component {
        id: ethernetPage
        BaliseSectionList {
            title: "Ethernet"
            model: BaliseState.wiredProfiles
            rowDelegate: wiredRowDelegate
            // No "Scan" affordance -- wired_profiles() is a plain,
            // instant enumeration, not a slow radio scan (see
            // BaliseState.listEthernet, called on goTo("ethernet")).
            showScan: false
            emptyText: "No wired profiles"
            onBackRequested: root.goHome()
        }
    }

    // One shared component for all three kinds (mirrors ui/detail.rs's
    // own "works identically for WiFi/Bluetooth/Ethernet" page) --
    // `kind` plus whichever of ap/details/device/profile is relevant
    // feeds BaliseDetailPage.qml's own per-kind display logic. `details`
    // binds to BaliseState.wifiDetail directly rather than a
    // root-level lookup like the other three (no array to search --
    // it's the single most-recently-fetched object, reset to null by
    // fetchWifiDetail itself, see BaliseState.qml).
    Component {
        id: detailPage
        BaliseDetailPage {
            kind: root.currentPage === "wifi-detail" ? "wifi" : (root.currentPage === "bt-detail" ? "bluetooth" : "ethernet")
            ap: root.detailWifiAp
            details: BaliseState.wifiDetail
            device: root.detailBtDevice
            profile: root.detailEthProfile
            onBackRequested: root.backFromDetail()
        }
    }

    // Two page layers that slide past each other horizontally -- asked
    // for explicitly: the DRAWER animation (this Item's own height
    // growing out of the island) is reserved for opening and closing
    // Balise itself, and moving BETWEEN pages once inside is a
    // horizontal push instead, deeper pages entering from the right and
    // leaving back to the right. Nothing here changes height any more:
    // `pageHeight` is fixed (see its own comment), so a page change
    // moves content sideways and never re-sizes the island.
    //
    // Two Loaders rather than QtQuick.Controls' StackView: this bar
    // builds its own controls throughout (see NotificationCard.qml's
    // hand-drawn close button, DrawerIsland's own reveal sequences), and
    // a stack of exactly two live pages is all a push/pop transition
    // ever needs. The outgoing page keeps its own instance while it
    // slides (roles swap rather than the old page being rebuilt), so its
    // scroll position doesn't jump to the top on the way out.
    Item {
        id: pageArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        clip: true

        Loader {
            id: loaderA
            width: pageArea.width
            height: pageArea.height
            Behavior on x {
                id: behaviorA
                NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
            }
        }
        Loader {
            id: loaderB
            width: pageArea.width
            height: pageArea.height
            Behavior on x {
                id: behaviorB
                NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
            }
        }
    }

    // Which Loader currently holds the page on screen, and what it is.
    property bool _frontIsA: true
    property string _shownPage: "home"

    function componentFor(page) {
        switch (page) {
        case "wifi": return wifiPage;
        case "bluetooth": return bluetoothPage;
        case "ethernet": return ethernetPage;
        case "wifi-detail": case "bt-detail": case "eth-detail": return detailPage;
        default: return homePage;
        }
    }
    // How deep a page sits: the grid, a section list, then one endpoint's
    // detail. The direction of the slide falls straight out of comparing
    // two of these, so "back" never needs its own bookkeeping.
    function pageDepth(page) {
        if (page === "home") return 0;
        if (page === "wifi" || page === "bluetooth" || page === "ethernet") return 1;
        return 2;
    }

    onCurrentPageChanged: root._slideTo(root.currentPage)

    function _slideTo(page) {
        if (page === root._shownPage) return;

        const incoming = root._frontIsA ? loaderB : loaderA;
        const outgoing = root._frontIsA ? loaderA : loaderB;
        const incomingBehavior = root._frontIsA ? behaviorB : behaviorA;
        const outgoingBehavior = root._frontIsA ? behaviorA : behaviorB;
        const forward = root.pageDepth(page) > root.pageDepth(root._shownPage);
        // Closed, or mid-open-reset: no one is watching a slide behind a
        // collapsed drawer, and the open-time reset to "home"
        // deliberately opts out of one entirely (see `_instantSwap`).
        const animate = root.drawerOpen && !root._instantSwap;

        incomingBehavior.enabled = false;
        incoming.sourceComponent = root.componentFor(page);
        incoming.x = animate ? (forward ? pageArea.width : -pageArea.width) : 0;
        incomingBehavior.enabled = animate;

        outgoingBehavior.enabled = animate;
        incoming.x = 0;
        outgoing.x = animate ? (forward ? -pageArea.width : pageArea.width) : 0;

        root._frontIsA = !root._frontIsA;
        root._shownPage = page;
        cleanupTimer.restart();
    }

    // Frees whichever layer is now parked off screen, once the slide has
    // finished -- a page left loaded there would keep its bindings (and
    // its scan timer, for a section list) alive for nothing.
    Timer {
        id: cleanupTimer
        interval: 300
        onTriggered: {
            const back = root._frontIsA ? loaderB : loaderA;
            back.sourceComponent = null;
            back.x = 0;
        }
    }

    Component.onCompleted: {
        loaderA.sourceComponent = root.componentFor(root.currentPage);
        root._shownPage = root.currentPage;
    }
}
