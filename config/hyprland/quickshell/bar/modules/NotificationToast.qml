import QtQuick
import "../services"

// Transient notification stack -- one PanelWindow instance per screen
// (shell.qml's Variants), mapped while toasts exist and briefly after the
// last row leaves so its exit transition can finish. NotificationState.qml
// owns which rows are in `toasts` and when they expire; this file only
// renders that model -- dismissing a card here just calls dismissToast()
// (hides the popup, keeps the notification in the center's history), never
// dismissForever().
//
// A ListView, where this was a Column + Repeater over a JS array. Two
// reasons, both of them about the animations below:
//   - positioners only expose add/move/populate transitions, with no
//     `remove` -- a Column destroys a delegate the instant its row goes,
//     so an exit animation is simply not expressible there;
//   - a JS array is not a diffable model, so every arrival and every
//     expiry reset the whole view and re-ran the arrival slide on every
//     card that happened to still be on screen.
// See NotificationState.qml's `toastModel` for the model half of that.
//
// The model is newest-first (rows are inserted at index 0), so new toasts
// appear at the top of the vertically centered stack.
ListView {
    id: root

    // NotificationCard's own fixed width, restated rather than read off
    // `root.width`: the add transition needs a slide distance at the
    // moment the FIRST card is created, when the view has not laid out yet
    // and its width is still 0 -- that card would then "slide" from 0 to 0,
    // i.e. just appear.
    readonly property int cardWidth: 340

    // The parent window is a fixed size (see shell.qml) and this fills it,
    // so the stack's own extent is `contentHeight` -- which is what that
    // window masks its input region down to.
    width: root.cardWidth
    interactive: false          // a popup stack, not something to flick
    spacing: 8
    verticalLayoutDirection: ListView.TopToBottom
    model: NotificationState.toasts

    // The cards on screen, leaving ones included until their exit is over:
    // shell.qml asks Hyprland to blur behind each of them, and only them.
    property var cards: []

    delegate: NotificationCard {
        id: toastDelegate
        // `model` rather than named role properties: the roles are dynamic
        // (see NotificationState.qml), and one of them would collide with
        // NotificationCard's own `notification` property anyway.
        required property var model

        width: root.cardWidth
        notification: toastDelegate.model.notification
        // Pure black, no edge -- see NotificationCard's `toast`.
        toast: true
        Component.onCompleted: root.cards = root.cards.concat([toastDelegate])
        Component.onDestruction: root.cards = root.cards.filter((c) => c !== toastDelegate)

        onDismissRequested: NotificationState.dismissToast(toastDelegate.model.notifId)
        onActionRequested: (action) => NotificationState.invokeAction(toastDelegate.notification, action)
    }

    // Enter by sliding in from the left -- asked for: the popups "doivent
    // plutot glisser de la gauche vers l'ecran". Nothing clips this by
    // hand: the parent PanelWindow is exactly one card wide, so a card
    // parked at -cardWidth is entirely outside the Wayland surface and
    // simply is not drawn, then wipes into view as x climbs back to 0.
    //
    // The surface is inset from the left screen edge (shell.qml pins it
    // at left: 20), so the card slides in without crossing the edge.
    add: Transition {
        NumberAnimation {
            property: "x"
            from: -root.cardWidth
            to: 0
            duration: 260
            easing.type: Easing.OutCubic
        }
    }

    // ...and leaves back the way it came in, to the LEFT -- asked for
    // ("pour popup il repart vers la gauche"), whether it was dismissed by
    // hand or simply timed out. Faster than the entrance (180 vs 260) and
    // `InCubic` rather than OutCubic: an arrival should settle, a
    // dismissal should get out of the way.
    remove: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "x"
                to: -root.cardWidth
                duration: 180
                easing.type: Easing.InCubic
            }
            NumberAnimation { property: "opacity"; to: 0; duration: 180 }
        }
    }

    // Keep the stack's motion smooth in either vertical direction: the
    // new card pushes existing ones inward, and its removal pulls them back.
    addDisplaced: Transition {
        NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic }
    }
    removeDisplaced: Transition {
        NumberAnimation { properties: "y"; duration: 180; easing.type: Easing.OutCubic }
    }
}
