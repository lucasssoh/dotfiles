import QtQuick
import Quickshell.Hyprland
import "../theme"
import "../services"

// A bare "hdr" word at the head of the TOOLS row, present ONLY while HDR
// is actually on -- asked for, after the interactive badge that used to
// live in this slot moved into Balise's SYSTEM block.
//
// So this is an INDICATOR, not a control: no MouseArea, no badge, no
// GlassChip. That is the whole point of the split -- Balise owns the
// switch, the row just reports. Clicking it does nothing on purpose;
// there is one place to change HDR now.
//
// Presence is the signal, which is why there is no "off" look to design:
// the old badge had to render in both states and spent three passes
// trying to say "off" legibly (a diagonal strike, then a grey fill, both
// dropped -- see Hdr.qml). A word that is simply absent when HDR is off
// says it without a look at all.
Item {
    id: root

    // The screen this bar instance is on, same contract the badge had:
    // each bar reports ITS OWN monitor, not whichever is focused.
    property var monitor: Hyprland.focusedMonitor

    // Trailing gap folded INTO this item rather than left to a separate
    // spacer in the row. A Row excludes an invisible child from layout,
    // but it would NOT have excluded a sibling `Item { width: groupGap }`
    // sitting next to it -- that would have left 4px of dead air at the
    // head of the row every time HDR was off, which is most of the time.
    // Carrying its own gap means the whole thing leaves together.
    property real trailingPad: 6

    readonly property bool active: HdrState.activeOn(root.monitor)

    // Excluded from the Row's layout entirely when false (positioners
    // skip invisible children), so nothing else needs to know this
    // module exists.
    visible: root.active

    implicitWidth: label.implicitWidth + root.trailingPad
    implicitHeight: 24

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: "hdr"
        // Plain white, the bar's own #f2f2f7, NOT the cyan the badge
        // turned when active -- asked for, and it follows from what this
        // module is: the badge needed a colour because it was on screen
        // in both states and had to say WHICH one, while this is only
        // ever on screen in one. Presence is the whole signal, so an
        // accent on top of it encodes the same fact twice, and the second
        // encoding is the one that reads as an alert.
        //
        // That also puts it in the row's own voice: everything else here
        // is #f2f2f7 too, and the only accents left in the band now mean
        // something a word cannot (the power dot's red, a workspace's
        // fill).
        color: "#f2f2f7"
        font.family: Fonts.ui
        // 13 bold, inherited from the badge's own label. Bold because at
        // 13px a three-letter lowercase word next to 15px icons
        // disappears otherwise, and NOT bumped to 15 to match them: this
        // is type, not an icon, and the row's icon size does not govern
        // it -- the same call the `hdr` label already got when the badge
        // grew to 22px and its text deliberately stayed at 13.
        font.pixelSize: 13
        font.bold: true
    }
}
