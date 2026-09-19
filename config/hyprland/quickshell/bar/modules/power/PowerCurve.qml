import QtQuick
import "../../theme"

// The charge history chart: battery level over time, on a fixed 0-100
// axis, with the line coloured by what the battery was doing -- blue
// while it was running down, green while it was charging.
//
// It replaced a watts sparkline, and the axis is the reason. Watts have
// no natural ceiling, so the scale was set by whatever the tallest spike
// in the window happened to be, which made two windows of the same
// machine incomparable and put a "pic 41 W" label on a chart that was
// meant to be about consumption. Percent is bounded by definition: 0 is
// the bottom, 100 is the top, the gridlines mean the same thing in every
// window, and a glance at the slope is a glance at how fast the machine
// is draining.
//
// Layout: the plot occupies the left of this item and the % labels sit in
// a reserved strip on the right (`labelStrip`), with the time labels in
// their own row underneath. Drawing the labels as real Text rather than
// inside the Canvas is deliberate -- a Canvas rasterises text into its
// own FBO, where it would not match the NativeRendering glyphs used
// everywhere else in this drawer.
//
// Cost: the Canvas repaints when the data changes, which is at most every
// 30s and only while the drawer is open. Hover does NOT repaint it -- the
// crosshair, the dot and the bubble are plain QML items layered on top,
// so moving the pointer across the chart moves three rectangles and
// changes one string.
Item {
    id: root

    // [{ t, pct, s }, ...] oldest first -- PowerState.samples as-is.
    property var samples: []
    // Axis bounds in epoch seconds. Not derived from the samples: the
    // right edge is NOW, so a sparse series does not make the curve
    // creep rightwards between refreshes.
    property real axisStart: 0
    property real axisEnd: 0
    // Seconds between two samples past which they are NOT joined -- see
    // PowerState.gapSeconds.
    property int gapSeconds: 3600

    // Same two tokens the rest of the bar already uses for these states:
    // BatteryIcon's charging green, and the sky blue Battery.qml picked
    // for "charging under the conservation cap". Deliberately NOT the
    // saturated blue/green of a phone's battery screen -- this drawer is
    // greyed glass, and two fully saturated primaries in it would read as
    // a different application.
    readonly property color dischargeColor: "#8ecae6"
    readonly property color chargeColor: Ink.positive

    // Room on the right for "100%". Everything that draws inside the plot
    // measures against plotWidth, never width.
    readonly property int labelStrip: 34
    readonly property int plotHeight: 112
    readonly property int timeStrip: 14
    // Vertical breathing room so the 100% line and an endpoint dot on it
    // are not clipped by the item's own edge.
    readonly property int padV: 5

    readonly property real plotWidth: Math.max(0, width - labelStrip)
    readonly property real span: Math.max(1, root.axisEnd - root.axisStart)

    implicitHeight: plotHeight + 4 + timeStrip

    readonly property bool hasData: root.samples.length >= 2 && root.plotWidth > 0

    function xOf(t) { return ((t - root.axisStart) / root.span) * root.plotWidth; }
    function yOf(pct) {
        const usable = root.plotHeight - 2 * root.padV;
        return root.padV + (1 - Math.max(0, Math.min(100, pct)) / 100) * usable;
    }

    onSamplesChanged: canvas.requestPaint()
    onAxisStartChanged: canvas.requestPaint()
    onAxisEndChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    // ---------------------------------------------------------------
    // horizontal gridlines + % labels
    // ---------------------------------------------------------------

    Repeater {
        model: [0, 25, 50, 75, 100]

        Item {
            required property int modelData
            anchors.left: parent.left
            anchors.right: parent.right
            y: root.yOf(modelData)
            height: 1

            Rectangle {
                width: root.plotWidth
                height: 1
                // 0 and 100 are the frame of the chart, the three between
                // them are only a reading aid -- drawn fainter so the
                // curve stays the most contrasted thing in the block.
                color: (parent.modelData === 0 || parent.modelData === 100)
                    ? Qt.rgba(1, 1, 1, 0.13)
                    : Qt.rgba(1, 1, 1, 0.06)
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: root.plotWidth + 6
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: parent.modelData + "%"
                color: Ink.muted
                font.family: Fonts.ui
                font.pixelSize: 9
            }
        }
    }

    // ---------------------------------------------------------------
    // the curve
    // ---------------------------------------------------------------

    Canvas {
        id: canvas
        x: 0
        y: 0
        width: root.plotWidth
        height: root.plotHeight
        // Threaded rendering would hand the paint to another thread and
        // back for a repaint that happens twice a minute -- the handoff
        // costs more than the drawing does.
        renderStrategy: Canvas.Immediate
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.reset();
            if (!root.hasData) return;

            const pts = root.samples;
            const n = pts.length;
            const h = canvas.height;

            // Walk the series once, cutting it into runs that share a
            // DIRECTION (see PowerState's `up`) and are not separated by
            // a gap. Each run starts on the PREVIOUS point, so
            // consecutive runs share their boundary sample and the
            // colours meet with no seam between them: the segment
            // leading into a charge is already green.
            const segs = [];
            let cur = null;
            for (let i = 1; i < n; i++) {
                if (pts[i].t - pts[i - 1].t > root.gapSeconds) {
                    // A suspend or a shutdown. Nothing is known about
                    // what happened in between, so nothing is drawn
                    // across it.
                    cur = null;
                    continue;
                }
                if (cur === null || cur.up !== pts[i].up) {
                    cur = { up: pts[i].up, idx: [i - 1, i] };
                    segs.push(cur);
                } else {
                    cur.idx.push(i);
                }
            }

            for (const seg of segs) {
                const c = seg.up ? root.chargeColor : root.dischargeColor;
                const idx = seg.idx;

                // ---- area under this run ----
                ctx.beginPath();
                ctx.moveTo(root.xOf(pts[idx[0]].t), root.yOf(pts[idx[0]].pct));
                for (let k = 1; k < idx.length; k++)
                    ctx.lineTo(root.xOf(pts[idx[k]].t), root.yOf(pts[idx[k]].pct));
                ctx.lineTo(root.xOf(pts[idx[idx.length - 1]].t), h);
                ctx.lineTo(root.xOf(pts[idx[0]].t), h);
                ctx.closePath();

                const grad = ctx.createLinearGradient(0, 0, 0, h);
                grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.30));
                grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.02));
                ctx.fillStyle = grad;
                ctx.fill();

                // ---- line on top ----
                ctx.beginPath();
                ctx.moveTo(root.xOf(pts[idx[0]].t), root.yOf(pts[idx[0]].pct));
                for (let k = 1; k < idx.length; k++)
                    ctx.lineTo(root.xOf(pts[idx[k]].t), root.yOf(pts[idx[k]].pct));
                ctx.strokeStyle = c;
                ctx.lineWidth = 1.6;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.stroke();
            }

            // ---- the two ends ----
            // Marks where the window's data actually begins and ends,
            // which on a sparse series is not the same as where the plot
            // begins and ends -- without them a curve that starts two
            // hours into a 24h window looks like a rendering bug.
            const ends = [pts[0], pts[n - 1]];
            for (const p of ends) {
                ctx.beginPath();
                ctx.arc(root.xOf(p.t), root.yOf(p.pct), 3.2, 0, 2 * Math.PI);
                ctx.fillStyle = p.up ? root.chargeColor : root.dischargeColor;
                ctx.fill();
            }
        }
    }

    // ---------------------------------------------------------------
    // hover: crosshair, dot, bubble
    // ---------------------------------------------------------------

    // Index into `samples` of the point nearest the pointer, or -1.
    property int hoverIndex: -1
    readonly property var hoverPoint: (root.hoverIndex >= 0 && root.hoverIndex < root.samples.length)
        ? root.samples[root.hoverIndex] : null

    // A day is only worth printing when the window spans more than one.
    readonly property bool hoverShowsDate: root.span > 86400 * 1.2

    // Spelled out here rather than taken from Qt.formatDateTime's "MMM",
    // which renders in the APPLICATION's locale -- this session runs
    // under fr_FR, so that would put "sept." on an axis every other
    // label of which is English. A literal table is the only way the
    // date reads the same as the rest of the drawer on any machine.
    readonly property var monthNames: [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]
    function dayLabel(d) { return root.monthNames[d.getMonth()] + " " + d.getDate(); }

    function _nearest(px) {
        const n = root.samples.length;
        if (n === 0) return -1;
        // Nearest in TIME, not in index: the series is sparse and
        // unevenly spaced, so an index search would snap to the wrong
        // side of a long flat stretch.
        const t = root.axisStart + (px / root.plotWidth) * root.span;
        let best = 0;
        let bestD = Math.abs(root.samples[0].t - t);
        for (let i = 1; i < n; i++) {
            const d = Math.abs(root.samples[i].t - t);
            if (d < bestD) { bestD = d; best = i; }
        }
        return best;
    }

    MouseArea {
        id: hover
        x: 0
        y: 0
        width: root.plotWidth
        height: root.plotHeight
        hoverEnabled: true
        // No click behaviour: this must not swallow the outside-click
        // that closes the drawer, nor look like a button.
        acceptedButtons: Qt.NoButton
        onPositionChanged: (mouse) => { root.hoverIndex = root._nearest(mouse.x); }
        onExited: root.hoverIndex = -1
    }

    Rectangle {
        id: crosshair
        visible: root.hoverPoint !== null
        width: 1
        y: 0
        height: root.plotHeight
        x: root.hoverPoint ? root.xOf(root.hoverPoint.t) : 0
        color: Qt.rgba(1, 1, 1, 0.22)
    }

    Rectangle {
        id: hoverDot
        visible: root.hoverPoint !== null
        width: 7
        height: 7
        radius: 3.5
        x: (root.hoverPoint ? root.xOf(root.hoverPoint.t) : 0) - 3.5
        y: (root.hoverPoint ? root.yOf(root.hoverPoint.pct) : 0) - 3.5
        color: root.hoverPoint && root.hoverPoint.up ? root.chargeColor : root.dischargeColor
        border.width: 1.5
        border.color: Surfaces.cardDeep
    }

    Rectangle {
        id: bubble
        visible: root.hoverPoint !== null
        // Sits at the top of the plot, out of the way of a curve that
        // spends most of its time in the upper half -- the same place a
        // phone's battery graph puts it.
        y: 2
        width: bubbleText.implicitWidth + 16
        height: 20
        radius: 10
        color: Surfaces.accentStrongest
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        // Centred on the crosshair, then clamped so it never hangs off
        // either end of the plot.
        x: {
            if (!root.hoverPoint) return 0;
            const want = root.xOf(root.hoverPoint.t) - width / 2;
            return Math.max(0, Math.min(root.plotWidth - width, want));
        }

        Text {
            id: bubbleText
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: {
                if (!root.hoverPoint) return "";
                const d = new Date(root.hoverPoint.t * 1000);
                const clock = Qt.formatDateTime(d, "HH:mm");
                const when = root.hoverShowsDate ? root.dayLabel(d) + " " + clock : clock;
                return when + "  ·  " + Math.round(root.hoverPoint.pct) + "%";
            }
            color: Ink.primary
            font.family: Fonts.ui
            font.pixelSize: 10
            font.bold: true
        }
    }

    // ---------------------------------------------------------------
    // time axis
    // ---------------------------------------------------------------

    // Tick spacing, picked as the smallest candidate that keeps the row
    // under eight labels -- past that they collide at this width.
    readonly property int tickStep: {
        const candidates = [900, 1800, 3600, 7200, 10800, 21600, 43200, 86400, 172800];
        for (const c of candidates) if (root.span / c <= 7) return c;
        return 172800;
    }

    // Hard ceiling on how many labels this Repeater can ever be asked
    // for. Belt to PowerState's braces: that file now orders its axis
    // assignments so the pathological span cannot occur, but a `while`
    // loop that trusts its bounds is one bad input away from taking the
    // whole shell down -- which is exactly what happened here (104% CPU,
    // 4.5GB RSS, every IPC call hung, killed by hand). Bounded by
    // construction, no input can do it again.
    readonly property int maxTicks: 10

    readonly property var ticks: {
        const out = [];
        const step = root.tickStep;
        if (step <= 0 || root.plotWidth <= 0 || root.axisEnd <= root.axisStart) return out;
        // Aligned to the wall clock rather than to the window's own start,
        // so the labels land on round hours instead of on "11:43".
        // getTimezoneOffset is what keeps that true off UTC.
        const offset = new Date().getTimezoneOffset() * 60;
        let t = Math.ceil((root.axisStart - offset) / step) * step + offset;
        for (let i = 0; i < root.maxTicks && t <= root.axisEnd; i++) {
            out.push(t);
            t += step;
        }
        return out;
    }

    Item {
        id: timeAxis
        x: 0
        y: root.plotHeight + 4
        width: root.plotWidth
        height: root.timeStrip

        Repeater {
            model: root.ticks

            Text {
                required property var modelData
                readonly property real cx: root.xOf(modelData)
                // Centred on its tick, then nudged in at the two ends so
                // the first and last labels stay inside the plot instead
                // of hanging over the drawer's padding.
                x: Math.max(0, Math.min(timeAxis.width - implicitWidth, cx - implicitWidth / 2))
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                // Midnight carries the date, everything else just the
                // clock -- which is what makes a 3-day axis readable
                // without a label wide enough to collide with its
                // neighbour.
                text: {
                    const d = new Date(modelData * 1000);
                    if (root.tickStep >= 3600 && d.getHours() === 0) return root.dayLabel(d);
                    return Qt.formatDateTime(d, "HH:mm");
                }
                color: Ink.muted
                font.family: Fonts.ui
                font.pixelSize: 9
            }
        }
    }

    // Shown in place of the curve until the first GetHistory lands, and
    // on a battery with no stored history at all.
    Text {
        x: root.plotWidth / 2 - implicitWidth / 2
        y: root.plotHeight / 2 - implicitHeight / 2
        visible: !root.hasData
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: "no data yet"
        color: Ink.muted
        font.family: Fonts.ui
        font.pixelSize: 11
    }
}
