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
// as the bar itself; the card fades/scales in and out instead of
// hard-cutting, same "smooth open/close" preference the bar's own
// header comment already states for Media.qml/ActiveWindow.qml.
//
// Battery-low is NOT part of this popup -- BatteryAlert.qml is its own
// centered, click-to-dismiss modal (styled after iOS/macOS's "Low
// Battery" alert), a deliberately different shape for a warning that
// wants an acknowledgement rather than a glance-and-forget corner popup.
//
// Redesigned around macOS's own brightness/volume HUD (reference
// screenshot: title label, small-icon/thin-track/big-icon row, tick
// marks): deliberately sidesteps the previous design's whole class of
// bugs. That one used a THICK fill (the full pill height) as the level
// indicator, which needed pixel-correct rounded-corner clipping at every
// width -- two different per-corner-radius attempts got it wrong at the
// extremes (near-0%, exactly-100%), and a MultiEffect rounded-mask
// attempt after that hit real QtQuick footguns live (a source item that
// went fully blank once actually hidden from the normal scene, an
// invisible mask rectangle painting solid white over everything once it
// wasn't). A THIN track (a few px tall) just doesn't have that problem
// -- its own rounded ends are small enough that no one will ever notice
// or care about sub-pixel correctness there, so the fill is back to a
// plain Rectangle with a plain `radius`, no clamping, no masking, no
// thresholds.
//
// Opaque card, not translucent glass -- asked for, after this used the
// shared glass recipe below at first. (Translucency was never a real
// compositor blur anyway: Hyprland's layerrule blur needs a distinct
// Wayland layer-shell namespace to target just this popup, and
// Quickshell hardcodes the same "quickshell" namespace for every
// PanelWindow in the process -- confirmed live via `hyprctl layers -j`
// -- so a layerrule on that shared namespace would've blurred the
// always-on bar too, continuously, for the whole session. Moot now:
// solid fill needs no blur to read cleanly, so that whole tradeoff
// stopped mattering.)
//
// Glass treatment: the SAME one shell.qml already uses on METRICS/
// Launchers/TOOLS, not a bespoke one -- for consistency with the rest
// of the bar (still true for the GlassRim edge highlight below, just
// not for the fill's alpha anymore). That system is a vertical Gradient
// body (lighter/denser at the top, darker/thinner at the bottom -- here
// at full 0xff alpha instead of those other blocks' shared 0x73, the
// one deliberate difference) plus GlassRim.qml traced around the edge
// as the actual highlight -- a five-stop diagonal-reading ramp raking
// across the top-left corner, the same one Hyprland's own active-window
// border, Roue's hub and Balise's panel all use (see GlassRim.qml's
// header). Two GlassRim instances, like those three blocks: topLeft at
// full strength, a fainter bottomRight one as a secondary source. (An
// earlier pass here built its own top-right glow out of overlapping
// circles instead, before being asked to just reuse this -- simpler,
// and actually consistent instead of a fourth slightly-different glass
// recipe in the same bar.)

Rectangle {
    id: card

    readonly property real level: OsdState.level
    readonly property bool muted: OsdState.muted
    readonly property string kind: OsdState.kind   // "volume" | "mic" | "brightness"

    width: 280
    height: 92
    radius: 20

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#ff3f4450" }
        GradientStop { position: 1.0; color: "#ff060608" }
    }

    // target left unset (null) -- these are plain CHILDREN of card, not
    // siblings, so GlassRim's own child-mode default (trace `parent`)
    // is correct as-is. `card` is a plain Rectangle here, not a
    // Block.qml instance with content-reparenting, so there's no
    // separate "sibling" wiring to do the way metrics/tools need it.
    GlassRim { cornerRadius: card.radius }
    GlassRim { cornerRadius: card.radius; lightOrigin: "bottomRight"; strength: 0.45 }

    opacity: OsdState.osdVisible ? 1 : 0
    scale: OsdState.osdVisible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    readonly property string titleText: {
        if (kind === "brightness") return "Brightness";
        if (kind === "mic") return "Micro";
        return "Volume";
    }

    // ph-sun / ph-microphone-slash / ph-microphone / ph-speaker-x /
    // ph-speaker-high -- the last two reused verbatim from
    // AudioOutput.qml's own muted/unmuted glyphs, same meaning here. ONE
    // glyph choice, rendered at two sizes (small left / big right) --
    // matches the reference's own small-sun/big-sun pair, which is the
    // same icon at two scales too, not two different icons.
    readonly property string iconGlyph: {
        if (kind === "brightness") return "";
        if (kind === "mic") return muted ? "" : "";
        return muted ? "" : "";
    }

    Text {
        id: titleLabel
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 20
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.titleText
        color: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 15
        font.bold: true
    }

    Text {
        id: smallIcon
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.top: titleLabel.bottom
        anchors.topMargin: 16
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.iconGlyph
        color: card.muted ? "#ff6e6e" : Qt.rgba(1, 1, 1, 0.55)
        font.family: Fonts.iconPhosphorBold
        font.pixelSize: 14
    }

    Text {
        id: bigIcon
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: smallIcon.verticalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: card.iconGlyph
        color: card.muted ? "#ff6e6e" : "#f2f2f7"
        font.family: Fonts.iconPhosphorBold
        font.pixelSize: 22
    }

    Item {
        id: track
        height: 6
        anchors.left: smallIcon.right
        anchors.leftMargin: 10
        anchors.right: bigIcon.left
        anchors.rightMargin: 10
        anchors.verticalCenter: smallIcon.verticalCenter

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.16)
        }

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (card.muted ? 0 : card.level)
            radius: height / 2
            color: card.muted ? "#ff6e6e" : "#f2f2f7"
            // SpringAnimation instead of a plain eased tween (asked for)
            // -- a physical settle instead of an instant/linear jump to
            // the new level.
            Behavior on width { SpringAnimation { spring: 3; damping: 0.3 } }
        }
    }

    // Reference points as small round dots BELOW the track (not tick
    // marks cutting across the gauge itself, corrected after the first
    // attempt) -- purely decorative, entirely independent of the fill,
    // never covered or interacted with by it. Evenly spaced by index
    // instead of Row+spacing -- this codebase doesn't use
    // QtQuick.Layouts anywhere, plain anchors/x math matches its
    // existing style better.
    Item {
        id: dotsRow
        height: 4
        anchors.top: track.bottom
        anchors.topMargin: 8
        anchors.left: track.left
        anchors.right: track.right

        Repeater {
            model: 14
            Rectangle {
                required property int index
                width: 4
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.3)
                x: (dotsRow.width - width) * (index / 13)
                anchors.verticalCenter: dotsRow.verticalCenter
            }
        }
    }
}
