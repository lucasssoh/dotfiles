import QtQuick
import "../services"

// A ramp that sits BETWEEN Ink and InkLight, at a position `t` the caller
// animates. Not a singleton: each bar has its own, because each screen
// decides its own material.
//
// This exists because the flip has to be a fade and an object swap cannot
// fade. Handing a module `Ink` one frame and `InkLight` the next makes
// every glyph jump, and putting a `Behavior on color` at each of the ~34
// call sites to cover that would be 34 chances to forget one -- and they
// would still drift out of step with the band, which is a separate
// animation with its own clock.
//
// So nothing here is animated at all. `t` is, once, by whoever owns it,
// and all ten colours below are plain bindings on it. One clock, one
// easing, every glyph and the band underneath them moving together by
// construction rather than by everyone being given the same duration.
//
// `band` is deliberately part of this and not left in shell.qml: it is
// the surface those inks are read against, and the entire reason the
// ramps differ. Animating the two separately is exactly the desync this
// component exists to make impossible.
QtObject {
    id: blend

    // 0 = dark material, 1 = light material. Put a Behavior on it where
    // it is assigned -- see shell.qml's `bar`.
    property real t: 0

    // Straight linear interpolation in sRGB, which is what
    // ColorAnimation itself does, so the band and the ink travel the same
    // curve. Both endpoints of the neutral tiers are near-achromatic so
    // the midpoint is a plain grey; the state colours pass through a
    // muted version of their own hue rather than through grey, which is
    // the right transit for them and comes out of the same lerp for free.
    function mix(a, b) {
        return Qt.rgba(a.r + (b.r - a.r) * blend.t,
                       a.g + (b.g - a.g) * blend.t,
                       a.b + (b.b - a.b) * blend.t,
                       a.a + (b.a - a.a) * blend.t);
    }

    // Same property names as Ink/InkLight -- that is the whole contract:
    // a module's `ink` can hold any of the three and it cannot tell.
    readonly property color primary: blend.mix(Ink.primary, InkLight.primary)
    readonly property color secondary: blend.mix(Ink.secondary, InkLight.secondary)
    readonly property color muted: blend.mix(Ink.muted, InkLight.muted)
    readonly property color faint: blend.mix(Ink.faint, InkLight.faint)
    readonly property color danger: blend.mix(Ink.danger, InkLight.danger)
    readonly property color accent: blend.mix(Ink.accent, InkLight.accent)
    readonly property color positive: blend.mix(Ink.positive, InkLight.positive)
    readonly property color play: blend.mix(Ink.play, InkLight.play)
    readonly property color hdr: blend.mix(Ink.hdr, InkLight.hdr)
    readonly property color onLight: blend.mix(Ink.onLight, InkLight.onLight)

    // The band these inks are read against. Alpha is 0x73 at both ends,
    // so the lerp moves colour only and the wallpaper never shows through
    // by a different amount mid-transition -- the same reasoning
    // shell.qml's barBand records for why its two gradient stops kept a
    // constant alpha.
    readonly property color band: blend.mix(BandTint.bandDark, BandTint.bandLight)
}
