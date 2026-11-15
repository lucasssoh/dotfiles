import QtQuick
import "../services"

// The band's inks and veil, decided from the wallpaper behind it
// (BandTint.decideBlocks): each block -- the clock, Programme, the
// metrics, the launchers, the tools -- picks its own ink, light or dark,
// and the band gives each slice of the screen the veil its block's ink
// needs there. The blocks read their ink through a BlockInk each.
//
// One ink for the whole bar was tried first: over a wallpaper dark on one
// side and pale on the other, it laid a dark veil under light text where
// black text would simply have read.
QtObject {
    id: bar

    property string monitor: ""
    // The blocks that carry text, as [{x, w}] in the bar's coordinates.
    // Bound live: a block that grows re-decides against what it covers.
    property var rects: []

    // Per block, true = light text.
    property var lights: []
    // Per slice: the veil, 0..1, eased across slices, and whether it sits
    // under light text (so is the dark veil) or under dark text (light).
    property var veils: []
    property var veilLights: []

    function reevaluate(): void {
        if (!bar.monitor || !BandTint.ready) return;
        const d = BandTint.decideBlocks(bar.monitor, bar.rects, bar.lights, Ink.primary, InkLight.primary);
        if (!d) return;
        if (JSON.stringify(d.lights) !== JSON.stringify(bar.lights)) bar.lights = d.lights;
        const old = bar.veils;
        let same = old.length === d.veils.length
            && JSON.stringify(d.veilLights) === JSON.stringify(bar.veilLights);
        for (let i = 0; same && i < old.length; i++) same = Math.abs(old[i] - d.veils[i]) < 0.005;
        if (!same) {
            bar.veilLights = d.veilLights;
            bar.veils = d.veils;
        }
    }

    onMonitorChanged: bar.reevaluate()
    onRectsChanged: bar.reevaluate()
    Component.onCompleted: bar.reevaluate()
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: bar.reevaluate()
}
