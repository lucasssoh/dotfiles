import QtQuick
import QtQuick.Shapes
import "../theme"

// The low-battery / charging card's icon: one THICK RING whose stroke
// IS the gauge (asked for: "un simple cercle epaix suffit et la jauge
// c'est le remplissage du border"). Replaces the rounded-square tile +
// BatteryIcon.qml gauge that sat here before -- that little battery
// glyph is still the right thing in the top bar, where it has to read
// at 20x10px next to a number, but at 84px on a card it was a small
// picture floating in a box rather than the thing the card is about.
//
// Three layers, back to front:
//   1. track    -- the full 360 degrees, barely-there white, so the
//                  ring reads as a ring even at 3%
//   2. level    -- the actual charge, an arc from 12 o'clock clockwise,
//                  round-capped, animated on every percentage change
//   3. flow     -- charging ONLY: a green comet orbiting the ring on
//                  top of the level (asked for: "une sorte de flux vert
//                  en plus du niveau de charge", and explicitly NOT
//                  there when low+unplugged). It's a fixed Shape inside
//                  a rotating Item rather than an arc whose startAngle
//                  animates: rotating the item is a transform on an
//                  already-tessellated path, so the ring is built once
//                  instead of re-tessellated every frame of the orbit.
//
// QtQuick.Shapes (CurveRenderer) rather than the "build it out of
// Rectangles" approach the rest of this bar uses (BatteryIcon.qml,
// GlassRim.qml, BatteryAlert.qml's hand-drawn X) -- those shapes are
// all axis-aligned boxes, an arc isn't, and Canvas would mean an
// imperative repaint on every frame of both the level animation and the
// orbit. CurveRenderer also antialiases without needing the whole item
// put in a multisampled layer.
Item {
    id: root

    property real percent: 0
    property bool charging: false

    // The two "appropriate colors" (asked for), kept as SEPARATE
    // properties rather than one pre-resolved accent: the center
    // content cross-fades between a low face and a charging face that
    // are on screen at the same time mid-scroll, so both colors have to
    // exist at once.
    property color lowColor: "#a8b4c4"
    property color chargeColor: "#a3d9a5"
    property color flowColor: "#d6f7dd"

    property real thickness: 7

    // Not `readonly` -- a Behavior can only attach to a writable
    // property (same constraint BatteryAlert.qml's accent hit).
    property color ringColor: root.charging ? root.chargeColor : root.lowColor
    Behavior on ringColor { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real radius: Math.min(width, height) / 2 - thickness / 2
    readonly property real sweep: 360 * Math.max(0, Math.min(100, root.percent)) / 100

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // Track. Flat caps, full turn -- a round-capped 360 arc would
        // overlap itself at 12 o'clock and print a visible seam there.
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.10)
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.radius; radiusY: root.radius
                startAngle: -90; sweepAngle: 360
            }
        }

        // Level. Starts at 12 o'clock (-90 in Qt's angle space, where 0
        // is 3 o'clock) and runs clockwise, the direction a gauge is
        // read.
        ShapePath {
            strokeColor: root.ringColor
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.radius; radiusY: root.radius
                startAngle: -90
                sweepAngle: root.sweep
                Behavior on sweepAngle { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            }
        }
    }

    // ---- charging flow ----
    Item {
        id: flow
        anchors.fill: parent
        opacity: root.charging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // Animator (not NumberAnimation): runs on the render thread, so
        // the orbit keeps its own beat even when the UI thread is busy.
        RotationAnimator on rotation {
            from: 0; to: 360
            duration: 2600
            loops: Animation.Infinite
            running: flow.visible
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Wide, faint halo -- the comet's glow. Sits UNDER the head
            // (declared first) and is deliberately wider than the ring
            // itself so it bleeds a little past both edges.
            ShapePath {
                strokeColor: Qt.rgba(root.flowColor.r, root.flowColor.g, root.flowColor.b, 0.16)
                strokeWidth: root.thickness + 6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.cx; centerY: root.cy
                    radiusX: root.radius; radiusY: root.radius
                    startAngle: -150; sweepAngle: 84
                }
            }
            // Tail, then head: two arcs of the same stroke at rising
            // opacity, which is how the comet gets a direction without
            // a stroke gradient (ShapePath has fillGradient only, no
            // stroke gradient in Qt 6).
            ShapePath {
                strokeColor: Qt.rgba(root.flowColor.r, root.flowColor.g, root.flowColor.b, 0.38)
                strokeWidth: root.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.cx; centerY: root.cy
                    radiusX: root.radius; radiusY: root.radius
                    startAngle: -138; sweepAngle: 40
                }
            }
            ShapePath {
                strokeColor: root.flowColor
                strokeWidth: root.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.cx; centerY: root.cy
                    radiusX: root.radius; radiusY: root.radius
                    startAngle: -104; sweepAngle: 14
                }
            }
        }
    }

    // ---- center: status icon + percentage, side by side ----
    //
    // The number does NOT scroll (asked for: "le pourcentage (la valeur)
    // n'est animé que d'un changement de couleur, mais seul l'icon,
    // qu'il faut mettre à coté, doit defiler haut-bas"). It's the same
    // value before and after the plug -- scrolling it would have been
    // motion for nothing, and the eye reads a number that stays put and
    // just warms/greens far more easily than one that slides. Only the
    // STATUS, which really does change, moves: the icon sits beside the
    // number in a clipped one-line window, and plugging in scrolls the
    // plug out through the top while the lightning rises into its place.
    // Unplugging runs the same move backwards.
    readonly property real lineHeight: 24

    Row {
        id: center
        anchors.centerIn: parent
        spacing: 4

        // Guard, not a layout: "100%" plus the icon is wider than the
        // ring's inner opening, and text crossing the stroke would look
        // broken. Everything in this Row is laid out at its natural size
        // and the whole cluster is scaled down only if it would touch
        // the ring.
        readonly property real available: 2 * root.radius - root.thickness - 8
        scale: Math.min(1, center.available / Math.max(1, center.implicitWidth))

        // Clipped window, one line tall. Its width tracks the WIDER of
        // the two glyphs so the number beside it doesn't shift by a
        // pixel or two as the icon changes.
        Item {
            id: iconWindow
            width: Math.max(lowGlyph.implicitWidth, chargeGlyph.implicitWidth)
            height: root.lineHeight
            clip: true

            Column {
                width: parent.width
                y: root.charging ? -root.lineHeight : 0
                Behavior on y { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }

                Glyph { id: lowGlyph; glyph: "\ue946"; tone: root.lowColor }      // plug-bold
                Glyph { id: chargeGlyph; glyph: "\ue2de"; tone: root.chargeColor } // lightning-bold
            }
        }

        // Same height as the icon window + vertical centering in both,
        // which is how the two line up: Row aligns its children's TOPS
        // (it has no vertical alignment of its own, and anchoring inside
        // a positioner fights the positioner).
        Text {
            id: value
            height: root.lineHeight
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: Math.round(root.percent) + "%"
            // The number's ONLY animation -- ringColor carries the
            // warmth ramp while unplugged and the swing to green on
            // plug-in, Behavior-animated at the top of this file.
            color: root.ringColor
            font.family: Fonts.ui
            font.pixelSize: 19
            font.bold: true
        }
    }

    // Phosphor codepoints above are NOT guesses and NOT read off a
    // rendered glyph sheet (how BatteryAlert.qml's checkmark was found
    // -- slow, and this subset's codepoints aren't ordered in any way
    // that lets you extrapolate). The web font carries a LIGATURE per
    // icon name, so fontTools can resolve a name straight to a glyph and
    // the glyph back to its codepoint:
    //   GSUB ligature "plug-bold"      -> uniE946
    //   GSUB ligature "lightning-bold" -> uniE2DE
    // (component names in the font spell '-' as "hyphen", so the
    // ligature key to look up is "plughyphenbold".)
    component Glyph: Text {
        required property string glyph
        required property color tone

        width: iconWindow.width
        height: root.lineHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: glyph
        color: tone
        font.family: Fonts.iconPhosphorBold
        font.pixelSize: 16
    }
}
