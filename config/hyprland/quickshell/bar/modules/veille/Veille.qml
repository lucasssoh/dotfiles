import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../../theme"
import "../"

// VEILLE -- a large, non-interactive clock that pulses briefly around
// each round hour at night (see VeillePhase.qml's `inPulse`) to make the
// passage of time hard to ignore during focused work/study, without
// sitting permanently on screen -- escalating through the evening, with
// occasional context-aware messages once it's late enough. Full design
// rationale in the project plan (temporal-drifting-hippo.md); this file
// is purely the wiring: VeilleConfig (hot-reloaded JSON) -> VeillePhase
// (time -> escalation level + pulse timing) + VeilleContext (focused
// window -> app family/token) -> VeilleMessages (what to say, and how
// often) -> the actual PanelWindow.
//
// Deliberately a single instance, not one per screen like `bar` -- a
// big clock repeated on every monitor would be noise, and unlike the bar
// (which needs one real surface per screen it spans), this is describing
// a single thing: how late it's gotten.
// Scope, not Item: this whole tree is a grouping container for logic
// components (VeilleConfig/Phase/Context/Messages) and one real window
// (the PanelWindow below), never itself rendered -- Scope is Quickshell's
// purpose-built non-visual QObject container (see quickshell-core's
// ReloadPropagator/Scope), so nothing here inherits Item's geometry
// properties it would never use.
Scope {
    id: root

    // Bound in from shell.qml -- Zen mode is a shared property on the
    // ShellRoot (`shell.zenMode`), not something this module can see on
    // its own without either a singleton or this kind of pass-through
    // (same idea as ActiveWindow.qml's `monitor` property).
    property bool zenMode: false

    VeilleConfig { id: config }

    SystemClock {
        id: sysClock
        precision: config.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Debug time override (see the IpcHandler below) -- a fixed offset
    // applied to the real clock rather than a frozen fake Date, so
    // seconds/phases keep advancing naturally from wherever `setNow`
    // pointed them, instead of a still image. Only reachable when
    // veille.json has "debug": true.
    property real debugOffsetMs: 0
    readonly property date now: new Date(sysClock.date.getTime() + root.debugOffsetMs)

    VeillePhase {
        id: phase
        config: config
        now: root.now
    }

    VeilleContext {
        id: context
        config: config
    }

    VeilleMessages {
        id: messages
        config: config
        phase: phase
        context: context
        now: root.now
    }

    // Mode gaming: profile Performance OR the focused window is
    // fullscreen (see the plan's own rationale -- both signals already
    // exist elsewhere in this bar/repo, nothing new to read). By explicit
    // choice this changes NOTHING by default -- it only feeds
    // `muteWhileGaming` below, which stays false unless set in
    // veille.json.
    readonly property bool gaming:
        PowerProfiles.profile === PowerProfile.Performance
        || (context.ipc !== null && context.ipc.fullscreen !== 0)

    readonly property bool suppressed:
        !config.enabled
        || !phase.phaseVisible
        || !phase.inPulse
        || (config.respectZenMode && root.zenMode)
        || (config.muteWhileGaming && root.gaming)

    // ---- placement ----------------------------------------------------
    function pickScreen() {
        const wanted = config.monitor;
        if (wanted === "") return Quickshell.screens[0] || null;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === wanted) return Quickshell.screens[i];
        }
        return Quickshell.screens[0] || null;
    }

    readonly property var activeScreen: root.pickScreen()

    // Docked under the bar's central island (ActiveWindow/Workspaces/
    // Media), asked for explicitly -- top-anchored, centered on the
    // SCREEN's own horizontal center. Reading straight off the screen
    // rather than reaching into shell.qml's own `centerIsland` geometry
    // (Veille is one Scope instance; `bar`/`centerIsland` are one
    // PanelWindow per screen under Variants -- no shared property to
    // read it from without new cross-file wiring) still matches exactly:
    // centerIsland's own x/width were reworked to stay symmetric around
    // that same fixed point regardless of which side (ActiveWindow or
    // Media) is driving its growth (see that file's own comment), so
    // there's no drift left to chase any more. `barHeight` mirrors
    // shell.qml's `bar`/`barRow`/`centerIsland` height (31) -- keep the
    // two in sync by hand if that ever changes.
    readonly property int barHeight: 31
    readonly property int gapBelowBar: 10

    // ---- screen-relative sizing -----------------------------------------
    // Asked for: the clock's size is a FRACTION OF THE SCREEN'S WIDTH,
    // not a raw pixel font size -- "proportionnel à la taille de l'ecran
    // pas mesuré au pixel". A 1440p/4K panel gets a genuinely bigger
    // clock instead of the same pixel count read smaller. ONE fixed
    // fraction (config.widthFraction) at every phase now, not an
    // escalation -- dropped, asked for explicitly ("garde la même taille
    // pour chaque heure").
    //
    // TextMetrics measures THIS font rendering THIS exact string once at
    // a reference size (100px) -- `width / 100` is then "screen pixels
    // of rendered width per 1px of font.pixelSize" for this font/string
    // combo, however wide its glyphs actually are. Solving that ratio
    // for the target width (a fraction of the screen) gives the
    // font.pixelSize that hits it exactly, without hardcoding or
    // guessing a character-width constant.
    TextMetrics {
        id: clockMetrics
        font.family: Fonts.clock
        font.pixelSize: 100
        text: config.showSeconds ? "00:00:00" : "00:00"
    }
    readonly property real clockWidthPerPixelSize: clockMetrics.width / 100

    // The width the clock text should occupy on THIS screen -- stored
    // separately from the font.pixelSize it implies (below) so clockText
    // can be pinned to this exact width directly. Fonts.clock isn't
    // monospace, so this also keeps the surrounding glass card from
    // resizing as the visible digits change.
    readonly property real clockTargetWidth:
        config.widthFraction * (root.activeScreen ? root.activeScreen.width : 1920)

    readonly property int clockPixelSize:
        Math.round(root.clockTargetWidth / Math.max(0.001, root.clockWidthPerPixelSize))

    // Everything else in the overlay (date/message text, the Column's
    // own spacing, the glass card's padding/corner radius below) scales
    // off the clock's own resolved size rather than a second, independent
    // screen-based factor -- one reference number, so the whole thing
    // grows/shrinks as one piece regardless of screen. Ratios carried
    // over from the previous fixed-pixel version (16/48, 15/48, 6/48
    // relative to its old default 48px clock).
    readonly property int dateTextSize: Math.round(root.clockPixelSize * 0.32)
    readonly property int messageTextSize: Math.round(root.clockPixelSize * 0.3)
    readonly property int columnSpacing: Math.round(root.clockPixelSize * 0.08)
    readonly property int cardPadding: Math.round(root.clockPixelSize * 0.28)
    readonly property int cardRadius: Math.round(root.clockPixelSize * 0.16)

    PanelWindow {
        id: overlay
        screen: root.activeScreen

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "veille"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        color: "transparent"
        focusable: false
        exclusiveZone: 0
        // Empty region = accepts input NOWHERE on this surface, so every
        // click/scroll passes straight through to whatever's behind it
        // -- the one hard requirement from the plan ("ne bloque jamais
        // les clics"). First use of PanelWindow.mask in this repo (see
        // the plan's own risk list); an empty Region is the documented
        // Quickshell idiom for full click-through.
        mask: Region {}

        // Mapped whenever there's a screen to put it on, regardless of
        // `suppressed` -- the open/close animation below (`card.scale`)
        // needs the surface to stay mapped THROUGH the retract, which an
        // instant unmap would prevent. Same always-mapped-but-animated-
        // invisible pattern Osd.qml already uses for its own show/hide.
        visible: root.activeScreen !== null

        // Top-anchored + spanning the full width (left+right both
        // anchored, the same trick `bar`'s own PanelWindow in shell.qml
        // uses for its centered island) -- layer-shell has no "anchor to
        // screen center" primitive, so a full-width surface with its
        // CONTENT centered inside is the standard way to get a
        // horizontally-centered floating panel. margins.top clears the
        // bar + a small gap below it.
        anchors { top: true; left: true; right: true }
        margins {
            top: root.barHeight + root.gapBelowBar
            left: 0
            right: 0
        }

        implicitHeight: content.implicitHeight + root.cardPadding * 2

        // Solid, pure opaque black -- dropping the translucent glass
        // gradient this used to carry (Osd.qml's own treatment): "un
        // fond noir pur opaque, peu importe l'heure". GlassRim still
        // traces the edge -- it's an independent border highlight, not
        // dependent on the fill being translucent -- kept for the same
        // rim-light read the rest of the bar uses.
        Rectangle {
            id: card
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: content.implicitWidth + root.cardPadding * 2
            height: content.implicitHeight + root.cardPadding * 2
            // Rounded on all four corners again -- asked for explicitly
            // ("garde l'arrondi de bordure partout"). A previous pass
            // squared off three of them for a corner-flush layout; now
            // that the card floats under the bar instead of hugging a
            // screen corner, there's no straight screen edge to justify
            // that any more.
            radius: root.cardRadius
            color: "#000000"

            // Zoom in/out from the TOP edge (where it's anchored, right
            // under the bar) -- asked for, after a horizontal slide
            // (tried in between) got asked to be swapped back: turned
            // out the SLIDE wasn't the fix, the easing was -- "utilise un
            // simple zoom avec un bon ease-in ease-out ou mieux un
            // spring". SpringAnimation, matching the same "physical
            // settle" tuning Osd.qml's own track fill already uses,
            // rather than a plain eased tween.
            transformOrigin: Item.Top
            scale: root.suppressed ? 0 : 1
            Behavior on scale {
                SpringAnimation { spring: 3; damping: 0.3 }
            }

            GlassRim { cornerRadius: root.cardRadius }
            GlassRim { cornerRadius: root.cardRadius; lightOrigin: "bottomRight"; strength: 0.45 }

            Column {
                id: content
                anchors.centerIn: parent
                spacing: root.columnSpacing

                Text {
                    id: clockText
                    // Left-anchored, same as messageText below -- asked
                    // for explicitly ("aligne l'horloge avec le quote").
                    // Both share the exact same width (clockTargetWidth)
                    // and AlignLeft, so their glyphs start flush at the
                    // same x regardless of how much of that width either
                    // string's own glyphs actually fill -- AlignHCenter
                    // on just the clock (the previous state) put its
                    // digits centered WITHIN that box while the quote
                    // sat flush left in an identically-positioned box,
                    // so the two visibly didn't line up even though
                    // their boxes did.
                    anchors.left: parent.left
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    // Fonts.clock (Clash Grotesk Medium) -- latest of
                    // several tried here (Fonts.mono, Nosifer, DSEG7
                    // Classic, Liberation Serif all came before it).
                    // `width`/`horizontalAlignment` below pin the box to
                    // the phase's computed target width explicitly
                    // instead of leaving the Text auto-sized (Fonts.clock
                    // isn't monospace).
                    font.family: Fonts.clock
                    font.pixelSize: root.clockPixelSize
                    width: root.clockTargetWidth
                    horizontalAlignment: Text.AlignLeft
                    // Slightly warm off-white, not pure white -- asked
                    // for explicitly ("pas de blanc parfait mais
                    // legerement creme").
                    color: "#f2ecd9"
                    text: Qt.formatDateTime(root.now, config.showSeconds ? "HH:mm:ss" : "HH:mm")

                    // Size (not opacity any more -- that escalation was
                    // dropped, see phases' own comment in VeilleConfig.qml)
                    // should still be FELT arriving, not snap.
                    Behavior on font.pixelSize {
                        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                    }
                    Behavior on width {
                        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                    }
                }

                Text {
                    id: dateText
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: config.showDate
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    font.family: Fonts.ui
                    font.pixelSize: root.dateTextSize
                    color: "#8e8e93"
                    text: Qt.formatDateTime(root.now, "dddd d MMMM")
                }

                Text {
                    id: messageText
                    // Left-anchored, not centered -- asked for
                    // explicitly ("l'ancrer à gauche"). Width matches
                    // the clock's own target width exactly, so the
                    // message block's left edge lines up with the
                    // clock's rather than floating independently.
                    anchors.left: parent.left
                    width: root.clockTargetWidth
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    // Fonts.clockLight -- a lighter weight than the
                    // clock's own Fonts.clock (Medium), asked for
                    // explicitly ("un font plus light pour le quote").
                    font.family: Fonts.clockLight
                    font.pixelSize: root.messageTextSize
                    // Dimmer cream, not cool gray -- same warm shift as
                    // clockText's own color, kept proportionally dimmer.
                    color: "#c9c4b3"
                    text: messages.text
                    opacity: messages.text !== "" ? 0.9 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    // ---- debug / development hooks -------------------------------------
    // Everything here is a no-op unless veille.json has "debug": true --
    // asked for explicitly (the plan's own verification section): there
    // is no input-injection tool in this environment, so exercising the
    // five phases / midnight event / cooldown without waiting for the
    // real clock needs a way to fast-forward it, and filling in
    // appFamilies/tokenPatterns needs a way to see the REAL class/title
    // of whatever's focused, rather than guessing.
    IpcHandler {
        target: "veille"

        // `qs -c bar ipc call veille setNow "01:12"` -- jumps the
        // effective clock to that time today, then lets it keep ticking
        // forward normally from there (see root.debugOffsetMs above).
        function setNow(hhmm: string): void {
            if (!config.debug) {
                console.warn("[veille] setNow ignored -- set \"debug\": true in veille.json first");
                return;
            }
            const parts = hhmm.split(":");
            const h = parseInt(parts[0], 10) || 0;
            const m = parseInt(parts[1], 10) || 0;
            const target = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate(), h, m, 0);
            root.debugOffsetMs = target.getTime() - sysClock.date.getTime();
        }

        // Clears the debug offset, back to the real clock.
        function resetNow(): void {
            root.debugOffsetMs = 0;
        }

        // `qs -c bar ipc call veille probe` -- prints the REAL class and
        // title Hyprland reports for whatever's focused right now, so
        // veille.json's appFamilies/tokenPatterns can be filled in from
        // fact instead of guesswork (see VeilleContext.qml's header
        // comment on why the table starts mostly empty).
        function probe(): string {
            if (!config.debug) return "veille debug disabled -- set \"debug\": true in veille.json";
            return "class=[" + context.windowClass + "] title=[" + context.windowTitle
                + "] family=[" + context.family + "] token=[" + context.token
                + "] level=" + context.level;
        }
    }
}
