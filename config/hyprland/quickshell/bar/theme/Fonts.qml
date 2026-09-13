pragma Singleton
import QtQuick

// Central font definitions for the whole bar -- change `ui` here and
// every module picks it up, instead of hunting through ~20 individual
// `font.family:` lines. Cross-referenced with (and kept in sync by hand
// with) config/hyprland/theme/fonts.css, the real source of truth for
// Roue and Prisme -- QML can't @import a CSS file, so this is that
// value's Quickshell-side copy. See fonts.css's own header comment for
// the full picture across all 4 apps.
//
// `mono` is kept for any spot that genuinely needs fixed-width digits so
// fast-changing numbers don't jitter the layout -- currently unused
// (every module defaults to `ui`), opt back in per-module by swapping
// `font.family: Fonts.ui` for `font.family: Fonts.mono` where it
// actually matters.
//
// `icon` is the Nerd Font glyphs (battery/volume/network/cpu icons etc)
// render with -- those codepoints live in JetBrains Mono's own Nerd Font
// patch, not in the UI face, so leaving `font.family: Fonts.ui` on a Text that
// mixes an icon glyph with real text left the icon's shape/weight up to
// whatever fontconfig happened to fall back to. Modules that mix an icon
// with a value now use two Text items side by side (Fonts.icon + Fonts.ui)
// instead of one Text with both in the same string, so each renders with
// the font actually meant for it.
QtObject {
    // Was Inter, which holds up at 15px+ but goes mushy at the 11-13px
    // the bar actually runs at: this screen is 2560x1440 at scale 1
    // (~109 PPI), so a bar glyph gets barely 5-6 real pixels of x-height
    // and Inter's tight apertures close up at that size. MiSans Latin
    // (Xiaomi's HyperOS UI face, free for commercial use, downloaded
    // from hyperos.mi.com/font-download/MiSans_Latin.zip and installed
    // by config/fonts/install.sh) was picked for the opposite trade:
    // open counters, low stroke contrast, slightly narrower advance --
    // all of which survive being rasterised that small, which is the
    // whole reason a phone UI face reads at a phone's physical size.
    //
    // IMPORTANT: the family string is the bare "MiSans Latin", NOT one
    // of the per-weight names fc-list also prints ("MiSans Latin
    // Medium", "MiSans Latin Normal", ...). MiSans ships its 10 weights
    // the way Inter does -- one family with the whole weight range
    // reachable through it -- so the bare name keeps `font.bold: true`
    // working (~20 modules rely on it). Pinning a per-weight family
    // instead silently kills bold everywhere: that family holds ONE
    // face, Qt finds nothing bolder, and the ActiveWindow badge just
    // renders regular. Verified on screen, not guessed.
    //
    // The bare name is also not as light as MiSans' own "Regular"
    // suggests: MiSans splits the middle of its range into Regular
    // (fc weight 53) AND Normal (68), so the face fontconfig actually
    // returns for a plain 400 request is Medium (`fc-match "MiSans
    // Latin"` -> MiSansLatin-Medium.ttf). That lands a touch heavier
    // than Inter Regular did, which is exactly what the small sizes
    // wanted -- no per-module weight bump needed.
    readonly property string ui: "MiSans Latin"
    readonly property string mono: "JetBrains Mono"
    readonly property string icon: "JetBrainsMono Nerd Font"

    // Font Awesome 6 Free/Brands -- first icon-font POC (still used for
    // `iconSolid`/`iconBrand` wherever nothing below has taken over yet).
    // `iconSolid` needs `font.weight: Font.Black` alongside it -- Font
    // Awesome 6 Free ships Regular (400, outline) and Solid (900, filled)
    // as the SAME family name, disambiguated by weight/style, not a
    // separate family string (verified via `fc-match`). `iconBrand` is a
    // genuinely separate family ("Font Awesome 6 Brands") -- product/
    // protocol logos (bluetooth, steam, discord) live there, not in Free.
    readonly property string iconSolid: "Font Awesome 6 Free"
    readonly property string iconBrand: "Font Awesome 6 Brands"

    // Phosphor -- second POC, now applied on Bluetooth/Temperature/Fan/
    // Battery in place of Font Awesome there (same root motivation: ONE
    // coherent family instead of Nerd Font's multi-project patchwork).
    // Tried instead of the real SF Symbols: Apple's own license
    // explicitly restricts SF Symbols to apps built FOR Apple platforms,
    // so it can't legally go in a Linux/Hyprland bar -- Phosphor is MIT-
    // licensed and, unlike Font Awesome, actually ships SF Symbols'
    // core idea: several DISTINCT weights of the same glyph set (thin/
    // light/regular/bold/fill/duotone) instead of a fixed
    // outline-or-filled split. Downloaded from the official
    // @phosphor-icons/web npm package (MIT, verified via its own
    // LICENSE file), installed to ~/.local/share/fonts.
    // Each weight is its OWN family/file (not one variable font with a
    // weight axis, unlike the Font Awesome Regular/Solid trick above) --
    // `fc-list` confirms this, so each needs its own `Fonts.` entry
    // rather than a shared name + `font.weight`. `iconPhosphor` is the
    // Regular weight specifically, chosen to track the UI face's own
    // default (400) body weight -- the same "icon weight should track
    // the type weight next to it" idea SF Symbols itself is built around.
    // LUCIDE TEST ------------------------------------------------------
    //
    // Third icon-font POC, asked for as a straight A/B against Phosphor.
    // Lucide (ISC, the maintained community fork of Feather) ships a
    // real icon TTF in the `lucide-static` npm package -- family
    // "lucide", ONE face, 2118 glyphs -- installed to
    // ~/.local/share/fonts the same way Phosphor was.
    //
    // The trade versus Phosphor is a real one, not a wash: Lucide has
    // exactly ONE weight. Phosphor's whole reason for being picked over
    // Font Awesome was the SF-Symbols idea of several distinct weights
    // of the same glyph set, and this bar leans on that -- 17 sites on
    // Bold, 3 on Fill. Under Lucide all three families below resolve to
    // the same face, so:
    //   - the Bold/Regular hierarchy between the METRICS/TOOLS blocks
    //     and the rest flattens out;
    //   - NotificationBell's filled-while-unread state is gone, which
    //     is why its unread glyph moved from bell-simple to lu-bell-dot
    //     (a dot ON the bell) -- the state now rides the glyph instead
    //     of the weight;
    //   - the transport buttons (skip/play/pause) go from solid to
    //     outline.
    // Lucide also inks a little wider and thinner inside its em-box than
    // Phosphor Bold does at the same pixelSize, so glyphs read lighter
    // at the bar's 11-15px without any size change.
    // The three properties below keep their `iconPhosphor*` NAMES on
    // purpose -- ~36 call sites across 20 modules reference them, and
    // renaming all of those would bury the one thing this test is
    // actually about (the glyphs) in churn. They now all resolve to the
    // single Lucide face. There is deliberately NO runtime toggle back
    // to Phosphor: the per-module glyph literals are Lucide codepoints
    // now, so swapping only the family would render 36 wrong glyphs.
    // Going back to Phosphor means reverting this commit, not flipping
    // a flag.
    readonly property string iconLucide: "lucide"

    readonly property string iconPhosphor: iconLucide

    // Was Phosphor-Bold; under the Lucide test it is the same single
    // face as `iconPhosphor`, and the note below is kept only so the
    // hierarchy it describes can be put back on revert.
    //
    // Bold weight, same "separate family per weight" deal as above --
    // confirmed via `fc-list` (Phosphor-Bold.ttf -> family "Phosphor-Bold",
    // not "Phosphor" + font.weight: Font.Bold, which does nothing on this
    // font). Opt-in per module, same as `mono` -- the OSD (Osd.qml, asked
    // for specifically: "plus grand et plus gras") and, since the
    // "thicken toutes les polices icones" pass, every Phosphor glyph in
    // the METRICS and TOOLS blocks (Cpu/Temperature/Fan/Memory/Traffic,
    // AudioOutput/AudioInput/BaliseButton/Performance/NotificationBell).
    // Bold is a whole extra family here, so those modules' glyphs ink a
    // touch wider than the Regular ones did -- the two blocks' pill
    // widths follow their content, so nothing needed re-measuring.
    readonly property string iconPhosphorBold: iconLucide

    // Was Phosphor-Fill; under the Lucide test it too collapses onto the
    // single face, which is the one substantive thing the test costs --
    // see NotificationBell.qml for what replaced it there.
    //
    // Fill weight -- solid glyphs, not an outline. Another whole family,
    // same as Bold above. Used to carry a STATE rather than a hierarchy:
    // NotificationBell inks solid while something is unread and goes back
    // to an outline once it is read, which reads at a glance in a way the
    // outline weights do not differ enough to.
    readonly property string iconPhosphorFill: iconLucide

    // Clash Grotesk (Fontshare/Indian Type Foundry, free) -- Veille's
    // clock/message font, downloaded via api.fontshare.com's CSS
    // endpoint (the fonts.com share page itself is a JS app with no
    // static download link) and installed to ~/.local/share/fonts same
    // as Phosphor above. Regular/Bold specifically came back with a
    // broken name table (`fc-list` shows family "false" for those two),
    // so only Light/Medium/Semibold got kept; each is its own family
    // string, same "separate family per weight" deal as Phosphor above.
    // `clock` (Medium) is the clock digits; `clockLight` is the message/
    // quote underneath, asked for specifically ("un font plus light pour
    // le quote").
    readonly property string clock: "Clash Grotesk Medium"
    readonly property string clockLight: "Clash Grotesk Light"
    readonly property string clockSemibold: "Clash Grotesk Semibold"
}
