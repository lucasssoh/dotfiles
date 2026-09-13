import QtQuick
import "../services"

// One island's ink: an InkBlend that decides its own position on the
// dark<->light axis from the wallpaper behind that island, and animates
// itself there.
//
// One of these per island rather than one per bar. The band is flat and
// translucent at a single colour and never changes, so three islands can
// carry three different inks across it with no seam between them -- which
// is not something the earlier material flip could have done, since three
// materials would have meant cutting the band into three colours.
//
// It is also worth the granularity, measured rather than assumed: the
// three islands disagree about which ink reads better on 27% of this
// machine's 56 wallpapers, and letting each choose for itself rescues 4
// of the 7 wallpapers where the bar currently falls below WCAG AA, where
// a single ink for the whole bar rescues only 2.
//
// Everything else -- the ramp itself, the interpolation, the single
// animated `t` -- is InkBlend's; this adds the decision and the trigger.
InkBlend {
    id: island

    // The screen this island is on, and where it sits across it. The
    // caller binds these to the island's live x/width: they move as the
    // content does (metrics with the CPU digits, tools with its own
    // modules, launchers with the running apps), and the decision follows
    // the stretch of wallpaper actually covered rather than the one that
    // was covered at startup.
    property string monitor: ""
    property real rectX: 0
    property real rectW: 0

    // "dark" (white ink, Ink) or "light" (dark ink, InkLight). Held here
    // rather than computed as a binding because the decision reads its
    // own previous value -- BandTint.recommend applies hysteresis against
    // it, and a binding that depends on the property it assigns is a loop.
    property string inkChoice: "dark"

    t: island.inkChoice === "light" ? 1 : 0
    // 900 ms sits just inside awww's own 1 s wallpaper transition, so the
    // bar finishes changing with the picture rather than after it.
    Behavior on t { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

    function reevaluate(): void {
        if (!island.monitor || island.rectW <= 0 || !BandTint.ready) return;
        island.inkChoice = BandTint.recommend(island.monitor, island.rectX, island.rectW,
                                              island.inkChoice, Ink.primary, InkLight.primary);
    }

    onMonitorChanged: island.reevaluate()
    onRectXChanged: island.reevaluate()
    onRectWChanged: island.reevaluate()
    Component.onCompleted: island.reevaluate()

    // Un miroir de BandTint.seq plutot qu'un `Connections`: InkBlend est
    // un QtObject, qui n'a pas de propriete par defaut et n'accepte donc
    // aucun enfant -- un Connections dedans echoue au chargement
    // ("Cannot assign to non-existent default property"). Une propriete
    // liee et son handler font le meme travail sans enfant.
    //
    // `seq`, et pas `profile`: BandTint publie le profil d'abord et le
    // numero de sequence ensuite, precisement pour que ce qui se reveille
    // la-dessus voie deja les nouveaux buckets.
    readonly property int profileSeq: BandTint.seq
    onProfileSeqChanged: island.reevaluate()
}
