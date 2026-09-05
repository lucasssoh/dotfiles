import QtQuick
import "../services"

// Transient corner popup stack -- one PanelWindow instance per screen
// (shell.qml's Variants), always mapped so NotificationCard's fade can
// actually animate rather than pop (same convention Osd.qml/
// BatteryAlert.qml already use). NotificationState.qml owns which
// entries are in `toastQueue` and when they expire; this file only
// renders that list -- dismissing a card here just calls dismissToast()
// (hides the popup, keeps the notification in the center's history),
// never dismissForever().
//
// Newest-on-top: entries arrive appended at the END of toastQueue, so
// this Column is built from a REVERSED copy rather than reordering
// toastQueue itself (that array's order is also what NotificationState
// uses for its maxToasts cap -- oldest-first there, unrelated to how
// this renders it).
Column {
    id: root

    spacing: 8
    readonly property var entries: NotificationState.toastQueue.slice().reverse()

    Repeater {
        model: root.entries
        delegate: NotificationCard {
            id: toastDelegate
            required property var modelData
            notification: toastDelegate.modelData.notification

            onDismissRequested: NotificationState.dismissToast(toastDelegate.modelData.id)
            onActionRequested: (action) => NotificationState.invokeAction(toastDelegate.notification, action)

            // No enter/exit animation yet -- cards just appear/disappear.
            // Osd.qml/BatteryAlert.qml fade because they're single fixed
            // Rectangles bound to one visibility bool; animating entries
            // moving in/out of a Repeater-backed Column would need
            // Column's own add/remove Transitions, deferred as a v1
            // simplification (no precedent for that pattern in this bar
            // yet to match against).
        }
    }
}
