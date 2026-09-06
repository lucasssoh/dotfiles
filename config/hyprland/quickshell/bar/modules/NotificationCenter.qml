import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import "../theme"
import "../services"

// swaync's control-center replacement -- header/clear-all, a DND toggle,
// a trimmed mpris section, then the notification history itself
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
    // 600 - 56: the quick-actions row (40) plus the Column spacing above
    // it (16) that went with it. Shrinking the drawer by exactly what was
    // removed keeps the history list the same size it always was, rather
    // than paying out the freed space as extra empty pane under "No
    // notifications".
    implicitHeight: 544
    // Kept equal to DrawerIsland's `revealDuration` -- see the comment
    // there; the island waits out exactly this long before fading content in.
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

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

    Column {
        id: topSection
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        spacing: 16

        // ---- header ----
        Item {
            width: parent.width
            height: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "Notifications"
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 17
                font.bold: true
            }
            Text {
                id: clearAllLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
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

        // ---- DND toggle ----
        Rectangle {
            width: parent.width
            height: 44
            radius: 12
            color: "#14161d"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "Do not disturb"
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 14
            }

            // Track + thumb switch -- swaync's own dnd widget was a plain
            // checkbox, built here from Rectangles like every other
            // control in this bar (BatteryAlert's pills, GlassRim, etc.).
            Rectangle {
                id: dndTrack
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 22
                radius: 11
                color: NotificationState.dnd ? "#a8b4c4" : Qt.rgba(1, 1, 1, 0.18)
                Behavior on color { ColorAnimation { duration: 120 } }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: "#0c0c0e"
                    anchors.verticalCenter: parent.verticalCenter
                    x: NotificationState.dnd ? parent.width - width - 2 : 2
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationState.toggleDnd()
            }
        }

        // ---- mpris (autohide when nothing's playing, like swaync's own) ----
        Rectangle {
            width: parent.width
            height: 56
            radius: 12
            color: "#14161d"
            visible: root.mprisPlayer !== null

            Item {
                id: iconTile
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "#1a1d2a"
                }
                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    fillMode: Image.PreserveAspectCrop
                    source: root.mprisPlayer ? (root.mprisPlayer.trackArtUrl || "") : ""
                }
            }
            Column {
                anchors.left: iconTile.right
                anchors.leftMargin: 10
                anchors.right: parent.right
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
            MouseArea {
                anchors.fill: parent
                onClicked: if (root.mprisPlayer) root.mprisPlayer.togglePlaying()
            }
        }
    }

    // ---- notification history -- fills the rest of the card below topSection ----
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topSection.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 16
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
