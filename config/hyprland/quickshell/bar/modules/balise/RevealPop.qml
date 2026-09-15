import QtQuick
import "../../services"

// One element's entrance: hidden -> its turn in the queue -> pop.
// Attach one per animated item, giving it `item` and a stagger `index`.
// See services/BaliseReveal.qml for the shared timing and for why this
// replaced the page slide.
//
// Deliberately a SequentialAnimation and not a Behavior: the first thing
// it has to do is SNAP the item back to hidden. On a replay the element
// is still sitting at opacity 1 from last time, and without those two
// PropertyActions it would stay visible right through its own stagger
// delay and then blink out an instant before popping in.
//
// It animates `scale`, never width/height: scale is a render transform,
// so it never re-enters layout. A Row of two tiles mid-cascade keeps its
// geometry exactly; animating size instead would make the whole column
// jitter on every open.
SequentialAnimation {
    id: anim

    required property Item item
    // Position in the queue. Explicit rather than derived from the
    // item's `y`, because a tile lives inside a Row and its own y is 0 --
    // only the Row's means anything, and walking up the parent chain
    // would have to wait for layout instead of being a binding. Explicit
    // indices also let two side-by-side tiles pop one after the other,
    // which no purely vertical rule can express.
    property int index: 0
    // 1.0 opts out of the zoom while keeping the slot in the cascade --
    // what the small caps labels use. They are NativeRendering text, and
    // scaling native-rendered glyphs makes them crawl for the length of
    // the animation, so they fade and everything else zooms.
    property real fromScale: BaliseReveal.fromScale

    property int gen: BaliseReveal.gen
    onGenChanged: anim.restart()
    Component.onCompleted: anim.restart()

    PropertyAction { target: anim.item; property: "opacity"; value: 0 }
    PropertyAction { target: anim.item; property: "scale"; value: anim.fromScale }
    PauseAnimation {
        duration: Math.min(BaliseReveal.maxDelay, anim.index * BaliseReveal.stagger)
    }
    ParallelAnimation {
        NumberAnimation {
            target: anim.item; property: "opacity"; to: 1
            duration: BaliseReveal.duration; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: anim.item; property: "scale"; to: 1
            duration: BaliseReveal.duration
            // A little overshoot so it reads as a pop rather than a fade
            // that happens to change size. 1.4 is deliberately mild --
            // at the default 4-ish these cards visibly wobble.
            easing.type: Easing.OutBack; easing.overshoot: 1.4
        }
    }
}
