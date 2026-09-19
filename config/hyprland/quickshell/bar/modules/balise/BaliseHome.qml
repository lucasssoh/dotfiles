import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Hyprland
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
// 2x2 grid (WiFi/Bluetooth/Ethernet/Charge limit) + a SYSTEM block
// (Night mode + HDR side by side, then Capture), porting ui/home.rs's
// own layout and then diverging from it: Airplane mode is gone (asked
// for) and HDR came down from the bar's own badge to sit next to Night
// mode.
//
// Icons only where this bar has a VERIFIED codepoint to reuse -- the
// four tiles copy theirs from BaliseButton.qml/Network.qml/Ethernet.qml's
// own icon() functions, and lu-battery-medium was rendered and looked at
// before use like the rest. The rows stay text-only: a ToggleRow has no
// glyph slot at all, so nothing there is guessing a codepoint.
//
// Second slice (see the project plan): right-click on WiFi/Bluetooth (a
// plain click on Ethernet, which has no radio to toggle) opens that
// section's list -- scan + connect/disconnect for an already-existing
// profile only, no password entry, no pairing, no detail page (all
// deferred at the time; the detail page landed in the third slice and
// WiFi credential entry, including enterprise/eduroam, in the fourth --
// see BaliseDetailPage.qml. Bluetooth pairing is still outstanding).
// Navigation stays inside this same file rather
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
    // The `_instantSwap` flag that used to guard this is gone with the
    // slide it guarded: it existed only to keep this reset from playing a
    // sideways push underneath the drawer's own reveal, and there is no
    // sideways push left to suppress.
    onDrawerOpenChanged: {
        if (root.drawerOpen) {
            root.currentPage = "home";
            root.detailId = "";
            // Only needed when nothing is rebuilt -- see BaliseReveal.replay.
            BaliseReveal.replay();
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
    // + the handle's band: pageHeight measures the PAGE, the handle sits
    // above it, so the drawer has to grow by exactly that much.
    implicitHeight: root.pageHeight + handle.implicitHeight
    // Still here, and still only ever exercised by DrawerIsland driving
    // this Item's height between 0 and `pageHeight` -- i.e. the drawer
    // reveal for Balise itself, the notification center's own entry
    // being the other one on the same island.
    // Kept equal to DrawerIsland's `revealDuration` -- see the comment there.
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    // ---- Lenovo conservation mode ----
    // Gone from this drawer: the ~60% charge cap is a BATTERY control,
    // and it lived in this tile grid only because dropping "Airplane
    // mode" had freed the slot. It now sits in the power drawer
    // (modules/power/PowerHome.qml) next to the power profile and the
    // consumption curve, which is where someone goes to think about
    // charge at all. The state reads and the sysfs write moved with it
    // verbatim, still through SystemStats rather than BaliseState's
    // socket -- a sysfs attribute is not something the Rust daemon has
    // any business proxying.

    // ---- HDR ------------------------------------------------------------
    //
    // Moved here from the bar's own Hdr badge (shell.qml no longer
    // instantiates it) -- asked for, "à côté de night mode". The state
    // read and the toggle both live in services/HdrState.qml now: this
    // file held its own copy for exactly one pass, until the "hdr"
    // indicator in the TOOLS row would have made it a third. See that
    // singleton's header for why the toggle has to be a real Process.
    //
    // The badge's capability check is NOT reinstated, for the same reason
    // it was dropped there: neither a strike nor a grey fill read
    // clearly, so the control looks the same regardless of what the EDID
    // claims. On a row with a real title that matters less than it did on
    // a 35px badge -- "HDR" is legible either way.
    //
    // `monitor` is passed in from shell.qml, because HDR is per screen.
    property var monitor: Hyprland.focusedMonitor
    readonly property bool hdrActive: HdrState.activeOn(root.monitor)

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
    // tiles below use: same glyphs (ph-network / ph-wifi-low /
    // -medium / -high / -slash, all already verified in Network.qml and
    // Ethernet.qml), just spelled in a form that survives every editor
    // and diff tool unambiguously.
    readonly property string heroGlyph: {
        if (root.activeWiredProfile) return String.fromCharCode(0xedde);   // ph-network
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
    readonly property color accent: Ink.accent

    // ---- entrance cascade -------------------------------------------
    // Lives in RevealPop.qml + services/BaliseReveal.qml now: the section
    // list, the detail page and the three row delegates all animate the
    // same way, and six files cannot share an inline component.
    // BaliseReveal's header has the reasoning; the `revealIndex` on each
    // call site below is just this page's running order.

    // Moved out to modules/DrawerTile.qml, unchanged, when PowerHome.qml
    // became the third drawer on this island and needed the same card.
    // Kept as an alias so every `Tile { ... }` below reads exactly as it
    // did -- see that file's header for the one difference (`accent` is a
    // property there instead of reaching into this file's `root.accent`,
    // and defaults to the same Ink.accent).
    component Tile: DrawerTile {}

    // Small-caps group label above a block of tiles/rows -- the mockup's
    // own "CONNECTIVITÉ"/"OPTIONS" rhythm, same typography
    // BaliseSectionList.qml's own section headers already use.
    component GroupLabel: DrawerGroupLabel {}

    // Full-width settings row (Night mode) -- a filled card with a real
    // track+thumb switch on the right rather than the bordered pill
    // button this used before, matching the mockup (and reusing
    // NotificationCenter.qml's own DND toggle recipe verbatim so the two
    // drawers' switches are literally the same control).
    component ToggleRow: Rectangle {
        id: trow
        property int revealIndex: 0
        RevealPop { item: trow; index: trow.revealIndex }
        required property string title
        property string subtitle: ""
        property string glyph: ""
        property bool checked: false
        signal toggled(bool value)

        height: trow.subtitle !== "" ? 54 : 46
        radius: 12

        // Same glass edge every other block in this bar now carries --
        // see GlassCard.qml. Only the block itself goes through the lens;
        // any icon tile nested inside it is left plain, or the two
        // rims would sit 4px apart and read as noise.
        // Only while this is HOVERED or ON -- asked for: the glass is a
        // state cue, not decoration, so a zone nobody is touching and
        // nothing has switched on carries no edge at all. It also means
        // the layer is allocated only for the one element in play.
        layer.enabled: trow.checked || mouseArea.containsMouse
        layer.effect: GlassCard { radius: 12 }
        // The card itself carries the state -- there is no switch. It used
        // to have a real track+thumb on the right; dropping it and tinting
        // the card instead is exactly what the WiFi/Bluetooth/Ethernet
        // tiles above already do, so SYSTEM stops speaking a different
        // visual language from the grid directly above it, and the ~56px
        // the track and its margin occupied goes back to the label.
        //
        // Those 56px are also what retired the `compact` variant this
        // briefly carried: at half width the titles fit unaided once
        // nothing sits to their right, so the tighter margins and the
        // 13px title are gone again.
        //
        // Same four combinations as Tile (off/on x rest/hover) reading the
        // same tokens, so the two cannot drift apart. That includes the
        // off/rest cell, which is `cardDeep` on both: everything in this
        // panel that is switched off now recedes into it, and only what
        // is on or under the pointer comes forward.
        color: trow.checked
            ? (mouseArea.containsMouse ? Surfaces.accentStrongest : Surfaces.accentMedium)
            : (mouseArea.containsMouse ? Surfaces.cardHover : Surfaces.cardDeep)
        border.width: 1
        border.color: trow.checked ? root.accent : Qt.rgba(1, 1, 1, 0.18)
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        // The same badge the connectivity tiles above carry -- asked
        // for, so that SYSTEM reads as the same kind of control as the
        // grid rather than as a list of bare labels. One shared
        // component, see DrawerIconBadge.qml.
        DrawerIconBadge {
            id: trowBadge
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            glyph: trow.glyph
            active: trow.checked
            accent: root.accent
        }

        Column {
            // Anchored to the badge when there is one and to the card
            // edge when there is not, so a row without an icon keeps the
            // layout it had before this existed.
            anchors.left: trow.glyph !== "" ? trowBadge.right : parent.left
            anchors.leftMargin: trow.glyph !== "" ? 12 : 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: trow.title
                // Accent when on, same as Tile.fg -- the label is part of
                // the highlight, not a neutral sitting inside it.
                color: trow.checked ? root.accent : Ink.primary
                font.family: Fonts.ui
                // 13, matching DrawerTile's own title, not the 14 these
                // rows used before they had icons. Two reasons and they
                // point the same way: the badge these gained takes 42px
                // out of a 152px half-width cell, which left 78px against
                // the 80px "Night mode" measures at 14 -- it elided. And
                // "same style as the connectivity tiles" is about the
                // type as much as the badge.
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: trow.subtitle !== ""
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: trow.subtitle
                color: Ink.secondary
                font.family: Fonts.ui
                font.pixelSize: 11
                elide: Text.ElideRight
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
        property int revealIndex: 0
        RevealPop { item: arow; index: arow.revealIndex }
        required property string title
        property string glyph: ""
        signal activated()

        height: 46
        radius: 12

        // Same glass edge every other block in this bar now carries --
        // see GlassCard.qml. Only the block itself goes through the lens;
        // any icon tile nested inside it is left plain, or the two
        // rims would sit 4px apart and read as noise.
        // Only while this is HOVERED or ON -- asked for: the glass is a
        // state cue, not decoration, so a zone nobody is touching and
        // nothing has switched on carries no edge at all. It also means
        // the layer is allocated only for the one element in play.
        layer.enabled: mouseArea.containsMouse
        layer.effect: GlassCard { radius: 12 }
        // Near-black at rest, same as ToggleRow above -- asked for, and
        // the two sit next to each other in the SYSTEM group so they
        // have to match.
        color: mouseArea.containsMouse ? Surfaces.cardHover : Surfaces.cardDeep
        // A hairline this row did NOT have before, matching ToggleRow's
        // own. Without it a near-black fill on a near-black panel leaves
        // nothing at all to aim at: the glass edge only arrives on
        // hover, so at rest the border IS the button.
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Behavior on color { ColorAnimation { duration: 120 } }

        // Never `active`: a one-shot action has no on-state to tint,
        // so this badge stays the neutral tier permanently.
        DrawerIconBadge {
            id: arowBadge
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            glyph: arow.glyph
            accent: root.accent
        }

        Text {
            anchors.left: arow.glyph !== "" ? arowBadge.right : parent.left
            anchors.leftMargin: arow.glyph !== "" ? 12 : 16
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: arow.title
            color: Ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13   // matches ToggleRow and DrawerTile
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
            GroupLabel { text: "CURRENT NETWORK"; revealIndex: 0 }

            Rectangle {
                // The one animated block that is not one of the reusable
                // components above, so it carries the cascade inline.
                id: heroCard
                RevealPop { item: heroCard; index: 1 }

                width: parent.width
                height: 66
                radius: 14

                // Near-black at rest -- asked for. This block is pure
                // display (it names the network you are on), so it has
                // no active state to brighten into; it simply recedes,
                // and its border is what keeps the shape. See
                // Surfaces.cardDeep.
                color: Surfaces.cardDeep
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
                        color: Ink.primary
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
                        color: root.heroConnected ? root.accent : Ink.secondary
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
                        color: root.heroConnected ? root.accent : Ink.secondary
                        font.family: Fonts.iconPhosphor
                        font.pixelSize: 18
                    }
                }
            }

            Item { width: 1; height: 4 }

            GroupLabel { text: "CONNECTIVITY"; revealIndex: 2 }

            Row {
                width: parent.width
                spacing: 16
                Tile {
                    width: (parent.width - 16) / 2
                    height: 92
                    title: "WiFi"
                    revealIndex: 3
                    status: root.wifiTileStatus
                    glyph: BaliseState.wifiEnabled ? "\uE1AE" : "\uE1AF"   // lu-wifi / lu-wifi-off
                    active: BaliseState.wifiEnabled
                    onActivated: BaliseState.toggleWifi()
                    onActivatedSecondary: root.goTo("wifi")
                }
                Tile {
                    width: (parent.width - 16) / 2
                    height: 92
                    title: "Bluetooth"
                    revealIndex: 4
                    status: root.bluetoothTileStatus
                    glyph: BaliseState.bluetoothEnabled ? "\uE05C" : "\uE1B9"   // lu-bluetooth / lu-bluetooth-slash
                    active: BaliseState.bluetoothEnabled
                    onActivated: BaliseState.toggleBluetooth()
                    onActivatedSecondary: root.goTo("bluetooth")
                }
            }
            Row {
                width: parent.width
                spacing: 16
                Tile {
                    // Full width, unconditionally: the charge cap that
                    // used to take the other half of this row moved to
                    // the power drawer, and Ethernet is alone here now.
                    // Still an explicit width rather than a stretch -- a
                    // positioner reclaims a hidden child's space, it does
                    // not stretch the survivor into it.
                    width: parent.width
                    height: 92
                    title: "Ethernet"
                    revealIndex: 5
                    status: root.ethernetTileStatus
                    glyph: root.activeWiredProfile ? "\uE125" : "\uE45D"   // lu-network / lu-unplug
                    active: root.activeWiredProfile !== null
                    // No radio to toggle -- both buttons open the section.
                    onActivated: root.goTo("ethernet")
                    onActivatedSecondary: root.goTo("ethernet")
                }
            }
            Item { width: 1; height: 4 }

            GroupLabel { text: "SYSTEM"; revealIndex: 7 }

            // Night mode and HDR sit SIDE BY SIDE -- asked for ("à coté
            // de night mode, ajoute les bouton hdr"). HDR replaces the
            // charge cap in this slot; the cap moved up into the tile
            // grid, where the Airplane tile used to be.
            //
            // The pair is unconditional now, which is what let both
            // widths go back to a plain half: the cap was gated on
            // hardware that most machines do not have, so this Row needed
            // the "survivor takes the full width" dance. HDR has no such
            // gate (see the hdrActive block up top for why the capability
            // check is deliberately not reinstated), so there is always
            // exactly one row of two here.
            //
            // Both still drop their subtitle: at half width "Warmer
            // screen temperature" does not fit, and a subtitle on one but
            // not the other reads as a mistake. ToggleRow collapses
            // 54 -> 46px when subtitle is empty, so the pair stays a tidy
            // band.
            Row {
                width: parent.width
                spacing: 16

                ToggleRow {
                    width: (parent.width - parent.spacing) / 2
                    title: "Night mode"
                    glyph: "\uE11E"   // lu-moon
                    revealIndex: 8
                    checked: BaliseState.nightModeEnabled
                    onToggled: BaliseState.toggleNightMode()
                }

                ToggleRow {
                    width: (parent.width - parent.spacing) / 2
                    title: "HDR"
                    // lu-monitor: HDR is a per-DISPLAY capability here (this
                    // page binds `monitor: Hyprland.monitorFor(...)`), so a
                    // screen is the honest picture -- and it collides with
                    // none of the other three glyphs in this group.
                    glyph: "\uE11D"
                    revealIndex: 9
                    checked: root.hdrActive
                    onToggled: HdrState.toggle()
                }
            }

            // Full width, and NOT a third cell in the Row above: that pair
            // is deliberately exactly two half-widths, and this one earns
            // the subtitle a half-width cannot fit. The scope is the whole
            // point here -- "Dark mode" on its own would read as a promise
            // to darken everything, including this bar, which is precisely
            // what it does not do (see AppearanceState.qml's header: the
            // bar's own ink comes from the wallpaper, and Qt apps are
            // knowingly not covered).
            ToggleRow {
                width: parent.width
                title: "Dark mode"
                glyph: "\uE09D"   // lu-contrast
                revealIndex: 10
                subtitle: "turn dark mode on"
                checked: AppearanceState.dark
                onToggled: (value) => AppearanceState.setDark(value)
            }

                ActionRow {
                    width: parent.width
                    title: "Screenshot"
                    glyph: "\uE064"   // lu-camera
                    revealIndex: 11
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
    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: BaliseState.close()
    }

    Item {
        id: pageArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        clip: true

        // No `Behavior on x` on either Loader any more -- the sideways
        // push is gone (asked for: "c'est le slide justement que je veux
        // remplacer par ça"). Both layers now sit at x 0 always and the
        // swap is instant; what the eye follows is the incoming page's
        // own cascade, which starts on the same frame. The two Loaders
        // are still two, though: the outgoing page has to stay alive and
        // untouched for the frame the swap happens on, and rebuilding it
        // into the same Loader would throw away its scroll position on
        // the way out.
        Loader {
            id: loaderA
            width: pageArea.width
            height: pageArea.height
        }
        Loader {
            id: loaderB
            width: pageArea.width
            height: pageArea.height
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
    onCurrentPageChanged: root._swapTo(root.currentPage)

    // Was _slideTo, and the direction bookkeeping went with it: nothing
    // moves sideways any more, so "forward" and "back" look identical and
    // pageDepth no longer has a caller. What replaces it is the incoming
    // page building itself element by element -- every one of them is
    // constructed fresh here, so RevealPop's own Component.onCompleted
    // starts the cascade with no signal needed from this function.
    function _swapTo(page) {
        if (page === root._shownPage) return;

        const incoming = root._frontIsA ? loaderB : loaderA;
        const outgoing = root._frontIsA ? loaderA : loaderB;

        incoming.sourceComponent = root.componentFor(page);
        incoming.x = 0;
        outgoing.x = 0;

        root._frontIsA = !root._frontIsA;
        root._shownPage = page;
        cleanupTimer.restart();
    }

    // Frees whichever layer is now parked off screen, once the slide has
    // finished -- a page left loaded there would keep its bindings (and
    // its scan timer, for a section list) alive for nothing.
    Timer {
        id: cleanupTimer
        // Was 300, to outlast the 280ms slide. Nothing is sliding now, so
        // this only has to outlast the frame the swap lands on -- kept at
        // a comfortable 50 rather than 0 so the outgoing page is never
        // torn down inside the same event loop pass that built its
        // replacement.
        interval: 50
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
