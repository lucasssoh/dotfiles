import QtQuick
import "../../theme"

// A row of mutually exclusive pills -- the EAP method / phase-2 auth
// pickers on the enterprise credential form (BaliseDetailPage.qml).
//
// A segmented control rather than a dropdown because the whole option set
// is three items wide and fits on one line: a popup list would need its
// own overlay layer inside a drawer that is already a layer-shell surface,
// for no gain. Same hand-drawn-control reasoning as BaliseTextField.qml's
// own header.
//
// `options` is [{ label, value }, ...]; `value` is the selected entry's
// `value`, and is what gets written straight into the credentials object.
Item {
    id: seg

    property var options: []
    property string value: ""
    signal picked(string value)

    width: parent ? parent.width : 0
    height: 32

    Row {
        anchors.fill: parent
        spacing: 6

        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: pill
                required property var modelData
                readonly property bool selected: seg.value === pill.modelData.value

                // Equal thirds (or halves, ...) of the row minus its gaps,
                // so the control fills the form's width whatever the
                // option count is.
                width: seg.options.length > 0
                    ? (seg.width - 6 * (seg.options.length - 1)) / seg.options.length
                    : 0
                height: seg.height
                radius: 10
                // An unselected pill needs a fill AND an outline of its
                // own: this control sits on a `Surfaces.card` panel, and
                // painting the idle state that same card colour made the
                // unselected options read as bare floating labels with no
                // hit target -- confirmed on a screenshot before this was
                // a raised tint.
                color: pill.selected
                    ? (pillArea.containsMouse ? Surfaces.accentStrongest : Surfaces.accentMedium)
                    : (pillArea.containsMouse ? Surfaces.cardRaised : Surfaces.cardHover)
                border.width: 1
                border.color: pill.selected ? Surfaces.accent : Qt.rgba(1, 1, 1, 0.08)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: pill.modelData.label
                    color: pill.selected ? Surfaces.accent : "#8e8e93"
                    font.family: Fonts.ui
                    font.pixelSize: 11
                    font.bold: pill.selected
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: pillArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(pill.modelData.value)
                }
            }
        }
    }
}
