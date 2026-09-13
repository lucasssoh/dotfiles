import QtQuick
import Quickshell

// The convex-glass treatment for this bar's opaque popups -- used as a
// `layer.effect`, so it receives the panel it is applied to as `source`
// and hands back the same panel seen through a thick pane.
//
//     Rectangle { id: card
//         radius: 20
//         layer.enabled: true
//         layer.effect: GlassLens { radius: card.radius }
//     }
//
// `radius` MUST match the item's own, or the silhouette the shader
// computes analytically drifts off the one the Rectangle draws.
//
// See shaders/glass.frag for what it actually does and why it refracts
// the panel's own content rather than a backdrop (short version: a
// Wayland client cannot read what is under its own layer surface, and
// these four popups float above real windows).
//
// Cost: ONE offscreen pass the size of the panel, three texture fetches
// per pixel, and only while the panel is on screen -- `layer.enabled`
// should be bound to the same condition that shows the surface wherever
// that is not already implied. Nothing here runs per frame otherwise,
// and nothing runs at all while the popup is shut.
ShaderEffect {
    id: lens

    // Pixel size, fed to the shader because every length below is
    // authored in px and UV space has no idea what a pixel is.
    readonly property real srcW: width
    readonly property real srcH: height

    property real radius: 20

    // Thickness of the glass: how deep the curved edge reaches before
    // the pane goes flat. Tuned per surface -- the same 14px band is a
    // heavy bevel on a 92px-tall OSD and a delicate one on a 600px
    // drawer.
    property real band: 14
    // Peak displacement at the rim, in px. This is the strength of the
    // refraction itself.
    property real depth: 6
    // Channel separation in PIXELS -- the chromatic aberration itself.
    // This is how far apart the red and blue edges sit; above ~2px it
    // stops reading as dispersion and starts reading as a misconverged
    // display.
    property real aberration: 1.0
    // Strength of the light raking across the curved band.
    property real specular: 0.11

    // The rim line at the very silhouette. This REPLACES GlassRim on a
    // surface using this effect -- the shader draws the same five-stop
    // decay, so the edge stays in the family, but now it curves and
    // disperses. Stacking a real GlassRim on top as well just doubles
    // the line and kills the fringe.
    // Deliberately well under 1: a bright white line is the LEAST
    // important part of this, and at full strength it dominates
    // everything else and the surface just reads as an outlined box.
    // The convex read is carried by `trough` and `fresnel` below, which
    // are what got raised as this came down.
    property real rimStrength: 0.38
    // Depth of the dark trough just inside the rim -- see the shader.
    // One of the two real convexity knobs: at 0 the edge is a lit line
    // on a flat pane, and raising it is what makes the surface roll
    // away. No longer scaled by `rimStrength`, so the white can be taken
    // down without taking the shape down with it.
    property real trough: 0.18
    // The other one, and the stronger of the two on anything
    // translucent: how much the pane densifies toward its edge. See the
    // shader -- this is opacity, not light, so it reads as thickness
    // rather than as a highlight and it survives distance.
    property real fresnel: 0.6
    property real rimThickness: 3.0
    // GlassRim's own default highlight. Declared as a real colour and
    // split into the three uniforms below, rather than asking every call
    // site to hand-convert: a shader uniform block holds floats, not
    // colours, but that is the shader's problem and not the caller's --
    // and it is what lets Hdr.qml keep its `Behavior on rimColor`
    // crossfading the whole ramp to cyan, which three separate floats
    // could not do without three separate animations.
    property color rimColor: "#e5e5ea"
    readonly property real rimR: rimColor.r
    readonly property real rimG: rimColor.g
    readonly property real rimB: rimColor.b

    // Two light sources, one per horizontal edge, rather than a single
    // direction -- see the shader for why symmetric beats directional on
    // shapes this shallow.
    //
    // DELIBERATELY UNEQUAL. They were 1.0/1.0 first, and at arm's length
    // that read as a thick soft border rather than as glass: a line of
    // even brightness all the way round is what an outline IS, and no
    // amount of dispersion in it changes that read. A real pane lit from
    // above catches a hard highlight on its top arete and only a weaker
    // bounce underneath, and it is that IMBALANCE the eye uses to decide
    // which way the surface is facing. Keep the two different.
    property real lightTop: 1.0
    property real lightBottom: 0.45

    // The layer texture must not live in an atlas: the shader samples at
    // offsets from qt_TexCoord0, and inside an atlas those offsets walk
    // straight into a neighbouring item's texels.
    supportsAtlasTextures: false

    // Absolute, via Quickshell's own shell-root helper -- NOT the
    // relative "../shaders/..." this started as.
    //
    // A relative URL here is resolved against the file that INSTANTIATES
    // the lens, not against this one. From modules/ (Osd, BatteryAlert,
    // DrawerIsland) that happened to land on the right file; from
    // shell.qml one directory up it resolved to a path that does not
    // exist, and Quickshell's URL interceptor rewrites anything it
    // cannot resolve to `qrc:/qs-blackhole` -- so the failure surfaced as
    // "Failed to find shader :/qs-blackhole" and the two panes declared
    // in shell.qml (METRICS, LAUNCHERS) simply vanished, while the three
    // declared in modules/ were fine.
    fragmentShader: "file://" + Quickshell.shellPath("shaders/glass.frag.qsb")
}
