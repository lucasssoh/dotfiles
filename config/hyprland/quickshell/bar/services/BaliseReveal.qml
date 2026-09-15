pragma Singleton
import QtQuick
import Quickshell

// Timing + trigger for Balise's entrance cascade -- every button and
// every sizeable block popping in with a quick zoom, one after the
// other, instead of the whole page landing at once.
//
// This REPLACED the horizontal page slide (two Loaders trading places
// with a 280ms Behavior on x, see BaliseHome.qml's pageArea): asked for
// explicitly, "c'est le slide justement que je veux remplacer par ça".
// The slide moved a finished page sideways; the cascade builds the new
// page in front of you, which reads as arriving somewhere rather than
// being pushed there.
//
// A singleton rather than properties on BaliseHome, because the three
// page kinds live in three files (BaliseHome, BaliseSectionList,
// BaliseDetailPage) plus the three row delegates, and all six have to
// agree on the same rhythm. RevealPop.qml is what reads this.
Singleton {
    id: root

    // Bumped to replay the cascade on surfaces that are NOT rebuilt.
    // Most navigation needs nothing from this: the page Loader swaps
    // sourceComponent, every element is constructed fresh, and
    // RevealPop's own Component.onCompleted fires. The one case that
    // needs an explicit kick is reopening the drawer while it is already
    // on the page it would reset to -- BaliseHome's `_swapTo` returns
    // early there, nothing is rebuilt, and without this the panel would
    // reopen fully drawn.
    property int gen: 0
    function replay() { root.gen++; }

    // Between two consecutive items. The whole point is "rapidement":
    // twelve items at 24ms means the last one starts 264ms in, so the
    // cascade is over well before it could feel like a queue.
    readonly property int stagger: 24
    // One item's own pop.
    readonly property int duration: 210
    // Ceiling on the accumulated delay. A section list can hold thirty
    // WiFi networks; without this the last row would start seven tenths
    // of a second late and the list would feel like it was loading.
    // Past the cap the tail simply pops together.
    readonly property int maxDelay: 360
    readonly property real fromScale: 0.9
}
