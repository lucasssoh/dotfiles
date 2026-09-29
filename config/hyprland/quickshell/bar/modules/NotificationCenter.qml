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
    readonly property var mprisPlayer: {
        const real = Mpris.players.values.filter((p) => p.dbusName.indexOf("playerctld") === -1);
        for (let i = 0; i < real.length; i++) if (real[i].isPlaying) return real[i];
        return real.length > 0 ? real[0] : null;
    }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: NotificationState.close()
    }

    Column {
        id: topSection
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        spacing: 16

        // ---- clock + DND ----
        //
        // The "Notifications" title is gone (asked for) and the DND
        // control came up here with it, as the icon button on the LEFT of
        // the clock -- the layout in the reference screenshot, mirrored,
        // since the clock stays right-aligned. What it replaces was a
        // full-width 44px row reading "Do not disturb" with a switch on
        // its end: that row cost the drawer a whole band to carry one
        // boolean, and with the title deleted there was no longer a
        // left-hand column of labels for it to line up with anyway.
        //
        // Same two Phosphor codepoints NotificationBell.qml already uses
        // for these exact two states -- U+E0CE bell / U+E5EE bell-z --
        // reused verbatim rather than re-picked, so the trigger in the
        // bar and the toggle in the drawer never drift into showing
        // different glyphs for one state. "On" is carried by an inverted
        // fill (accent plate, dark glyph) rather than by the glyph swap
        // alone: bell and bell-z differ by a couple of small strokes,
        // which at 18px is not a state you can read at a glance.
        //
        // The time is inked to the RIGHT edge (asked for). That is
        // exactly where proportional figures hurt most -- the ragged edge
        // lands on the side the eye is using as its alignment reference,
        // so a "1" in the minutes would visibly pull the whole string
        // sideways on the turn of a minute. Inter's TABULAR figures
        // (`tnum`) fix every digit to one advance; its proportional "1"
        // inks barely two thirds the width of its "0". Clash Grotesk
        // (Fonts.clock, what Veille's big clock uses) was the other
        // candidate and is out for that reason -- it ships no tnum
        // feature at all and its "1" is less than half the width of its
        // "0" (checked in the font's own hmtx/GSUB tables, not guessed).
        //
        // The date is forced to en_US rather than run through
        // Qt.formatDateTime, which would follow this session's fr_FR
        // locale and print "dim. 13 sept." -- every other string in this
        // drawer is English ("Clear all", "No notifications"), and the
        // format asked for was "Sun 13 Sep".
        Item {
            width: parent.width
            height: Math.max(clockBlock.height, dndButton.height)

            Rectangle {
                id: dndButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 12
                color: NotificationState.dnd ? DrawerTheme.accent
                     : dndHover.containsMouse ? DrawerTheme.cardHover
                     : DrawerTheme.card
                Behavior on color { ColorAnimation { duration: 140 } }

                // Same glass edge every other block in this bar now
                // carries -- see GlassCard.qml. The colour Behavior
                // above still runs underneath it: the layer simply
                // re-renders as the fill crossfades.
                //
                // Only while ON or hovered -- asked for: the glass is a
                // state cue, not decoration.

                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: NotificationState.dnd ? "\uF12A" : "\uF126"   // mgc notification_off / notification
                    color: NotificationState.dnd ? DrawerTheme.onInk : DrawerTheme.primary
                    font.family: Fonts.iconMingcute
                    font.pixelSize: 18
                }
                MouseArea {
                    id: dndHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationState.toggleDnd()
                }
            }

            Column {
                id: clockBlock
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: DrawerTheme.primary
                    font.family: Fonts.ui
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd MMM d")
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 13
                }
            }
        }

        // ---- mpris (autohide when nothing's playing, like swaync's own) ----
        //
        // No album art. It was a 36px thumbnail that spent most of its life
        // either empty (players that publish no trackArtUrl) or showing a
        // postage stamp too small to recognise, and it was the one element
        // in this drawer pulling a raster image into an otherwise entirely
        // drawn interface. Dropping it is what makes the row read as part
        // of the panel rather than as an embedded widget -- asked for
        // ("miser surtout sur le côté sleek de l'élément"). Note this is
        // the one thing from the reference screenshot's player NOT
        // reproduced here: only its elapsed/remaining readout was asked
        // about ("si c'est possible de recup la durée du media").
        //
        // radius 16, not the 12 this had: that is NotificationCard.qml's
        // own corner, and this row sits directly above a stack of them.
        //
        // Height follows the content rather than the flat 56 it was, so
        // the progress row below simply makes the card taller on the
        // players that publish a length and leaves it at its old size on
        // the ones that do not.
        Rectangle {
            width: parent.width
            height: mediaColumn.height + 24
            radius: 16
            color: DrawerTheme.card
            visible: root.mprisPlayer !== null


            Column {
                id: mediaColumn
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                // 6, not 16: the transport buttons carry ~7px of their own
                // padding inside their 30px hit target, so a real 16 here
                // would optically sit the glyphs a good 23px off the edge.
                // The progress row below re-adds the difference itself.
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

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
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: root.mprisPlayer ? (root.mprisPlayer.trackArtist || "") : ""
                            color: DrawerTheme.ink(0.6)
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }

                    // Transport. Replaces a MouseArea over the WHOLE card that
                    // toggled playback -- with real buttons on it, that made every
                    // stray click on the title pause the music.
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
                            // The only one that changes shape, and the reason the
                            // row needs no play/pause label anywhere else.
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

                // ---- elapsed / scrubber / total ----
                //
                // Two tiers, because the two halves of this readout do not
                // come from the same place. `position` is supported by
                // every player worth showing, so the elapsed time on the
                // left is shown whenever the card is. The bar and the
                // total need a LENGTH, which some media never publish at
                // all (YouTube mixes/live streams through Firefox are the
                // case at hand) -- those two hide on their own and leave
                // the elapsed count standing.
                //
                // Splitting it that way is the point: the row's presence no
                // longer depends on a field the player drops and re-adds,
                // so the card stops changing height under the pointer.
                // A scrubber with nothing to scrub along is still worse
                // than no scrubber, which is why the bar itself goes rather
                // than sitting at zero.
                //
                // Read-only: dragging it would be a seek, and `canSeek` is
                // a separate capability this is not wired to. It shows
                // where the track is, nothing more.
                Item {
                    id: progressRow
                    width: parent.width - 10
                    height: 14
                    visible: root.mprisPlayer !== null && root.mprisPlayer.positionSupported

                    readonly property bool hasLength: root.mprisTrackLength > 0
                    readonly property real progress: {
                        if (!progressRow.hasLength) return 0;
                        return Math.max(0, Math.min(1, root.mprisPosition / root.mprisTrackLength));
                    }

                    Text {
                        id: elapsedLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.formatDuration(root.mprisPosition)
                        color: DrawerTheme.ink(0.5)
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        // Same reason as the clock's own: this one ticks
                        // every second, and a proportional "1" would walk
                        // the track's left end back and forth as it counts.
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        id: totalLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: progressRow.hasLength
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: root.formatDuration(root.mprisTrackLength)
                        color: DrawerTheme.ink(0.5)
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        font.features: ({ "tnum": 1 })
                    }

                    Rectangle {
                        anchors.left: elapsedLabel.right
                        anchors.right: totalLabel.left
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        // `visible: false` does not zero an item's size, and
                        // this one is anchored to totalLabel, which is also
                        // hidden -- both still resolve, they just draw
                        // nothing. Nothing below reads this item's geometry,
                        // so there is no layout left to get wrong.
                        visible: progressRow.hasLength
                        height: 3
                        radius: height / 2
                        color: DrawerTheme.ink(0.14)

                        Rectangle {
                            width: parent.width * progressRow.progress
                            height: parent.height
                            radius: parent.radius
                            color: DrawerTheme.accent
                        }
                    }
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
            color: NotificationState.trackedNotifications.values.length > 0 ? DrawerTheme.accent : DrawerTheme.faint
            font.family: Fonts.ui
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: clearAllLabel
            anchors.margins: -6
            enabled: NotificationState.trackedNotifications.values.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationState.clearAll(root.clearUnits())
        }
    }

    // ---- notification history, grouped by app (N2) ----------------------
    //
    // One stack per app, newest app first, under TODAY / EARLIER labels
    // (a stack goes where its newest notification does). A collapsed stack
    // shows its newest card with the stack's size beside the app name and
    // up to two ghost edges under it; clicking the card unfolds the stack,
    // "Show less" folds it back. Single-notification apps are just a card.
    //
    // Rebuilt from NotificationServer's own list on every change, so a
    // dismissed notification simply drops out of the next build.
    // Arrival times come from NotificationState.receivedAt; anything
    // without one (none should be) counts as Earlier, oldest.
    property var expanded: ({})

    function toggleApp(app) {
        const e = Object.assign({}, root.expanded);
        if (e[app]) delete e[app]; else e[app] = true;
        root.expanded = e;
    }

    // Re-read when midnight passes while the drawer is open.
    readonly property real midnight: {
        const now = clock.date;
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
        const all = NotificationState.trackedNotifications.values;
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

    // What "Clear all" takes away together, in screen order: a folded
    // stack is one card on screen, so it goes as one; an unfolded one goes
    // card by card. See NotificationState.clearAll().
    function clearUnits() {
        const units = [];
        for (const sec of root.sections)
            for (const g of sec.groups) {
                if (g.notes.length > 1 && root.expanded[g.app]) g.notes.forEach((n) => units.push([n]));
                else units.push(g.notes.slice());
            }
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
        anchors.bottom: parent.bottom
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
                                color: DrawerTheme.secondary
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
                                color: DrawerTheme.primary
                                font.family: Fonts.ui
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }

                        Repeater {
                            model: section.modelData.groups
                            delegate: AppStack {
                                required property var modelData
                                required property int index
                                width: sectionBody.width
                                group: modelData
                                gap: index < section.modelData.groups.length - 1 ? 14 : 0
                            }
                        }
                    }
                }
            }
        }

        // Positioned, not `anchors.centerIn: parent`: a Flickable's child
        // lands in its contentItem, which is as tall as the (empty) list --
        // centring on it put the text up against "Clear all".
        Text {
            x: (list.width - width) / 2
            y: (list.height - height) / 2
            visible: NotificationState.trackedNotifications.values.length === 0
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "No notifications"
            color: DrawerTheme.ink(0.4)
            font.family: Fonts.ui
            font.pixelSize: 13
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
    // section title or an unfolded stack's header, whose cards already
    // slide out on their own.
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

    // One app's notifications. Collapsed: the newest card, the stack's size
    // on its meta line, and ghost edges for what is under it. Unfolded: a
    // small header (app, "Show less") over every card.
    component AppStack: Exit {
        id: stack
        property var group

        readonly property int size: stack.group ? stack.group.notes.length : 0
        readonly property bool open: stack.size > 1 && root.expanded[stack.group.app] === true
        readonly property int ghosts: stack.open ? 0 : Math.min(2, stack.size - 1)

        // Folded, it is one card on screen and leaves as one (Clear all
        // marks all of it at once, so does its x). Unfolded, the cards
        // leave one by one and the header goes with the last of them.
        leaving: stack.open ? stack.group.notes.every((n) => root.isLeaving(n))
                            : stack.group.notes.some((n) => root.isLeaving(n))
        slides: !stack.open
        bodyHeight: stack.open ? openColumn.height : (frontCard.height + stack.ghosts * 5)

        // ---- collapsed ----
        Rectangle {
            visible: stack.ghosts >= 2
            x: 20
            width: parent.width - 40
            y: frontCard.height - 14
            height: 24
            radius: 14
            color: "#0d0d10"
        }
        Rectangle {
            visible: stack.ghosts >= 1
            x: 10
            width: parent.width - 20
            y: frontCard.height - 14
            height: 19
            radius: 14
            color: "#121215"
        }
        NotificationCard {
            id: frontCard
            visible: !stack.open
            width: parent.width
            notification: stack.group.notes[0]
            showMeta: true
            count: stack.size
            timeText: root.timeText(stack.group.stamps[0])
            clickable: stack.size > 1
            onClicked: root.toggleApp(stack.group.app)
            // The x on a folded stack clears the whole stack -- it is the
            // only card of it you can see.
            onDismissRequested: NotificationState.leave(stack.group.notes)
            onActionRequested: (action) => NotificationState.invokeAction(notification, action)
        }

        // ---- unfolded ----
        Column {
            id: openColumn
            visible: stack.open
            width: parent.width

            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    y: (20 - height) / 2
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: stack.group.app
                    color: DrawerTheme.primary
                    font.family: Fonts.ui
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    id: lessLabel
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    y: (20 - height) / 2
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "Show less"
                    color: DrawerTheme.secondary
                    font.family: Fonts.ui
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: lessLabel
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleApp(stack.group.app)
                }
            }

            Repeater {
                model: stack.open ? stack.group.notes : []
                delegate: Exit {
                    id: entry
                    required property var modelData
                    required property int index
                    width: openColumn.width
                    gap: entry.index < stack.size - 1 ? 8 : 0
                    leaving: root.isLeaving(entry.modelData)
                    bodyHeight: card.height

                    NotificationCard {
                        id: card
                        width: parent.width
                        notification: entry.modelData
                        showMeta: true
                        // The header above already names the app.
                        showApp: false
                        timeText: root.timeText(stack.group.stamps[entry.index])
                        onDismissRequested: NotificationState.leave([notification])
                        onActionRequested: (action) => NotificationState.invokeAction(notification, action)
                    }
                }
            }
        }
    }
}
