#version 440

// Convex glass edge -- the "verre épais" treatment for this bar's opaque
// popups (the notification/Balise drawer, BatteryAlert, Osd).
//
// It reads NOTHING behind the surface, on purpose: these four surfaces
// float above real windows (exclusionMode: Ignore), and a Wayland client
// cannot sample what is under its own layer surface. What it refracts is
// the panel's OWN already-rendered content, which is what `layer.effect`
// hands it as `source`.
//
// WHY THE DISPERSION IS APPLIED TO THE EDGE GEOMETRY, NOT JUST TO THE
// TEXTURE LOOKUP. The first version of this shader only split the three
// channels' sampling offsets, which is the textbook way to write
// chromatic aberration -- and on these panels it was invisible, because
// dispersion can only show up where there is something to disperse and
// the middle of these fills is a near-flat gradient. So the ramps that
// make the edge (the rim line and the bevel's shading) are themselves
// evaluated at three slightly different distances from the silhouette.
// Red's edge sits a fraction outside, blue's a fraction inside, and the
// fringe exists even on a perfectly flat fill -- which is exactly what
// the thick edge of a real pane does.
//
// The rim ramp reproduces GlassRim.qml's five stops rather than
// inventing a new edge: same near-white highlight decaying to almost
// nothing away from the light, so these surfaces stay in the same visual
// family as Hyprland's own window borders, Roue's hub and the bar's
// translucent panes. What is new is that it now curves and disperses.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Pixel size of the surface. Needed because every length below (the
    // band, the displacement, the rim) is authored in PIXELS and has to
    // survive being expressed in a UV space whose two axes have wildly
    // different scales on a 416x600 drawer.
    float srcW;
    float srcH;
    float radius;
    // Thickness of the glass: how deep the curved edge reaches before
    // the pane goes flat. Everything inside this is flat glass.
    float band;
    // Peak refraction displacement at the rim, in px.
    float depth;
    // Channel separation, in px. This is the whole chromatic aberration
    // knob: it is how far apart the red and blue edges sit.
    float aberration;
    // Strength of the light raking across the curved band.
    float specular;
    // TWO vertical light sources, one per horizontal edge, each with its
    // own strength -- not a single direction vector.
    //
    // This is the same call GlassRim.qml makes with its "top"/"bottom"
    // symmetric origins, for the reason its header gives: a corner hot
    // spot reads as a direction on a big pane, but on a 24px pill it
    // mostly reads as one lopsided corner. Going vertical-only also
    // makes the left and right sides identical BY CONSTRUCTION rather
    // than by picking a lucky angle -- any horizontal component is
    // precisely what makes one side brighter than the other.
    float lightTop;
    float lightBottom;
    // How much denser the pane gets at its edge -- Fresnel.
    //
    // This is the term that carries THICKNESS on a translucent pane, and
    // the reason a white highlight cannot do it alone: glass seen
    // edge-on reflects more and transmits less, so a real pane goes
    // solid toward its rim while staying see-through in the middle.
    // That gradient in OPACITY is a completely different cue from a
    // bright line, and it survives being looked at from across the room,
    // which a 2px specular does not.
    //
    // A no-op on the opaque popups (their alpha is already 1), which is
    // why those lean on the trough and the bevel instead.
    float fresnel;
    // The rim line at the very silhouette.
    float rimStrength;
    float rimThickness;
    float rimR;
    float rimG;
    float rimB;
    // The dark trough sitting just inside the bright rim. This is what
    // actually communicates THICKNESS: a lit line on its own reads as a
    // painted outline whatever its colour ramp, because a flat surface
    // can have one too. Only the bright-then-dark-then-flat sequence is
    // unique to a curve rolling away from the light, and on panels this
    // dark it does more for the convex read than the body shading does.
    float trough;
};

layout(binding = 1) uniform sampler2D source;

