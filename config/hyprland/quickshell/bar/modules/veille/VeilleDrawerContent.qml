import QtQuick
import ".."
import "../../theme"

// Veille's pulse -- the "Classique" layout (2026-09-29): the hour, large
// and thin, and the message under it across the full width, both in
// DrawerTheme's cream. Nothing else. Both matter alike ("les deux sont
// tout aussi important"), which is what several heavier layouts tried in
// between got wrong: a white pill around the hour took every look, an
// outlined card around both and a bar splitting the night along
// veille.json's thresholds only added things to read past ("simple, et
// straightforward"). This is the original Veille layout, moved to MiSans
// and a fixed size instead of a clock scaled to the island's width.
//
// Clock + message content for Veille's drawer -- now living inside the
// bar's own central island instead of a separate floating panel (asked
// for explicitly: "combiner veille dans l'island central"). Pure
// rendering, no logic of its own -- `veille` is the shared Veille.qml
// instance (one Scope for the whole shell, not per-screen -- see its
// own header), threaded in the same way ActiveWindow.qml takes a
// `monitor` property.
//
// A generic Item as far as its own PARENT (DrawerIsland.qml) is
// concerned: sized by plain `width` (an ordinary Item property, set
// externally) rather than a bespoke "availableWidth" property. `height`
// is driven and ANIMATED entirely by DrawerIsland's own open/close
// sequence (not a Behavior declared here) -- that sequence has to
// strictly order this against the island's own width animation
// ("l'animation en deux temps, l'elargissement d'abord et ensuite
// l'allongement"), which a Behavior on a property of a totally separate
// object can't do (Behaviors run independently of each other). Folds
// its own padding (hPad/topGap/bottomGap below) into `implicitHeight`,
// which DrawerIsland reads to know how tall to animate this open to.
Item {
    id: root

    property var veille: null

    // DrawerIsland's drawer-entry contract (see its header): the caller
    // binds `drawerOpen`, DrawerIsland drives width/height/opacity off
    // it, and this Behavior is what actually animates the open/close --
    // each entry owns its own height animation now that the drawer is a
    // stack rather than one slot, since entries come and go
    // independently of each other. Same curve and duration the single
    // shared sequence used to run.
    property bool drawerOpen: false
    // Kept equal to centerIsland's own `revealDuration` (its default,
    // 320 -- centerIsland overrides none of DrawerIsland's timings).
    Behavior on height {
        NumberAnimation { duration: 320; easing.type: Easing.InOutCubic }
    }

    readonly property int hPad: 24
    readonly property int topGap: 10
    readonly property int bottomGap: 20

    readonly property bool showSeconds: root.veille ? root.veille.config.showSeconds : true
    // The width this card asks the island for (DrawerIsland's
    // `entryWidthFloor`): the row alone is ~520 px with nothing playing,
    // which squeezed the message into five lines. Also
    // the most it takes when the keybinds sheet widens the island
    // further -- the card then stays this wide, centred.
    readonly property int drawerWidth: 840
    readonly property real textWidth: Math.max(0, Math.min(root.width, root.drawerWidth) - root.hPad * 2)
    readonly property real contentInset: root.hPad + Math.max(0, (root.width - root.textWidth - root.hPad * 2) / 2)

    // + the handle's own band: it sits ABOVE topGap, so the drawer grows
    // by exactly what the handle takes.
    implicitHeight: handle.implicitHeight + root.topGap + content.implicitHeight + root.bottomGap

    // ---- force-close -------------------------------------------------
    // The same grabber the tools drawers use (DrawerHandle), instantiated
    // here in the content rather than in DrawerIsland -- for the reason
    // that file's own header gives: the island is shared with TOOLS, and
    // centerIsland's feel is meant to stay exactly as it is.
    //
    // Why Veille needs one at all, when it already closes itself after
    // `pulse.durationSeconds`: those 30 seconds are 30 seconds of the
    // screen's middle being taken over, and there are evenings where that
    // is simply not affordable. This dismisses the pulse on screen; the
    // next round hour is unaffected (see Veille.qml's `dismiss`).
    //
    // NARROWER than the drawer, unlike the tools handles which span
    // theirs. centerIsland's drawer deliberately sits OUTSIDE the bar's
    // input mask ("ne bloque jamais les clics", see shell.qml) so
    // shell.qml has to punch a hole in that mask for this band -- and the
    // hole has to be the handle, not the full width of a clock nobody
    // ever clicks.
    DrawerHandle {
        id: handle
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: 120
        tint: DrawerTheme.islandAccent
        onCloseRequested: if (root.veille) root.veille.dismiss()
    }

    // The hole shell.qml opens in that mask, in THIS item's coordinates.
    // Exported rather than recomputed over there so the handle's size and
    // placement stay one fact, stated where the handle actually is.
    //
    // Four ints rather than the one `rect` property this obviously wants
    // to be: a Quickshell Region reading its x/width through a rect-typed
    // property does not track it -- the mask keeps the rect's first,
    // pre-layout value forever while every number on screen looks right.
    // See the Region in shell.qml for how that was pinned down.
    readonly property int closeHitX: handle.x
    readonly property int closeHitY: handle.y
    readonly property int closeHitWidth: handle.width
    readonly property int closeHitHeight: handle.height

    // ---- the pulse -----------------------------------------------------
    Column {
        id: content
        x: root.contentInset
        anchors.top: handle.bottom
        anchors.topMargin: root.topGap
        width: root.textWidth
        spacing: 12

        Row {
            spacing: 7
            Text {
                id: hourText
                text: root.veille ? root.veille.hourString : ""
                color: DrawerTheme.cream
                font.family: Fonts.ui
                font.pixelSize: 104
                font.weight: Font.ExtraLight
                font.letterSpacing: -2
                font.features: { "tnum": 1 }
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
            }
            Text {
                visible: root.showSeconds
                anchors.baseline: hourText.baseline
                text: root.veille ? root.veille.secondsString : ""
                color: DrawerTheme.creamInk(0.45)
                font.family: Fonts.ui
                font.pixelSize: 36
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        // The message; before the first one of the night (none until
        // "late"), the date holds its place.
        Text {
            width: parent.width
            readonly property bool hasMessage: root.veille !== null && root.veille.messageString !== ""
            text: hasMessage ? root.veille.messageString : (root.veille ? root.veille.dateString : "")
            color: hasMessage ? DrawerTheme.cream : DrawerTheme.cream2
            wrapMode: Text.WordWrap
            lineHeight: 1.1
            font.family: Fonts.ui
            font.pixelSize: 28
            font.weight: Font.Medium
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }
    }
}
