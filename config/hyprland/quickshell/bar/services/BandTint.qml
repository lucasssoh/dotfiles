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
    readonly property color bandDark: "#730c0c0e"
    // The light material's band: the same alpha, the opposite end of the
    // ramp. Alpha is identical at both ends on purpose -- the crossfade
    // between them then moves colour only, and the amount of wallpaper
    // coming through never changes mid-transition.
    readonly property color bandLight: "#73f2f2f7"

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

    // How much better the challenger must score before the material
    // actually switches. Without it a slideshow's crossfade walks the
    // measurement back and forth across the threshold and the bar
    // strobes. Chosen against the measured curve rather than by feel:
    // the two materials cross at wallpaper grey 115, where both sit near
    // 8.7:1, and the curve moves ~0.35:1 per 16 grey levels there -- so
    // 1.0 is worth about 45 levels of travel, far more than a crossfade's
    // own wobble and far less than any real wallpaper change.
    readonly property real switchMargin: 1.0

    // Single-rect version of recommendBand below. Not what the band
    // uses -- it is the primitive `describe()` reports with, so one
    // island's own reading can be inspected without the minimax folding
    // it into the other two. `current` carries the hysteresis state for
    // the same reason it does there.
    function recommend(monitor, x, w, current, inkDark, inkLight) {
        const behind = root.backgroundAt(monitor, x, w);
        if (!behind) return current || "dark";
        const sDark = root.contrast(root.composite(root.bandDark, behind), inkDark);
        const sLight = root.contrast(root.composite(root.bandLight, behind), inkLight);
        if (current === "light")
            return sDark > sLight + root.switchMargin ? "dark" : "light";
        return sLight > sDark + root.switchMargin ? "light" : "dark";
    }

    // ONE material for the whole band, chosen by minimax over the islands
    // that actually carry ink: the material whose WORST island reads best.
    //
    // One decision and not three, even though the islands genuinely
    // disagree -- they do so on 27% of this machine's 56 wallpapers.
    // Measured before choosing: with a single material picked this way,
    // the worst island never drops below 5.57:1 on any of those 56
    // (median 11.12:1, zero below AA), against 12% of them failing AA
    // today. Three materials would buy contrast nobody can perceive at
    // the cost of splitting "une bande unie" -- which was an explicit
    // requirement -- into three colours, or smearing a gradient across
    // it. The per-island `ink` property the modules carry is what lets
    // the band differ from the DRAWERS; it is not there to let the three
    // islands differ from each other, and this is the measurement that
    // says they need not.
    //
    // `rects` is [[x, w], ...] in the monitor's own coordinates. Only
    // `primary` is scored: it is what nearly every glyph on the band
    // uses, and a tier that is deliberately faint (see InkLight.qml)
    // must not get a vote on legibility.
    function recommendBand(monitor, rects, current, dark, light) {
        let worstDark = Infinity, worstLight = Infinity;
        for (let i = 0; i < rects.length; i++) {
            const behind = root.backgroundAt(monitor, rects[i][0], rects[i][1]);
            if (!behind) continue;
            worstDark = Math.min(worstDark, root.contrast(root.composite(root.bandDark, behind), dark.primary));
            worstLight = Math.min(worstLight, root.contrast(root.composite(root.bandLight, behind), light.primary));
        }
        if (!isFinite(worstDark) || !isFinite(worstLight)) return current || "dark";
        if (current === "light")
            return worstDark > worstLight + root.switchMargin ? "dark" : "light";
        return worstLight > worstDark + root.switchMargin ? "light" : "dark";
    }

    // Debug: what each island would be told, as one line. Wired to an IPC
    // in shell.qml so the pipeline can be inspected end to end without
    // anything on screen having to change first.
    function describe(monitor, x, w, inkDark, inkLight) {
        const behind = root.backgroundAt(monitor, x, w);
        if (!behind) return "pas de profil";
        const cd = root.composite(root.bandDark, behind);
        const cl = root.composite(root.bandLight, behind);
        const f = v => Math.round(v * 255);
        return "derriere rgb(" + f(behind.r) + "," + f(behind.g) + "," + f(behind.b) + ")"
             + "  sombre " + root.contrast(cd, inkDark).toFixed(2) + ":1"
             + "  clair " + root.contrast(cl, inkLight).toFixed(2) + ":1"
             + "  -> " + root.recommend(monitor, x, w, "dark", inkDark, inkLight);
    }
}
