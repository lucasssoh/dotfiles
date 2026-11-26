import QtQuick
import Qt5Compat.GraphicalEffects
import "../services"

// The cartoon reflection: a hairline just inside the inked outline that
// follows the container's own rounded corners, then fades out down its
// sides. Only the top of the ring is left visible, so it reads as light
// catching the curve rather than as a second border.
Item {
    id: gloss

    property bool active: true
    property real opacityScale: 1
    property real rimInset: 3
    readonly property real rimRadius: Math.max(0, (parent.radius !== undefined ? parent.radius : 18) - rimInset)

    anchors.fill: parent
    visible: ShellTheme.cartoon && active

    Rectangle {
        id: rim
        anchors.fill: parent
        anchors.margins: gloss.rimInset
        radius: gloss.rimRadius
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.5 * gloss.opacityScale)

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Item {
                width: rim.width
                height: rim.height
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Math.min(parent.height * 0.4, 20)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1) }
                        GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.6) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
            }
        }
    }
}
