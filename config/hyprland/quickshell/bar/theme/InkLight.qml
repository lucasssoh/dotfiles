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
// Not by eye, and not by holding them to WCAG AA. Each one reproduces
// the contrast its Ink counterpart achieves on the DARK material, at the
// same hue and saturation, with lightness solved for. The light material
// is meant to be a faithful mirror, not a stricter or a looser palette:
// `faint` is nearly invisible on the dark band (1.06:1 -- it is the
// notification bell's do-not-disturb state, deliberately almost gone)
// and it has to stay nearly invisible here, which a 4.5:1 floor would
// have destroyed by making it a perfectly readable grey.
//
// Both materials are measured at their OWN worst case, which is the same
// wallpaper value for both: they cross at wallpaper grey ~115, so the
// dark material's hardest job is a background of 69 and the light
// material's is 172. Every pair below is matched at those two points:
//
//     token       dark            light           delta
//     primary     #f2f2f7 8.64:1  #0c0c0e 8.65:1  0.01
//     secondary   #8e8e93 2.96:1  #5c5c60 2.96:1  0.00
//     muted       #636366 1.61:1  #868689 1.61:1  0.00
//     faint       #48484a 1.06:1  #a7a7aa 1.06:1  0.00
//     danger      #ff6e6e 3.54:1  #a60000 3.54:1  0.00
//     accent      #a8b4c4 4.59:1  #364150 4.59:1  0.00
//     positive    #a3d9a5 5.98:1  #163517 5.97:1  0.01
//     play        #237823 1.74:1  #2b942b 1.74:1  0.00
//     hdr         #6be3e8 6.33:1  #082f31 6.34:1  0.01
//
// One constraint the solver needed beyond matching the ratio: the ink
// has to stay DARKER than its own background. Matching `muted` and
// `faint` numerically alone produced colours LIGHTER than the light band
// -- the same ratio, the wrong side of it, and they would have read as
// glowing rather than as receding. The de-emphasised tiers fade toward
// the background from below here, as they fade toward it from above on
// the dark material.
QtObject {
    // See Ink.qml's `t`.
    readonly property real t: 1.0

    // `primary` is Ink.onLight's value rather than the hue-preserved
    // #0c0c13 the solver returned: the two score identically (8.65:1)
    // and Ink already names this colour, so naming it twice with a
    // one-bit difference would be a difference with no meaning.
    readonly property color primary: "#0c0c0e"
    readonly property color secondary: "#5c5c60"
    readonly property color muted: "#868689"
    readonly property color faint: "#a7a7aa"

    readonly property color danger: "#a60000"
    readonly property color accent: "#364150"
    readonly property color positive: "#163517"
    readonly property color play: "#2b942b"
    readonly property color hdr: "#082f31"

    // Symmetric counterpart to Ink.onLight: the ink the OTHER material
    // would use. Unused here for the same reason it is unused there --
    // it exists so the pair reads as a pair.
    readonly property color onLight: "#f2f2f7"
}
