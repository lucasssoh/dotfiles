import QtQuick
import "../theme"
import "../services"

// The band's veil: one density per profile slice across the screen
// (BarInk.veils), full behind the text, then fading out over the next
// 74 px instead of stopping on a hard line ("la coupure nette n'est pas
// forcément très élégante").
//
// A Canvas rather than a Rectangle gradient: a QML Gradient takes a fixed
// list of stops, and this one has a stop per slice (64), in a colour that
// moves between the dark and the light veil with the ink. It is painted
// only when the decision changes -- a new wallpaper, or a block resizing
// over a different stretch -- and while the veil eases to the new one;
// the rest of the time it is a plain texture.
Canvas {
    id: band

    // BarInk: its `veils` and its `t` (0 = light text over a dark veil,
    // 1 = dark text over a light one).
    property QtObject ink: null
    // Which screen edge the band hangs from.
    property bool fromBottom: false
    // Full veil from the edge over this much, then the fade.
    property int solid: 26

    property var fromVeils: []
    property var toVeils: []
    property real progress: 1

    NumberAnimation {
        id: ease
        target: band; property: "progress"
        from: 0; to: 1
        duration: 900; easing.type: Easing.InOutQuad
    }

    function shown() {
        const to = band.toVeils, from = band.fromVeils;
        if (from.length !== to.length || band.progress >= 1) return to;
        return to.map((v, i) => from[i] + (v - from[i]) * band.progress);
    }

    function adopt() {
        if (!band.ink) return;
        const next = band.ink.veils ? band.ink.veils.slice() : [];
        band.fromVeils = band.toVeils.length === next.length ? band.shown() : next;
        band.toVeils = next;
        ease.restart();
    }

    Connections {
        target: band.ink
        function onVeilsChanged() { band.adopt(); }
        function onTChanged() { band.requestPaint(); }
    }
    Component.onCompleted: {
        if (band.ink) band.toVeils = band.ink.veils.slice();
        band.requestPaint();
    }
    onProgressChanged: band.requestPaint()
    onWidthChanged: band.requestPaint()
    onHeightChanged: band.requestPaint()
    onFromBottomChanged: band.requestPaint()

    onPaint: {
        const ctx = band.getContext("2d");
        ctx.reset();
        const veils = band.shown();
        const n = veils.length;
        if (!n || band.width <= 0 || band.height <= 0) return;

        const t = band.ink ? band.ink.t : 0;
        const dark = BandTint.band, light = BandTint.lightBand;
        const r = Math.round(255 * (dark.r + (light.r - dark.r) * t));
        const g = Math.round(255 * (dark.g + (light.g - dark.g) * t));
        const b = Math.round(255 * (dark.b + (light.b - dark.b) * t));
        const a = dark.a + (light.a - dark.a) * t;

        const across = ctx.createLinearGradient(0, 0, band.width, 0);
        for (let i = 0; i < n; i++)
            across.addColorStop((i + 0.5) / n, "rgba(" + r + "," + g + "," + b + "," + (a * veils[i]).toFixed(4) + ")");
        ctx.fillStyle = across;
        ctx.fillRect(0, 0, band.width, band.height);

        // The fade, eased: kept where the mask is opaque, gone where clear.
        const h = band.height;
        const down = ctx.createLinearGradient(0, band.fromBottom ? h : 0, 0, band.fromBottom ? 0 : h);
        const s = band.solid / h;
        const stops = [[0, 1], [s, 1], [s + 0.08, 0.9], [s + 0.20, 0.7], [s + 0.34, 0.45],
                       [s + 0.50, 0.22], [s + 0.64, 0.07], [1, 0]];
        for (const st of stops)
            down.addColorStop(Math.min(1, st[0]), "rgba(0,0,0," + st[1] + ")");
        ctx.globalCompositeOperation = "destination-in";
        ctx.fillStyle = down;
        ctx.fillRect(0, 0, band.width, band.height);
        ctx.globalCompositeOperation = "source-over";
    }
}
