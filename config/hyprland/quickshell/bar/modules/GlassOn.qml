import QtQuick

// GlassChip's lens, retuned for the white fill of an ACTIVE control in
// the drawers (an inverted tile, row, segment or button). Asked for after
// the flat HyperOS pass read "trop plat": the "on" state keeps its
// inversion and gets the convex edge back.
//
// On white, GlassChip's own numbers all but vanish -- its rim is a light
// highlight and there is no lighter colour left to draw it in. So the
// convexity comes from the other two terms instead: a deeper trough (the
// soft dark dip just inside the edge) and a wider chromatic fringe. The
// rim stays, in pure white, as the lit lip right at the silhouette.
//
// Like every layer.effect here: gate `layer.enabled` on the active state,
// so an inactive control allocates nothing.
GlassLens {
    band: 5
    depth: 1.5
    aberration: 1.0
    rimThickness: 1.6
    rimStrength: 0.35
    trough: 0.22
    fresnel: 0.0
    specular: 0.06
    rimColor: "#ffffff"
}
