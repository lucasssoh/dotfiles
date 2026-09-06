import QtQuick
import QtQuick.Shapes

// Reusable "pill with an optional second row that drops open below it"
// -- factored out so shell.qml's real central island (ActiveWindow/
// Workspaces/Media) and its own preview.qml mock share ONE
// implementation of the grow/shrink-with-a-drawer mechanics, instead of
// two independently-coded copies of the same thing drifting apart
// ("eviter de coder deux fois à la fois veille et preview"). Nothing in
// here knows about Veille specifically -- `drawerItem` is any Item,
// `drawerOpen` is whatever boolean the caller's own "observable"
// (Veille today, some other widget later -- "un widget qui se déclenche
// dans cet endroit sans que ça ne soit forcement Veille") currently
// wants shown; this is just the display block it plugs into. The first
// row is built from this Item's own default-property children, same
// convention Block.qml already uses for its single-row pills.
Item {
    id: root

    default property alias content: topRow.children

    // A STACK of drawer contents, not one exclusive slot. Each entry
    // opens and closes on its own `drawerOpen`, and the ones currently
    // open sit stacked under the top row in declaration order -- so
    // Veille showing its clock and the keybinds cheatsheet being held
    // open are not rivals for a single slot: the island simply extends
    // once further to fit both, then retracts by exactly that much when
    // one of them goes away. Asked for explicitly, replacing a
    // priority-based swap ("au lieu de changer, il s'etend une fois de
    // plus pour afficher keybinding") -- and the more coherent model
    // anyway: nothing has to be arbitrated away, and adding a third
    // widget later needs no new rule about who beats whom.
    //
    // The CONTRACT each entry has to meet (both current ones do, see
    // VeilleDrawerContent.qml / KeybindsDrawerContent.qml):
    //   - `property bool drawerOpen` -- its own show/hide state, bound
    //     by the caller (shell.qml) to whatever drives it.
    //   - `implicitHeight` -- how tall it is when fully open. Its
    //     `width` and `height` are driven from here; don't set them.
    //   - `Behavior on height` -- see `expanded` below for why the
    //     height animation is each entry's own rather than one
    //     sequence's here.
    // Objects declared inline in this list have no parent until the
    // Instantiator at the bottom of this file reparents them into
    // drawerColumn -- the same "pass a pre-built Item in as a slot"
    // idiom the single-slot version used, just once per entry.
    property list<Item> drawerItems

    // Counts rather than returning early on the first open entry: an
    // early return would leave the entries after it unread, and a
    // property this binding never read is a dependency QML never
    // registered, so a later entry opening or closing would not
    // re-evaluate this. Harmless with today's two (the stale answer
    // happens to match the correct one either way), but exactly the kind
    // of thing that turns into a silent non-updating binding the moment
    // a third entry joins the stack.
    readonly property int openCount: {
        let n = 0;
        for (let i = 0; i < root.drawerItems.length; i++) {
            if (root.drawerItems[i].drawerOpen) n++;
        }
        return n;
    }
    readonly property bool anyOpen: root.openCount > 0

    // Set once the WIDEN phase has finished, cleared at the start of the
    // close. Every entry's height is gated on it (see the Instantiator),
    // which is what still gets "l'elargissement d'abord et ensuite
    // l'allongement" out of a stack whose members come and go
    // independently: the first entry to open waits for the island to
    // reach full width, while any LATER one opening against an island
    // that is already wide just lengthens straight away -- no pointless
    // re-run of a widen phase that has nothing left to do.
    property bool expanded: false

    readonly property int margin: 6
    readonly property int cornerRadius: 18
    // The drawer block's own, deliberately rounder than the row pill's
    // (asked for: "arrondir beaucoup plus les coins du conteneur
    // principal"). Separate from `cornerRadius` above rather than a bump
    // to it: that one is also the row pill's shape, and the pill is only
    // ~24-31px tall, so any radius past half its height is clamped away
    // anyway -- raising it there would change nothing while quietly
    // reshaping centerIsland's own flush-top rim/gloss geometry too.
    property int drawerRadius: 30
    // 31 was tuned for centerIsland's own row (ActiveWindow/Workspaces/
    // Media) -- overridable now that TOOLS' row (METRICS-style icons,
    // originally a plain 24px-tall Block) needs to match METRICS' own
    // height instead, or its closed pill visibly sits lower/taller than
    // METRICS right next to it.
    property int rowHeight: 31
    // ---- reveal timings ----
    // Every default below is centerIsland's ORIGINAL value, and
    // centerIsland must keep getting exactly those: asked for explicitly
    // after a previous pass generalized this component and silently
    // dragged the middle island along with TOOLS ("il ne faut pas
    // affecter les animations et effet de l'island du milieu, les autres
    // sessions ont factorisé celui-ci avec les autres alors que je ne
    // voulais pas ça"). Being a shared component is not license to give
    // the two islands one shared feel -- the sharing is of MECHANICS,
    // and every number that makes up the feel is a knob the consumer
    // sets. toolsIsland overrides these in shell.qml; centerIsland
    // overrides nothing and is therefore untouched by anything here.
    //
    // `revealDuration` doubles as the PauseAnimation both open sequences
    // wait out before fading content in, so it MUST stay equal to the
    // duration of the `Behavior on height` of THAT island's own entries
    // (centerIsland: VeilleDrawerContent/KeybindsDrawerContent, both
    // 320; toolsIsland: NotificationCenter/BaliseHome, both 220). Lower
    // one without the other and the fade starts while the pane is still
    // stretching -- exactly the lockstep the staged reveal exists to
    // avoid.
    property int revealDuration: 320
    // How long the content fade itself takes, once the stretch is done,
    // and how long it takes to fade back out on close.
    property int contentFadeDuration: 200
    property int contentFadeOutDuration: 140
    // The drawer PANEL's own fade (opaqueProgress below), and the width
    // phase's two legs (twoPhase: true only -- see openSequence).
    property int panelFadeDuration: 260
    property int widenDuration: 260
    property int narrowDuration: 220
    // Breathing room between the row and the drawer block below it --
    // asked for explicitly ("ajoute un espace entre les tools et la
    // ligne"), now that the two are independent blocks rather than one
    // continuous shape (see opaqueProgress's own header below). This
    // gap is the ONLY thing separating them now that the hairline that
    // used to sit in it is gone (see the note where it was drawn).
    // Scaled by opaqueProgress like drawerFill itself, so it opens and
    // closes with it instead of permanently adding dead space to the
    // closed pill's own height.
    readonly property int drawerGap: 8

    // Visual chrome, generalized for a second consumer with a different
    // look (TOOLS' own floating pane, unlike centerIsland which is flush
    // against the screen's top edge) -- defaults below reproduce the
    // original hardcoded look byte-for-byte, so centerIsland itself is
    // untouched by this. `flushTop` mirrors Block.qml's own property of
    // the same name/meaning (square top corners + asymmetric GlassRim
    // when true, all 4 corners rounded + the METRICS/TOOLS-style
    // symmetric GlassRim pair when false). `fillGradient` (null by
    // default) takes precedence over `fillColor` when set, same
    // precedence Rectangle itself already gives gradient over color.
    property bool flushTop: true
    property color fillColor: "#000000"
    property Gradient fillGradient: null

    // The drawer block's own fill. Overridable per consumer because the
    // two islands want opposite things: TOOLS' drawers (Balise, the
    // notification center) put opaque cards on it and can therefore
    // afford a translucent panel, while centerIsland's drawers (Veille's
    // clock, the keybinds sheet) draw bare text straight onto it, where
    // translucency would eat legibility. Defaults reproduce the opaque
    // look both had before, so centerIsland is untouched.
    property color drawerFillTop: "#ff1e2128"
    property color drawerFillBottom: "#ff060608"

    // Pins the island's content width instead of letting it track its
    // own row -- asked for explicitly ("fixer la largeur pour match la
    // largeur du modules tools. il ne doit absolument pas bouger"). The
    // TOOLS row's own width genuinely fluctuates in normal use (the
    // battery percentage going 100 -> 9, the HDR chip appearing), and
    // every one of those moved the whole pill's left edge, drawer
    // included. `Math.max` with the row's own implicitWidth is pure
    // insurance: it only ever engages if the row grows past the pinned
    // value, where clipping icons would be worse than a rare nudge.
    property int fixedContentWidth: 0

    // The width arrow points ONE way, and it points from the row down into
    // the drawer: the Instantiator at the bottom of this file forces every
    // entry to `effectiveWidth`, and entries are expected to reflow into
    // whatever that turns out to be. Asked for: "la largeur du tiroir doit
    // suivre impérativement celle de la barre (pour les tiroirs à droite)".
    //
    // A `drawerDrivesWidth` opt-in briefly did the reverse here (an entry
    // declaring its own implicitWidth, the island stretching sideways to
    // host it). It is gone: with the TOOLS pill now sized to its own icons,
    // a drawer that set its own width would have made the island snap to a
    // different shape on open, which is exactly what pinning and then
    // unpinning that pill was working to get rid of.

    // Whether opening widens the island to `maxRowWidth` first.
    //
    // TRUE (centerIsland) is the original behaviour and the reason
    // maxRowWidth exists: its row holds genuinely variable content
    // (ActiveWindow's title, Media's marquee), so the drawer widens to a
    // fixed floor before revealing, and that floor deliberately counts
    // items that are not currently visible -- Media when nothing is
    // playing -- so the island does not resize when playback starts under
    // an open drawer.
    //
    // FALSE (toolsIsland) because that same "count everything" is wrong
    // for a pill that is supposed to hug its icons: `maxRowWidth` sums
    // every child's implicitWidth regardless of `visible`, so the hidden
    // Battery module was still in the total and opening a drawer widened
    // the pill by its 42px out of nowhere. That went unnoticed while the
    // row was pinned at a fixed 416 (the pin swallowed it); unpinning
    // made it visible. Measured: 356 closed, 398 open, for a row whose
    // content never changed.
    //
    // Fixed here rather than by teaching maxRowWidth to skip invisible
    // children, which would silently change centerIsland's floor -- the
    // one thing it must keep.
    property bool widenOnOpen: true

    // The row and the drawer are two independent blocks, not one shape
    // that grows taller -- asked for explicitly after the first fade
    // pass merged them into one continuous fill ("laisser le bloc tools
    // intact... le tiroir est un bloc à part"): the row's own `fill`
    // below stays exactly as it always was (fixed height, its usual
    // fillColor/fillGradient, no reaction to anyOpen at all) and
    // `drawerFill` further down is a wholly separate Rectangle that
    // simply doesn't exist (zero height) until something opens under it.
    // `opaqueProgress` is what that block's fade-in and the gap above it
    // both animate on: the row stays put, and the drawer FADES/GROWS
    // INTO the space below rather than the whole island darkening as one
    // slab.
    //
    // This is the PANEL's own fade, and it deliberately still runs
    // alongside the stretch: the empty pane has to be visibly there
    // while it extends, otherwise there is nothing to watch stretching.
    // What must NOT fade in with it is the panel's CONTENT -- that's
    // `contentProgress` below, a separate phase.
    property real opaqueProgress: root.anyOpen ? 1 : 0
    Behavior on opaqueProgress {
        NumberAnimation { duration: root.panelFadeDuration; easing.type: Easing.InOutCubic }
    }

    // 0 = drawer contents invisible, 1 = fully revealed. A SEPARATE
    // phase from opaqueProgress above, asked for explicitly: "S'etire
    // d'abord / Fade en affichant les elements une fois le tiroir
    // ouvert". Before this, every entry's opacity was bound straight to
    // its own height ratio (see opacityBinding in the Instantiator at
    // the bottom), so the content faded in *in lockstep with* the
    // stretch -- the two motions were one, which is the thing that was
    // wrong. Now the stretch happens against an empty pane, and only
    // once it has finished does this ramp the content in.
    //
    // Driven by the open/close sequences in BOTH twoPhase modes -- the
    // twoPhase:false path (TOOLS: notifications + Balise) previously had
    // no sequence at all, which is why an earlier attempt at this that
    // only touched openSequence/closeSequence changed nothing there.
    property real contentProgress: 0

    // centerIsland's own row holds genuinely variable-width content
    // (ActiveWindow's title, Media's marquee) -- widening to the fixed
    // `maxRowWidth` floor BEFORE revealing height avoids that content
    // visibly resizing while a drawer is already open (see
    // `maxRowWidth`'s own comment). TOOLS' row is effectively fixed-width
    // (no maxWidth hints anywhere in it -- see NotificationBell.qml's
    // header for why one was deliberately NOT added), so gating height
    // behind a width phase that has nothing real to do would just be a
    // pure, pointless delay before the drawer can even start opening
    // (asked for explicitly: "l'ideal c'est de ne pas elargir la largeur
    // d'abord... car ici le texte est fixe"). `twoPhase: false` skips the
    // sequencing entirely: `expanded` tracks `anyOpen` immediately, and
    // `openProgress` (still there for the rare case TOOLS' own row width
    // *does* shift slightly, e.g. BaliseButton's IconSlot animations)
    // gets its own plain, unblocking Behavior instead of being driven by
    // openSequence/closeSequence.
    property bool twoPhase: true
    // centerIsland's top row (ActiveWindow/Workspaces/Media) relies on
    // this 6px auto-spacing entirely, no manual spacers between its
    // children. TOOLS' own content instead uses spacing:0 plus hand-tuned
    // Item spacers per gap (documented "6 -> 3 -> 2" iteration in
    // shell.qml) -- exposed so a floating consumer can opt into that
    // same fine-grained control instead of double-spacing on top of it.
    property int rowSpacing: 6

    // The FULL height this could ever need -- every entry's
    // `implicitHeight` summed (i.e. all of them open at once), not their
    // current (possibly mid-animation, possibly closed) `height`. The
    // PARENT PanelWindow (shell.qml's
    // `bar`) sizes its own real Wayland surface off THIS, not off
    // `root.height` below -- so the surface itself is allocated once at
    // its maximum and never actually resized at the compositor level
    // while the drawer animates open/closed; only in-scene geometry
    // (this Item's own height, the fill Rectangle, GlassRim) changes
    // frame to frame. Real wl_surface resizes on every frame of a 300ms
    // animation is a plausible source of exactly the kind of hitch
    // reported ("l'island se retracte un peu" right at the start/end of
    // a transition) -- a live buffer renegotiation with the compositor
    // is a fundamentally heavier operation than an in-scene repaint.
    readonly property real maxHeight: {
        let total = root.rowHeight;
        // Only relevant once something can actually be open (an empty
        // stack never shows the gap either) -- matches implicitHeight's
        // own `drawerColumn.height > 0` gate below.
        if (root.drawerItems.length > 0) total += root.drawerGap;
        for (let i = 0; i < root.drawerItems.length; i++) {
            total += root.drawerItems[i].implicitHeight;
        }
        return total;
    }

    // The row's width at its OWN theoretical widest -- not a live
    // snapshot, a genuine constant: sums each top-row child's own
    // `maxWidth` (ActiveWindow.qml and Media.qml both already expose
    // one -- 258px each, by design symmetry) where it has one, falling
    // back to `implicitWidth` for anything that doesn't (Workspaces has
    // no growth mechanism to bound in the first place -- its own
    // implicitWidth already IS its max, for a given monitor's workspace
    // count). Asked for explicitly: "une large fixe à veille qui est la
    // taille maximum de activewindow + max workspaces + max media (+
    // les marges)" -- sizing the drawer off the island's continuously-
    // changing "current" width instead made whatever's showing visibly
    // resize/jitter while it was open, not just once when it first
    // appeared. Generic on purpose -- this file doesn't hardcode
    // knowing ActiveWindow/Workspaces/Media by name, any future item
    // dropped into the top row just needs to expose `maxWidth` (or not,
    // and get measured by its own current size instead).
    readonly property real maxRowWidth: {
        let total = Math.max(0, topRow.children.length - 1) * topRow.spacing;
        for (let i = 0; i < topRow.children.length; i++) {
            const child = topRow.children[i];
            total += (child.maxWidth !== undefined ? child.maxWidth : child.implicitWidth);
        }
        return total;
    }

    // 0 = fully closed (island tracks the row's own live width, ordinary
    // bar behavior), 1 = fully open (island pinned at the fixed
    // maxRowWidth floor) -- animated by openSequence/closeSequence
    // below. A pure 0..1 LERP FRACTION, not a raw pixel offset added on
    // top of a possibly-moving baseline (what this replaced): the old
    // version calibrated its boost once, against whatever topRow.
    // implicitWidth happened to be AT THE MOMENT it started animating,
    // and never revisited that number -- so switching to an empty
    // workspace (ActiveWindow shrinks) or stopping playback (Media
    // shrinks) WHILE the drawer was sitting open made the island
    // visibly retract, since the stale boost no longer summed back up
    // to the fixed floor. `effectiveWidth` below re-reads
    // topRow.implicitWidth LIVE on every recompute, at BOTH ends of the
    // lerp, so it's self-correcting instead: at openProgress 1 the
    // (topRow.implicitWidth - topRow.implicitWidth) terms cancel out
    // exactly regardless of what the row's current width actually is,
    // always landing on the true maxRowWidth. Asked for explicitly.
    property real openProgress: 0

    // If the row is narrower than the fixed maximum, Veille (or
    // whatever else opens here) is what stretches the island out to it
    // ("si island n'a pas de largeur max active, veille est censé
    // l'etendre") -- with the row's own (still just its compact current
    // self) content staying centered in the middle of that wider shape
    // (see topRow's own `x` below), not stretched or left flush.
    // `Math.max(0, ...)` never SHRINKS the island below what the row
    // itself currently needs, even if the row somehow exceeds
    // maxRowWidth.
    //
    // Snapped to an EVEN number of pixels, which is what keeps the top
    // row's own glyphs still while this animates. The island is centered
    // in the bar, so its left edge sits at (barWidth - islandWidth) / 2:
    // at a raw fractional width that edge lands on fractional pixels and
    // wobbles between them frame to frame, and ActiveWindow, Workspaces
    // and Media all render their text with NativeRendering, which
    // re-rasterizes glyphs against the pixel grid rather than sliding
    // them smoothly -- so sub-pixel drift shows up as the text visibly
    // shimmering in place. Worst exactly where it was reported, at the
    // very start and very end of the movement: InOutCubic is at its
    // slowest there, so the width creeps across those fractions for
    // several frames instead of passing through them. Even, not just
    // whole: halving an odd difference reintroduces the same .5 that was
    // being removed (the bar's own width is even).
    readonly property real effectiveWidth: {
        if (root.fixedContentWidth > 0)
            return Math.max(root.fixedContentWidth, topRow.implicitWidth);
        // `widenOnOpen: false` collapses the open-time term to zero, so
        // the island is simply its row, open or closed.
        const target = root.widenOnOpen ? root.maxRowWidth : topRow.implicitWidth;
        const raw = topRow.implicitWidth
            + root.openProgress * Math.max(0, target - topRow.implicitWidth);
        return Math.round(raw / 2) * 2;
    }

    implicitWidth: root.effectiveWidth + root.margin * 2
    // drawerColumn's own height is the live sum of its children's
    // (animating) heights -- the Column reflows as each entry grows or
    // shrinks, so entries below a closing one slide up on their own and
    // nothing here has to compute stacking offsets by hand.
    // Scaled by opaqueProgress, not a flat +drawerGap the instant
    // drawerColumn's own height leaves 0 -- that would pop in as one
    // discontinuous 8px jump on the very first frame of a grow/shrink
    // instead of easing in with the other thing the same progress
    // already drives (drawerFill's own opacity).
    implicitHeight: root.rowHeight + root.drawerGap * root.opaqueProgress + drawerColumn.height
    width: root.implicitWidth
    height: root.implicitHeight

    // Three-phase reveal: widen FIRST, then fade, then grow height --
    // asked for explicitly ("S'etire d'abord, Fade en affichant les
    // elements une fois le tiroir ouvert"). The width phase (openProgress)
    // happens first, *then* opaqueProgress (the fade) starts. On close,
    // this reverses: fade out first, wait for height to shrink, then
    // narrow back. `Easing.InOutCubic` on every leg -- asked for ("plutot
    // douce au demarrage et rapide au milieu puis re-douce à la fin").
    //
    // Only the WIDTH and OPACITY legs are animated here. The height legs
    // belong to the entries themselves (a `Behavior on height` each),
    // because with a stack there is no longer one height to sequence:
    // entries open and close independently, and a NumberAnimation here
    // could only ever drive whichever single item it was pointed at.
    // Sequencing survives the change because `expanded` -- flipped by the
    // ScriptAction below only AFTER the widen finishes -- is what
    // releases every entry's height binding; the ordering guarantee just
    // moved from "animate B after A" to "B cannot start until A says
    // so", which also holds for entries that open later.
    SequentialAnimation {
        id: openSequence
        // 1. Widen to max width first
        NumberAnimation {
            target: root
            property: "openProgress"
            to: 1
            duration: root.widenDuration
            easing.type: Easing.InOutCubic
        }
        // 2. Once wide, release the entries' height bindings -- they
        //    stretch open on their own `Behavior on height`.
        ScriptAction { script: root.expanded = true }
        // 3. Wait out that stretch, THEN fade the content in. The pause
        //    is what makes this a real second phase rather than two
        //    motions overlapping.
        PauseAnimation { duration: root.revealDuration }
        NumberAnimation {
            target: root
            property: "contentProgress"
            to: 1
            duration: root.contentFadeDuration
            easing.type: Easing.OutCubic
        }
    }
    SequentialAnimation {
        id: closeSequence
        // 1. Fade the content back out first -- the exact reverse of the
        //    open order, so the pane is empty again before it retracts.
        NumberAnimation {
            target: root
            property: "contentProgress"
            to: 0
            duration: root.contentFadeOutDuration
            easing.type: Easing.OutCubic
        }
        // 2. Then collapse the content's height
        ScriptAction { script: root.expanded = false }
        // 3. Wait for entries' height Behaviors to finish shrinking
        PauseAnimation { duration: root.revealDuration }
        // 4. Finally, narrow back to normal width
        NumberAnimation {
            target: root
            property: "openProgress"
            to: 0
            duration: root.narrowDuration
            easing.type: Easing.InOutCubic
        }
    }

    // twoPhase: false path -- no sequencing at all. `expanded` mirrors
    // `anyOpen` the instant it changes (so entries' own height Behaviors
    // start right away, nothing waits on a width phase), and both
    // `openProgress` and `opaqueProgress` track `anyOpen` through plain
    // Behaviors instead of the sequences above. `enabled` on the Binding/
    // Behavior (not an `if` in onAnyOpenChanged alone) so a LIVE toggle
    // of `twoPhase` itself would never leave either property stuck
    // half-owned by the wrong mechanism -- not something any current
    // caller does, but cheap insurance since both drive the same
    // property.
    Binding {
        target: root
        property: "openProgress"
        value: root.anyOpen ? 1 : 0
        when: !root.twoPhase
    }
    Behavior on openProgress {
        enabled: !root.twoPhase
        NumberAnimation { duration: root.widenDuration; easing.type: Easing.InOutCubic }
    }
    // ...but the CONTENT reveal is still sequenced even here. There is
    // no width phase to wait on in this mode (TOOLS pins
    // `fixedContentWidth`, so the island never actually widens -- the
    // only thing that stretches is the drawer growing DOWNWARD), so
    // these skip straight to the stretch and then fade, which is the
    // whole of "s'etire d'abord, fade ensuite" for a fixed-width island.
    //
    // Sequences rather than a Binding+Behavior on contentProgress: the
    // reveal has to START only after the stretch has finished, and a
    // Behavior can only stretch out a transition, not delay its start.
    SequentialAnimation {
        id: fastOpenSequence
        ScriptAction { script: root.expanded = true }
        PauseAnimation { duration: root.revealDuration }
        NumberAnimation {
            target: root
            property: "contentProgress"
            to: 1
            duration: root.contentFadeDuration
            easing.type: Easing.OutCubic
        }
    }
    SequentialAnimation {
        id: fastCloseSequence
        NumberAnimation {
            target: root
            property: "contentProgress"
            to: 0
            duration: root.contentFadeOutDuration
            easing.type: Easing.OutCubic
        }
        ScriptAction { script: root.expanded = false }
    }

    onAnyOpenChanged: {
        if (!root.twoPhase) {
            // Was a bare `root.expanded = root.anyOpen` -- which is
            // exactly why an earlier pass at the staged reveal appeared
            // to do nothing on TOOLS: with no sequence running here,
            // openSequence/closeSequence below are dead code in this
            // mode and editing them changed nothing that TOOLS renders.
            if (root.anyOpen) {
                fastCloseSequence.stop();
                fastOpenSequence.start();
            } else {
                fastOpenSequence.stop();
                fastCloseSequence.start();
            }
            return;
        }
        if (root.anyOpen) {
            closeSequence.stop();
            // Already wide with something else open: the widen phase has
            // nothing to do and `expanded` is already true, so the new
            // entry lengthens the island straight from its own Behavior.
            if (!root.expanded) openSequence.start();
        } else {
            openSequence.stop();
            closeSequence.start();
        }
    }

    // Same black fill + bottom-only rounding shell.qml's real central
    // island used to draw straight into itself -- flush against
    // whatever screen edge the PARENT is flush against (top corners
    // square), rounded at the bottom regardless of whether a drawer is
    // open below it. Non-flush consumers (TOOLS) get all 4 corners
    // rounded instead, same as Block.qml's own flushTop gating.
    // Fixed height (just the row), not anchors.fill: parent -- this is
    // the row's OWN pill, complete and unaffected on its own regardless
    // of anyOpen (see opaqueProgress's header above); `drawerFill` below
    // is the separate block that actually reacts.
    Rectangle {
        id: fill
        x: 0
        y: 0
        width: parent.width
        height: root.rowHeight
        topLeftRadius: root.flushTop ? 0 : root.cornerRadius
        topRightRadius: root.flushTop ? 0 : root.cornerRadius
        bottomLeftRadius: root.cornerRadius
        bottomRightRadius: root.cornerRadius
        color: root.fillColor
        gradient: root.fillGradient
    }

    // Flush-top treatment (centerIsland's original, only consumer until
    // now): symmetric light from directly below (hSpan: 0), not the
    // usual diagonal corner-to-corner ramp -- a single corner hotspot
    // read lopsided on a shape this wide. topOverflow pushes the traced
    // rect's top edge above the surface entirely, so only the bottom arc
    // (the one edge this flush-top shape actually has) ever paints.
    GlassRim {
        visible: root.flushTop
        target: fill
        cornerRadius: root.cornerRadius - 1
        lightOrigin: "bottomLeft"
        hSpan: 0
        strength: 0.35
        highlightColor: "#8e8e93"
        topOverflow: root.cornerRadius + 6
    }

    // Floating-pane treatment (all 4 edges visible, nothing to hide) --
    // the exact topLeft-full + bottomRight-faint pairing METRICS/TOOLS'
    // own Blocks already use elsewhere in this bar (see shell.qml).
    GlassRim {
        visible: !root.flushTop
        target: fill
        cornerRadius: root.cornerRadius
    }
    GlassRim {
        visible: !root.flushTop
        target: fill
        cornerRadius: root.cornerRadius
        lightOrigin: "bottomRight"
        strength: 0.45
    }

    // Second, fainter glossy catch-light toward the bottom-right, same
    // as before -- a soft RADIAL highlight echoing the diagonal
    // topLeft/bottomRight pairing GlassRim uses elsewhere, baked into
    // the fill since this shape carries no second rim to hang it off.
    Shape {
        id: gloss
        anchors.fill: fill
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: gloss.width * 1.05
                centerY: gloss.height * 1.15
                centerRadius: gloss.height * 1.1
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0.0; color: "#1cffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
            PathRectangle {
                x: 0; y: 0
                width: gloss.width
                height: gloss.height
                topLeftRadius: root.flushTop ? 0 : root.cornerRadius
                topRightRadius: root.flushTop ? 0 : root.cornerRadius
                bottomLeftRadius: root.cornerRadius
                bottomRightRadius: root.cornerRadius
            }
        }
    }

    // Top row -- centered within root's own (possibly wider than the
    // row itself, see `effectiveWidth` above) width, not just flush
    // left with margin, so it stays visually centered ("en gardant
    // compact au milieu les trois parties du island") whenever the
    // drawer's fixed maxRowWidth floor is wider than the row's own
    // current content.
    Row {
        id: topRow
        // Rounded for the same reason effectiveWidth is snapped even:
        // the row's own implicitWidth can be odd, and halving it puts
        // this offset back on a half pixel. NativeRendering text does
        // not tolerate that quietly -- it re-rasterizes rather than
        // sliding, so the row appears to vibrate horizontally.
        x: Math.round(root.margin + (root.effectiveWidth - topRow.implicitWidth) / 2)
        y: 0
        height: root.rowHeight
        spacing: root.rowSpacing
    }

    // The drawer's own block -- a wholly separate Rectangle from `fill`
    // above (asked for explicitly: "le tiroir est un bloc à part"), not
    // a taller version of the row's own pill. Zero height (invisible)
    // until something opens under it, then tracks drawerColumn's live
    // height exactly, so it grows/shrinks in lockstep with the content
    // without a second, separately-timed animation of its own -- only
    // its opacity gets one (opaqueProgress), fading it in/out alongside
    // the gap opening above it rather than popping in at full strength
    // the instant height leaves 0. Independently rounded on all 4 corners
    // (not just matching fill's bottom-only rounding) since it now reads
    // as its own distinct pane sitting under the row, not a continuation
    // of its shape. Same dark BatteryAlert.qml gradient as before --
    // constant now rather than lerped, since this block simply isn't
    // there at all when closed instead of needing a translucent rest
    // state to fade from.
    //
    // x/width match `fill` exactly (its full 0..parent.width span, not
    // drawerColumn's own margin-inset one) -- asked for explicitly
    // ("aligner le bloc tools et la largeur des elements tiroir"): the
    // row's icons sit inset by `margin` WITHIN fill, and drawerColumn's
    // own content sits inset by that same margin within THIS block, so
    // the two panes' outer edges line up while each still insets its
    // content identically.
    Rectangle {
        id: drawerFill
        x: 0
        y: root.rowHeight + root.drawerGap * root.opaqueProgress
        width: parent.width
        height: drawerColumn.height
        radius: root.drawerRadius
        opacity: root.opaqueProgress
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.drawerFillTop }
            GradientStop { position: 1.0; color: root.drawerFillBottom }
        }
    }

    // There was a hairline divider drawn across this seam (a 1px rule
    // growing from the centre outward on `opaqueProgress`, added when
    // the row and the drawer first became two separate blocks). It's
    // gone: asked to make it "completement transparente", and a fully
    // transparent rule is just an invisible Rectangle to maintain. The
    // separation now rests entirely on `drawerGap` plus the two blocks'
    // own distinct shapes -- the "ligne imaginaire" ended up genuinely
    // imaginary.

    // Where the stack lives. A plain Column: its height is the live sum
    // of its children's animating heights, and it re-lays-out on every
    // change, so an entry closing above another makes the one below
    // slide up without any offset arithmetic here.
    Column {
        id: drawerColumn
        x: root.margin
        y: root.rowHeight + root.drawerGap * root.opaqueProgress
        width: root.effectiveWidth
    }

    // One set of bindings per entry. An Instantiator rather than a
    // Repeater because these delegates are not visual children of
    // anything -- they exist only to own the three Bindings below and to
    // reparent their entry into drawerColumn once; the entry itself is
    // an already-built Item passed in from outside, not something a
    // delegate creates.
    Instantiator {
        model: root.drawerItems
        delegate: QtObject {
            required property var modelData

            property Binding widthBinding: Binding {
                target: modelData
                property: "width"
                value: root.effectiveWidth
            }
            // Closed is height 0; open is its natural implicitHeight --
            // but only once `expanded` says the widen phase is done (see
            // its own comment). The animation between the two is the
            // entry's own `Behavior on height`, part of the contract at
            // the top of this file.
            property Binding heightBinding: Binding {
                target: modelData
                property: "height"
                value: (modelData.drawerOpen && root.expanded) ? modelData.implicitHeight : 0
            }
            // The dévoilé (reveal) -- asked for back when Veille was the
            // only thing in here ("il est caché puis affiché
            // progressivement que le tiroir s'ouvre complement"), and
            // driven from here for EVERY entry rather than re-declared
            // by each content file, so the keybinds cheatsheet reveals
            // exactly the way Veille does instead of drifting from it.
            // `clip: true` (set below) already wipes the content in
            // top-to-bottom as `height` grows, but a plain wipe alone
            // reads as content getting cut off rather than unveiled.
            //
            // This USED to be the height ratio alone, which faded the
            // content in exactly in lockstep with the stretch -- the two
            // motions were one, and that is the thing that was asked to
            // change ("S'etire d'abord / Fade en affichant les elements
            // une fois le tiroir ouvert").
            //
            // The `min` of the two terms is what gets the staged reveal
            // without breaking the case it replaces:
            //   - FIRST entry to open: the island stretches while
            //     `contentProgress` is still 0, so the height ratio
            //     hits 1 with opacity pinned at 0 -- an empty pane
            //     extending. The sequence then ramps contentProgress and
            //     THAT term becomes the one doing the fade. Staged.
            //   - An entry opening LATER, against an island already
            //     open (contentProgress already 1): no stretch phase is
            //     being sequenced for it, so the height ratio is the
            //     smaller term and it fades in with its own growth --
            //     the original lockstep behaviour, which is still the
            //     right answer there.
            property Binding opacityBinding: Binding {
                target: modelData
                property: "opacity"
                value: modelData.implicitHeight > 0
                    ? Math.min(root.contentProgress, modelData.height / modelData.implicitHeight)
                    : 0
            }

            Component.onCompleted: {
                modelData.clip = true;
                modelData.parent = drawerColumn;
            }
        }
    }
}
