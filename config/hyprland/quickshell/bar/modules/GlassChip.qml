import QtQuick

// GlassLens tuned for the bar's 18px chips -- the hdr / display / balise
// badges in TOOLS, ActiveWindow's app chip and the active workspace pill.
//
// One preset rather than the same eight overrides copied into five
// files, for the same reason GlassRim.qml exists rather than a hex ramp
// per call site: these have to stay tuned TOGETHER, and they cannot when
// the numbers are spread around.
//
// Everything here is a scaled-down version of the popups' values, and it
// has to be. A band of 10-14px is most of an 18px chip's height, leaving
// it no flat centre at all, and the dispersion and trough have to shrink
// with it or the whole chip becomes edge.
//
// `fresnel` is off: these chips are either fully opaque (the active
// workspace pill's #34383f) or fully transparent (every other one is
// shaped by its edge alone), and the Fresnel term only means anything in
// between. On the fill-less ones the rim is visible purely through the
// emissive alpha the shader folds in -- see glass.frag.
GlassLens {
    band: 4
    depth: 1.5
    aberration: 0.6
    rimThickness: 1.6
    // Lower than the panes' own 0.38. Hdr.qml already measured this
    // exact trap on this exact chip: a symmetric source lights the whole
    // bottom run at the ramp's brightest stop, where a corner hot spot
    // only ever lit a short arc -- so pane numbers read as a white
    // underline here rather than as a highlight ("la puissance du blanc
    // est trop forte", 157 luminance against the diagonal's 92).
    rimStrength: 0.28
    trough: 0.10
    fresnel: 0.0
    specular: 0.09
}
