import QtQuick
import "../../theme"

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
    Behavior on height {
        NumberAnimation { duration: 320; easing.type: Easing.InOutCubic }
    }

    readonly property int hPad: 20
    readonly property int topGap: 10
    readonly property int bottomGap: 16

    readonly property bool showSeconds: root.veille ? root.veille.config.showSeconds : true
    readonly property bool showDate: root.veille ? root.veille.config.showDate : false
    readonly property real textWidth: Math.max(0, root.width - root.hPad * 2)

    implicitHeight: root.topGap + content.implicitHeight + root.bottomGap

    // The dévoilé (reveal) that used to be declared here is now owned by
    // DrawerIsland instead (it drives `opacity` off this Item's own
    // height progress, see its Binding) -- one implementation, applied
    // to whatever currently holds the drawer, so the keybinds cheatsheet
    // reveals identically instead of each content file carrying its own
    // near-copy of the same formula.

    // Same width -> font.pixelSize solve the old standalone overlay used
    // to do against a fraction of the SCREEN's width instead of this
    // island's own (see git history on this file's predecessor,
    // Veille.qml, for the full rationale). TextMetrics measures a fixed
    // reference string ("00:00:00"/"00:00", not the live-changing text)
    // at 100px so the ratio itself never jitters as digits change.
    TextMetrics {
        id: clockMetrics
        font.family: Fonts.clock
        font.pixelSize: 100
        text: root.showSeconds ? "00:00:00" : "00:00"
    }
    readonly property real clockWidthPerPixelSize: clockMetrics.width / 100
    readonly property int clockPixelSize:
        Math.round(root.textWidth / Math.max(0.001, root.clockWidthPerPixelSize))

    readonly property int dateTextSize: Math.round(root.clockPixelSize * 0.32)
    readonly property int messageTextSize: Math.round(root.clockPixelSize * 0.3)
    readonly property int columnSpacing: Math.round(root.clockPixelSize * 0.08)

    Column {
        id: content
        anchors.left: parent.left
        anchors.leftMargin: root.hPad
        anchors.top: parent.top
        anchors.topMargin: root.topGap
        spacing: root.columnSpacing

        Text {
            id: clockText
            anchors.left: parent.left
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            font.family: Fonts.clock
            font.pixelSize: root.clockPixelSize
            width: root.textWidth
            horizontalAlignment: Text.AlignLeft
            // Slightly warm off-white, not pure white -- carried over
            // from the standalone overlay ("pas de blanc parfait mais
            // legerement creme").
            color: "#f2ecd9"
            text: root.veille ? root.veille.clockString : ""
            // No Behavior on font.pixelSize any more -- DrawerIsland
            // reads `implicitHeight` (which this feeds into) to set its
            // OWN height animation's target the instant its width
            // animation finishes; if this were still easing afterward,
            // implicitHeight would keep growing for another 600ms past
            // that point, taller than the height DrawerIsland had
            // already locked in and started animating toward -- the
            // text visibly ran past the drawer's own (too-short)
            // bottom edge, clipped there since this whole Item stays
            // `clip: true` while showing.
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            font.family: Fonts.ui
            font.pixelSize: root.dateTextSize
            color: "#8e8e93"
            text: root.veille ? root.veille.dateString : ""
        }

        Text {
            anchors.left: parent.left
            width: root.textWidth
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            // Lighter weight than the clock's own Fonts.clock (Medium),
            // asked for ("un font plus light pour le quote"), left-
            // aligned to match the clock above it exactly.
            font.family: Fonts.clockLight
            font.pixelSize: root.messageTextSize
            color: "#c9c4b3"
            text: root.veille ? root.veille.messageString : ""
            opacity: text !== "" ? 0.9 : 0

            Behavior on opacity {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
            }
        }
    }
}
