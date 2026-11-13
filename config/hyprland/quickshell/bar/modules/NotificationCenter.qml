import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Mpris
import "../theme"
import "../services"

// swaync's control-center replacement -- a clock with the DND toggle
// beside it, a trimmed mpris section, then "Clear all" sitting on top
// of the notification history itself
// (NotificationState.trackedNotifications -- see that file's header for
// why this list IS the daemon's own history, not a separate buffer).
//
// The quick-action buttons swaync's buttons-grid had (Night mode,
// Screenshot) are NOT here any more -- asked for: "enlever les boutons
// pour screenshot et pour nightmode car c'est deja dans balise". Both
// now live as real rows in Balise's own home page
// (modules/balise/BaliseHome.qml, driven by BaliseState.toggleNightMode()
// /triggerScreenshot()), which is the toggle surface for system controls
// -- and Balise's night-mode row is a *stateful* switch reflecting the
// daemon's live state, where this file's button was a fire-and-forget
// `bash -c` with no idea whether night mode was currently on. Two
// controls for one setting, one of them blind: the blind one goes. This
// drawer keeps only what is about notifications themselves.
//
// A DrawerIsland entry now (shell.qml's `toolsIsland`, the TOOLS block
// turned into a drawer -- asked for explicitly: "même mécanisme que
// Veille/Keybindings", after a first pass built this as its own separate
// floating PanelWindow+HyprlandFocusGrab). Satisfies the exact contract
// DrawerIsland.qml's header documents: `drawerOpen` (bound from outside,
// shell.qml), `implicitHeight` (this file's job), and this file's own
// `Behavior on height` -- DrawerIsland itself drives `width`/`height`/
// `opacity` from outside via Binding, so none of those three are set
// here any more. That Binding is ALSO what gives "fade + scroll, super
// naturel" for free (opacity tied to height/implicitHeight ratio, i.e.
// the fade tracks the scroll in lockstep) -- exactly the motion already
// proven on Veille/Keybindings, so no bespoke animation timing needs
// tuning here by hand any more.
//
// Width is NOT fixed at 380 any more either: DrawerIsland forces every
// entry to `effectiveWidth`, the TOOLS row's own natural max width (see
// NotificationBell.qml's header for why inflating just the bell's own
// width hint would be the wrong lever) -- every section below already
// sizes off `parent.width`, so this reflows cleanly whatever width that
// turns out to be, rather than assuming a specific number.
//
// Closed on outside click via shell.qml's existing Hyprland raw-event
// listener (the same one that already dismisses the keybinds sheet) --
// no HyprlandFocusGrab needed once this lives inside the bar's own
// always-present window instead of a separate focusable one. Balise
// (TOOLS' other, unrelated occupant) still gets pre-emptively hidden
// when this opens and vice versa -- pure declutter now that both live in
// the same block anyway, not overlap-avoidance.
//
// No own background/radius/GlassRim any more (asked for: "puisque tu
// intègre ça directement, plus besoin de border") -- that was a card
// drawn INSIDE toolsIsland's own already-rounded, already-rimmed pill, a
// border-within-a-border once this became a real drawer entry rather
// than free-floating content. Plain `Item` now, same as
// KeybindsDrawerContent.qml/VeilleDrawerContent.qml -- content sits
// directly on toolsIsland's own shared fill (DrawerIsland sets
// `clip: true` on this entry itself, so the rounded-bottom clipping
// still applies).
Item {
    id: root

    property bool drawerOpen: false
    // How far the pane may run: from under the band down to the bottom of
    // Hyprland's tiled windows, handed in by shell.qml (asked for: "au même
    // alignement en haut que le reste des tiroirs, mais en bas ne dépasse
    // pas les fenêtres tiles"). The history takes whatever the clock, the
    // player and "Clear all" leave of it. The fallback is the old fixed
    // 404px history, for a screen this is not told about.
    //
    // Cost, measured before doing it: the bar's surface is sized to its
    // tallest drawer and fully damaged on every commit, so this makes it
    // ~1160px tall for good (696px read ~8.6% render busy, 2250px ~16.1%).
    property int availableHeight: 0
    implicitHeight: root.availableHeight > 0 ? root.availableHeight
        : handle.implicitHeight + 20 + topSection.height + 16 + listHeader.height + 8 + 404 + 20
    // Kept equal to DrawerIsland's `revealDuration` -- see the comment
    // there; the island waits out exactly this long before fading content in.
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    // Minutes, not Seconds -- the display dropped its seconds, so asking
    // the clock for them would be a wakeup a minute's worth of frames
    // that change nothing on screen. Still gated on `drawerOpen`: no
    // reason to tick for a pane nobody can see.
    SystemClock {
        id: clock
        enabled: root.drawerOpen
        precision: SystemClock.Minutes
    }

    // mpris `position` is a live value Quickshell interpolates on READ --
    // it is not a property that notifies once a second, so a binding on
    // it would render the playhead once and then sit there. Probed
    // against the real player before building the progress row on it:
    // `length`/`position`/`lengthSupported`/`positionSupported` all come
    // back populated and position advances by 1.0 per second between
    // reads. Hence a timer that pulls it into a plain property the bar
    // below can bind to. Gated on `drawerOpen`, same as the clock.
    property real mprisPosition: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.drawerOpen && root.mprisPlayer !== null
        // Without this the bar would sit at 0 for a second every time
        // the drawer opens.
        triggeredOnStart: true
        onTriggered: root.mprisPosition = root.mprisPlayer ? root.mprisPlayer.position : 0
    }
    // ---- track length, LATCHED per track -------------------------------
    //
    // Firefox -- the player this drawer sees most of the time -- publishes
    // `mpris:length` in some metadata updates and simply omits the field
    // from the next update for the SAME track. Quickshell's `length` then
    // falls back to tracking `position`, and `lengthSupported` goes false.
    // That is exactly the "ça marche au début, après ça s'enlève" this row
    // did in its first version, which read `lengthSupported` live: the
    // readout appeared when the track started and vanished on the next
    // metadata update. Verified by logging lengthChanged /
    // lengthSupportedChanged / uniqueIdChanged against the real player
    // rather than inferred from the symptom.
    //
    // So the last real length seen for the current track is kept until the
    // TRACK itself changes. A track's duration does not change while it
    // plays, so holding on to it is not a guess -- it is the same number
    // the player itself published a moment earlier.
    //
    // Signal handlers, not a poll, and deliberately NOT gated on
    // `drawerOpen` like the position timer below: these fire only on
    // metadata updates (a handful per track), and the one update that
    // carries a usable length normally arrives when the track starts,
    // long before anyone opens this drawer.
    property int mprisTrackId: -1
    property real mprisTrackLength: 0

    function _latchMprisLength() {
        const p = root.mprisPlayer;
        if (!p) {
            root.mprisTrackId = -1;
            root.mprisTrackLength = 0;
            return;
        }
        if (p.uniqueId !== root.mprisTrackId) {
            root.mprisTrackId = p.uniqueId;
            root.mprisTrackLength = 0;
            // A track change resets the playhead immediately rather than
            // leaving the previous track's position on screen until the
            // next tick.
            root.mprisPosition = p.position;
        }
        if (p.lengthSupported && p.length > 0) root.mprisTrackLength = p.length;
    }

    Connections {
        target: root.mprisPlayer
        function onUniqueIdChanged() { root._latchMprisLength(); }
        function onLengthChanged() { root._latchMprisLength(); }
        function onLengthSupportedChanged() { root._latchMprisLength(); }
    }
    onMprisPlayerChanged: root._latchMprisLength()

    // mm:ss, growing to h:mm:ss only for the tracks that need it -- a
    // fixed h:mm:ss would print "0:03:32" for every song.
    function formatDuration(seconds: real): string {
        if (!isFinite(seconds) || seconds <= 0) return "0:00";
        const total = Math.floor(seconds);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const sec = total % 60;
        const pad = (n) => (n < 10 ? "0" + n : "" + n);
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : pad(m) + ":" + pad(sec);
    }

    // Same playerctld blacklist Media.qml's own mpris widget applies
    // (that file's header: "same blacklist swaync/config.json already
    // applies to its mpris widget") -- copied rather than reusing
    // Media.qml itself, which is built for a 24px bar pill, not a 340px
    // vertical card.
    // The player's cover, round beside the title when it loads.
    readonly property string artUrl: root.mprisPlayer ? (root.mprisPlayer.trackArtUrl || "") : ""

    readonly property var mprisPlayer: {
        const real = Mpris.players.values.filter((p) => p.dbusName.indexOf("playerctld") === -1);
        for (let i = 0; i < real.length; i++) if (real[i].isPlaying) return real[i];
        return real.length > 0 ? real[0] : null;
    }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: BarPosition.bottom ? undefined : parent.top
        anchors.bottom: BarPosition.bottom ? parent.bottom : undefined
        onCloseRequested: NotificationState.close()
    }

    Column {
        id: topSection
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: BarPosition.bottom ? parent.top : handle.bottom
        // 20, the history's own margins: one left edge down the drawer.
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        // 12, as Programme's tabs: the two sheets start on the same line.
        anchors.topMargin: 12
        spacing: 12

        // ---- clock, date, DND ----
        //
        // Editorial (asked for, variant C): a big, very thin clock on the
        // left, the day spelled out on its right, then "Do not disturb" as
        // a named switch on its own row under a hairline. Fewer boxes: the
        // player and the history lose their fills, hairlines part them.
        //
        // The time keeps Inter-style TABULAR figures (`tnum`): every digit
        // one advance, so the minutes turning never shifts the string.
        // The date is forced to en_US, like every string in this drawer.
        Item {
            width: parent.width
            height: clockText.implicitHeight

            Text {
                id: clockText
                anchors.left: parent.left
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: Qt.formatDateTime(ShellClock.at(clock.date), "HH:mm")
                color: DrawerTheme.primary
                font.family: Fonts.ui
                font.pixelSize: 54
                font.weight: Font.ExtraLight
                font.letterSpacing: -1.5
                font.features: ({ "tnum": 1 })
            }
            // Its second line sits on the clock's baseline.
            Column {
                anchors.right: parent.right
                y: clockText.baselineOffset - (dateLine.y + dateLine.baselineOffset)
                spacing: 1

                Text {
                    anchors.right: parent.right
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: ShellClock.at(clock.date).toLocaleDateString(Qt.locale("en_US"), "dddd")
                    color: DrawerTheme.primary
                    font.family: Fonts.ui
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    id: dateLine
                    anchors.right: parent.right
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: ShellClock.at(clock.date).toLocaleDateString(Qt.locale("en_US"), "MMMM d")
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 13
                }
            }
        }

        // The whole row toggles; the switch shows the state.
        Item {
            width: parent.width
            height: 40

            Rectangle {
                width: parent.width
                height: 1
                color: DrawerTheme.ink(DrawerTheme.dark ? 0.07 : 0.08)
            }
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "Do not disturb"
                color: DrawerTheme.primary
                font.family: Fonts.ui
                font.pixelSize: 13
            }
            Rectangle {
                id: dndSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2
                width: 34
                height: 20
                radius: 10
                color: NotificationState.dnd ? DrawerTheme.accent : DrawerTheme.cardRaised
                border.width: NotificationState.dnd ? 0 : 1
                border.color: DrawerTheme.ink(DrawerTheme.dark ? 0.10 : 0.12)
                Behavior on color { ColorAnimation { duration: 140 } }

                Rectangle {
                    x: NotificationState.dnd ? parent.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: NotificationState.dnd ? DrawerTheme.onInk : DrawerTheme.secondary
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationState.toggleDnd()
            }
        }

        // ---- mpris (autohide when nothing's playing, like swaync's own) ----
        //
        // No card under it any more: the row sits on the drawer itself. The
        // album art is back, round, but only when the player publishes one
        // that loads -- no empty tile in its place. Elapsed / total as two
        // numbers under the title; the total only when the player gives a
        // length (some never do: YouTube mixes, live streams), so the row
        // never waits on a field the player drops and re-adds.
        Item {
            width: parent.width
            height: mediaColumn.height
            // Not in demo mode: what you are playing is yours, like the
            // figures demo mode makes up.
            visible: root.mprisPlayer !== null && !DemoState.active

            Item {
                id: artDisc
                readonly property bool shown: artImage.status === Image.Ready
                anchors.left: parent.left
                anchors.top: parent.top
                width: artDisc.shown ? 38 : 0
                height: 38

                // Round by a mask: a layer drawn once per cover and cached.
                Image {
                    id: artImage
                    anchors.fill: parent
                    visible: artDisc.shown
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    source: root.artUrl
                    sourceSize.width: 76
                    sourceSize.height: 76
                    layer.enabled: artDisc.shown
                    layer.effect: OpacityMask {
                        maskSource: Rectangle { width: 38; height: 38; radius: 19 }
                    }
                }
            }

            Column {
                id: mediaColumn
                anchors.left: artDisc.right
                anchors.leftMargin: artDisc.shown ? 12 : 0
                anchors.right: parent.right
                // The transport buttons carry ~7px of their own padding
                // inside their 30px hit target.
                anchors.rightMargin: -7
                spacing: 4

                Item {
                    width: parent.width
                    height: Math.max(titleColumn.height, transport.height)

                    Column {
                        id: titleColumn
                        anchors.left: parent.left
                        anchors.right: transport.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: root.mprisPlayer ? (root.mprisPlayer.trackTitle || root.mprisPlayer.identity || "") : ""
                            color: DrawerTheme.primary
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: root.mprisPlayer ? (root.mprisPlayer.trackArtist || "") : ""
                            color: DrawerTheme.secondary
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }

                    // Transport. Real buttons, so a stray click on the title
                    // never pauses the music.
                    Row {
                        id: transport
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        TransportButton {
                            glyph: "\uF37C"                                  // mgc skip_previous
                            enabled: root.mprisPlayer ? root.mprisPlayer.canGoPrevious : false
                            onTriggered: root.mprisPlayer.previous()
                        }
                        TransportButton {
                            glyph: (root.mprisPlayer && root.mprisPlayer.isPlaying) ? "\uF17A" : "\uF1D8"   // mgc pause / play
                            glyphSize: 17
                            enabled: root.mprisPlayer ? root.mprisPlayer.canTogglePlaying : false
                            onTriggered: root.mprisPlayer.togglePlaying()
                        }
                        TransportButton {
                            glyph: "\uF37A"                                  // mgc skip_forward
                            enabled: root.mprisPlayer ? root.mprisPlayer.canGoNext : false
                            onTriggered: root.mprisPlayer.next()
                        }
                    }
                }

                // Read-only: where the track is, nothing more.
                Text {
                    visible: root.mprisPlayer !== null && root.mprisPlayer.positionSupported
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: root.formatDuration(root.mprisPosition)
                        + (root.mprisTrackLength > 0 ? " / " + root.formatDuration(root.mprisTrackLength) : "")
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 12
                    // Ticks every second: tabular, so it never walks.
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // One transport control. Bare glyph, no chrome at rest -- the card it
    // sits on is already a surface, and stacking a second one per button
    // would turn a two-line row into a control panel. The hover disc is
    // what makes it read as pressable, and it only exists while the
    // pointer is on it.
    //
    // Phosphor FILL, not the Bold outline the bar's own icons use: at
    // 15px a hollow triangle and a hollow pair of bars lose their inside,
    // and transport symbols are read by silhouette. Checked against both
    // weights at size before picking.
    component TransportButton: Item {
        id: tb
        required property string glyph
        property int glyphSize: 15
        signal triggered()

        width: 30
        height: 30
        // Not `opacity`: that would fade the hover disc too on the frame
        // where a player gains the capability mid-hover. Only the glyph
        // dims, the geometry never moves -- a player losing canGoNext
        // must not reflow the row.
        enabled: true

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: DrawerTheme.cardHover
            opacity: (tb.enabled && hover.containsMouse) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 110 } }

            // GlassChip, not GlassCard: this disc is 30px and a 7px band
            // would be most of its radius. It fades in and out with the
            // disc it edges (the layer follows `opacity`, and drops out
            // entirely at 0), so the transport buttons still show
            // nothing at rest -- the glass appears with the hover, it
            // does not put a permanent ring on every button.
        }

        Text {
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: tb.glyph
            color: !tb.enabled ? DrawerTheme.ink(0.22)
                 : hover.containsMouse ? DrawerTheme.accent : DrawerTheme.primary
            Behavior on color { ColorAnimation { duration: 110 } }
            font.family: Fonts.iconMingcute
            font.pixelSize: tb.glyphSize
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            enabled: tb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.triggered()
        }
    }

    // ---- "Clear all", sitting on the history's own top edge ----
    //
    // Moved out of the deleted header row down to here, right where the
    // real notifications start -- asked for ("Clear all sera juste en
    // haut à droite où commence les vrais notifs"). It now labels the
    // thing it acts on instead of floating in a title bar two bands
    // above it, which is also what lets the header row go away without
    // leaving the action homeless.
    Item {
        id: listHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topSection.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 16
        height: clearAllLabel.implicitHeight

        Text {
            id: clearAllLabel
            anchors.right: parent.right
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "Clear all"
            // Only when there is something to clear.
            visible: NotificationState.shown.length > 0
            color: DrawerTheme.accent
            font.family: Fonts.ui
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: clearAllLabel
            anchors.margins: -6
            enabled: NotificationState.shown.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationState.clearAll(root.clearUnits())
        }
    }

    // ---- notification history, one card per app ------------------------
    //
    // One card per app, newest app first, under TODAY / EARLIER labels (a
    // card goes where its newest notification does). The card names the
    // app once, then gives every notification its own line, time and x;
    // the header's x clears the app. Nothing folds: asked for, "une ligne
    // pour chaque notif même si c'est la même app".
    //
    // Rebuilt from NotificationServer's own list on every change, so a
    // dismissed notification simply drops out of the next build.
    // Arrival times come from NotificationState.receivedAt; anything
    // without one (none should be) counts as Earlier, oldest.

    // Re-read when midnight passes while the drawer is open.
    readonly property real midnight: {
        const now = ShellClock.at(clock.date);
        return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    }

    // "22:31" today, "Sep 27" before.
    function timeText(stamp) {
        if (!stamp) return "";
        const d = new Date(stamp);
        return stamp >= root.midnight ? Qt.formatDateTime(d, "HH:mm")
                     : d.toLocaleDateString(Qt.locale("en_US"), "MMM d");
    }

    readonly property var sections: {
        const all = NotificationState.shown;
        const stamps = NotificationState.receivedAt;
        const midnight = root.midnight;

        const items = all.map((n, i) => ({ n: n, at: stamps[n.id] || 0, i: i }));
        items.sort((x, y) => (y.at - x.at) || (y.i - x.i));

        const byApp = {};
        const order = [];
        for (const it of items) {
            const app = it.n.appName || "Notifications";
            if (!byApp[app]) { byApp[app] = { app: app, at: it.at, notes: [] }; order.push(app); }
            byApp[app].notes.push(it.n);
        }
        const today = { title: "Today", count: 0, groups: [], notes: [] };
        const earlier = { title: "Earlier", count: 0, groups: [], notes: [] };
        for (const app of order) {
            const g = byApp[app];
            g.stamps = g.notes.map((n) => stamps[n.id] || 0);
            const sec = g.at >= midnight ? today : earlier;
            sec.groups.push(g);
            sec.count += g.notes.length;
            sec.notes = sec.notes.concat(g.notes);
        }
        return [today, earlier].filter((sec) => sec.groups.length > 0);
    }

    // What "Clear all" takes away together, in screen order: line by
    // line. See NotificationState.clearAll().
    function clearUnits() {
        const units = [];
        for (const sec of root.sections)
            for (const g of sec.groups)
                g.notes.forEach((n) => units.push([n]));
        return units;
    }

    function isLeaving(n) {
        return NotificationState.leaving[n.id] === true;
    }

    Flickable {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: listHeader.bottom
        anchors.bottom: BarPosition.bottom ? handle.top : parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 12
        anchors.bottomMargin: 20
        clip: true
        contentWidth: width
        contentHeight: sectionsColumn.height
        boundsBehavior: Flickable.StopAtBounds

        // Soft edges instead of a hard cut wherever the history is taller
        // than the pane -- see ScrollFadeMask.qml.
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: listMask }

        // No `spacing` in these columns: each entry carries its own gap
        // below it (Exit's `gap`), so a leaving entry closes its gap along
        // with its height instead of leaving a spacing to snap shut.
        Column {
            id: sectionsColumn
            width: list.width

            Repeater {
                model: root.sections
                delegate: Exit {
                    id: section
                    required property var modelData
                    width: sectionsColumn.width
                    gap: 18
                    slides: false
                    // The title folds away with the section's last card.
                    leaving: section.modelData.notes.every((n) => root.isLeaving(n))
                    bodyHeight: sectionBody.height

                    Column {
                        id: sectionBody
                        width: parent.width

                        Item {
                            width: parent.width
                            height: sectionTitle.implicitHeight + 10
                            Text {
                                id: sectionTitle
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferNoHinting
                                text: section.modelData.title.toUpperCase()
                                color: DrawerTheme.muted
                                font.family: Fonts.ui
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.letterSpacing: 0.9
                            }
                            // Beside the title, not at the far right: that end
                            // is "Clear all"'s, just above.
                            Text {
                                anchors.left: sectionTitle.right
                                anchors.leftMargin: 6
                                anchors.baseline: sectionTitle.baseline
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferNoHinting
                                text: section.modelData.count
                                color: DrawerTheme.muted
                                font.family: Fonts.ui
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }

                        Repeater {
                            model: section.modelData.groups
                            delegate: AppCard {
                                required property var modelData
                                required property int index
                                width: sectionBody.width
                                group: modelData
                                gap: index < section.modelData.groups.length - 1 ? 6 : 0
                            }
                        }
                    }
                }
            }
        }

        // Positioned, not `anchors.centerIn: parent`: a Flickable's child
        // lands in its contentItem, which is as tall as the (empty) list --
        // centring on it put the text up against "Clear all".
        // A pale bell over the line, a third of the way down.
        Column {
            x: (list.width - width) / 2
            y: Math.round(list.height / 3 - height / 2)
            visible: NotificationState.shown.length === 0
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "\uF126"   // mgc notification, the bell the DND button shows
                color: DrawerTheme.faint
                font.family: Fonts.iconMingcute
                font.pixelSize: 26
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "No notifications"
                color: DrawerTheme.ink(0.4)
                font.family: Fonts.ui
                font.pixelSize: 13
            }
        }
    }

    // Size mirrors `list` exactly; position is irrelevant (see
    // ScrollFadeMask.qml -- this is consumed as a texture, never drawn
    // where it sits).
    ScrollFadeMask {
        id: listMask
        view: list
        width: list.width
        height: list.height
    }

    // Something in the history that can leave it: while `leaving`, the
    // body slides off to the right and fades (180ms, accelerating away --
    // flicked off, not easing to a stop), then the entry's height, gap
    // included, closes (160ms) so what is below moves up. The same exit
    // the ListView's remove/removeDisplaced transitions gave the flat list.
    // NotificationState holds the real dismissal until both are done.
    //
    // `slides: false` skips the slide and only fades and closes -- for a
    // section title or an app's card, whose lines already slide out on
    // their own.
    component Exit: Item {
        id: exit
        property bool leaving: false
        property bool slides: true
        property real bodyHeight: 0
        property real gap: 0
        default property alias content: body.data

        property bool closed: false
        // Rebuilt while already leaving (another notification arrived
        // mid-exit): start out closed rather than play the exit again.
        Component.onCompleted: if (exit.leaving) exit.closed = true
        onLeavingChanged: {
            if (exit.leaving) closeTimer.restart();
            else { closeTimer.stop(); exit.closed = false; }
        }
        Timer { id: closeTimer; interval: 180; onTriggered: exit.closed = true }

        height: exit.closed ? 0 : exit.bodyHeight + exit.gap
        Behavior on height {
            enabled: exit.leaving
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Item {
            id: body
            width: parent.width
            height: exit.bodyHeight
            opacity: exit.leaving ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180 } }
            transform: Translate {
                x: exit.leaving && exit.slides ? exit.width : 0
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.InCubic } }
            }
        }
    }

    // One app's notifications: a header (icon, name, an x that clears
    // them all) over one line per notification, newest first, a hairline
    // between lines. The card fades and closes with its last line.
    component AppCard: Exit {
        id: appCard
        property var group

        readonly property var newest: appCard.group.notes[0]
        // The header shows the app's own icon when it sends one. Else the
        // image its notifications share, if they all carry the same. When
        // each has its own (a screenshot's thumbnail, a contact's photo),
        // each line shows its own and the header the generic bell.
        readonly property bool oneImage: appCard.group.notes.every((n) => n.image === appCard.newest.image)
        readonly property string sharedImage: appCard.oneImage ? appCard.newest.image : ""
        readonly property string appIconPath: {
            const n = appCard.newest;
            let icon = n ? n.appIcon : "";
            // Else the desktop entry's (the desktop-entry hint): an icon
            // sent with -i lands in `image`, where a picture replaces it.
            if (!icon && n && n.desktopEntry) {
                const entry = DesktopEntries.byId(n.desktopEntry);
                icon = entry ? entry.icon : "";
            }
            if (!icon) return "";
            if (icon.startsWith("/") || icon.includes("://")) return icon;
            return Quickshell.iconPath(icon, true);
        }
        // A picture sent as a file path arrives as "image://icon//<path>",
        // which the icon provider returns at icon size: load the file.
        readonly property string image: {
            const image = appCard.appIconPath || appCard.sharedImage;
            return image.startsWith("image://icon//") ? "file://" + image.slice("image://icon/".length) : image;
        }

        leaving: appCard.group.notes.every((n) => root.isLeaving(n))
        slides: false
        bodyHeight: cardColumn.height

        // No fill: a hairline above each app parts it from the last.
        Rectangle {
            width: parent.width
            height: 1
            color: DrawerTheme.ink(DrawerTheme.dark ? 0.07 : 0.08)
        }

        Column {
            id: cardColumn
            width: parent.width

            Item {
                width: parent.width
                height: 38

                // The x that clears the app shows under the pointer only.
                HoverHandler { id: headerHover }

                Rectangle {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2
                    width: 22
                    height: 22
                    radius: 7
                    color: DrawerTheme.cardRaised

                    Image {
                        id: appImage
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: appCard.image !== "" && status !== Image.Error
                        fillMode: Image.PreserveAspectCrop
                        source: appCard.image
                    }
                    Text {
                        visible: !appImage.visible
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: "\uF126"   // mgc notification
                        color: DrawerTheme.accent
                        font.family: Fonts.iconMingcute
                        font.pixelSize: 12
                    }
                }
                Text {
                    anchors.left: appIcon.right
                    anchors.leftMargin: 8
                    anchors.right: clearApp.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: appIcon.verticalCenter
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: appCard.group.app
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Item {
                    id: clearApp
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.verticalCenter: appIcon.verticalCenter
                    width: 20
                    height: 20
                    opacity: headerHover.hovered ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Rectangle { anchors.centerIn: parent; width: 12; height: 1.5; radius: 1; color: DrawerTheme.ink(0.5); rotation: 45 }
                    Rectangle { anchors.centerIn: parent; width: 12; height: 1.5; radius: 1; color: DrawerTheme.ink(0.5); rotation: -45 }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationState.leave(appCard.group.notes)
                    }
                }
            }

            Repeater {
                model: appCard.group.notes
                delegate: Exit {
                    id: line
                    required property var modelData
                    required property int index
                    width: cardColumn.width
                    leaving: root.isLeaving(line.modelData)
                    bodyHeight: rowCard.height

                    // Same sender as the line above: the summary is not
                    // repeated, and no hairline splits the two.
                    readonly property bool continued: line.index > 0
                        && appCard.group.notes[line.index - 1].summary === line.modelData.summary
                    readonly property real stamp: appCard.group.stamps[line.index]

                    Rectangle {
                        visible: line.index > 0 && !line.continued
                        x: 2
                        width: parent.width - 4
                        height: 1
                        color: DrawerTheme.ink(DrawerTheme.dark ? 0.07 : 0.08)
                    }
                    NotificationCard {
                        id: rowCard
                        width: parent.width
                        notification: line.modelData
                        inset: 2
                        groupImage: appCard.sharedImage
                        timeText: root.timeText(line.stamp)
                        continued: line.continued
                        last: line.index === appCard.group.notes.length - 1
                        // Arrived just now, with the drawer open: comes in
                        // like a toast. The list is rebuilt on every
                        // change, so only the newest line may animate.
                        arriving: root.drawerOpen && line.stamp > 0
                            && ShellClock.now().getTime() - line.stamp < 1500
                        onDismissRequested: NotificationState.leave([notification])
                        onActionRequested: (action) => NotificationState.invokeAction(notification, action)
                    }
                }
            }

            // Room under the last line, inside the card.
            Item { width: 1; height: 4 }
        }
    }
}
