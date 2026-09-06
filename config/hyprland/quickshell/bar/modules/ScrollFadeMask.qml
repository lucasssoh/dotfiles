import QtQuick

// Alpha mask for a scrolling list's soft top/bottom edges -- asked for:
// "puisqu'on a scroll, il ne faut pas couper les elements brutement mais
// faire un fade lorsque la liste d'element empilé en trop grande".
//
// Used as the `maskSource` of an OpacityMask layer effect on the list
// itself; the consumer side is three lines, see NotificationCenter.qml:
//
//     ListView { id: list
//         layer.enabled: true
//         layer.effect: OpacityMask { maskSource: listMask }
//     }
//     ScrollFadeMask { id: listMask; view: list; width: list.width; height: list.height }
//
// Only the SIZE has to match the masked item -- the mask is consumed as a
// texture, so where this sits in the scene is irrelevant (it is never
// drawn there). That is what lets the two Balise pages, whose Flickable
// IS the root of a Component and so has no sibling slot to put this in,
// simply declare it as one of the Flickable's own children.
//
// A real alpha mask rather than the usual cheap trick of laying opaque
// scrim Rectangles over each end: these lists live on TOOLS' drawer pane,
// which is translucent (theme/Surfaces.qml), so there is no solid colour
// a scrim could fade to -- it would read as two grey bands sitting on top
// of the content instead of the content dissolving.
//
// `visible: false` + `layer.enabled: true` is the standard mask idiom:
// the item is never composited into the scene itself, but the layer still
// renders it to the texture the effect samples.
Rectangle {
    id: root

    // The Flickable/ListView this masks -- read only for its scroll
    // position, so each end's fade appears only when there is actually
    // something in that direction to scroll to. A list that fits shows no
    // fade at all, and the top edge stays crisp until you scroll off it.
    property Flickable view: null
    property int fadeSize: 36

    // Guarded against a zero height (before first layout) and clamped
    // below 0.5 so the two stops can never cross over each other and
    // invert the gradient on a very short list.
    readonly property real ratio: root.height > 0
        ? Math.min(0.45, root.fadeSize / root.height)
        : 0
    readonly property bool fadeTop: root.view !== null && !root.view.atYBeginning
    readonly property bool fadeBottom: root.view !== null && !root.view.atYEnd

    visible: false
    layer.enabled: true

    // Only the ALPHA of these stops matters (OpacityMask multiplies the
    // source's alpha by the mask's); black is just a conventional opaque
    // value. Animated so the edge does not snap from crisp to faded the
    // instant a list becomes scrollable.
    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: root.fadeTop ? "#00000000" : "#ff000000"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        GradientStop { position: root.ratio; color: "#ff000000" }
        GradientStop { position: 1.0 - root.ratio; color: "#ff000000" }
        GradientStop {
            position: 1.0
            color: root.fadeBottom ? "#00000000" : "#ff000000"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
}
