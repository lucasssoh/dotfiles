import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// A full-height sheet down one edge of the screen (Programme on the left,
// the notification centre on the right), in one of bar.json's two ways
// (`sheets`, IslandStyle.sheetsAttached):
//
//   floating (default)  like a window: `gap` from the edge, the bar and
//                       the bottom, corners at `radius`, so its curves run
//                       parallel to the screen's and the bar's, and no
//                       shadow, as windows have none. Its inner edge lines
//                       up with the bar's side above when that side is at
//                       least as wide. It slides in from the edge.
//   attached            the bar's side group carried on down: as wide as
//                       that group (SheetGeometry), flush with the bar and
//                       the edge, meeting the far edge of the screen in a
//                       concave curve. It unrolls from the bar, and the bar
//                       draws its half of the join (BarBackdrop's
//                       extendLeft and extendRight).
//
//   SideSheet { edge: "right"; open: …; screen: …; SomeContent { anchors.fill: parent } }
PanelWindow {
    id: sheet

    required property string edge          // "left" or "right"
    property bool open: false
    // The content, laid out over the sheet's own rectangle.
    default property alias content: body.data

    readonly property bool atLeft: sheet.edge === "left"
    readonly property bool attached: IslandStyle.sheetsAttached
    readonly property real gap: sheet.attached ? 0 : IslandStyle.edgeGap
    readonly property real panelWidth: sheet.attached
        ? SheetGeometry.width(sheet.screen, sheet.edge)
        : SheetGeometry.width(sheet.screen, sheet.edge) - IslandStyle.edgeGap
    // Attached: the concave curve hangs outside the rectangle, in the window.
    readonly property real curve: sheet.attached ? IslandStyle.outerRadius : 0
    // How far it is in, 0 to 1.
    property real shown: entered && sheet.open ? 1 : 0
    Behavior on shown { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    // The motion waits for the new window's first few frames: started on
    // creation, it shared them with the first render and held a frame.
    property bool entered: false
    FrameAnimation {
        running: !sheet.entered
        onTriggered: if (currentFrame >= 3) sheet.entered = true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    anchors { top: true; bottom: true; left: sheet.atLeft; right: !sheet.atLeft }
    margins {
        top: BarPosition.bottom ? 0 : IslandStyle.band
        bottom: BarPosition.bottom ? IslandStyle.band : 0
    }
    implicitWidth: sheet.gap + sheet.panelWidth + sheet.curve
    // Its own namespace, for hypr/windowrules.lua's no_anim: the sheet
    // moves itself.
    WlrLayershell.namespace: "quickshell-sheet"
    // Clicks outside the rectangle go through to the desktop.
    mask: Region { item: panel }
    // The glass over the rectangle, dropped near the end of a close: the
    // region reaches the compositor a frame or two late and left a blurred
    // strip behind.
    BackgroundEffect.blurRegion: SmoothRegion {
        pixelRatio: sheet.devicePixelRatio
        x: panel.x + slider.x
        y: sheet.attached ? reveal.y : panel.y
        width: DrawerTheme.glass && sheet.shown > 0.2 ? panel.width : 0
        height: sheet.attached ? reveal.height : panel.height
        radius: panel.radius
    }

    // Attached: what is unrolled so far, from the bar. Floating: all of it.
    Item {
        id: reveal
        width: parent.width
        height: sheet.attached ? Math.round(parent.height * sheet.shown) : parent.height
        y: BarPosition.bottom ? parent.height - height : 0
        clip: sheet.attached

        // Floating: the slide in from the edge.
        Item {
            id: slider
            width: sheet.width
            height: sheet.height
            x: sheet.attached ? 0 : (sheet.atLeft ? -1 : 1) * (1 - sheet.shown) * sheet.width
            y: BarPosition.bottom ? reveal.height - height : 0

            // Attached: the rectangle and its concave curve, with the edge
            // running down from the bar's.
            Canvas {
                id: shape
                visible: sheet.attached
                anchors.fill: parent
                readonly property color fill: DrawerTheme.paneTop
                readonly property real ink: DrawerTheme.edgeWidth(1)
                readonly property color inkColour: DrawerTheme.edgeColour(DrawerTheme.paneRim)
                onFillChanged: requestPaint()
                onInkChanged: requestPaint()
                onInkColourChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: requestPaint()
                Connections {
                    target: sheet
                    function onCurveChanged() { shape.requestPaint() }
                    function onAtLeftChanged() { shape.requestPaint() }
                }
                Connections {
                    target: BarPosition
                    function onBottomChanged() { shape.requestPaint() }
                }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (!visible) return;
                    // Drawn as the right-hand sheet hanging from a top bar,
                    // flipped for the others.
                    if (sheet.atLeft) { ctx.translate(width, 0); ctx.scale(-1, 1); }
                    if (BarPosition.bottom) { ctx.translate(0, height); ctx.scale(1, -1); }
                    const a = sheet.curve, x0 = a, H = height;
                    const rgba = c => "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                        + Math.round(c.b * 255) + "," + c.a + ")";
                    ctx.fillStyle = rgba(fill);
                    ctx.fillRect(x0, 0, width - x0, H);
                    // The concave curve, 1 px over the rectangle so no seam
                    // shows between them.
                    ctx.beginPath();
                    ctx.moveTo(x0 + 1, H - a);
                    ctx.lineTo(x0 + 1, H);
                    ctx.lineTo(x0 - a, H);
                    ctx.arc(x0 - a, H - a, a, Math.PI / 2, 0, true);
                    ctx.closePath();
                    ctx.fill();
                    // Down from the bar (whose own line it continues), then
                    // along the curve. Never on the screen's edges.
                    if (ink > 0) {
                        const h = ink / 2;
                        ctx.lineWidth = ink;
                        ctx.strokeStyle = rgba(inkColour);
                        ctx.beginPath();
                        ctx.moveTo(x0 + h, -1);
                        ctx.lineTo(x0 + h, H - a);
                        ctx.arc(x0 - a, H - a, a + h, 0, Math.PI / 2, false);
                        ctx.stroke();
                    }
                }
            }

            Rectangle {
                id: panel
                x: sheet.attached
                    ? (sheet.atLeft ? 0 : sheet.curve)
                    : (sheet.atLeft ? sheet.gap : 0)
                y: sheet.gap
                width: sheet.panelWidth
                height: parent.height - 2 * sheet.gap
                radius: sheet.attached ? 0 : IslandStyle.drawerRadius
                color: sheet.attached ? "transparent" : DrawerTheme.paneTop

                // Denser glass on the lower part, mostly empty, where the
                // wallpaper's colours showed through in blotches.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.38; color: DrawerTheme.clear(DrawerTheme.paneVeil) }
                        GradientStop { position: 1.0; color: DrawerTheme.paneVeil }
                    }
                }
                // Floating: its edge, a faded rim in glass, the ink outline
                // in cartoon.
                PaneEdge {
                    visible: !sheet.attached
                    radius: panel.radius
                    highlight: false
                    fade: true
                }

                Item {
                    id: body
                    anchors.fill: parent
                    anchors.topMargin: 8
                }
            }
        }
    }

    // The bar's concave corner at this screen edge, drawn again over the
    // sheet. A sliding sheet passes under it, as under the bar: both are
    // on the Top layer, where the surface mapped last (the sheet) would
    // otherwise cover the bar. In place, the sheet clears it by `gap`.
    Canvas {
        id: barCorner
        visible: !sheet.attached && IslandStyle.cornerFill.a > 0
        readonly property real r: IslandStyle.cornerRadius
        readonly property color fill: IslandStyle.cornerFill
        readonly property real ink: ShellTheme.outline
        readonly property color inkColour: ShellTheme.outlineColour
        width: r + ink
        height: r + ink
        x: sheet.atLeft ? 0 : parent.width - width
        y: BarPosition.bottom ? parent.height - height : 0
        onFillChanged: requestPaint()
        onInkChanged: requestPaint()
        onInkColourChanged: requestPaint()
        onRChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!visible) return;
            // As the right-hand corner under a top bar, flipped for the others.
            if (!sheet.atLeft) { ctx.translate(width, 0); ctx.scale(-1, 1); }
            if (BarPosition.bottom) { ctx.translate(0, height); ctx.scale(1, -1); }
            const rgba = c => "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                + Math.round(c.b * 255) + "," + c.a + ")";
            // BarBackdrop's fillet at the left edge: the corner (0, 0), the
            // arc around (r, r).
            ctx.fillStyle = rgba(fill);
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(r, 0);
            ctx.arc(r, r, r, -Math.PI / 2, Math.PI, true);
            ctx.closePath();
            ctx.fill();
            if (ink > 0) {
                const h = ink / 2;
                ctx.lineWidth = ink;
                ctx.strokeStyle = rgba(inkColour);
                ctx.beginPath();
                ctx.arc(r, r, r + h, Math.PI, 1.5 * Math.PI, false);
                ctx.stroke();
            }
        }
    }
}
