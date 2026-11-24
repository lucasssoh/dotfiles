import QtQuick

// What sits behind the bar's blocks, from bar.json: the bar's own surface
// (solid), and over it the side blocks' shapes (island, notch, pill) in
// their own colour. Drawn from the screen edge down; flipped for a bottom
// bar.
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
            const innerR = Math.max(0, Math.min(root.radius, H / 2));

            // A concave corner hanging from (x, y), opening toward +dir.
            function fillet(x, y, r, dir) {
                ctx.beginPath();
                ctx.moveTo(x, y);
                ctx.lineTo(x + dir * r, y);
                if (dir > 0)
                    ctx.arc(x + r, y + r, r, -Math.PI / 2, Math.PI, true);
                else
                    ctx.arc(x - r, y + r, r, -Math.PI / 2, 0, false);
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
                if (root.sides === "none") return;
            }

            // The sides zone, on top of the bar (or on the band alone).
            ctx.fillStyle = rgba(root.sideColour);
            const L = root.leftEnd, R = root.rightStart;
            if (root.sides === "notch") {
                rect(0, 0, L, H, 0, 0, innerR, 0);
                rect(R, 0, W, H, 0, 0, 0, innerR);
                // On a solid bar the side shapes reach the screen edges,
                // so they have to carry the same concave descent under
                // those edges as the bar itself, in the sides' own colour.
                if (root.solid) {
                    fillet(0, H, root.corner, 1);
                    fillet(W, H, root.corner, -1);
                }
                fillet(L, 0, root.fillet, 1);
                fillet(R, 0, root.fillet, -1);
            } else {
                const r = root.sides === "pill" ? (H - 4) / 2 : innerR;
                rect(2, 2, L, H - 2, r, r, r, r);
                rect(R, 2, W - 2, H - 2, r, r, r, r);
            }
        }
    }
}
