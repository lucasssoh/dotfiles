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

    // ---- the band's own fill ----------------------------------------
    // THE definition, read by shell.qml's barBand rather than repeated
    // there. It has to live wherever the contrast maths lives: every
    // number below is a function of this alpha, and a band whose colour
    // drifted from the value the maths assumed would produce confident
    // and wrong answers.
    //
    // 0x73 is ~45% -- the band blocks less than half of what is behind
    // it, which is the whole reason this machinery exists.
    //
    // ONE band material: flat, translucent, this near-black. A second,
    // WHITE band was tried and removed -- it worked on the numbers (worst
    // island 5.57:1 against 4.22:1 here) and was wrong on the design: a
    // bar whose surface turns white is a different bar.
    //
    // What moves since the HyperOS pass is HOW MUCH of it there is, per
    // island: `veil`, 0 to 1, scales this alpha. Asked for after a test
    // with no band at all read "parfait" on calm wallpapers: "si le fond
    // est très irrégulier, alors la bande est plus pertinente, quand le
    // fond est relativement uniforme, c'est très lisible et très beau".
    // So an island over a calm wallpaper gets no veil, one over a busy or
    // high-contrast stretch gets exactly as much as its text needs --
    // see `decide` below for how much that is.
    //
    // (A lighter 0x40 veil under dark-ink islands existed for a while; it
    // is gone -- a dark veil only ever LOWERS dark text's contrast, so
    // dark text now always sits on the bare wallpaper.)
    readonly property color band: "#730c0c0e"

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
    // is ignored and the contrast rule alone decides; from there the band
    // comes in with WHITE text, at a minimum density that reaches full at
    // `textureFull`.
    readonly property real textureStart: 15
    readonly property real textureFull: 35

    // Which ink an island takes, and how much veil goes under it:
    // { ink: "dark" | "light", veil: 0..1 }. ("dark" is the dark MATERIAL,
    // i.e. white text; "light" is dark text -- the names Ink/InkLight use.)
    //
    //   1. Without any veil, score dark text against the brightest-but-
    //      darkest pixel (`lo`) and white text against the brightest
    //      (`hi`). Whichever clears `target` wins with veil 0; if both do,
    //      the better one, with the old hysteresis so a crossfade cannot
    //      flip-flop the ink.
    //   2. If neither does, white text takes the SMALLEST veil (in 5%
    //      steps) that lifts its worst case over `target` -- the veil
    //      darkens the bright spots under it, which is the only thing a
    //      dark veil can do for text.
    //   3. If even the full band is not enough, whichever of "white on the
    //      full band" and "dark on nothing" scores higher.
    //
    // `current` is the caller's previous ink, where the hysteresis state
    // lives (a singleton cannot hold it for several islands).
    function decide(monitor, x, w, current, inkDark, inkLight) {
        const r = root.rangeAt(monitor, x, w);
        if (!r) return { ink: current || "dark", veil: 1 };
        const whiteAt = v => root.contrast(root.composite(root.bandFor(v), r.hi), inkDark);
        // 0. A busy wallpaper gets the band whatever the contrast says --
        //    added after country-road's foliage passed the contrast rule
        //    with dark text at 4.54:1 and was still hard to read: contrast
        //    against the worst pixel says nothing about visual noise, and
        //    only the band calms it. White text on it, the veil at least
        //    as dense as the texture asks and at least as dense as white
        //    text's contrast needs.
        if (r.texture >= root.textureStart) {
            const k = Math.min(1, (r.texture - root.textureStart) / (root.textureFull - root.textureStart));
            let v = 0.35 + 0.65 * k;
            while (v < 1 && whiteAt(v) < root.target) v = Math.min(1, v + 0.05);
            return { ink: "dark", veil: v };
        }
        const darkBare = root.contrast(r.lo, inkLight);
        const whiteBare = whiteAt(0);
        const okDark = darkBare >= root.target, okWhite = whiteBare >= root.target;
        if (okDark && okWhite) {
            if (current === "light")
                return { ink: whiteBare > darkBare + root.switchMargin ? "dark" : "light", veil: 0 };
            return { ink: darkBare > whiteBare + root.switchMargin ? "light" : "dark", veil: 0 };
        }
        if (okDark) return { ink: "light", veil: 0 };
        if (okWhite) return { ink: "dark", veil: 0 };
        for (let v = 0.05; v <= 1.0001; v += 0.05) {
            if (whiteAt(v) >= root.target) return { ink: "dark", veil: Math.min(1, v) };
        }
        return whiteAt(1) >= darkBare ? { ink: "dark", veil: 1 } : { ink: "light", veil: 0 };
    }

    // Kept for callers that only want the ink.
    // ---- one ink for the whole bar, a veil per slice -------------------
    // `decide` above judges each island alone, on the 10th/90th
    // percentiles of what it covers. Over a wallpaper that changes across
    // the width (country-road: autumn leaves on the left, a calm sky on
    // the right) that gave a bar in two inks, and a small busy patch
    // inside an island -- branches behind the battery -- fell under the
    // percentile and got no veil at all.
    //
    // `decideBar` picks ONE ink for every block, the one that needs the
    // least veil where there is text, and then gives each of the
    // profile's slices exactly the veil that ink needs there. The veil is
    // dark under light text and light under dark text: a dark veil only
    // lowers dark text's contrast, which is why the white band of an
    // earlier pass is back, but only as a local haze over a busy patch,
    // never as the bar's surface.
    readonly property color lightBand: "#73f5f3ee"
    function lightBandFor(veil) {
        const k = Math.max(0, Math.min(1, veil));
        return Qt.rgba(root.lightBand.r, root.lightBand.g, root.lightBand.b, root.lightBand.a * k);
    }

    // Per slice and per ink, the least veil that holds `target`, from the
    // same busy-wallpaper floor as `decide`. Pure function of the profile,
    // so it is computed once per profile and per monitor and kept:
    // islands resize far more often than the wallpaper changes.
    property var _needs: ({})
    function sliceNeeds(monitor, inkDark, inkLight) {
        if (!root.profile || !root.profile[monitor]) return null;
        const m = root.profile[monitor];
        if (!m.lo || !m.hi || !m.cells || !m.cells.length) return null;
        const cached = root._needs[monitor];
        if (cached && cached.seq === root.seq) return cached;
        const light = [], dark = [];
        for (let i = 0; i < m.cells.length; i++) {
            const lo = Qt.rgba(m.lo[i] / 255, m.lo[i] / 255, m.lo[i] / 255, 1);
            const hi = Qt.rgba(m.hi[i] / 255, m.hi[i] / 255, m.hi[i] / 255, 1);
            const texture = root.lstar(m.hi[i]) - root.lstar(m.lo[i]);
            const floor = texture >= root.textureStart
                ? 0.35 + 0.65 * Math.min(1, (texture - root.textureStart) / (root.textureFull - root.textureStart))
                : 0;
            light.push(root._least(floor, v => root.contrast(root.composite(root.bandFor(v), hi), inkDark)));
            // No floor under dark text: the texture measure is a spread of
            // lightness within the slice, which a smooth gradient has too
            // (macos-abstract-shapes' orange folds), and the floor laid a
            // light haze where dark text already read. The 10th
            // percentile in `lo` is what guards the dark patches.
            dark.push(root._least(0, v => root.contrast(root.composite(root.lightBandFor(v), lo), inkLight)));
        }
        const entry = { seq: root.seq, light: light, dark: dark };
        const all = Object.assign({}, root._needs);
        all[monitor] = entry;
        root._needs = all;
        return entry;
    }
    function _least(floor, contrastAt) {
        for (let v = floor; v <= 1.0001; v += 0.05)
            if (contrastAt(Math.min(1, v)) >= root.target) return { v: Math.min(1, v), ok: true };
        return { v: 1, ok: false };
    }

    // rects: [{x, w}] in the monitor's coordinates, the blocks that carry
    // text. currentLight: the ink in use, for the hysteresis. Returns
    // { lightText, veils } with one veil per slice, eased across slices
    // so it never ends on a slice edge, or null without a profile.
    readonly property real inkSwitchMargin: 1.0
    function decideBar(monitor, rects, currentLight, inkDark, inkLight) {
        const n = root.sliceNeeds(monitor, inkDark, inkLight);
        if (!n) return null;
        const m = root.profile[monitor];
        const count = n.light.length;
        const text = {};
        for (let r = 0; r < rects.length; r++) {
            if (!(rects[r].w > 0)) continue;
            const a = Math.max(0, Math.floor(rects[r].x / m.width * count));
            const b = Math.min(count - 1, Math.floor((rects[r].x + rects[r].w - 1) / m.width * count));
            for (let i = a; i <= b; i++) text[i] = true;
        }
        const cost = side => {
            let c = 0;
            for (const i in text) c += side[i].v + (side[i].ok ? 0 : 10);
            return c;
        };
        const cl = cost(n.light), cd = cost(n.dark);
        let lightText = currentLight;
        if (currentLight && cd + root.inkSwitchMargin < cl) lightText = false;
        else if (!currentLight && cl + root.inkSwitchMargin < cd) lightText = true;
        // Only under text: a slice no block covers gets no veil of its
        // own, and only the easing below reaches into it -- a veil along
        // the whole width spoiled wide empty stretches of the wallpaper.
        const raw = (lightText ? n.light : n.dark).map((e, i) => text[i] ? e.v : 0);
        // Eased over two slices each side (30 px at 128 slices), not
        // widened first: one dark corner slice spread its veil ~90 px
        // under the text beside it.
        const veils = raw.map((v, i) => {
            let s = 0, k = 0;
            for (let j = i - 2; j <= i + 2; j++) if (j >= 0 && j < count) { s += raw[j]; k++; }
            return s / k;
        });
        return { lightText: lightText, veils: veils };
    }
    // One ink PER BLOCK (2026-11-15, after a bar dark on the left and a
    // uniform pale pink on the right: one ink for the whole bar put a
    // dark veil under the right's light text, where black text would
    // simply have read). Each block picks the ink that needs the least
    // veil over the slices it covers, with the same hysteresis as the
    // bar-wide choice; each slice gets the veil its block's ink needs,
    // dark under light text and light under dark text.
    //
    // current: the blocks' inks in use (true = light text), for the
    // hysteresis. Returns { lights: [per block], veils: [per slice],
    // veilLights: [per slice, true where the veil sits under light text,
    // so is dark] }, or null without a profile.
    function decideBlocks(monitor, rects, current, inkDark, inkLight) {
        const n = root.sliceNeeds(monitor, inkDark, inkLight);
        if (!n) return null;
        const m = root.profile[monitor];
        const count = n.light.length;
        const lights = [];
        const raw = new Array(count).fill(0);
        const tone = new Array(count).fill(null);
        for (let bi = 0; bi < rects.length; bi++) {
            const r = rects[bi];
            let lt = current && current[bi] !== undefined ? current[bi] : true;
            if (!(r.w > 0)) { lights.push(lt); continue; }
            const a = Math.max(0, Math.floor(r.x / m.width * count));
            const b = Math.min(count - 1, Math.floor((r.x + r.w - 1) / m.width * count));
            let cl = 0, cd = 0;
            for (let i = a; i <= b; i++) {
                cl += n.light[i].v + (n.light[i].ok ? 0 : 10);
                cd += n.dark[i].v + (n.dark[i].ok ? 0 : 10);
            }
            if (lt && cd + root.inkSwitchMargin < cl) lt = false;
            else if (!lt && cl + root.inkSwitchMargin < cd) lt = true;
            lights.push(lt);
            for (let i = a; i <= b; i++) {
                raw[i] = Math.max(raw[i], (lt ? n.light : n.dark)[i].v);
                tone[i] = lt;
            }
        }
        // Slices no block covers take the tone of the nearest one that is,
        // for the easing to blend into.
        for (let i = 0; i < count; i++) {
            if (tone[i] !== null) continue;
            let d = 1;
            while (d < count) {
                if (i - d >= 0 && tone[i - d] !== null) { tone[i] = tone[i - d]; break; }
                if (i + d < count && tone[i + d] !== null) { tone[i] = tone[i + d]; break; }
                d++;
            }
            if (tone[i] === null) tone[i] = true;
        }
        const veils = raw.map((v, i) => {
            let s = 0, k = 0;
            for (let j = i - 2; j <= i + 2; j++) if (j >= 0 && j < count) { s += raw[j]; k++; }
            return s / k;
        });
        return { lights: lights, veils: veils, veilLights: tone };
    }
    function describeBar(monitor, rects, inkDark, inkLight) {
        const d = root.decideBar(monitor, rects, true, inkDark, inkLight);
        if (!d) return "pas de profil";
        const vs = d.veils.map(v => Math.round(v * 100));
        return "texte " + (d.lightText ? "clair" : "sombre") + ", voile " + (d.lightText ? "sombre" : "clair")
             + " " + Math.min.apply(null, vs) + ".." + Math.max.apply(null, vs) + "%";
    }

    function recommend(monitor, x, w, current, inkDark, inkLight) {
        return root.decide(monitor, x, w, current, inkDark, inkLight).ink;
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
