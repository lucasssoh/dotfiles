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
// HyperOS pass: a round dial, the "R2" of the mockups ("arc et
// curseur"), replacing a HUD that copied macOS's closely (title, small
// icon / thin track / big icon, tick dots). A knob in relief with a notch
// (after a Dribbble reference, "K2") came first and was swapped for this
// flatter one:
//
//   - a black disc, the drawers' panel colour, so it reads over anything;
//   - a THICK arc, open at the bottom like a potentiometer (270deg from
//     7:30 to 4:30), on a visible grey track;
//   - a white dot riding the arc's end -- the "cursor" -- ringed in the
//     disc's black so it stands off the arc it sits on;
//   - the glyph and the level in the middle.
//
// Brightness under HDR: the panel ignores backlight changes then, so the
// dial greys out and reads "HDR" instead of a level that means nothing.
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

    // Eased copy of `shown` for the arc and its cursor.
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

    // ---- arc: track, level, cursor ------------------------------------
    readonly property real arcRadius: 59
    readonly property real arcWidth: 9

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: DrawerTheme.cardRaised
            strokeWidth: card.arcWidth
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: card.width / 2; centerY: card.height / 2
                radiusX: card.arcRadius; radiusY: card.arcRadius
                startAngle: card.startAngle; sweepAngle: card.sweep
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: card.anim > 0.001 ? DrawerTheme.on : "transparent"
            strokeWidth: card.arcWidth
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: card.width / 2; centerY: card.height / 2
                radiusX: card.arcRadius; radiusY: card.arcRadius
                startAngle: card.startAngle; sweepAngle: card.sweep * card.anim
            }
        }
    }

    // The cursor: a white dot at the arc's end, ringed in the disc's black.
    // A zero-size item at the centre, rotated; the dot sits straight "up"
    // from it at the arc's radius, so rotation = angle + 90.
    Item {
        x: card.width / 2
        y: card.height / 2
        rotation: card.endAngle + 90
        visible: card.anim > 0.001
        Rectangle {
            width: 15
            height: 15
            radius: width / 2
            x: -width / 2
            y: -card.arcRadius - height / 2
            color: DrawerTheme.on
            border.width: 2.5
            border.color: DrawerTheme.panelTop
        }
    }

    // ---- glyph and level -----------------------------------------------
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -9
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.iconGlyph
        color: card.hdrLock ? DrawerTheme.muted : (card.muted ? DrawerTheme.danger : DrawerTheme.primary)
        font.family: Fonts.iconMingcute
        font.pixelSize: 24
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 16
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.hdrLock ? "HDR" : card.muted ? "—" : Math.round(card.level * 100)
        color: card.hdrLock ? DrawerTheme.secondary : DrawerTheme.primary
        font.family: Fonts.ui
        font.pixelSize: 15
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
}