// Signed distance to a rounded rectangle centred on the origin.
// Negative inside, 0 on the silhouette, positive outside.
float sdRoundRect(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The circular edge profile: 0 in the flat middle, 1 at the rim.
//
// A LINEAR ramp here reads as a chamfer -- a flat 45-degree cut, which
// looks machined rather than moulded. 1 - sqrt(1 - k^2) is a real
// circular profile: nearly flat where it meets the flat centre, turning
// hard only in the last pixels, which is what puts the whole optical
// event right at the edge where the eye expects it.
float lensProfile(float dd) {
    float k = clamp(1.0 + dd / band, 0.0, 1.0);
    return 1.0 - sqrt(max(0.0, 1.0 - k * k));
}

// The rim line, as a BUMP at a given depth rather than a ramp rising to
// the silhouette.
//
// This distinction is the whole effect, and the first two attempts at it
// got it wrong. A monotonic ramp cannot disperse: shifting the same
// rising curve by a pixel per channel leaves red above blue at EVERY
// point inside the rim, so the edge comes out uniformly warm -- a gold
// outline, which is what was on screen before this. Give each channel a
// peak at a different depth instead and the ordering flips as you cross
// the rim: warm on the outer pixel, white through the core, cool on the
// inside. That reversal is what the eye reads as glass.
float rimBump(float dd, float peakDepth, float width) {
    float x = (dd + peakDepth) / width;
    return exp(-x * x * 3.0);
}

// GlassRim.qml's five-stop decay, as a curve instead of a gradient. Its
// stops are at 0, .25, .5, .75, 1 with alphas bf/73/47/26/0f, and the
// colour scaled by 1 / .620 / .432 / .253 / .122 of the highlight along
// the way. Reproduced here so the edge decays away from the light the
// same way every other lit edge in this setup does.
float rimRamp(float t) {
    float a0 = 0.749, a1 = 0.451, a2 = 0.278, a3 = 0.149, a4 = 0.059;
    float s = clamp(t, 0.0, 1.0) * 4.0;
    if (s < 1.0) return mix(a0, a1, s);
    if (s < 2.0) return mix(a1, a2, s - 1.0);
    if (s < 3.0) return mix(a2, a3, s - 2.0);
    return mix(a3, a4, s - 3.0);
}

void main() {
    vec2 size = vec2(srcW, srcH);
    vec2 c = qt_TexCoord0 * size - size * 0.5;
    vec2 halfSize = size * 0.5;
    // Clamped the way Qt clamps a Rectangle's own radius, to half the
    // shorter side. Without this the two silhouettes diverge wherever a
    // caller's radius is larger than the item can actually take -- which
    // the bar hits for real: TOOLS' row pane is 24px tall and carries
    // DrawerIsland's cornerRadius of 18.
    float r = min(radius, min(halfSize.x, halfSize.y));

    float d = sdRoundRect(c, halfSize, r);

    // Outward normal of the silhouette, by central difference on the
    // distance field. This is what makes the effect follow the rounded
    // corners for free -- no special-casing, the normal simply rotates
    // through 90 degrees as it travels around each arc, which is also
    // exactly where a real rolled edge bends light most.
    float dx = sdRoundRect(c + vec2(1.0, 0.0), halfSize, r)
             - sdRoundRect(c - vec2(1.0, 0.0), halfSize, r);
    float dy = sdRoundRect(c + vec2(0.0, 1.0), halfSize, r)
             - sdRoundRect(c - vec2(0.0, 1.0), halfSize, r);
    vec2 n = normalize(vec2(dx, dy) + vec2(1e-6));

    // Distance from each lit edge, 0 at that edge and 1 at the far one.
    // Purely vertical, so every x reads the same value -- see the
    // lightTop/lightBottom comment above.
    float tTop = clamp(0.5 + (c.y / max(halfSize.y, 1.0)) * 0.5, 0.0, 1.0);
    float tBottom = 1.0 - tTop;

    // How squarely each source strikes the surface here. The normal
    // rotates through 90 degrees around every corner arc, so the top
    // source lights the top corners and hands over to the bottom one on
    // the way down, with no seam to place by hand.
    float lamTop = max(0.0, dot(n, vec2(0.0, -1.0))) * lightTop;
    float lamBottom = max(0.0, dot(n, vec2(0.0, 1.0))) * lightBottom;
    float lam = lamTop + lamBottom;

    // --- the three edges, one per channel ----------------------------
    // Red's silhouette sits `aberration` px outside the true one, blue's
    // the same distance inside. Everything below is evaluated three
    // times against these, which is where the colour fringe comes from.
    float dR = d + aberration;
    float dG = d;
    float dB = d - aberration;

    vec3 lens = vec3(lensProfile(dR), lensProfile(dG), lensProfile(dB));

    // Where each channel's rim peaks, in px inside the silhouette. Red
    // shallowest, blue deepest -- the order real glass disperses.
    float rimW = max(0.6, rimThickness * 0.6);
    float peak = rimThickness * 0.5;

    // --- refraction of the panel's own content -----------------------
    // Sample DEEPER IN (-n), never outward. Pulling the interior toward
    // the rim is what compresses it there, the way thickness does.
    // Sampling outward would reach past the silhouette into transparent
    // texels and eat the edge instead of bending it.
    vec4 mid = texture(source, qt_TexCoord0 - n * lens.g * depth / size);
    vec3 col = vec3(
        texture(source, qt_TexCoord0 - n * lens.r * depth / size).r,
        mid.g,
        texture(source, qt_TexCoord0 - n * lens.b * depth / size).b
    );

    // Fresnel densification -- see the uniform's comment. The pane keeps
    // its own colour; only how MUCH of it there is changes, so the edge
    // band hides more of what is behind it than the flat centre does.
    //
    // `col` arrives premultiplied by the source's own alpha, so the
    // transmitted colour has to be rescaled to the new density or
    // raising alpha would wash the edge out instead of thickening it.
    // Done HERE, before the emissive terms below -- those are light on
    // the surface, not more surface, and must not be scaled.
    float fres = fresnel * lensProfile(dG);
    float outAlpha = min(1.0, mid.a + (1.0 - mid.a) * fres);
    col *= (mid.a > 0.001) ? (outAlpha / mid.a) : 1.0;

    // --- the curved body of the edge ---------------------------------
    // A lit curve gains more than its opposite loses: matching the two
    // reads as an outline drawn around the box rather than as a surface
    // catching light. The constant term keeps the whole band slightly
    // raised, so the edge exists all the way round even where the light
    // is grazing it.
    // Neutral on purpose (lens.g for all three): `lensProfile` is
    // monotonic, so splitting it per channel only tints the whole band
    // one colour instead of dispersing it -- the same trap rimBump's
    // header describes. The rim below carries the dispersion; this
    // carries the shape.
    //
    // No darkened far side any more: with a source on each horizontal
    // edge there is no far side to darken, only the left and right
    // flanks where neither source strikes squarely, and those simply
    // fall back to the ambient term. Subtracting there instead put a
    // dark bar down both sides of every pill.
    float body = lensProfile(dG);
    vec3 emissive = vec3(body * specular * (0.30 + 0.70 * min(1.0, lam)));

    // --- the rim line at the silhouette ------------------------------
    // Each source contributes its own copy of GlassRim's decay, measured
    // from its own edge, and the two simply add. Top and bottom come out
    // brightest, the flanks at mid-height dimmest -- a pill lit from
    // above and below, which is the symmetric read.
    //
    // `rimStrength` is applied to the RIM ONLY, not baked in here. The
    // trough below reads the bare distribution instead, so dimming the
    // white highlight no longer drags the convexity down with it -- the
    // two used to be one number and could not be traded against each
    // other, which is exactly the adjustment that was wanted.
    float lightRamp = rimRamp(tTop) * lightTop + rimRamp(tBottom) * lightBottom;
    float ramp = lightRamp * rimStrength;
    vec3 rim = vec3(
        rimBump(d, peak - aberration * 0.5, rimW),
        rimBump(d, peak, rimW),
        rimBump(d, peak + aberration * 0.5, rimW)
    ) * vec3(rimR, rimG, rimB) * ramp;
    emissive += rim;

    // The trough, three rim-widths in and twice as broad -- a soft dip,
    // not a second line. Scaled by the same `ramp` so it fades away from
    // the light exactly as the rim does; a trough that outlived its own
    // highlight would read as a drop shadow cast inward.
    emissive -= vec3(rimBump(d, peak * 3.0, rimW * 2.0) * trough * lightRamp);

    // Analytic silhouette, antialiased over the last pixel. Taken from
    // the distance field rather than from the source's own alpha so the
    // displacement above can never nibble at the corner arcs.
    float aa = clamp(0.5 - d, 0.0, 1.0);

    // Opacity comes from the SOURCE (`outAlpha`, computed above from the
    // centre tap plus the Fresnel term), not from a hardcoded 1.0. The
    // four popups this started on are opaque, so the two were the same
    // thing there -- but the bar's own side panes are deliberately
    // translucent (0x73 over the wallpaper, see shell.qml), and forcing
    // alpha would have quietly turned the one property they are built
    // around off. The centre tap matters too: the displacement has
    // already pulled it in from the silhouette, so it reads the pane's
    // real interior alpha and never the source's own antialiased edge --
    // the rounding is `aa`'s job alone and must not be applied twice.
    //
    // The rim, bevel and trough stay OUT of the transmitted colour's own
    // alpha: they are light on the surface, not more surface, so on the
    // translucent panes the highlight brightens what is behind the glass
    // instead of hiding it -- which is what a specular on a real pane
    // does.
    //
    // But light still has to be VISIBLE, and a premultiplied pixel with
    // alpha 0 is invisible whatever its colour. That matters because
    // several of the bar's chips have no fill at all (Hdr's badge,
    // ScriptModule's, ActiveWindow's #34383f00 -- they are shaped purely
    // by their edge), and on those `outAlpha` above is 0 everywhere and
    // the rim would simply not draw. So the emissive term carries its
    // own alpha, folded in over whatever the surface already has: a
    // filled pane barely moves (it is already dense where the rim is
    // brightest), a fill-less chip gets exactly its edge and nothing
    // else.
    // The MEAN of the three channels, not their max.
    //
    // With max, the brightest channel divides out to a full 1.0 once the
    // premultiplied colour is unpacked, so on a fill-less chip the outer
    // pixel -- where red's bump peaks and blue's has not started -- came
    // out as saturated gold instead of as a warm fringe. Seen on
    // ActiveWindow's chip, which has no fill at all.
    //
    // The mean leaves red above the alpha and blue below it, so the warm
    // side renders as an additive glow and the cool side as a slight
    // subtraction -- which is what dispersion looks like, and keeps the
    // fringe a fringe rather than a coloured outline.
    float emissiveAlpha = max(0.0, (emissive.r + emissive.g + emissive.b) / 3.0);
    float finalAlpha = min(1.0, outAlpha + emissiveAlpha * (1.0 - outAlpha));

    col += emissive;
    fragColor = vec4(max(col, vec3(0.0)), finalAlpha) * aa * qt_Opacity;
}
