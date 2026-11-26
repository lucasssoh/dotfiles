import QtQuick

// What sits behind the bar's blocks, from bar.json: the bar's own surface
// (solid), and over it the side blocks' shapes (island, notch, pill) in
// their own colour. Drawn from the screen edge down; flipped for a bottom
// bar. With an `outline` (cartoon), the ink follows each shape's edge
// where it meets the desktop: the concave corners, the notch's S, the
// rounded ends. Never along the screen edge itself.
Item {
    id: root

    property bool fromBottom: false
    property bool solid: false
    property string sides: "none"
    property real band: 31            // the bar's height
    property real corner: 18          // solid: the concave corners under it
    property real fillet: 18          // notch: the joint with the screen edge
    property real radius: 18          // notch: the rounded inner corners
    property color barColour: "black" // the top level's fill
    property color sideColour: "black" // the sides zone's fill
    // The side groups' extent, in this item's x.
    property real leftEnd: 0
    property real rightStart: 0
    property real outline: 0
    property color outlineColour: "black"
    // A side sheet open under that side (modules/SideSheet.qml): the side
    // widens to the sheet's width if it is narrower, and runs straight
    // down into it instead of closing on a rounded corner.
    property bool extendLeft: false
    property bool extendRight: false
    property real sheetMinWidth: 440

    readonly property bool active: root.solid || root.sides !== "none"
    visible: root.active

    function repaint() { canvas.requestPaint(); }
    onFromBottomChanged: repaint()
    onSolidChanged: repaint()
    onSidesChanged: repaint()
    onBandChanged: repaint()
    onCornerChanged: repaint()
    onFilletChanged: repaint()
    onRadiusChanged: repaint()
    onBarColourChanged: repaint()
    onSideColourChanged: repaint()
    onLeftEndChanged: repaint()
    onRightStartChanged: repaint()
    onOutlineChanged: repaint()
    onExtendLeftChanged: repaint()
    onExtendRightChanged: repaint()
    onOutlineColourChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onVisibleChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.active || width <= 0 || height <= 0)
                return;
            if (root.fromBottom) {
                ctx.translate(0, height);
                ctx.scale(1, -1);
            }
            function rgba(c) {
                return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                    + Math.round(c.b * 255) + "," + c.a + ")";
            }
            const H = root.band;
            const W = width;
            const notch = root.sides === "notch";
            const xl = root.extendLeft && notch, xr = root.extendRight && notch;
            const L = xl ? Math.max(root.leftEnd, root.sheetMinWidth) : root.leftEnd;
            const R = xr ? Math.min(root.rightStart, W - root.sheetMinWidth) : root.rightStart;
            const innerR = Math.max(0, Math.min(root.radius, H / 2));

            // A concave corner hanging from (x, y), opening toward +dir.
            // It reaches 1 px back over what it joins: two antialiased
            // edges meeting exactly at x let the wallpaper through.
            function fillet(x, y, r, dir) {
                ctx.beginPath();
                ctx.moveTo(x - dir, y);
                ctx.lineTo(x + dir * r, y);
                if (dir > 0)
                    ctx.arc(x + r, y + r, r, -Math.PI / 2, Math.PI, true);
                else
                    ctx.arc(x - r, y + r, r, -Math.PI / 2, 0, false);
                ctx.lineTo(x - dir, y + r);
                ctx.closePath();
                ctx.fill();
            }
            // A rectangle with its own radius at each corner.
            function rect(x0, y0, x1, y1, tl, tr, br, bl) {
                ctx.beginPath();
                ctx.moveTo(x0 + tl, y0);
                ctx.lineTo(x1 - tr, y0);
                if (tr > 0) ctx.arc(x1 - tr, y0 + tr, tr, -Math.PI / 2, 0, false);
                ctx.lineTo(x1, y1 - br);
                if (br > 0) ctx.arc(x1 - br, y1 - br, br, 0, Math.PI / 2, false);
                ctx.lineTo(x0 + bl, y1);
                if (bl > 0) ctx.arc(x0 + bl, y1 - bl, bl, Math.PI / 2, Math.PI, false);
                ctx.lineTo(x0, y0 + tl);
                if (tl > 0) ctx.arc(x0 + tl, y0 + tl, tl, Math.PI, 3 * Math.PI / 2, false);
                ctx.closePath();
                ctx.fill();
            }

            if (root.solid) {
                ctx.fillStyle = rgba(root.barColour);
                ctx.fillRect(0, 0, W, H);
                fillet(0, H, root.corner, 1);
                fillet(W, H, root.corner, -1);
            }

            // The sides zone, on top of the bar (or on the band alone).
            if (root.sides !== "none") {
                ctx.fillStyle = rgba(root.sideColour);
                if (root.sides === "notch") {
                    rect(0, 0, L, H, 0, 0, xl ? 0 : innerR, 0);
                    rect(R, 0, W, H, 0, 0, 0, xr ? 0 : innerR);
                    // On a solid bar the side shapes reach the screen edges,
                    // so they have to carry the same concave descent under
                    // those edges as the bar itself, in the sides' own colour.
                    // Not over a sheet, which carries the side down instead.
                    if (root.solid) {
                        if (!xl) fillet(0, H, root.corner, 1);
                        if (!xr) fillet(W, H, root.corner, -1);
                    }
                    fillet(L, 0, root.fillet, 1);
                    fillet(R, 0, root.fillet, -1);
                } else {
                    const r = root.sides === "pill" ? (H - 4) / 2 : innerR;
                    rect(2, 2, L, H - 2, r, r, r, r);
                    rect(R, 2, W - 2, H - 2, r, r, r, r);
                }
            }

            // ---- the ink ---------------------------------------------------
            // Each line runs half inside its shape: same centres as the
            // fills, with edges and radii moved by h.
            const w = root.outline;
            if (w <= 0)
                return;
            const h = w / 2;
            const c = root.corner;
            ctx.lineWidth = w;
            ctx.lineJoin = "round";
            ctx.strokeStyle = rgba(root.outlineColour);

            // A solid band that shows: its lower edge, concave at both ends.
            const bandShows = root.solid && root.barColour.a > 0.02;
            if (bandShows) {
                ctx.beginPath();
                if (xl) ctx.moveTo(L, H - h);
                else ctx.arc(c, H + c, c + h, Math.PI, 1.5 * Math.PI, false);
                if (xr) ctx.lineTo(R, H - h);
                else ctx.arc(W - c, H + c, c + h, 1.5 * Math.PI, 2 * Math.PI, false);
                ctx.stroke();
            }

            // The side shapes, unless they melt into a band of their colour.
            if (root.sides === "none" || root.sideColour.a <= 0.02
                    || (bandShows && Qt.colorEqual(root.barColour, root.sideColour)))
                return;
            if (root.sides === "notch") {
                // The left group, from the screen edge to the S that joins
                // the top edge; the right one is the same path mirrored.
                const notchSide = (end, extended) => {
                    const f = root.fillet;
                    ctx.beginPath();
                    if (extended) {
                        // Straight down into the sheet, whose line goes on.
                        ctx.moveTo(end - h, H + 1);
                        ctx.lineTo(end - h, f);
                        ctx.arc(end + f, f, f + h, Math.PI, 1.5 * Math.PI, false);
                        ctx.stroke();
                        return;
                    }
                    if (root.solid)
                        ctx.arc(c, H + c, c + h, Math.PI, 1.5 * Math.PI, false);
                    else
                        ctx.moveTo(0, H - h);
                    ctx.lineTo(end - innerR, H - h);
                    if (innerR > h)
                        ctx.arc(end - innerR, H - innerR, innerR - h, Math.PI / 2, 0, true);
                    ctx.lineTo(end - h, f);
                    ctx.arc(end + f, f, f + h, Math.PI, 1.5 * Math.PI, false);
                    ctx.stroke();
                };
                notchSide(L, xl);
                ctx.save();
                ctx.translate(W, 0);
                ctx.scale(-1, 1);
                notchSide(W - R, xr);
                ctx.restore();
            } else {
                const r = Math.max(0, (root.sides === "pill" ? (H - 4) / 2 : innerR) - h);
                for (const [x0, x1] of [[2, L], [R, W - 2]]) {
                    ctx.beginPath();
                    ctx.roundedRect(x0 + h, 2 + h, x1 - x0 - w, H - 4 - w, r, r);
                    ctx.stroke();
                }
            }
        }
    }
}
