import QtQuick
import QtQuick.Shapes

// A 1px GRADIENT rim traced around another item -- the same "verre
// métal" edge Hyprland puts on the active window, Roue on its central
// hub and Balise on its panel. Same five stops as all three
// (hypr/hyprland.lua's general.col.active_border, roue/style.css's
// .roue-confirm-hub, balise/style.css's .balise-panel): a near-white
// highlight at the top-left corner decaying to near-nothing at the
// bottom-right, so the edge reads as light raking across a pane rather
// than as an outline drawn around a box.
//
// Why a Shape and not just `border.color` on the Rectangle: a QML
// Rectangle border takes a flat colour only. The usual workaround --
// a gradient-filled rectangle with the real fill laid on top, inset by
// the border width -- cannot work here, because these pills are
// deliberately translucent: the gradient underneath would show straight
// through the fill and wash the whole interior instead of staying in
// the 1px edge. (That is the same trap balise/style.css documents for
// `background-clip: border-box`, measured there as a fill jumping from
// 121 to 209 luminance.) So the ring is built as a real path with a
// hole in it -- outer rounded rect, inner rounded rect, OddEvenFill --
// and the gradient fills only what's left: the ring itself.
//
// Used as a SIBLING of its target when the target lives inside a Block:
// Block.qml declares `default property alias content: row.children`, so
// anything nested inside a Block is reparented into that Row and would
// track the content's width instead of the pill's -- `target` set to
// the Block itself (or any other item) is how the bar's own translucent
// panes (metrics/launchers/tools in shell.qml) and Hdr.qml's badge use
// it.
//
// Left unset (null), `target` falls back to `parent` instead -- lets
// this be dropped in as a plain CHILD of the thing it should trace
// (ActiveWindow.qml's app chip, Workspaces.qml's active pill), which is
// simpler whenever the target isn't itself a Block/reparenting
// container: x/y then default to (0,0), the correct origin for a child
// tracing its own parent's bounds, no separate sibling wiring needed.
Shape {
    id: rim

    // The item to trace. Its x/y/width/height are followed live, so this
    // keeps up with anchored and content-sized targets alike. Left null,
    // this traces `parent` instead (see header comment) -- for that mode
    // `rim` must actually BE a child of the item it's tracing.
    property Item target: null
    readonly property Item _traced: target ? target : parent
    // Match the target's own corner radius (Block defaults to 10).
    property real cornerRadius: 10
    property real thickness: 1

    // Where the light comes from, expressed as how much of the gradient
    // each axis consumes: hSpan is the share used up crossing the pill's
    // full WIDTH, vSpan the share used up crossing its full HEIGHT.
    //
    // Deliberately not an angle. These pills are ~17:1, so an angle is
    // meaningless here: a vector from corner to corner sits 3 degrees off
    // the horizontal, and the first version of this file used exactly
    // that. Measured, it gave 128 units of left-to-right travel against
    // 8-32 top-to-bottom -- light from the LEFT, not from the top-left.
    // Splitting it per axis is the only formulation that stays meaningful
    // whatever the pill's aspect ratio.
    property real hSpan: 0.65
    property real vSpan: 0.50

    // Which corner the highlight sits on: "topLeft", "topRight",
    // "bottomLeft" or "bottomRight". topLeft for anything that floats
    // free (it matches Hyprland's own window borders). A surface flush
    // against the screen's TOP edge has no visible upper arête, so a hot
    // spot up there would be spent on a boundary nobody can see -- those
    // take one of the bottom corners instead.
    property string lightOrigin: "topLeft"
    readonly property bool _fromBottom: lightOrigin === "bottomLeft" || lightOrigin === "bottomRight"
    readonly property bool _fromRight: lightOrigin === "topRight" || lightOrigin === "bottomRight"

    // Scales every stop's ALPHA only (never the RGB, so the highlight
    // stays the same colour, just fainter) -- lets a second GlassRim be
    // stacked on the same target as a weaker secondary source (metrics/
    // launchers/tools in shell.qml: topLeft at full strength plus a
    // fainter bottomRight one, asked for). 1.0 reproduces the original
    // fixed stop colours exactly.
    property real strength: 1.0

    // What colour the brightest (position 0) stop is -- default is the
    // original neutral "#e5e5ea" this whole ramp was built from. The
    // other 4 stops are this SAME colour scaled down by the exact ratios
    // the original hardcoded ramp used (each channel of e5e5ea/8e8e93/
    // 636366/3a3a3c/1c1c1e relative to e5e5ea's own R channel) -- so
    // retinting is just "what's the brightest point's colour", the decay
    // shape stays identical. Used by Hdr.qml to swap the rim cyan when
    // HDR is active, without needing a second hardcoded stop set.
    property color highlightColor: "#e5e5ea"
    readonly property real _r1: 142 / 229
    readonly property real _r2: 99 / 229
    readonly property real _r3: 58 / 229
    readonly property real _r4: 28 / 229

    // Pushes the traced rectangle's TOP edge this far above the item, so
    // it (and its corner arcs) fall outside the bar surface and are never
    // painted -- again for a flush-top target, which has square top
    // corners and no visible top edge. Must exceed cornerRadius, or the
    // top arc curves back into view.
    property real topOverflow: 0

    // Per-corner overrides, each defaulting to `cornerRadius` -- plain
    // childless bindings, so anything that only ever sets `cornerRadius`
    // (every call site before Veille.qml) renders identically to before.
    // Added for a target flush against two screen edges (Veille's
    // corner-anchored card): only the corner diagonally OPPOSITE the
    // screen's own corner should curve, the other three stay square.
    property real topLeftRadius: cornerRadius
    property real topRightRadius: cornerRadius
    property real bottomLeftRadius: cornerRadius
    property real bottomRightRadius: cornerRadius

    // In sibling mode (target set) these are the target's OWN x/y within
    // the shared parent. In child mode (target null, tracing `parent`)
    // x/y must stay 0 -- `parent` here IS this item's own coordinate
    // origin, not a position within some other, shared parent.
    x: target ? target.x : 0
    y: target ? target.y : 0
    width: _traced ? _traced.width : 0
    height: _traced ? _traced.height : 0

    // The default (geometry) renderer leaves visible stair-stepping on a
    // 1px curved ring this small; CurveRenderer antialiases it properly.
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        // -1 disables the stroke entirely -- the ring is a FILLED shape,
        // not a stroked outline, which is what lets it carry a gradient.
        strokeWidth: -1
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            // Solve for the gradient vector (dx, dy) that gives exactly
            // hSpan across the width and vSpan down the height:
            //   W*dx/D = hSpan,  H*dy/D = vSpan,  D = dx^2 + dy^2
            // => D = 1 / (hSpan^2/W^2 + vSpan^2/H^2)
            // The highlight still lands on the top-left corner and the
            // last stop on the bottom-right, like the 135deg in the CSS
            // versions and Hyprland's angle=45 -- but now both axes
            // actually contribute on a shape this wide.
            readonly property real _d: 1.0 / (Math.pow(rim.hSpan / Math.max(1, rim.width), 2)
                                            + Math.pow(rim.vSpan / Math.max(1, rim.height), 2))
            readonly property real _dx: rim.hSpan * _d / Math.max(1, rim.width)
            readonly property real _dy: rim.vSpan * _d / Math.max(1, rim.height)
            x1: rim._fromRight ? rim.width : 0
            y1: rim._fromBottom ? rim.height : 0
            x2: rim._fromRight ? rim.width - _dx : _dx
            y2: rim._fromBottom ? rim.height - _dy : _dy
            // Position 0 is `highlightColor` itself; the rest are that
            // same colour scaled by the original ramp's per-stop ratios
            // (see `_r1.._r4` above) -- reproduces the original fixed
            // #e5e5ea-based ramp exactly at the default `highlightColor`,
            // any other colour rides the same decay shape. Alpha is
            // still the original per-stop value scaled by `strength`.
            GradientStop { position: 0.00; color: Qt.rgba(rim.highlightColor.r, rim.highlightColor.g, rim.highlightColor.b, 0xbf/255 * rim.strength) }
            GradientStop { position: 0.25; color: Qt.rgba(rim.highlightColor.r * rim._r1, rim.highlightColor.g * rim._r1, rim.highlightColor.b * rim._r1, 0x73/255 * rim.strength) }
            GradientStop { position: 0.50; color: Qt.rgba(rim.highlightColor.r * rim._r2, rim.highlightColor.g * rim._r2, rim.highlightColor.b * rim._r2, 0x47/255 * rim.strength) }
            GradientStop { position: 0.75; color: Qt.rgba(rim.highlightColor.r * rim._r3, rim.highlightColor.g * rim._r3, rim.highlightColor.b * rim._r3, 0x26/255 * rim.strength) }
            GradientStop { position: 1.00; color: Qt.rgba(rim.highlightColor.r * rim._r4, rim.highlightColor.g * rim._r4, rim.highlightColor.b * rim._r4, 0x0f/255 * rim.strength) }
        }

        // Outer edge.
        PathRectangle {
            x: 0
            y: -rim.topOverflow
            width: rim.width
            height: rim.height + rim.topOverflow
            topLeftRadius: rim.topLeftRadius
            topRightRadius: rim.topRightRadius
            bottomLeftRadius: rim.bottomLeftRadius
            bottomRightRadius: rim.bottomRightRadius
        }
        // Inner edge -- OddEvenFill turns this second subpath into a hole,
        // leaving just the `thickness`-wide ring between the two.
        PathRectangle {
            x: rim.thickness
            y: -rim.topOverflow + rim.thickness
            width: Math.max(0, rim.width - rim.thickness * 2)
            height: Math.max(0, rim.height + rim.topOverflow - rim.thickness * 2)
            topLeftRadius: Math.max(0, rim.topLeftRadius - rim.thickness)
            topRightRadius: Math.max(0, rim.topRightRadius - rim.thickness)
            bottomLeftRadius: Math.max(0, rim.bottomLeftRadius - rim.thickness)
            bottomRightRadius: Math.max(0, rim.bottomRightRadius - rim.thickness)
        }
    }
}
