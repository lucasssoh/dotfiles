pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reader for hypr/scripts/bar-tint.py's luminance profile.
//
// The daemon samples the strip behind the bar and writes N buckets of
// mean colour across each monitor's width. It deliberately stops there:
// it knows pixels, this file knows layout. The split matters because the
// islands RESIZE -- metrics and tools follow their content, launchers
// follows the running apps -- so an island that moved would otherwise
// have to wake the daemon for a picture that had not changed. Here, a
// resize is just a different slice of the same buckets.
//
// Transport is a file, not `qs ipc call`. A file survives a quickshell
// restart (the bar re-reads it and is correct immediately, with nothing
// to re-push) and costs no subprocess spawn on either side. It is a
// regular file in ~/.cache specifically because Qt's FileView
// watchChanges is inotify-based -- OsdState.qml documents the case where
// that does NOT work, sysfs, which is kernfs and notified by
// poll()/uevent instead.
Singleton {
    id: root

    // ---- the bar's own fill -----------------------------------------
    // THE definition of the surface every contrast number below assumes.
    // It comes from bar.json's top level (the bar, not a zone): the same
    // material is drawn by the band in floating style and by the solid
    // bar, so the maths must read it here instead of a hard-coded value.
    // The default is the old near-black band at ~45 % -- it blocks less
    // than half of what is behind it, which is why this machinery exists.
    //
    // What moves per island is HOW MUCH veil goes under it: `veil`, 0 to
    // 1, scales this alpha. A calm wallpaper gets none; a busy or
    // high-contrast stretch gets exactly as much as its text needs --
    // see `decide` below.
    property color band: IslandStyle.barFill

    // The band at `veil` (0..1) of its full density.
    function bandFor(veil) {
        const k = Math.max(0, Math.min(1, veil));
        return Qt.rgba(root.band.r, root.band.g, root.band.b, root.band.a * k);
    }

    // ---- the profile -------------------------------------------------
    property var profile: null
    // How long the wallpaper's visible change lasts, in ms (bar-tint.py
    // --transition, from wallpaper-set), and its curve: the ink and the
    // veil ease over the same time, on the curve measured on awww's fade
    // (a symmetric S, half-way at half-time), so the band changes with
    // the image rather than after it. 0 is a cut.
    property int transition: 450
    readonly property var transitionCurve: [0.45, 0, 0.55, 1, 1, 1]
    readonly property bool ready: profile !== null
    property int seq: -1

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.cache/bar-tint.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.adopt(text())
    }

    function adopt(raw) {
        // The daemon writes the file in a single write(), but inotify can
        // still wake us mid-write in principle, so a parse failure is a
        // normal event and not an error: keep the previous profile and
        // wait for the next notification rather than blanking the bar.
        try {
            const d = JSON.parse(raw);
            if (!d || !d.monitors || d.seq === root.seq) return;
            // `profile` D'ABORD, `seq` ensuite. L'inverse a l'air
            // anodin et ne l'est pas: c'est `seqChanged` qui declenche le
            // recalcul du materiau cote shell.qml, donc publier seq en
            // premier fait tourner ce calcul sur l'ANCIEN profil, et plus
            // rien ne le relance ensuite. Trouve a l'ecran: la barre
            // restait claire sur un profil sombre.
            // `transition` avant les deux: ce qui reagit au profil anime
            // sur cette duree.
            root.transition = d.transition !== undefined ? d.transition : 450;
            root.profile = d.monitors;
            root.seq = d.seq;
        } catch (e) {
            // volontairement silencieux -- voir ci-dessus
        }
    }

    // ---- sampling ----------------------------------------------------
    // Mean colour of the strip behind [x, x+w) on `monitor`, in the
    // monitor's own coordinates. Averaged in LINEAR light for the same
    // reason the daemon buckets that way: sRGB is not linear in light,
    // so averaging the encoded values darkens anything spanning a strong
    // edge.
    function toLinear(c) {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }
    function toSrgb(c) {
        return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(Math.max(0, c), 1 / 2.4) - 0.055;
    }

    function backgroundAt(monitor, x, w) {
        if (!root.profile || !root.profile[monitor]) return null;
        const m = root.profile[monitor];
        const cells = m.cells;
        const n = cells.length;
        if (!n || w <= 0) return null;
        // Buckets overlapping [x, x+w), clamped -- an island briefly wider
        // than the screen during a layout pass must not index past the end.
        let i0 = Math.floor((x / m.width) * n);
        let i1 = Math.ceil(((x + w) / m.width) * n);
        i0 = Math.max(0, Math.min(n - 1, i0));
        i1 = Math.max(i0 + 1, Math.min(n, i1));
        let r = 0, g = 0, b = 0;
        for (let i = i0; i < i1; i++) {
            r += root.toLinear(cells[i][0] / 255);
            g += root.toLinear(cells[i][1] / 255);
            b += root.toLinear(cells[i][2] / 255);
        }
        const k = i1 - i0;
        return Qt.rgba(root.toSrgb(r / k), root.toSrgb(g / k), root.toSrgb(b / k), 1);
    }

    // ---- contrast ----------------------------------------------------
    function luminance(c) {
        return 0.2126 * root.toLinear(c.r) + 0.7152 * root.toLinear(c.g) + 0.0722 * root.toLinear(c.b);
    }
    function contrast(a, b) {
        const la = root.luminance(a), lb = root.luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    // Source-over of a translucent band onto an opaque background.
    function composite(band, behind) {
        const a = band.a;
        return Qt.rgba(a * band.r + (1 - a) * behind.r,
                       a * band.g + (1 - a) * behind.g,
                       a * band.b + (1 - a) * behind.b, 1);
    }

    // How much better the other ink must score before the island actually
    // switches. Without it a slideshow's crossfade walks the measurement
    // back and forth across the threshold and the bar strobes.
    //
    // Measured on the curve it actually rides, not guessed: the two inks
    // cross at wallpaper grey 201 (composite 116), both at 4.20:1, and
    // the gap opens by ~1.0 per 15 grey levels either side. So 1.0 leaves
    // a 29-level band around the crossover where nothing flips -- far
    // wider than a crossfade's own wobble, far narrower than the distance
    // between two real wallpapers.
    readonly property real switchMargin: 1.0

    // The legibility target every island is held to: WCAG AA for body
    // text, against the WORST pixel behind it (see `rangeAt`), not the
    // average.
    readonly property real target: 4.5

    // Darkest and brightest of what is behind [x, x+w), as two sRGB greys:
    // the lowest 10th and highest 90th luminance percentile across the
    // buckets it covers (bar-tint.py's `lo`/`hi`). Texture inside a bucket
    // and a gradient across the island both widen this range, and both
    // are what actually breaks one ink for the whole island. Falls back to
    // the bucket means on a profile written before `lo`/`hi` existed.
    function rangeAt(monitor, x, w) {
        if (!root.profile || !root.profile[monitor]) return null;
        const m = root.profile[monitor];
        const n = m.cells.length;
        if (!n || w <= 0) return null;
        let i0 = Math.max(0, Math.min(n - 1, Math.floor((x / m.width) * n)));
        let i1 = Math.max(i0 + 1, Math.min(n, Math.ceil(((x + w) / m.width) * n)));
        const los = [], his = [], local = [];
        for (let i = i0; i < i1; i++) {
            if (m.lo && m.hi) {
                los.push(m.lo[i]);
                his.push(m.hi[i]);
                local.push(root.lstar(m.hi[i]) - root.lstar(m.lo[i]));
            } else {
                const c = m.cells[i];
                const g = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
                los.push(g);
                his.push(g);
            }
        }
        // Robust across the island too, not just within a bucket: the
        // 10th percentile of the buckets' darks and the 90th of their
        // lights, not the single darkest and lightest. With plain min/max
        // one small patch decided for the whole island -- country-road's
        // right-hand tree, under the last three of ~20 buckets, forced
        // white text on a full band over bright sky, where it could never
        // be legible.
        los.sort((a, b) => a - b);
        his.sort((a, b) => a - b);
        const lo = los[Math.floor((los.length - 1) * 0.10)];
        const hi = his[Math.ceil((his.length - 1) * 0.90)];
        // Texture: how far apart dark and light are INSIDE a bucket (a
        // ~30px square of wallpaper), in L* -- the 75th percentile across
        // the island's buckets. Local on purpose: a smooth gradient spans
        // a wide range across the island but almost none within a bucket,
        // and one hard edge (a block of colour ending) moves only its own
        // bucket, not the percentile. Foliage, noise, busy photos move
        // most of them.
        local.sort((a, b) => a - b);
        const texture = local.length ? local[Math.floor((local.length - 1) * 0.75)] : 0;
        return { lo: Qt.rgba(lo / 255, lo / 255, lo / 255, 1),
                 hi: Qt.rgba(hi / 255, hi / 255, hi / 255, 1),
                 texture: texture };
    }

    // CIE L* (0-100) of an sRGB grey 0-255: perceived lightness, the scale
    // `texture` is measured on.
    function lstar(g) {
        const y = root.toLinear(g / 255);
        return y > 0.008856 ? 116 * Math.cbrt(y) - 16 : 903.3 * y;
    }

    // Texture thresholds, in L*, calibrated on the 87 cached wallpapers:
    // calm ones (flat, gradients, smooth photos) sit at 0-6; busy ones at
    // 15-75 (country-road's foliage at 46). Below `textureStart` texture
    // is ignored; above it, a dark veil can calm a busy stretch when white
    // text wins the contrast decision. Its density reaches full at
    // `textureFull`.
    readonly property real textureStart: 15
    readonly property real textureFull: 35

    // Which ink an island takes, and how much veil goes under it:
    // { ink: "dark" | "light", veil: 0..1 }. ("dark" is the dark MATERIAL,
    // i.e. white text; "light" is dark text -- the names Ink/InkLight use.)
    //
    // Contrast picks the ink before texture is considered. A dark veil can
    // calm a busy stretch and help white text, but it only hurts dark text;
    // texture must not force white text over a bright background.
    //
    // If both inks clear `target`, keep the better one with hysteresis. A
    // busy texture adds a veil only when white text wins. If neither ink
    // clears `target`, white text takes the smallest veil (in 5% steps)
    // that lifts its worst case over `target`.
    //
    // `current` is the caller's previous ink, where the hysteresis state
    // lives (a singleton cannot hold it for several islands).
    function decide(monitor, x, w, current, inkDark, inkLight) {
        const r = root.rangeAt(monitor, x, w);
        if (!r) return { ink: current || "dark", veil: 1 };
        const whiteAt = v => root.contrast(root.composite(root.bandFor(v), r.hi), inkDark);
        const darkBare = root.contrast(r.lo, inkLight);
        const whiteBare = whiteAt(0);
        const okDark = darkBare >= root.target, okWhite = whiteBare >= root.target;
        const textureVeil = r.texture >= root.textureStart
            ? 0.35 + 0.65 * Math.min(1, (r.texture - root.textureStart) / (root.textureFull - root.textureStart))
            : 0;
        const whiteVeil = floor => {
            let v = floor;
            while (v < 1 && whiteAt(v) < root.target) v = Math.min(1, v + 0.05);
            return v;
        };
        if (okDark && okWhite) {
            if (current === "light")
                return whiteBare > darkBare + root.switchMargin
                    ? { ink: "dark", veil: whiteVeil(textureVeil) }
                    : { ink: "light", veil: 0 };
            return darkBare > whiteBare + root.switchMargin
                ? { ink: "light", veil: 0 }
                : { ink: "dark", veil: whiteVeil(textureVeil) };
        }
        if (okDark) return { ink: "light", veil: 0 };
        if (okWhite) return { ink: "dark", veil: whiteVeil(textureVeil) };
        const veil = whiteVeil(Math.max(0.05, textureVeil));
        if (whiteAt(veil) >= root.target) return { ink: "dark", veil: veil };
        return whiteAt(1) >= darkBare ? { ink: "dark", veil: 1 } : { ink: "light", veil: 0 };
    }

    function recommend(monitor, x, w, current, inkDark, inkLight) {
        return root.decide(monitor, x, w, current, inkDark, inkLight).ink;
    }

    // Which ink reads best on the surface the bar actually draws: the
    // user's fill (colour + opacity from bar.json) over the wallpaper, with
    // the veil underneath it when one is drawn. A solid bar hides the veil
    // window: pass 0 there. -1 asks the band for its own veil density.
    // Judging the fill's colour alone is wrong as soon as it is
    // translucent: black at 0 % is the wallpaper, not black.
    function decideOn(monitor, x, w, current, inkDark, inkLight, fill, veil) {
        const r = root.rangeAt(monitor, x, w);
        if (!r) return current || "dark";
        const density = veil < 0
            ? root.decide(monitor, x, w, current, inkDark, inkLight).veil : veil;
        const veiled = behind => density > 0
            ? root.composite(root.bandFor(density), behind) : behind;
        // White ink's worst case is the lightest pixel, dark ink's the
        // darkest, both after the fill has been laid over the wallpaper.
        const white = root.contrast(root.composite(fill, veiled(r.hi)), inkDark);
        const dark = root.contrast(root.composite(fill, veiled(r.lo)), inkLight);
        if (white >= root.target && dark >= root.target) {
            if (current === "light")
                return white > dark + root.switchMargin ? "dark" : "light";
            return dark > white + root.switchMargin ? "light" : "dark";
        }
        if (white >= root.target) return "dark";
        if (dark >= root.target) return "light";
        return white >= dark ? "dark" : "light";
    }

    // The same probe as `describe`, for the fill the user chose.
    function describeOn(monitor, x, w, inkDark, inkLight, fill, veil) {
        const r = root.rangeAt(monitor, x, w);
        if (!r) return "pas de profil";
        const density = veil < 0
            ? root.decide(monitor, x, w, "dark", inkDark, inkLight).veil : veil;
        const veiled = behind => density > 0
            ? root.composite(root.bandFor(density), behind) : behind;
        const hi = root.composite(fill, veiled(r.hi));
        const lo = root.composite(fill, veiled(r.lo));
        const f = c => Math.round(c * 255);
        return "fond " + f(r.lo.r) + ".." + f(r.hi.r)
             + "  surface " + f(lo.r) + ".." + f(hi.r)
             + "  texte clair " + root.contrast(hi, inkDark).toFixed(2) + ":1"
             + "  texte sombre " + root.contrast(lo, inkLight).toFixed(2) + ":1"
             + "  -> " + (root.decideOn(monitor, x, w, "dark", inkDark, inkLight, fill, veil) === "dark"
                          ? "texte clair" : "texte sombre");
    }

    // Debug: what each island would be told, as one line. Wired to an IPC
    // in shell.qml so the pipeline can be inspected end to end without
    // anything on screen having to change first.
    function describe(monitor, x, w, inkDark, inkLight) {
        const r = root.rangeAt(monitor, x, w);
        if (!r) return "pas de profil";
        const d = root.decide(monitor, x, w, "dark", inkDark, inkLight);
        const f = v => Math.round(v * 255);
        return "fond " + f(r.lo.r) + ".." + f(r.hi.r)
             + "  texture " + r.texture.toFixed(1)
             + "  texte sombre nu " + root.contrast(r.lo, inkLight).toFixed(2) + ":1"
             + "  texte clair nu " + root.contrast(r.hi, inkDark).toFixed(2) + ":1"
             + "  -> " + (d.ink === "dark" ? "texte clair" : "texte sombre")
             + ", voile " + Math.round(d.veil * 100) + "%";
    }
}
