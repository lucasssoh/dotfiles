pragma Singleton
import QtQuick

// Foreground palette -- everything that is DRAWN ON a surface rather than
// being one: text, icon glyphs, the filled part of a meter, a state dot.
// Surfaces.qml is the other half of the pair and owns the opposite side
// (panel fills, card fills, their hovers); the two are deliberately
// separate files because the flip this exists to enable moves one of them
// and not the other -- see the MATERIAL note at the bottom.
//
// Why this file exists at all, in the same terms Surfaces.qml's own
// header uses: `#f2f2f7` was written out by hand 66 times across 20
// modules, `#8e8e93` 21 times, `#ff6e6e` 16. That is not a palette, it is
// the same decision re-taken 130 times, and it cannot be re-taken
// consistently once it is spread that far. Measured, not estimated: of
// the 66 `#f2f2f7` sites, 56 sit on a Text, and the other 10 are still
// foreground (BatteryIcon's outline/fill, Osd's meter fill, the
// colour-returning functions in Battery/Performance/NotificationBell).
// One meaning, one name.
//
// The tiers below are the ones the bar ALREADY used -- this file names
// what was there, it does not re-decide it. No value changed when the 130
// sites were migrated onto it; that was the point, and it was verified as
// a pixel-identical screenshot rather than assumed.
QtObject {
    // Position on the dark<->light axis, so `ink.t` is readable whichever
    // of the three ramps a module was handed -- InkBlend animates it, these
    // two are its endpoints. The glass chips need it: their rim is ADDITIVE
    // light (glass.frag: `emissive += rim`), so it has to fade out as the
    // material goes light, where added light cannot be seen.
    readonly property real t: 0.0

    // ---- the neutral ramp, brightest first ---------------------------
    // Four tiers, all four genuinely in use before this file existed
    // (66 / 21 / 7 / 3 sites respectively). `primary` is nearly
    // everything, which is itself worth knowing: the bar currently has
    // almost no typographic hierarchy, and giving the tiers names is the
    // precondition for changing that.
    readonly property color primary: "#f2f2f7"
    readonly property color secondary: "#8e8e93"
    readonly property color muted: "#636366"
    readonly property color faint: "#48484a"

    // ---- state colours ------------------------------------------------
    // `danger` is the threshold colour Cpu/Temperature/Memory swap to at
    // 90% (and BatteryAlert's whole accent). `accent` is the same
    // desaturated platinum token Hyprland's active border uses -- shared
    // on purpose, see shell.qml's header.
    readonly property color danger: "#ff6e6e"
    readonly property color accent: "#a8b4c4"
    // Charging green (BatteryRing/Battery/BatteryAlert) and the darker
    // "playing" green Media's transport disc and Performance's power-saver
    // profile share (colors.lua's `play` token).
    readonly property color positive: "#a3d9a5"
    readonly property color play: "#237823"
    // HDR-on cyan. Two sites (Hdr.qml's glyph and its chip rim), but it is
    // a STATE colour like the two above and belongs with them rather than
    // alone in one module.
    readonly property color hdr: "#6be3e8"

    // ---- MATERIAL: the light twin ------------------------------------
    // InkLight.qml is that twin and it is live: the band's three exposed
    // islands are handed an interpolation between the two ramps
    // (theme/InkBlend.qml), driven by hypr/scripts/bar-tint.py's
    // measurement of the wallpaper behind them. Centralising the 130
    // sites is what made that a per-instance change instead of a second
    // migration.
    //
    // The bar's band is `#730c0c0e`: alpha 0x73, so it blocks only 45% of
    // the wallpaper and 55% comes through. Measured over a white
    // wallpaper the composite lands at 145, where `primary` above scores
    // 2.81:1 -- below WCAG AA, and `monochrome-tree.jpg` in the wallpaper
    // cache already does exactly that. `onLight` scores 6.24:1 on the same
    // background.
    //
    // Flipping the INK ALONE does not work and the number is worth
    // keeping here so it is not re-derived: the crossover sits at
    // wallpaper grey 201, where both inks score 4.18:1 -- both below AA,
    // so a binary ink flip has a dead zone exactly where it switches.
    // Flipping the MATERIAL (band goes light, ink goes dark, together)
    // moves the crossover to grey 115 where both sides score ~8.7:1, and
    // guarantees 8.65:1 across the whole 0-255 range.
    //
    // Only the band flips. The drawers, the OSD and BatteryAlert sit over
    // WINDOWS rather than over the wallpaper, so they have nothing to
    // sample and keep the dark ramp above permanently -- which is why
    // this is a plain second token and not a mode switch on `primary`.
    readonly property color onLight: "#0c0c0e"
}
