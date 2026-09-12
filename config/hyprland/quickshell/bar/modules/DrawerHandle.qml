import QtQuick
import "../theme"

// The grabber bar at the top of a drawer -- a short thick rounded line,
// clicked to close.
//
// Why it exists: toolsIsland's drawers (Balise, the notification center)
// could always be closed, but only from OUTSIDE themselves -- by clicking
// the same bar button again, or by one of shell.qml's dismiss events
// (openwindow/workspace/..., see keybindsDismissEvents). Nothing inside
// the open panel said so. This is that affordance, in the one shape that
// reads as "put this away" without being a button competing with the
// panel's own controls.
//
// NOT part of DrawerIsland, deliberately. That component is shared with
// centerIsland (Veille, the keybinds sheet), whose feel is meant to stay
// exactly as it is -- putting a handle in there, even opt-in, makes every
// future change to it a change to both islands. A drawer that wants one
// instantiates it at the top of its own content instead, which also lets
// it call its own close function directly rather than routing a signal
// back through the island.
//
// Sits at the TOP, under the pill, rather than on the drawer's free
// bottom edge (asked for). Worth knowing it inverts the usual phone-sheet
// convention -- those rise from the bottom and put the grabber on the
// edge you pull -- because these drop DOWN from the bar, so the top is
// the hinge, not the free edge.
Item {
    id: root

    // The drawer's own close call is wired to this by the caller; this
    // component knows nothing about Balise or notifications.
    signal closeRequested()

    // Taller than the line it draws: the hit target is the whole 18px
    // band, so the handle is grabbable without having to land on 4px.
    implicitHeight: 18

    Rectangle {
        anchors.centerIn: parent
        // "Épais" and "long" both asked for: 4px on a ~340px-wide panel
        // is roughly twice a hairline separator, and 48 reads as a
        // deliberate handle rather than as a stray rule. Fully rounded
        // (radius = half the height) so it stays a lozenge, not a bar
        // with corners.
        width: 48
        height: 4
        radius: height / 2
        color: Surfaces.accent
        // Quiet at rest, clearly live on hover -- it is an affordance,
        // not a piece of the panel's information.
        opacity: hit.containsMouse ? 0.9 : 0.4
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.closeRequested()
    }
}
