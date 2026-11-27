import QtQuick
import Qt5Compat.GraphicalEffects
import "../services"

// The cartoon reflection: a hairline just inside the inked outline that
// follows the container's own rounded corners, then fades out down its
// sides. Only the top of the ring is left visible, so it reads as light
// catching the curve rather than as a second border.
//
// Its colour comes from what it sits on: the same colour lifted by one
// step on every channel (a smaller, softer step on a dark surface), or
// pure white on a light one, where a lift would not show. A fixed
// half-white vanished on light-mode cards and glared on dark panels.
Item {
    id: gloss

    property bool active: true
    property real opacityScale: 1
    property real rimInset: 3
    // What it sits on: the parent's fill. Its hue counts even while it is
    // still clear (a key fading in from DrawerTheme.clear()); only a parent
    // with no fill at all, plain "transparent", falls back to half-white.
    property color base: parent && parent.color !== undefined ? parent.color : "transparent"
    readonly property bool hasBase: gloss.base.a > 0 || gloss.base.r > 0 || gloss.base.g > 0 || gloss.base.b > 0
    readonly property real lightness: 0.2126 * gloss.base.r + 0.7152 * gloss.base.g + 0.0722 * gloss.base.b
    // Light enough that a lifted shade would barely show: full white
    // instead (off-whites, and pale fills like a pastel yellow).
    readonly property bool offWhite: gloss.hasBase && gloss.lightness >= 0.72
    // On an off-white or a dark surface, a rim right against the ink read
    // as part of the outline: 2 px of the surface between them make it a
    // highlight.
    readonly property bool darkBase: gloss.hasBase && gloss.lightness < 0.3
    readonly property real inset: gloss.rimInset + (gloss.offWhite || gloss.darkBase ? 2 : 0)
    readonly property real rimRadius: Math.max(0, (parent.radius !== undefined ? parent.radius : 18) - gloss.inset)
    // Fades with the fill, so a fill that animates in brings its rim along
    // instead of flashing another colour first.
    readonly property color shine: {
        const c = gloss.base;
        if (!gloss.hasBase) return Qt.rgba(1, 1, 1, 0.5 * gloss.opacityScale);
        // Already near white: only full white still reads as light.
        if (gloss.offWhite) return Qt.rgba(1, 1, 1, c.a);
        // On a dark surface a smaller, softer lift: a full one glared.
        const d = gloss.darkBase ? 0.14 : 0.22;
        const a = gloss.darkBase ? 0.75 : 1;
        return Qt.rgba(Math.min(1, c.r + d), Math.min(1, c.g + d), Math.min(1, c.b + d), a * gloss.opacityScale * c.a);
    }

    anchors.fill: parent
    visible: ShellTheme.cartoon && active

    Rectangle {
        id: rim
        anchors.fill: parent
        anchors.margins: gloss.inset
        radius: gloss.rimRadius
        color: "transparent"
        border.width: 2
        border.color: gloss.shine

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
