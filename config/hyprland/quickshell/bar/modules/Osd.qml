import QtQuick
import QtQuick.Shapes
import "../theme"
import "../services"

// Visual content for the transient volume/mic/brightness popup.
// OsdState.qml (services/) owns the trigger logic and the auto-hide
// timer -- Pipewire push for volume/mic (same live nodes AudioOutput.qml/
// AudioInput.qml already read, zero poll), an IPC-poked one-shot sysfs
// read for brightness (see that file's header for why brightness can't
// go fully push-based) -- this file only renders whatever OsdState
// currently holds. One instance per screen (shell.qml's Variants), same
// as the bar itself; the card fades/scales in and out instead of
// hard-cutting, same "smooth open/close" preference the bar's own
// header comment already states for Media.qml/ActiveWindow.qml.
//
// Battery-low is NOT part of this popup -- BatteryAlert.qml is its own
// centered, click-to-dismiss modal (styled after iOS/macOS's "Low
// Battery" alert), a deliberately different shape for a warning that
// wants an acknowledgement rather than a glance-and-forget corner popup.
//
// HyperOS pass: redesigned as a round knob, after a Dribbble reference the
// user picked ("Volume Control Buttons") -- replacing a HUD that copied
// macOS's closely (title, small icon / thin track / big icon, tick dots).
//
//   - a black disc, the drawers' panel colour, so it reads over anything;
//   - a knob in soft relief: an outer ring and a slightly sunken inner
//     face, two vertical gradients in the drawers' neutral greys;
//   - an arc around it, open at the bottom like a potentiometer (270deg
//     from 7:30 to 4:30), on a VISIBLE grey track (asked for: the
//     reference's arc floats alone, which reads poorly near 0%), with a
//     soft wider copy under it for the glow;
//   - a notch on the knob's rim turned to the same angle, so the knob
//     reads as having been turned, not just filled;
//   - the glyph, and the level under it (the reference's "K2" variant:
//     number instead of a caption).
//
// Brightness under HDR: the panel ignores backlight changes then, so the
// knob greys out and reads "HDR" instead of a level that means nothing.
// Drawn with Shapes (ShapePath + PathAngleArc): no image asset, no
// shader, and the arcs are exact at every level.
Item {
    id: card

    // Which monitor this popup is on, for the HDR check (shell.qml).
    property var monitor: null

    readonly property real level: OsdState.level
    readonly property bool muted: OsdState.muted
    readonly property string kind: OsdState.kind   // "volume" | "mic" | "brightness"
    readonly property bool hdrLock: card.kind === "brightness" && HdrState.activeOn(card.monitor)
    // What the arc shows: nothing while muted or locked.
    readonly property real shown: (card.muted || card.hdrLock) ? 0 : Math.max(0, Math.min(1, card.level))

    // Eased copy of `shown` for the arc and the notch.
    property real anim: card.shown
    Behavior on anim { SpringAnimation { spring: 3; damping: 0.35 } }

    readonly property real startAngle: 135
    readonly property real sweep: 270
    readonly property real endAngle: card.startAngle + card.sweep * card.anim

    width: 150
    height: 150

    opacity: OsdState.osdVisible ? 1 : 0
    scale: OsdState.osdVisible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Volume uses the output's own glyph (headphones, screen, Bluetooth,
    // speaker -- OsdState.outputGlyph), the same one the bar shows.
    readonly property string iconGlyph: {
        if (kind === "brightness") return "\uF408";
        if (kind === "mic") return muted ? "\uF0B0" : "\uF0AE";
        return OsdState.outputGlyph;
    }

    // ---- disc ----------------------------------------------------------
    Rectangle {
        anchors.centerIn: parent
        width: 144
        height: 144
        radius: width / 2
        color: DrawerTheme.panelTop
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    // ---- arc: track, glow, level ---------------------------------------
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: DrawerTheme.cardRaised
            strokeWidth: 2.6
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: card.width / 2; centerY: card.height / 2
                radiusX: 57; radiusY: 57
                startAngle: card.startAngle; sweepAngle: card.sweep
            }
        }
        // Glow: a wide, faint copy of the level arc under it.
        ShapePath {
            fillColor: "transparent"
            strokeColor: card.anim > 0.001 ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
            strokeWidth: 8
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: card.width / 2; centerY: card.height / 2
                radiusX: 57; radiusY: 57
                startAngle: card.startAngle; sweepAngle: card.sweep * card.anim
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: card.anim > 0.001 ? DrawerTheme.on : "transparent"
            strokeWidth: 2.6
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: card.width / 2; centerY: card.height / 2
                radiusX: 57; radiusY: 57
                startAngle: card.startAngle; sweepAngle: card.sweep * card.anim
            }
        }
    }

    // ---- knob ----------------------------------------------------------
    Rectangle {
        anchors.centerIn: parent
        width: 92
        height: 92
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1c1c20" }
            GradientStop { position: 1.0; color: "#0b0b0d" }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
    }
    Rectangle {
        anchors.centerIn: parent
        width: 72
        height: 72
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1f1f23" }
            GradientStop { position: 1.0; color: "#121215" }
        }
        border.width: 1.5
        border.color: Qt.rgba(0, 0, 0, 0.6)
    }

    // The notch: a short white mark on the knob's rim, turned with the
    // level. A zero-size item at the centre, rotated; the mark sits
    // straight "up" from it, so rotation = angle + 90.
    Item {
        x: card.width / 2
        y: card.height / 2
        rotation: card.endAngle + 90
        Rectangle {
            x: -1.1
            y: -33
            width: 2.2
            height: 4.5
            radius: 1.1
            color: card.hdrLock ? "#4a4a4f" : DrawerTheme.on
        }
    }

    // ---- glyph and level -----------------------------------------------
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -7
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.iconGlyph
        color: card.hdrLock ? DrawerTheme.muted : (card.muted ? DrawerTheme.danger : DrawerTheme.primary)
        font.family: Fonts.iconMingcute
        font.pixelSize: 20
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 14
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.hdrLock ? "HDR" : card.muted ? "—" : Math.round(card.level * 100)
        color: card.hdrLock ? DrawerTheme.secondary : DrawerTheme.primary
        font.family: Fonts.ui
        font.pixelSize: 13
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
}
