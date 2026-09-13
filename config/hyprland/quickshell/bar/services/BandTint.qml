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
    // ONE band, and it never changes: flat and translucent, always this
    // colour. A second, light band was tried and removed -- it worked on
    // the numbers (worst island 5.57:1 against 4.22:1 here) and was wrong
    // on the design: a bar whose surface turns white is a different bar.
    // Only the ink moves now.
    readonly property color band: "#730c0c0e"

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

    // Returns "dark" or "light" -- which INK reads better behind
    // [x, x+w). Both are scored against the same band, because the band
    // is the same; this is the whole difference from the material flip
    // that preceded it.
    //
    // Per island, not once for the whole bar. That is only possible
    // BECAUSE the band no longer moves: three islands with three inks on
    // one uniform surface have no seam between them, where three
    // materials would have had to cut the band into three colours. It is
    // also worth doing -- the islands disagree on 27% of the library, and
    // a single global ink fixes only 2 of the 7 wallpapers that fail
    // today, against 4 of 7 when each island chooses for itself.
    //
    // `current` is the caller's own previous answer, which is where the
    // hysteresis state lives: a singleton cannot hold it when three
    // islands each need their own.
    function recommend(monitor, x, w, current, inkDark, inkLight) {
        const behind = root.backgroundAt(monitor, x, w);
        if (!behind) return current || "dark";
        const surface = root.composite(root.band, behind);
        const sDark = root.contrast(surface, inkDark);
        const sLight = root.contrast(surface, inkLight);
        if (current === "light")
            return sDark > sLight + root.switchMargin ? "dark" : "light";
        return sLight > sDark + root.switchMargin ? "light" : "dark";
    }

    // Debug: what each island would be told, as one line. Wired to an IPC
    // in shell.qml so the pipeline can be inspected end to end without
    // anything on screen having to change first.
    function describe(monitor, x, w, inkDark, inkLight) {
        const behind = root.backgroundAt(monitor, x, w);
        if (!behind) return "pas de profil";
        const surface = root.composite(root.band, behind);
        const f = v => Math.round(v * 255);
        return "fond rgb(" + f(surface.r) + "," + f(surface.g) + "," + f(surface.b) + ")"
             + "  encre claire " + root.contrast(surface, inkDark).toFixed(2) + ":1"
             + "  encre sombre " + root.contrast(surface, inkLight).toFixed(2) + ":1"
             + "  -> " + root.recommend(monitor, x, w, "dark", inkDark, inkLight);
    }
}
