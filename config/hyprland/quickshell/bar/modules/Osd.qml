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
// Horizontal capsule with the FILL itself as the level indicator
// (referencing a phone media-volume slider), icon only -- no percentage
// text, the fill already says how much (asked for). Translucent, not a
// real compositor blur: Hyprland's layerrule blur needs a distinct
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

    // Fill IS the level. Per the reference screenshots (0%, ~40%, 100%):
    // the CONTAINER's corners stay rounded at every level, but the
    // fill's own LEADING edge is a flat cut, not rounded -- only at
    // 100%, where that edge coincides with the pill's own edge, does it
    // pick up the pill's rounding too. So: LEFT corners (fill always
    // starts at x:0, the pill's real left edge, at any level) match the
    // pill's radius, clamped to width/2 so they degrade gracefully
    // instead of a flat square once width gets small (found live, near
    // 0-10%: a fixed radius bigger than width/2 broke down into a
    // square -- per-corner radii don't auto-clamp the way the single
    // `radius` property does). RIGHT corners are square UNLESS width
    // has reached the pill's own width (100%), then they round to match
    // too -- previously hard-pinned to 0 always, so 100% never actually
    // matched the pill's rounded end.
    Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * (pill.muted ? 0 : pill.level)
        color: pill.muted ? "#ff6e6e" : "#a8b4c4"

        readonly property real leftRadius: Math.min(pill.radius, width / 2)
        // 1px tolerance: SpringAnimation can overshoot the target width
        // slightly on its way to settling, floating-point width vs.
        // parent.width could also miss an exact match by a hair.
        readonly property bool atFullWidth: width >= parent.width - 1

        topLeftRadius: leftRadius
        bottomLeftRadius: leftRadius
        topRightRadius: atFullWidth ? leftRadius : 0
        bottomRightRadius: atFullWidth ? leftRadius : 0

        Behavior on width { SpringAnimation { spring: 3; damping: 0.3 } }
    }

    // Icon only, bigger + the Bold weight (asked for -- Fonts.qml's own
    // header already flags Phosphor as one separate family PER weight,
    // not a variable font, so this is Fonts.iconPhosphorBold, not
    // font.weight: Font.Bold on the Regular family, which would do
    // nothing). Dark ink on the light accent fill -- it sits on the fill
    // almost always in practice (fill starts from x:0, levels are rarely
    // near-zero when this is even visible) -- measured better contrast
    // than white-on-silver.
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: pill.iconGlyph
        color: pill.muted ? "#ff6e6e" : "#0c0c0e"
        font.family: Fonts.iconPhosphorBold
        font.pixelSize: 24
    }

    // Muted keeps this word: the crossed-out icon alone, at a glance,
    // reads ambiguous between "muted" and "just an off-state glyph" --
    // same reasoning Bluetooth.qml/Network.qml distinguish shape per
    // state instead of leaning on color alone. Also the one state
    // genuinely sitting on the dark translucent track instead of the
    // fill (fill width 0 when muted), so it keeps the danger/light color
    // pair the rest of this bar already uses for that state.
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 48
        anchors.verticalCenter: parent.verticalCenter
        visible: pill.muted
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: "Muet"
        color: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 14
    }
}
