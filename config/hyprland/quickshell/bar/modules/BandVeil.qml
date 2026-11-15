import QtQuick
import "../theme"
import "../services"

// The band's veil: one density per profile slice across the screen
// (BarInk.veils), full behind the text, then fading out over the next
// 44 px instead of stopping on a hard line ("la coupure nette n'est pas
// forcément très élégante").
//
// Canvases rather than a Rectangle gradient: a QML Gradient takes a fixed
// list of stops, and this one has a stop per slice (64), dark or light
// with the ink.
//
// Each state is painted ONCE, in its final colour, and a new one replaces
// the old by a cross-fade of two canvases -- opacity only, done by the
// GPU. Repainting the 1920 px canvas on every frame of the change, while
// awww was fading the wallpaper under it, stalled the whole output for a
// few frames mid-fade.
Item {
    id: band

    // BarInk: its `veils` and its `lightText`.
    property QtObject ink: null
    // Which screen edge the band hangs from.
    property bool fromBottom: false
    // Full veil from the edge over this much, then the fade.
    property int solid: 26

    // Which canvas holds the current state.
    property bool frontIsA: true
    readonly property Canvas front: band.frontIsA ? canvasA : canvasB
    readonly property Canvas back: band.frontIsA ? canvasB : canvasA

    function adopt() {
        if (!band.ink) return;
        // A change landing mid-fade: finish that fade first, so the
        // canvas painted next is never one still on screen.
        if (fade.running) {
            fade.stop();
            band.front.opacity = 1;
            band.back.opacity = 0;
        }
        const target = band.back;
        target.veils = band.ink.veils ? band.ink.veils.slice() : [];
        target.lightText = band.ink.lightText;
        target.pending = true;
        target.requestPaint();
    }
    // The new state is on the back canvas: fade it in over the old one.
    function swap() {
        fade.stop();
        band.frontIsA = !band.frontIsA;
        if (BandTint.transition <= 0) {
            band.front.opacity = 1;
            band.back.opacity = 0;
            return;
        }
        fade.start();
    }

    ParallelAnimation {
        id: fade
        NumberAnimation {
            target: band.front; property: "opacity"; to: 1
            duration: BandTint.transition
            easing.type: Easing.BezierSpline; easing.bezierCurve: BandTint.transitionCurve
        }
        NumberAnimation {
            target: band.back; property: "opacity"; to: 0
            duration: BandTint.transition
            easing.type: Easing.BezierSpline; easing.bezierCurve: BandTint.transitionCurve
        }
    }

    Connections {
        target: band.ink
        function onVeilsChanged() { band.adopt(); }
        function onLightTextChanged() { band.adopt(); }
    }
    Component.onCompleted: {
        canvasA.opacity = 1;
        canvasB.opacity = 0;
        if (band.ink) {
            canvasA.veils = band.ink.veils.slice();
            canvasA.lightText = band.ink.lightText;
        }
        canvasA.requestPaint();
    }
    onWidthChanged: { canvasA.requestPaint(); canvasB.requestPaint(); }
    onHeightChanged: { canvasA.requestPaint(); canvasB.requestPaint(); }
    onFromBottomChanged: { canvasA.requestPaint(); canvasB.requestPaint(); }

    component VeilCanvas: Canvas {
        id: canvas
        anchors.fill: parent
        property var veils: []
        property bool lightText: true
        // Set when a new state is painted here, to swap once it is drawn.
        property bool pending: false

        onPainted: {
            if (canvas.pending) {
                canvas.pending = false;
                band.swap();
            }
        }
        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.reset();
            const veils = canvas.veils;
            const n = veils.length;
            if (!n || canvas.width <= 0 || canvas.height <= 0) return;

            const c = canvas.lightText ? BandTint.band : BandTint.lightBand;
            const r = Math.round(255 * c.r), g = Math.round(255 * c.g), b = Math.round(255 * c.b);
            const across = ctx.createLinearGradient(0, 0, canvas.width, 0);
            for (let i = 0; i < n; i++)
                across.addColorStop((i + 0.5) / n, "rgba(" + r + "," + g + "," + b + "," + (c.a * veils[i]).toFixed(4) + ")");
            ctx.fillStyle = across;
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            // The fade, eased over whatever is left past the solid part:
            // kept where the mask is opaque, gone where clear.
            const h = canvas.height;
            const down = ctx.createLinearGradient(0, band.fromBottom ? h : 0, 0, band.fromBottom ? 0 : h);
            const s = band.solid / h, k = 1 - s;
            const stops = [[0, 1], [s, 1], [s + 0.11 * k, 0.9], [s + 0.27 * k, 0.7], [s + 0.46 * k, 0.45],
                           [s + 0.68 * k, 0.22], [s + 0.86 * k, 0.07], [1, 0]];
            for (const st of stops)
                down.addColorStop(Math.min(1, st[0]), "rgba(0,0,0," + st[1] + ")");
            ctx.globalCompositeOperation = "destination-in";
            ctx.fillStyle = down;
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            ctx.globalCompositeOperation = "source-over";
        }
    }

    VeilCanvas { id: canvasA }
    VeilCanvas { id: canvasB }
}
