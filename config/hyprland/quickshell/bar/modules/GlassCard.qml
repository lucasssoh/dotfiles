import QtQuick

// GlassLens tuned for the blocks INSIDE the drawer panels -- the
// notification cards, the DND button, the media card, Balise's rows.
//
// The third and last preset, between GlassChip's 18px badges and the
// popups' own values, because these sit at 28-110px and neither of the
// other two fits: GlassChip's 4px band disappears on a 90px card, and
// the popups' 14px band would be half the height of a 28px action pill.
//
// Same reason GlassChip exists rather than eight overrides per call
// site: these have to stay tuned together, and they cannot when the
// numbers are spread across a dozen files.
//
// `fresnel` off: everything in this family is either fully opaque (the
// cards, on theme/Surfaces.qml's rule that nothing ON the panel is
// translucent) or fully transparent (NotificationCard's action pills at
// rest), never in between -- and Fresnel only means anything in between.
// The transparent ones are still drawn, through the emissive alpha the
// shader folds in; see glass.frag.
GlassLens {
    band: 7
    depth: 2.5
    aberration: 0.8
    rimThickness: 2.0
    // Between GlassChip's 0.28 and the panes' 0.38. These blocks sit ON
    // an already-rimmed panel, so every one of them adds a line to a
    // surface that has one -- the reason to stay at the quiet end is
    // stacking, not the size of any single block.
    rimStrength: 0.30
    trough: 0.13
    fresnel: 0.0
    specular: 0.10
}
