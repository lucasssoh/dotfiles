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
    // The stack's inset from the screen edge; shell.qml places it there,
    // and a card dismissed by a click slides out past the real edge.
    readonly property int edgeGap: 20
    // How long the others wait before closing a leaving card's gap.
    readonly property int closeDelay: 100

    // The height shell.qml centres the stack on: the cards plus the deck
    // of parked toasts under them. `growing` is set BEFORE `heldHeight`
    // changes, so the window's animation on y can tell an arrival (move
    // now, with the cards) from a departure (wait closeDelay, like them).
    readonly property int deckHeight: NotificationState.parkedCount > 0 ? 18 : 0
    readonly property real fullHeight: root.contentHeight + root.deckHeight
    property bool growing: true
    property real heldHeight: 0
    onFullHeightChanged: {
        root.growing = root.fullHeight >= root.heldHeight;
        root.heldHeight = root.fullHeight;
    }

    // The timers stop under the pointer (NotificationState.toastsHovered).
    HoverHandler {
        onHoveredChanged: NotificationState.toastsHovered = hovered
    }

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
        // Set just before a click dismisses it: the remove transition
        // reads it to pick the exit.
        property bool exitByClick: false
        Component.onCompleted: root.cards = root.cards.concat([toastDelegate])
        Component.onDestruction: root.cards = root.cards.filter((c) => c !== toastDelegate)

        onDismissRequested: {
            toastDelegate.exitByClick = true;
            NotificationState.dismissToast(toastDelegate.model.notifId);
        }
        onActionRequested: (action) => NotificationState.invokeAction(toastDelegate.notification, action)
    }

    // Arrive with a short step and a fade, rather than sliding the whole
    // card width in: a notification is secondary, it should settle, not
    // sweep across the screen.
    add: Transition {
        NumberAnimation { property: "x"; from: -28; to: 0; duration: 240; easing.type: Easing.OutQuint }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutQuint }
    }

    // Leave by how it was closed. Dismissed by a click: it slides off past
    // the screen's edge, a clear answer to the gesture. Timed out or closed
    // elsewhere: it fades where it is, nobody asked for it to go.
    remove: Transition {
        id: removeTrans
        readonly property bool byClick: removeTrans.ViewTransition.item ? removeTrans.ViewTransition.item.exitByClick : false
        NumberAnimation {
            property: "x"
            to: removeTrans.byClick ? -(root.cardWidth + root.edgeGap) : -12
            duration: 200
            easing.type: removeTrans.byClick ? Easing.InQuad : Easing.OutQuad
        }
        NumberAnimation { property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutQuad }
    }

    // A new card pushes the others down. The opacity and x lines finish
    // the arrival of a card displaced while still arriving (a burst comes
    // in 110ms apart), which would otherwise freeze half faded.
    addDisplaced: Transition {
        NumberAnimation { property: "y"; duration: 280; easing.type: Easing.OutQuint }
        NumberAnimation { property: "opacity"; to: 1; duration: 240 }
        NumberAnimation { property: "x"; to: 0; duration: 240; easing.type: Easing.OutQuint }
    }
    // ...and a leaving one lets the others close the gap once it has
    // mostly gone, so the two moves read one after the other.
    removeDisplaced: Transition {
        SequentialAnimation {
            PauseAnimation { duration: root.closeDelay }
            NumberAnimation { property: "y"; duration: 260; easing.type: Easing.OutQuint }
        }
    }
}
