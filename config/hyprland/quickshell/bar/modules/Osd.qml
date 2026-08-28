import QtQuick
import "../theme"
import "../services"

// Visual content for the transient volume/mic/brightness popup.
// OsdState.qml (services/) owns the trigger logic and the auto-hide
// timer -- Pipewire push for volume/mic (same live nodes AudioOutput.qml/
// AudioInput.qml already read, zero poll), an IPC-poked one-shot sysfs
// read for brightness (see that file's header for why brightness can't
// go fully push-based) -- this file only renders whatever OsdState
// currently holds. One instance per screen (shell.qml's Variants), same
// as the bar itself; the pill fades/scales in and out instead of
// hard-cutting, same "smooth open/close" preference the bar's own
// header comment already states for Media.qml/ActiveWindow.qml.

Rectangle {
    id: pill

    readonly property real level: OsdState.level
    readonly property bool muted: OsdState.muted
    readonly property string kind: OsdState.kind   // "volume" | "mic" | "brightness"

    width: 220
    height: 60
    radius: 16
    color: "#0c0c0e"

    opacity: OsdState.osdVisible ? 1 : 0
    scale: OsdState.osdVisible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // ph-sun / ph-microphone-slash / ph-microphone / ph-speaker-x /
    // ph-speaker-high -- the last two reused verbatim from
    // AudioOutput.qml's own muted/unmuted glyphs, same meaning here.
    readonly property string iconGlyph: {
        if (kind === "brightness") return "";
        if (kind === "mic") return muted ? "" : "";
        return muted ? "" : "";
    }
    readonly property string percentText: Math.round(level * 100) + "%"

    Row {
        id: header
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        spacing: 8

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: pill.iconGlyph
            color: pill.muted ? "#ff6e6e" : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 20
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: pill.muted ? "Muet" : pill.percentText
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 15
        }
    }

    Rectangle {
        id: track
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        height: 4
        radius: 2
        color: "#34383f"

        Rectangle {
            width: track.width * (pill.muted ? 0 : pill.level)
            height: parent.height
            radius: 2
            color: pill.muted ? "#ff6e6e" : "#a8b4c4"
            Behavior on width { NumberAnimation { duration: 120 } }
        }
    }
}
