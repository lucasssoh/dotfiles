import QtQuick
import "../services"

// The bar's one ink, and the veil under it, decided from the wallpaper
// behind the whole band (BandTint.decideBar): every block on the band --
// the clock, the metrics, the launchers, the tools and the central island
// -- reads the same text colour, and the band gives each slice of the
// screen exactly the veil that colour needs there.
//
// Replaces one IslandInk per island, which decided each island alone and
// left a varied wallpaper with a bar in two inks.
InkBlend {
    id: bar

    property string monitor: ""
    // The blocks that carry text, as [{x, w}] in the bar's coordinates.
    // Bound live: a block that grows re-decides against what it covers.
    property var rects: []

    property bool lightText: true
    t: bar.lightText ? 0 : 1
    Behavior on t { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

    // One veil per profile slice, 0..1, already eased across slices.
    property var veils: []

    function reevaluate(): void {
        if (!bar.monitor || !BandTint.ready) return;
        const d = BandTint.decideBar(bar.monitor, bar.rects, bar.lightText, Ink.primary, InkLight.primary);
        if (!d) return;
        bar.lightText = d.lightText;
        // Only a real change: the band repaints on it.
        const old = bar.veils;
        let same = old.length === d.veils.length;
        for (let i = 0; same && i < old.length; i++) same = Math.abs(old[i] - d.veils[i]) < 0.005;
        if (!same) bar.veils = d.veils;
    }

    onMonitorChanged: bar.reevaluate()
    onRectsChanged: bar.reevaluate()
    Component.onCompleted: bar.reevaluate()
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: bar.reevaluate()
}
