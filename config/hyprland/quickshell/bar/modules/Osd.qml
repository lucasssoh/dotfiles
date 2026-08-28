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
//
// Horizontal capsule with the FILL itself as the level indicator (asked
// for, referencing a phone media-volume slider) -- not a thin separate
// progress bar under an icon+text row like the first pass. Translucent,
// not a real compositor blur: Hyprland's layerrule blur needs a distinct
// Wayland layer-shell namespace to target just this popup, and
// Quickshell hardcodes the same "quickshell" namespace for every
// PanelWindow in the process (confirmed live via `hyprctl layers -j`
// while this was visible -- the always-on bar and this popup share one
// namespace, no per-window override anywhere in the installed QML API).
// A layerrule on that shared namespace would blur the bar too,
// continuously, for the whole session -- exactly what hyprland.lua's
// decoration.blur.enabled comment already argued against doing. Plain
// translucency still reads as glass without that cost.

Rectangle {
    id: pill

    readonly property real level: OsdState.level
    readonly property bool muted: OsdState.muted
    readonly property string kind: OsdState.kind   // "volume" | "mic" | "brightness"

    width: 240
    height: 48
    radius: height / 2
    clip: true
    color: Qt.rgba(12 / 255, 12 / 255, 14 / 255, 0.72)

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

    // Fill IS the level, not a separate bar -- clipped by the pill's own
    // rounding (clip: true above), so only its leading edge is a hard
    // vertical line; the outer edges stay capsule-round for free, no
    // per-corner radius math needed.
    Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * (pill.muted ? 0 : pill.level)
        color: pill.muted ? "#ff6e6e" : "#a8b4c4"
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    // Icon + text sit on the fill almost always in practice (it starts
    // from x:0, and levels are rarely near-zero when this is even
    // visible) -- dark ink on the light accent fill, same idea as the
    // reference image's dark glyph on its own bright fill, rather than
    // white-on-light-silver which measured too low-contrast to read.
    // Muted is the one state genuinely sitting on the dark translucent
    // track instead (fill width 0), so it keeps the danger/light pair
    // the rest of this bar already uses for that state.
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: pill.iconGlyph
            color: pill.muted ? "#ff6e6e" : "#0c0c0e"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 18
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: pill.muted ? "Muet" : pill.percentText
            color: pill.muted ? "#f2f2f7" : "#0c0c0e"
            font.family: Fonts.ui
            font.pixelSize: 14
        }
    }
}
