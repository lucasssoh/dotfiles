import QtQuick

// The notch style's strip along the screen edge, the central island hanging
// from it joined by concave fillets. The island's own pane draws the
// hanging part; this draws the strip on both sides and the fillets. With an
// `outline` (cartoon), the ink runs along each fillet's curve, where the
// island pane's own edge (cut short by `fillet`, see PaneEdge) takes over.
Item {
    id: band

    property bool fromBottom: false
    property real islandX: -1
    property real islandWidth: 0
    property real fillet: 8
    property real strip: 10
    property color notchColor: "black"
    property real outline: 0
    property color outlineColour: "black"

    onFromBottomChanged: notchCanvas.requestPaint()
    onWidthChanged: notchCanvas.requestPaint()
    onHeightChanged: notchCanvas.requestPaint()
    onFilletChanged: notchCanvas.requestPaint()
    onIslandXChanged: notchCanvas.requestPaint()
    onIslandWidthChanged: notchCanvas.requestPaint()
    onStripChanged: notchCanvas.requestPaint()
    onNotchColorChanged: notchCanvas.requestPaint()
    onOutlineChanged: notchCanvas.requestPaint()
    onOutlineColourChanged: notchCanvas.requestPaint()

    Canvas {
        id: notchCanvas
        anchors.fill: parent
        onVisibleChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width <= 0 || height <= 0)
                return;
            if (band.fromBottom) {
                ctx.translate(0, height);
                ctx.scale(1, -1);
            }
            const s = Math.min(band.strip, height);
            const r = Math.max(0, Math.min(band.fillet, height - s));
            const left = band.islandX;
            const right = left + band.islandWidth;
            const nc = band.notchColor;
            ctx.fillStyle = "rgba(" + Math.round(nc.r * 255) + "," + Math.round(nc.g * 255) + "," + Math.round(nc.b * 255) + "," + nc.a + ")";
            if (band.islandWidth <= 0 || left < 0) {
                ctx.fillRect(0, 0, width, s);
                return;
            }
            ctx.fillRect(0, 0, left, s);
            ctx.fillRect(right, 0, width - right, s);
            if (r > 0) {
                ctx.beginPath();
                // 1 px under the island's pane, so no seam shows between.
                ctx.moveTo(left - r, s);
                ctx.lineTo(left + 1, s);
                ctx.lineTo(left + 1, s + r);
                ctx.lineTo(left, s + r);
                ctx.arc(left - r, s + r, r, 0, -Math.PI / 2, true);
                ctx.closePath();
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(right + r, s);
                ctx.lineTo(right - 1, s);
                ctx.lineTo(right - 1, s + r);
                ctx.lineTo(right, s + r);
                ctx.arc(right + r, s + r, r, Math.PI, 3 * Math.PI / 2, false);
                ctx.closePath();
                ctx.fill();

                const w = band.outline;
                if (w > 0) {
                    const h = w / 2;
                    const oc = band.outlineColour;
                    ctx.lineWidth = w;
                    ctx.strokeStyle = "rgba(" + Math.round(oc.r * 255) + "," + Math.round(oc.g * 255) + "," + Math.round(oc.b * 255) + "," + oc.a + ")";
                    ctx.beginPath();
                    ctx.arc(left - r, s + r, r + h, 0, -Math.PI / 2, true);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(right + r, s + r, r + h, Math.PI, 3 * Math.PI / 2, false);
                    ctx.stroke();
                }
            }
        }
    }

}
