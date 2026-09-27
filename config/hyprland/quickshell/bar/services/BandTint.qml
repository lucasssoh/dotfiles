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
        let lo = 255, hi = 0;
        for (let i = i0; i < i1; i++) {
            if (m.lo && m.hi) {
                lo = Math.min(lo, m.lo[i]);
                hi = Math.max(hi, m.hi[i]);
            } else {
                const c = m.cells[i];
                const g = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
                lo = Math.min(lo, g);
                hi = Math.max(hi, g);
            }
        }
        return { lo: Qt.rgba(lo / 255, lo / 255, lo / 255, 1),
                 hi: Qt.rgba(hi / 255, hi / 255, hi / 255, 1) };
    }

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
             + "  texte sombre nu " + root.contrast(r.lo, inkLight).toFixed(2) + ":1"
             + "  texte clair nu " + root.contrast(r.hi, inkDark).toFixed(2) + ":1"
             + "  -> " + (d.ink === "dark" ? "texte clair" : "texte sombre")
             + ", voile " + Math.round(d.veil * 100) + "%";
    }
}
