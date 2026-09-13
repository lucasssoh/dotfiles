pragma Singleton
import QtQuick

// The light material's ink -- Ink.qml's twin, same property names, so a
// module can be handed one or the other through its own `ink` property
// and needs to know nothing about which it got.
//
// Only the band's three exposed islands (metrics, launchers, tools) are
// ever handed this. The drawers, the OSD and BatteryAlert sit over
// WINDOWS rather than over the wallpaper and keep Ink permanently -- see
// Ink.qml's MATERIAL note.
//
// HOW THESE VALUES WERE PICKED
// ----------------------------
// Not by eye, and not by holding them to WCAG AA. Each one reproduces the
// contrast its Ink counterpart achieves, at the same hue and saturation,
// with lightness solved for -- and both are measured on the SAME
// background, because the band no longer changes: only the ink does.
//
// That common worst case is the crossover. With the band fixed at
// `#730c0c0e`, white ink and dark ink score equally at wallpaper grey
// 201, which composites to 116. Every pair below is matched there:
//
//     token       white ink       dark ink        delta
//     primary     #f2f2f7 4.20:1  #0c0c0e 4.20:1  0.00
//     secondary   #8e8e93 1.44:1  #5b5b5f 1.44:1  0.00
//     danger      #ff6e6e 1.72:1  #a50000 1.72:1  0.00
//     accent      #a8b4c4 2.23:1  #36404f 2.23:1  0.00
//     positive    #a3d9a5 2.91:1  #163417 2.91:1  0.00
//     hdr         #6be3e8 3.07:1  #082f31 3.07:1  0.00
//
// 4.20:1 at the crossover is the honest cost of keeping the band flat and
// translucent: the material flip reached 5.57:1 at its own worst point by
// lifting the background too, and was dropped because a band that turns
// white is not what this bar is. Measured over the 56 wallpapers in the
// library: worst island 4.22:1, three of them between 4.22 and 4.38,
// against seven falling to 2.82:1 with white ink alone.
//
// `muted`, `faint` and `play` are DELIBERATELY absent below and resolve
// to Ink's own values. Solving for them returns the colour they already
// are: on a mid-grey composite they sit below the background already, so
// there is no twin to have. A tier that does not need to move should not
// be given a second name that happens to equal the first.
//
// One constraint the solver needed beyond matching the ratio: the ink has
// to stay DARKER than its background. Without it, matching `secondary`
// numerically returned a colour LIGHTER than the band -- the same ratio,
// the wrong side of it, reading as a glow rather than as a recession.
QtObject {
    // See Ink.qml's `t`.
    readonly property real t: 1.0

    // `primary` is Ink.onLight's value rather than the hue-preserved
    // #0c0c13 the solver returned: the two score identically (8.65:1)
    // and Ink already names this colour, so naming it twice with a
    // one-bit difference would be a difference with no meaning.
    readonly property color primary: "#0c0c0e"
    readonly property color secondary: "#5b5b5f"
    readonly property color muted: Ink.muted
    readonly property color faint: Ink.faint

    readonly property color danger: "#a50000"
    readonly property color accent: "#36404f"
    readonly property color positive: "#163417"
    readonly property color play: Ink.play
    readonly property color hdr: "#082f31"

    // Symmetric counterpart to Ink.onLight: the ink the OTHER material
    // would use. Unused here for the same reason it is unused there --
    // it exists so the pair reads as a pair.
    readonly property color onLight: "#f2f2f7"
}
