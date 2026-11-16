import QtQuick
import "../services"

// Each block chooses its own ink and dark veil from the wallpaper behind it.
QtObject {
    id: bar

    property string monitor: ""
    property var rects: []
    property var lights: []
    property var veils: []

    function reevaluate(): void {
        if (!bar.monitor || !BandTint.ready) return;
        const m = BandTint.profile[bar.monitor];
        if (!m || m.width <= 0 || !m.cells || !m.cells.length) return;
        const count = m.cells.length;
        const lights = [];
        const raw = new Array(count).fill(0);

        for (let bi = 0; bi < bar.rects.length; bi++) {
            const r = bar.rects[bi];
            let light = bar.lights[bi] !== false;
            if (!(r.w > 0)) { lights.push(light); continue; }

            const a = Math.max(0, Math.floor(r.x / m.width * count));
            const b = Math.min(count - 1, Math.floor((r.x + r.w - 1) / m.width * count));
            if (b < a) { lights.push(light); continue; }

            const current = light ? "dark" : "light";
            const d = BandTint.decide(bar.monitor, r.x, r.w, current, Ink.primary, InkLight.primary);
            light = d.ink === "dark";
            lights.push(light);
            for (let i = a; i <= b; i++) raw[i] = Math.max(raw[i], d.veil);
        }

        const veils = raw.map((v, i) => {
            let sum = 0, samples = 0;
            for (let j = i - 2; j <= i + 2; j++) {
                if (j >= 0 && j < count) { sum += raw[j]; samples++; }
            }
            return sum / samples;
        });

        if (JSON.stringify(lights) !== JSON.stringify(bar.lights)) bar.lights = lights;
        let same = veils.length === bar.veils.length;
        for (let i = 0; same && i < veils.length; i++) same = Math.abs(veils[i] - bar.veils[i]) < 0.005;
        if (!same) bar.veils = veils;
    }

    onMonitorChanged: bar.reevaluate()
    onRectsChanged: bar.reevaluate()
    Component.onCompleted: bar.reevaluate()
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: bar.reevaluate()
}
