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
    //
    // Zero unless the drawer is its own block: with `splitDrawer: false`
    // there are no two blocks to separate in the first place, the island
    // is one continuous shape, and any gap here would just be a band of
    // its own fill nothing is ever drawn into.
    // Settable, not readonly any more: the split look does not have to
    // mean a VISIBLE split. TOOLS now sets this to 0 to sit its drawer
    // flush under the row ("enlever la ligne imaginaire"), keeping
    // `splitDrawer` true only for the mechanism it really needs --
    // `drawerFill`, the pane that carries the drawer's own background.
    // Dropping splitDrawer instead would have left that drawer with no
    // background at all: TOOLS also sets `rowPane: false`, so the
    // island's own `fill` is invisible and there would be nothing left
    // to paint behind the notification cards.
    property int drawerGap: root.splitDrawer ? 8 : 0


    // Where the drawer BLOCK starts, in island-local coordinates.
    // Defaults to this island's own row, which is what it always
    // implicitly was -- so centerIsland is unaffected.
    //
    // TOOLS needs it to differ. Its row is 24px, but the bar band behind
    // it (shell.qml's `barBand`) is 31 -- sized on centerIsland's row,
    // not on this island's. With the gap removed, the drawer pane
    // therefore started 7px INSIDE the band, and since both are now the
    // same translucent BandTint.band, those 7px stacked two 45% layers
    // into roughly 70% and drew a visibly darker strip right at the
    // seam. Reported live: "deux translucide accentue l'opacité et du
    // coup il y a un fond plus prononcé sur l'intersection".
    //
    // Stacking is the whole hazard of tinting a surface the same colour
    // as the one behind it, and the answer is to butt the two edges
    // rather than overlap them: the drawer starts where the band ends.
    property real drawerTop: root.rowHeight

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

    // Whether the drawer is a SEPARATE block sitting under the row, or
    // simply the island itself getting taller.
    //
    // FALSE (centerIsland, the default) is the original behaviour and
    // the one it must keep: ONE shape, `fill` spanning the whole island,
    // its own colour, growing downward as the drawer opens -- "il ne
    // doit pas partir d'une ligne imaginaire mais directement c'est
    // l'island qui s'etend (comme avant) et avec ses couleurs". No gap,
    // no second pane, no second fill: the row's pill just becomes taller
    // and the drawer's content is drawn straight onto it. This is why
    // the drawer entries here (Veille's clock, the keybinds sheet) can
    // draw bare text with no card behind them.
    //
    // TRUE (toolsIsland) is the two-block look asked for there ("laisser
    // le bloc tools intact... le tiroir est un bloc à part"): the row's
    // pill keeps a fixed height and its own shape, and `drawerFill`
    // below is a wholly separate rounded pane that fades/grows in under
    // it across `drawerGap`, hosting opaque cards (notifications,
    // Balise).
    //
    // A previous pass made the two-block look unconditional, which
    // dragged centerIsland into a look that was never meant for it --
    // the same mistake the timing knobs above already document. Sharing
    // MECHANICS is not sharing the look: every visual difference between
    // the two islands is a knob the consumer sets.
    property bool splitDrawer: false

    // false = this island's ROW draws no background whatever: no fill,
    // no gloss, no edge. Set by TOOLS, whose surface is now shell.qml's
    // full-width `barBand` rather than a pill of its own -- the island
    // is then only its content, plus the drawer below it, which is a
    // separate block and is untouched by this.
    //
    // This replaces a switch that stood the row's GlassRims down in
    // favour of a GlassLens. That lens is gone with the pill it was
    // edging, and the whole `!flushTop` rim treatment with it: TOOLS was
    // its only consumer, so those two rims had already become
    // unreachable and are deleted rather than kept as dead branches.
    property bool rowPane: true

    // Convex glass on the island's own block instead of a traced rim --
    // asked for on the central island: "plus de border classique pour
    // l'island centre, mais un effet du convexe pour lui et ses
    // extensions".
    //
    // Its extensions come along for free: with `splitDrawer` false the
    // drawer IS this same `fill` grown tall, so one lens covers the row
    // and whatever opens below it as a single pane, which is the whole
    // point of that look.
    //
    // Opt-in from shell.qml rather than a changed default, because
    // DrawerIsland is shared.
    property bool rowLens: false

    // The drawer block's own fill. Overridable per consumer because the
    // two islands want opposite things: TOOLS' drawers (Balise, the
    // notification center) put opaque cards on it and can therefore
    // afford a translucent panel, while centerIsland's drawers (Veille's
    // clock, the keybinds sheet) draw bare text straight onto it, where
    // translucency would eat legibility. Read only when `splitDrawer` is
    // true -- centerIsland has no second pane to colour, its drawer IS
    // the island's own `fillColor`.
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

    // Pins the DRAWER's content width, independently of the row above
    // it -- asked for ("une largeur fixe pour balise et notif, plus en
    // fonction de la largeur de tools"). 0 (the default, and what
    // centerIsland keeps) means the old behaviour exactly: the drawer is
    // the row, and every expression below collapses to what it was.
    //
    // This is the one place the width arrow documented below is allowed
    // to be cut rather than reversed. The drawer still does not DRIVE the
    // island -- an entry declaring its own implicitWidth is still not a
    // thing -- it is simply told a constant instead of being told the
    // row. That distinction is what keeps the island from snapping to a
    // different shape on open: the row's own width is untouched by any of
    // this, so the band above the drawer never moves.
    //
    // Why it was needed: the TOOLS row legitimately changes width in
    // normal use -- the battery module appears when discharging, the
    // "hdr" word appears when HDR is on -- and the drawer inherited every
    // one of those. Measured on this machine, the same Balise panel was
    // 296px wide with both absent and 367px with the hdr badge present:
    // a 70px swing in a panel whose own content had not changed at all.
    property int fixedDrawerWidth: 0

    // Where the drawer band wants its CENTRE, in this island's own
    // coordinate space (the same space `drawerBandX` is expressed in).
    // -1, the default, keeps the right-aligned band every island had
    // until now -- so centerIsland and toolsIsland go through exactly the
    // code they went through before.
    //
    // Why it exists: launchersIsland's row is five chips and the drawer
    // is about ONE of them, so a band glued to the island's right edge
    // points at whichever chip happens to be last rather than at the one
    // the panel names. Asked for ("centrer le milieu du tiroir avec
    // l'icone en question"). Only that island sets it, and it sets it
    // from the chip the panel is about -- not from the pointer -- so the
    // band stays put while the pointer travels down into it.
    property real drawerAnchorX: -1

    // The row's own horizontal inset inside the island, published for the
    // one thing that cannot compute it from outside: a `drawerAnchorX`
    // derived from the position of one of this row's CHILDREN. A child's
    // x is relative to topRow, drawerAnchorX is relative to the island,
    // and this is the term between the two. Read-only, and there is no
    // mapToItem in the chain on purpose -- that is a function call, not a
    // binding, and the anchor has to re-derive itself whenever a chip
    // appears or disappears beside the one the panel is about.
    readonly property real rowContentX: topRow.x

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

    // In the SPLIT look only (`splitDrawer: true`, TOOLS -- centerIsland
    // is one shape that grows taller and none of the paragraph below
    // applies to it), the row and the drawer are two independent blocks
    // -- asked for explicitly after the first fade
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

    // No reveal at all -- the pane is simply there, at full height, and
    // fades. Asked for, for launchersIsland: "pas d'effet tiroir, juste
    // un fade rapide".
    //
    // It is not a shorter `twoPhase: false`. That mode still SEQUENCES
    // (stretch, wait out `revealDuration`, then fade the content), and
    // the stretch is the thing being refused here, not its duration. So
    // this reduces `onAnyOpenChanged` to a single assignment: `expanded`
    // is whatever `anyOpen` says on that frame, `openProgress` follows it
    // through a Binding with no Behavior, and `contentProgress` is the
    // only thing left with a duration.
    // Combined with dropping the entry's own `Behavior on height` (see
    // LauncherActions.qml), the pane reaches its full height on the frame
    // it opens and the only thing moving is opacity.
    //
    // Why THAT island and not the other two: it opens on a hover now, and
    // it holds three verbs. A staged reveal is for a panel you settle
    // into -- it was ~780ms here (260 widen + 220 stretch + 320 pause +
    // 200 fade) before anything was readable, which is longer than the
    // pointer is going to be there.
    property bool instantDrawer: false

    // The thick-glass edge traced around the drawer block (GlassLens, see
    // drawerFill below). Off gives a flat pane -- the fill and nothing
    // else -- which is what a drawer whose fill is already one constant
    // colour wants: the lens is a light source, and there is no gradient
    // under it here for it to be the light FOR. Asked for ("il faut juste
    // un bg plat"), and it also takes an FBO the size of the pane out of
    // a panel that opens and closes on hover.
    property bool drawerLens: true
    // centerIsland's top row (ActiveWindow/Workspaces/Media) relies on
    // this 6px auto-spacing entirely, no manual spacers between its
    // children. TOOLS' own content instead uses spacing:0 plus hand-tuned
    // Item spacers per gap (documented "6 -> 3 -> 2" iteration in
    // shell.qml) -- exposed so a floating consumer can opt into that
    // same fine-grained control instead of double-spacing on top of it.
    property int rowSpacing: 6

    // The height this island needs with its TALLEST single entry open.
    // A genuine constant, not a live snapshot: it reads each entry's
    // `implicitHeight`, never their current (possibly mid-animation,
    // possibly zero) `height`.
    //
    // The PARENT PanelWindow (shell.qml's `bar`) sizes its own real
    // Wayland surface off THIS, not off `root.height` below -- so the
    // surface is allocated once and never resized at the compositor
    // level while a drawer animates. Only in-scene geometry (this
    // Item's own height, the fill Rectangle, GlassRim) changes frame to
    // frame. That matters: a live wl_surface renegotiation is a
    // fundamentally heavier operation than an in-scene repaint, and
    // sizing this dynamically was tried and produced a hitch visible on
    // the opening frame of every drawer.
    //
    // `max`, not `sum`. This replaced a version that totalled EVERY
    // entry -- the honest answer to "how tall could this ever get", but
    // the wrong question: entries only take height when their own
    // `drawerOpen` is set (see heightBinding further down,
    // `(drawerOpen && expanded) ? implicitHeight : 0`) and exactly one
    // is ever open at a time. The sum was unreachable by construction,
    // and asking the compositor for 2250px to show a ~600px
    // notification centre cost real work every frame -- see shell.qml's
    // implicitHeight for the WAYLAND_DEBUG capture and the numbers.
    //
    // The gap is included only when there is something to separate: an
    // empty stack never shows it either.
    readonly property real openHeight: {
        let tallest = 0;
        for (let i = 0; i < root.drawerItems.length; i++) {
            tallest = Math.max(tallest, root.drawerItems[i].implicitHeight);
        }
        return tallest > 0 ? root.drawerTop + root.drawerGap + tallest : root.rowHeight;
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

    // ---- drawer geometry -------------------------------------------------
    //
    // Three derived numbers, and all three are identities when
    // `fixedDrawerWidth` is 0 -- drawerContentWidth == effectiveWidth,
    // drawerBandX == 0, drawerBandWidth == the island's own width -- so
    // centerIsland goes through exactly the code it went through before.
    //
    // The band is RIGHT-aligned on the island, not centred on it: this
    // island is anchored to the right edge of the bar, so a drawer wider
    // than its row has to grow leftward or it grows off the screen. It
    // also keeps the one alignment that was asked for when the row and
    // the drawer first became two blocks ("aligner le bloc tools et la
    // largeur des elements tiroir") -- their right edges still line up,
    // which is the edge both are anchored to.
    //
    // ...unless `drawerAnchorX` names a point to centre on instead, which
    // only launchersIsland does: its row is five interchangeable chips
    // rather than one fixed set of modules, so "the island's right edge"
    // stops being a meaningful thing for its drawer to point at. See that
    // property.
    readonly property real drawerContentWidth: root.fixedDrawerWidth > 0
        ? root.fixedDrawerWidth : root.effectiveWidth
    // Offset of the drawer band within the island, negative when the
    // drawer is the wider of the two. Ints, and published, because
    // shell.qml's input mask has to reproduce this band exactly -- see
    // the note there about a Region that reads a `rect` never following
    // it.
    readonly property int drawerBandTargetX: {
        // Right-aligned, the default and the only behaviour until
        // `drawerAnchorX` existed -- see the paragraph above for why that
        // is the right answer for an island anchored to the bar's right
        // edge.
        if (root.drawerAnchorX < 0)
            return Math.round(root.effectiveWidth - root.drawerContentWidth);
        // Centred on the anchor instead. `- margin` because the band's
        // own x is its OUTER edge while the anchor names a point in the
        // content: drawerBandWidth is drawerContentWidth plus a margin at
        // each end (see just below), so the content's centre sits half a
        // content-width past the outer edge plus that one margin.
        const raw = root.drawerAnchorX - root.margin - root.drawerContentWidth / 2;
        // Clamped against the WINDOW, not against the island: a 210px
        // pane centred on a 22px chip legitimately overhangs both of the
        // island's own edges (that is the whole point), but an overhang
        // past the bar's left or right edge is a pane with a piece
        // missing. `root.x` is the island's offset in that window, so
        // these two limits are the window's edges expressed in island
        // coordinates. Falls back to the left limit alone before there is
        // a parent to measure.
        const leftLimit = -root.x;
        if (!root.parent) return Math.round(Math.max(leftLimit, raw));
        const rightLimit = root.parent.width - root.drawerBandWidth - root.x;
        return Math.round(Math.max(leftLimit, Math.min(rightLimit, raw)));
    }
    // Slides rather than jumps when the anchor moves from one chip to the
    // next under a travelling pointer -- the pane is already open and
    // fully visible at that point, so a hard cut would read as a second
    // panel replacing the first. Gated on the pane actually being on
    // screen: opening and closing must place the band instantly, or the
    // first frame of a reveal would come out of wherever the LAST one
    // ended. Matches the row hover tint's own 120ms rather than the
    // reveal's much slower 320 -- this is a correction, not an entrance.
    // Published separately from the target above, and NOT readonly, for
    // one reason: a Behavior animates a property by writing to it, which
    // a readonly property will not accept. Nothing outside writes it --
    // the binding below is its only source.
    property int drawerBandX: root.drawerBandTargetX
    Behavior on drawerBandX {
        enabled: root.opaqueProgress > 0.99
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
    readonly property int drawerBandWidth: Math.round(root.drawerContentWidth + root.margin * 2)
    // drawerColumn's own height is the live sum of its children's
    // (animating) heights -- the Column reflows as each entry grows or
    // shrinks, so entries below a closing one slide up on their own and
    // nothing here has to compute stacking offsets by hand.
    // Scaled by opaqueProgress, not a flat +drawerGap the instant
    // drawerColumn's own height leaves 0 -- that would pop in as one
    // discontinuous 8px jump on the very first frame of a grow/shrink
    // instead of easing in with the other thing the same progress
    // already drives (drawerFill's own opacity).
    implicitHeight: root.drawerTop + root.drawerGap * root.opaqueProgress + drawerColumn.height
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
        when: !root.twoPhase || root.instantDrawer
    }
    Behavior on openProgress {
        // ...and not even a Behavior in `instantDrawer`: that mode's whole
        // point is that nothing about the island's SHAPE animates.
        enabled: !root.twoPhase && !root.instantDrawer
        NumberAnimation { duration: root.widenDuration; easing.type: Easing.InOutCubic }
    }

    // `instantDrawer`'s last moving part. `expanded` is not here -- it is
    // assigned straight from `onAnyOpenChanged` below, the same way the
    // two fast sequences assign it in `twoPhase: false` mode. A
    // declarative Binding on it was tried first and the drawer never
    // opened at all: `expanded` is a property three ScriptActions also
    // write imperatively, and mixing the two ways of owning one property
    // is how it ends up owned by neither. `contentProgress` gets a
    // Binding because nothing else writes it in this mode, and it needs
    // the Behavior below.
    //
    // A Binding + Behavior rather than a sequence precisely because there
    // is nothing to wait for any more: the delayed START that a
    // SequentialAnimation exists to express IS the effect being removed.
    Binding {
        target: root
        property: "contentProgress"
        value: root.anyOpen ? 1 : 0
        when: root.instantDrawer
    }
    Behavior on contentProgress {
        enabled: root.instantDrawer
        NumberAnimation {
            duration: root.anyOpen ? root.contentFadeDuration
                                   : root.contentFadeOutDuration
            easing.type: Easing.OutCubic
        }
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
        // Nothing to sequence: `expanded` is simply what `anyOpen` says,
        // on this frame, and openProgress/contentProgress are owned by
        // the two Bindings above.
        if (root.instantDrawer) {
            root.expanded = root.anyOpen;
            return;
        }
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
    // Height depends on which look this island is in (see `splitDrawer`):
    //   - splitDrawer FALSE (centerIsland): the WHOLE island, row and
    //     open drawer together, exactly as it always was -- one shape in
    //     one colour that simply gets taller. Everything hung off `fill`
    //     below (the GlassRim, the gloss) follows it down automatically,
    //     so the rim stays on the real bottom edge of the extended
    //     island rather than stranded at the row's own.
    //   - splitDrawer TRUE (toolsIsland): just the row, fixed, complete
    //     and unaffected by anyOpen (see opaqueProgress's header above);
    //     `drawerFill` below is the separate block that reacts.
    Rectangle {
        id: fill
        visible: root.rowPane
        x: 0
        y: 0
        width: parent.width
        height: root.splitDrawer ? root.rowHeight : root.height
        topLeftRadius: root.flushTop ? 0 : root.cornerRadius
        topRightRadius: root.flushTop ? 0 : root.cornerRadius
        bottomLeftRadius: root.cornerRadius
        bottomRightRadius: root.cornerRadius
        color: root.fillColor
        gradient: root.fillGradient

        // See `rowLens`. Square top corners are passed through honestly:
        // this island is flush against the screen's top edge, and a lens
        // that rounded them would notch the silhouette the Rectangle
        // actually draws.
        layer.enabled: root.rowLens
        layer.effect: GlassLens {
            topRadius: root.flushTop ? 0 : root.cornerRadius
            bottomRadius: root.cornerRadius
            // Flush against the screen's top edge: that edge gets no
            // treatment at all, the island simply melts into the border.
            // Comfortably past the 7px band plus the rim's reach.
            topOverflow: root.flushTop ? 18 : 0
            // Card values, not the popups': this pane is 31px tall when
            // shut, and a 14px band would be most of it. It still reads
            // once a drawer grows it -- the band lives at the edge, and
            // the edge is where the eye looks either way.
            band: 7
            depth: 2.5
            aberration: 0.8
            rimThickness: 2.0
            rimStrength: 0.30
            trough: 0.13
            fresnel: 0.0
            specular: 0.10
            rimColor: "#8e8e93"
        }

    }

    // Flush-top treatment (centerIsland's original, only consumer until
    // now): symmetric light from directly below (hSpan: 0), not the
    // usual diagonal corner-to-corner ramp -- a single corner hotspot
    // read lopsided on a shape this wide. topOverflow pushes the traced
    // rect's top edge above the surface entirely, so only the bottom arc
    // (the one edge this flush-top shape actually has) ever paints.
    GlassRim {
        visible: root.flushTop && root.rowPane && !root.rowLens
        target: fill
        cornerRadius: root.cornerRadius - 1
        lightOrigin: "bottomLeft"
        hSpan: 0
        strength: 0.35
        highlightColor: "#8e8e93"
        topOverflow: root.cornerRadius + 6
    }

    // The floating-pane rim pair (topLeft full + bottomRight faint) that
    // used to sit here is gone -- see `rowPane` above for why nothing
    // could reach it any more.

    // Second, fainter glossy catch-light toward the bottom-right, same
    // as before -- a soft RADIAL highlight echoing the diagonal
    // topLeft/bottomRight pairing GlassRim uses elsewhere, baked into
    // the fill since this shape carries no second rim to hang it off.
    // Stood down under `rowLens` as well: this radial is a PAINTED
    // convexity, and stacking it under a real one gives the pane two
    // highlights disagreeing about where the light is.
    Shape {
        id: gloss
        visible: root.rowPane && !root.rowLens
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
    // Only exists in the split look -- with `splitDrawer: false` the
    // island's own `fill` above already spans the drawer, in the
    // island's own colour, and a second pane on top of it would be
    // precisely the separate block centerIsland must not have.
    Rectangle {
        id: drawerFill
        visible: root.splitDrawer
        x: root.drawerBandX
        y: root.drawerTop + root.drawerGap * root.opaqueProgress
        width: root.drawerBandWidth
        height: drawerColumn.height
        radius: root.drawerRadius
        opacity: root.opaqueProgress
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.drawerFillTop }
            GradientStop { position: 1.0; color: root.drawerFillBottom }
        }

        // Thick-glass edge -- see GlassLens.qml / shaders/glass.frag.
        // This replaces the GlassRim that used to be traced around this
        // block (symmetric light from below, #8e8e93 at 0.35): the same
        // source and the same ramp, now curved and dispersed.
        //
        // Only the PANEL goes through the lens, not the drawer's
        // contents -- drawerColumn is a sibling, not a child, so the
        // cards and text sit ON the glass rather than in it. That is
        // also the physically right answer, and it keeps every card edge
        // in the notification list crisp.
        //
        // Gated rather than left on: an FBO the size of this block is
        // not something to keep allocated for a drawer that is shut most
        // of the time.
        layer.enabled: root.drawerLens && root.splitDrawer && root.opaqueProgress > 0.01
        layer.effect: GlassLens {
            radius: root.drawerRadius
            // The greyer, fainter edge this block already had.
            rimStrength: 0.22
            rimColor: "#8e8e93"
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
        // `drawerBandX + margin`, NOT a bare `margin`. This is the line
        // that decides whether the drawer's contents sit centred in the
        // pane or glued to its left: the pane moved (drawerFill above),
        // and the content inset has to move with it. Leaving this at
        // `margin` is precisely how a fixed-width drawer ends up with its
        // cards hanging off one side of the block they are supposed to be
        // inside -- the pane widens leftward and the column does not
        // follow, so every entry keeps starting where the ROW starts.
        x: root.drawerBandX + root.margin
        y: root.drawerTop + root.drawerGap * root.opaqueProgress
        width: root.drawerContentWidth
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
                value: root.drawerContentWidth
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
