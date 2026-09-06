import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import "../theme"
import "../services"

// swaync's control-center replacement -- header/clear-all, a DND toggle,
// a trimmed mpris section, the same 2 quick-action buttons swaync's own
// buttons-grid had, then the notification history itself
// (NotificationState.trackedNotifications -- see that file's header for
// why this list IS the daemon's own history, not a separate buffer).
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
    implicitHeight: 600
    Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }

    // Quick-action scripts -- swaync/config.json's buttons-grid, ported
    // 1:1 (same two scripts, same "shell out via bash -c" shape
    // BatteryAlertState.lowPowerProc already uses for its own button).
    Process { id: nightModeProc; command: ["bash", "-c", "$HOME/.config/hypr/scripts/toggle-night-mode.sh"] }
    Process { id: screenshotProc; command: ["bash", "-c", "$HOME/.config/waybar/scripts/screenshot-region.sh"] }

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

        // ---- quick actions (swaync's buttons-grid, ported 1:1) ----
        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: (parent.width - 8) / 2
                height: 40
                radius: 12
                color: nightArea.containsMouse ? "#14161d" : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "Night mode"
                    color: "#f2f2f7"
                    font.family: Fonts.ui
                    font.pixelSize: 13
                }
                MouseArea {
                    id: nightArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: nightModeProc.running = true
                }
            }
            Rectangle {
                width: (parent.width - 8) / 2
                height: 40
                radius: 12
                color: shotArea.containsMouse ? "#14161d" : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "Screenshot"
                    color: "#f2f2f7"
                    font.family: Fonts.ui
                    font.pixelSize: 13
                }
                MouseArea {
                    id: shotArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: screenshotProc.running = true
                }
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
}
