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
    // The history pane's own height, and the one number in this drawer
    // that is deliberately a constant: every rework of the top of this
    // file so far ("keeps the history list the same size it always was")
    // has been about NOT letting the list pay for whatever was added or
    // removed above it. 404 is what it measured back when the drawer was
    // a flat 544 of content -- 544 minus the 20 top margin, the old
    // header+DND stack (24 + 16 + 44), the list's own 16 top margin and
    // its 20 bottom one.
    readonly property int historyHeight: 404
    // Summed from the real measured pieces rather than a magic total, so
    // adding or dropping a row above the list moves the DRAWER's height
    // and leaves `historyHeight` alone. The mpris card is the one piece
    // that comes and goes at runtime; when it does, the drawer grows or
    // shrinks by exactly its band (through the `Behavior on height`
    // below) instead of squeezing the history to absorb it.
    implicitHeight: handle.implicitHeight + 20 + topSection.height
                  + 16 + listHeader.height + 8 + root.historyHeight + 20
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
                color: NotificationState.dnd ? Surfaces.accent
                     : dndHover.containsMouse ? Surfaces.cardHover
                     : Surfaces.card
                Behavior on color { ColorAnimation { duration: 140 } }

                // Same glass edge every other block in this bar now
                // carries -- see GlassCard.qml. The colour Behavior
                // above still runs underneath it: the layer simply
                // re-renders as the fill crossfades.
                //
                // Only while ON or hovered -- asked for: the glass is a
                // state cue, not decoration.
                layer.enabled: NotificationState.dnd || dndHover.containsMouse
                layer.effect: GlassCard { radius: 12 }

                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: NotificationState.dnd ? "\uE5EE" : "\uE0CE"   // bell-z / bell
                    color: NotificationState.dnd ? "#0c0c0e" : "#f2f2f7"
                    font.family: NotificationState.dnd ? Fonts.iconPhosphorFill
                                                       : Fonts.iconPhosphorBold
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
                    color: "#f2f2f7"
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
                    text: clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd d MMM")
                    color: "#8e8e93"
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
            color: Surfaces.card
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
                            color: "#f2f2f7"
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
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.family: Fonts.ui
                            font.pixelSize: 12
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
                            glyph: "\uE5A4"                                  // ph-skip-back
                            enabled: root.mprisPlayer ? root.mprisPlayer.canGoPrevious : false
                            onTriggered: root.mprisPlayer.previous()
                        }
                        TransportButton {
                            // The only one that changes shape, and the reason the
                            // row needs no play/pause label anywhere else.
                            glyph: (root.mprisPlayer && root.mprisPlayer.isPlaying) ? "\uE39E" : "\uE3D0"   // ph-pause / ph-play
                            glyphSize: 17
                            enabled: root.mprisPlayer ? root.mprisPlayer.canTogglePlaying : false
                            onTriggered: root.mprisPlayer.togglePlaying()
                        }
                        TransportButton {
                            glyph: "\uE5A6"                                  // ph-skip-forward
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
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Fonts.ui
                        font.pixelSize: 11
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
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Fonts.ui
                        font.pixelSize: 11
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
                        color: Qt.rgba(1, 1, 1, 0.14)

                        Rectangle {
                            width: parent.width * progressRow.progress
                            height: parent.height
                            radius: parent.radius
                            color: Surfaces.accent
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
            color: Surfaces.cardHover
            opacity: (tb.enabled && hover.containsMouse) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 110 } }

            // GlassChip, not GlassCard: this disc is 30px and a 7px band
            // would be most of its radius. It fades in and out with the
            // disc it edges (the layer follows `opacity`, and drops out
            // entirely at 0), so the transport buttons still show
            // nothing at rest -- the glass appears with the hover, it
            // does not put a permanent ring on every button.
            layer.enabled: opacity > 0.01
            layer.effect: GlassChip { radius: 15 }
        }

        Text {
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: tb.glyph
            color: !tb.enabled ? Qt.rgba(1, 1, 1, 0.22)
                 : hover.containsMouse ? Surfaces.accent : "#f2f2f7"
            Behavior on color { ColorAnimation { duration: 110 } }
            font.family: Fonts.iconPhosphorFill
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
            color: NotificationState.trackedNotifications.values.length > 0 ? "#a8b4c4" : "#48484a"
            font.family: Fonts.ui
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: clearAllLabel
            anchors.margins: -6
            enabled: NotificationState.trackedNotifications.values.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationState.clearAll()
        }
    }

    // ---- notification history -- fills the rest of the card below listHeader ----
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: listHeader.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 8
        anchors.bottomMargin: 20
        clip: true
        spacing: 8
        model: NotificationState.trackedNotifications
        delegate: NotificationCard {
            required property var modelData
            width: list.width
            notification: modelData
            onDismissRequested: NotificationState.dismissForever(notification)
            onActionRequested: (action) => NotificationState.invokeAction(notification, action)
        }

        // Leaves to the RIGHT -- asked for, and the opposite of the
        // toasts' own exit ("pour popup il repart vers la gauche, pour les
        // notifcenter, il repart vers la droite"), which is the direction
        // each one arrived from in the first place: toasts slide in from
        // the screen's left edge, history cards belong to a pane on the
        // right of the bar.
        //
        // A ListView, unlike the Column the toasts used to be, keeps a
        // removed delegate alive for the duration of this transition
        // instead of destroying it with its model row -- that is the whole
        // reason an exit animation is possible here at all. `InCubic`
        // (accelerating away) rather than the OutCubic used on arrivals:
        // the card should look like it is being flicked off, not easing to
        // a stop somewhere off-pane.
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; to: list.width; duration: 180; easing.type: Easing.InCubic }
                NumberAnimation { property: "opacity"; to: 0; duration: 180 }
            }
        }
        // The cards below a dismissed one closing the gap. Kept slightly
        // shorter than the exit itself so the list has already settled by
        // the time the next one in a Clear-all cascade starts leaving.
        removeDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic }
        }

        // Soft edges instead of a hard cut wherever the history is taller
        // than the pane -- see ScrollFadeMask.qml.
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: listMask }

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "No notifications"
            color: Qt.rgba(1, 1, 1, 0.4)
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
}
