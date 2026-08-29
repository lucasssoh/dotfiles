import QtQuick
import Quickshell
import Quickshell.Io
import "i18n/fr.js" as CatalogFr
import "i18n/en.js" as CatalogEn
import "i18n/grammar.js" as Grammar
import "i18n/fr-grammar.js" as GrammarFr

// Picks WHEN and WHAT to show under the clock. Never renders anything
// itself -- Veille.qml owns the fade/hold animation, this just exposes
// `text` (empty string = nothing to show right now).
//
// Two sources feed it, mixed on every draw:
//
//   * the CURATED catalogs (i18n/fr.js, i18n/en.js) -- whole sentences
//     written by hand, kept because some of them are better than anything
//     a grammar produces and there was no reason to lose them.
//   * the GRAMMAR (i18n/grammar.js + i18n/fr-grammar.js) -- patterns and
//     fragments assembled into sentences that were never written down.
//
// The grammar exists because the curated pools got NARROWER the better
// the context matched: at 23:30 in a terminal the eligible set was
// byFamily.terminal.serious plus .reflective, four sentences, drained in
// forty minutes at the default interval -- while an unrecognized window
// fell back to `generic` and got thirty-two. Widening the pools would
// only have raised that ceiling; every line still had the same shape, so
// the mould stayed recognizable however many lines you wrote. See
// i18n/grammar.js's header for how the three-level draw fixes that.
//
// Anti-repetition works differently on each side, on purpose. Curated
// pools keep the shuffle bag they always had (draw without replacement,
// reshuffle only when empty, never open the new deck on the card that
// just came out) -- a pool of sixteen needs exactly that. The grammar
// can't use a bag, because its eligible set changes from draw to draw as
// the context does; it uses per-bank recency rings instead, plus a ring
// of the last forty RENDERED sentences that survives a restart.
Scope {
    id: root

    property var config: null    // VeilleConfig
    property var phase: null     // VeillePhase
    property var context: null   // VeilleContext
    property date now: new Date()

    // Startup grace period: a message the instant the bar restarts would
    // fire on every quickshell reload during development, and reads as
    // nagging right at login -- not tied to messageIntervalMinutes, this
    // is a one-time settle window.
    //
    // A real elapsed-time timer, NOT `now - startedAt`: `now` is the
    // debug-shifted clock (see Veille.qml's setNow), so comparing it
    // against a real-clock start date made the grace window depend on
    // which way the debug clock had been moved -- jumping it backwards
    // left pastGrace false permanently, silently disabling every message
    // for the rest of the session. That's a trap whether or not anyone
    // is debugging, and a timer has no opinion about the clock at all.
    readonly property int graceMs: 60000
    property bool pastGrace: false

    Timer {
        interval: root.graceMs
        running: true
        repeat: false
        onTriggered: root.pastGrace = true
    }

    readonly property bool english: root.config && root.config.language === "en"
    readonly property var catalog: root.english ? CatalogEn.catalog : CatalogFr.catalog

    // English has no grammar yet -- it falls back to curated-only, which
    // is a complete, working system, just a smaller one. Writing ~290
    // fragments twice before knowing the French ones survive contact
    // would have been the wrong order.
    readonly property var grammar: root.english ? null : GrammarFr.grammar

    // How often a draw starts from the hand-written catalog rather than
    // the grammar. Not 0 and not 1 on purpose: the curated lines are the
    // ones with a voice, the generated ones are the ones you can't see
    // coming, and the mix is what keeps both.
    readonly property real curatedRatio:
        (root.config && root.config.curatedRatio !== undefined) ? root.config.curatedRatio : 0.35

    property string text: ""

    // Read-only view of the persisted streak, for Veille.qml's `probe`
    // and for the tone weighting.
    readonly property int streak: (state.nights && state.nights.count) || 0

    // ---- persisted state -------------------------------------------------
    // Survives a quickshell restart (bar crash/reload) -- without this,
    // every restart would immediately re-fire a message regardless of how
    // recently one was actually shown, since in-memory state resets to
    // zero. Quickshell.statePath() is the documented spot for exactly
    // this kind of small durable state (see its own header in
    // quickshell-core.qmltypes); separate from veille.json, which the
    // user hand-edits and this file never writes to.
    //
    // `recent` and the streak pair joined it for the grammar: a ring of
    // rendered sentences is worthless if it empties on every reload, and
    // "third night in a row" is by definition not knowable in-memory.
    FileView {
        id: stateFile
        path: Quickshell.statePath("veille-state.json")
        printErrors: false
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: state
            property real lastShownAt: 0
            property var recent: []

            // The night index and the streak live in ONE object because
            // they're written together. Two back-to-back assignments to
            // this adapter inside a single function do not both survive:
            // the second one reads a stale value for the first, and the
            // first is lost by the time anything reads it again (measured
            // -- `streak` came back 0 while `lastNightIndex` had taken).
            // `onAdapterUpdated: writeAdapter()` re-enters per property,
            // so the only safe shape is one assignment per fact.
            property var nights: ({ index: 0, count: 0 })
        }
    }

    // ---- shuffle bags (curated pools only) --------------------------------
    // Keyed by an arbitrary pool id (e.g. "generic:serious",
    // "byFamily:ide:humorous") so every distinct pool gets its own
    // independent deck -- switching families/tones between draws doesn't
    // perturb a pool's own remaining cards.
    property var bags: ({})

    function shuffled(array) {
        const a = array.slice();
        for (let i = a.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
    }

    // Draws one entry from `pool` (an array of template strings),
    // remembering position across calls under `poolId`. Returns "" for
    // an empty/missing pool rather than throwing -- callers fall back to
    // a broader pool when that happens.
    function draw(poolId, pool) {
        if (!pool || pool.length === 0) return "";
        if (pool.length === 1) return pool[0];   // nothing to shuffle

        let bag = root.bags[poolId];
        if (!bag) {
            bag = { deck: [], last: "" };
            root.bags[poolId] = bag;
        }
        if (bag.deck.length === 0) {
            let fresh = root.shuffled(pool);
            // Guarantee against "empties, reshuffles, draws the exact
            // same line it just showed" -- swap it out of the front slot.
            if (bag.last !== "" && fresh[0] === bag.last) {
                const swapAt = 1 + Math.floor(Math.random() * (fresh.length - 1));
                [fresh[0], fresh[swapAt]] = [fresh[swapAt], fresh[0]];
            }
            bag.deck = fresh;
        }
        const picked = bag.deck.shift();
        bag.last = picked;
        return picked;
    }

    // ---- grammar memory ----------------------------------------------------
    // Seeded lazily rather than in Component.onCompleted: the state file
    // loads asynchronously, and the grace period guarantees nothing draws
    // for the first minute anyway, so by the first real call `state` is
    // populated. Doing it eagerly would seed from an empty adapter and
    // silently lose the ring across every restart.
    property var memoryStore: Grammar.newMemory()
    property bool memorySeeded: false

    function memory() {
        if (!root.memorySeeded) {
            root.memorySeeded = true;
            const saved = state.recent || [];
            for (let i = 0; i < saved.length; i++)
                Grammar.ringPush(root.memoryStore.messages, saved[i], root.recentRingSize);
        }
        return root.memoryStore;
    }

    readonly property int recentRingSize: 40

    // ---- context ------------------------------------------------------------
    // The object the grammar reasons over. Every field is either a fact
    // the compositor reported or a fact this file persisted -- nothing is
    // guessed, so a fragment gated on one of them is never wrong when it
    // fires, only absent when the fact isn't there.
    function messageContext(tone) {
        const family = root.context ? root.context.family : "";
        const phaseName = root.phase ? root.phase.phaseName : "late";

        return {
            tone: tone,
            phase: phaseName,
            family: family,
            facets: (root.grammar && root.grammar.facets[family]) || [],
            token: root.context ? root.context.token : "",
            level: root.context ? root.context.level : 0,
            time: Qt.formatDateTime(root.now, "HH:mm"),
            dayIndex: root.now.getDay(),
            hours: Math.floor((root.phase ? root.phase.minutesSince("late") : 0) / 60),
            sameFamilyMinutes: root.context ? root.context.sameFamilyMinutes : 0,
            churn: root.context ? root.context.churn : 0,
            streak: state.streak,
            weekend: root.context ? root.context.weekend : false,
            midnightPassed: phaseName === "midnight" || phaseName === "veryLate"
        };
    }

    // ---- slot substitution (curated templates) ------------------------------
    // The grammar fills its own slots (it has to gate on which ones
    // resolve). This one is only for the hand-written catalogs, whose
    // templates always substitute -- hence the Math.max(1) floor on
    // {hours}, which those lines were written assuming.
    function fill(template, appLabel, token) {
        const hours = Math.max(1, Math.floor((root.phase ? root.phase.minutesSince("late") : 0) / 60));
        const time = Qt.formatDateTime(root.now, "HH:mm");
        return template
            .replace(/\{app\}/g, appLabel || "")
            .replace(/\{token\}/g, token || "")
            .replace(/\{time\}/g, time)
            .replace(/\{hours\}/g, String(hours));
    }

    // A curated pool below this size isn't a deck, it's an alternation --
    // and the shuffle bag can't fix that, because the problem is the
    // number of cards.
    readonly property int thinPoolSize: 4

    // Share of curated draws that use the family pool rather than the
    // generic one, when a family is known at all. See selectCurated().
    readonly property real curatedFamilyShare: 0.5

    // Which hand-written family pool to draw from, and under which bag id.
    //
    // The old version fell back to ONE other tone when the requested one
    // was missing, which looked harmless and wasn't: every byFamily pool
    // holds two lines, `tender` has no byFamily pools at all (it postdates
    // them), so all five tones ended up cycling the same two sentences
    // under five different bag ids -- five decks, two cards, one visible
    // result. Merging every tone the family has gives a real deck instead,
    // and keeps all of its hand-written lines rather than reaching only
    // whichever tone the fallback happened to land on.
    function familyDeck(family, tone) {
        const pools = (root.catalog.byFamily || {})[family];
        if (!pools) return null;

        const exact = pools[tone];
        if (exact && exact.length >= root.thinPoolSize)
            return { id: "byFamily:" + family + ":" + tone, pool: exact };

        let merged = [];
        for (const t in pools) if (pools[t]) merged = merged.concat(pools[t]);
        if (merged.length === 0) return null;
        return { id: "byFamily:" + family + ":*", pool: merged };
    }

    // ---- curated selection ---------------------------------------------------
    // Same ladder as before the grammar landed -- level-2 token pool a
    // minority of the time, then the family pool, then generic, with a
    // fallback at every step so a thin catalog entry never surfaces a
    // blank message -- with one change: the family rung is now taken only
    // half the time (see curatedFamilyShare below), because the grammar
    // took over the job those pools were too small to do.
    function selectCurated(ctx) {
        const family = ctx.family;
        const appLabel = family ? (root.catalog.appLabels[family] || family) : "";

        // Level 2: drawn a minority of the time on purpose ("rester
        // subtil", not every message) -- the rest of level-2 draws fall
        // through to level 1 below, same as a family with no token pool.
        if (ctx.level === 2 && Math.random() < (1 / 3)) {
            const tokenPool = (root.catalog.withToken || {})[family];
            const picked = root.draw("withToken:" + family, tokenPool);
            if (picked !== "") return root.fill(picked, appLabel, ctx.token);
        }

        // Half the family-level draws deliberately go to the generic
        // pools instead. The byFamily catalogs hold eight lines per
        // family against roughly seventy-eight generic ones, so always
        // preferring them meant a curated family line came back every
        // other evening, measurably (tools/veille-sample.mjs --curated:
        // 191/300 unique with, 247/300 without). The family-specific WORK
        // is the grammar's now -- it reaches all eight families with the
        // whole vocabulary rather than two sentences each -- so what's
        // left for these pools is voice, not coverage, and voice survives
        // being rarer.
        if (ctx.level >= 1 && family !== "" && Math.random() < root.curatedFamilyShare) {
            const chosen = root.familyDeck(family, ctx.tone);
            if (chosen) {
                const picked = root.draw(chosen.id, chosen.pool);
                if (picked !== "") return root.fill(picked, appLabel, "");
            }
        }

        // `tender` is a grammar tone; the curated catalogs predate it and
        // only fr.js has a pool for it, so fall through to serious rather
        // than to nothing.
        const genericPool = root.catalog.generic[ctx.tone] || root.catalog.generic.serious;
        return root.fill(root.draw("generic:" + ctx.tone, genericPool), appLabel, "");
    }

    // ---- selection ------------------------------------------------------------
    function selectMessage() {
        const tone = Grammar.pickTone(root.phase ? root.phase.phaseName : "late",
                                      { streak: state.streak });
        const ctx = root.messageContext(tone);
        const mem = root.memory();

        // Which side goes first is the coin flip; the other is the
        // fallback either way, so a thin grammar or a thin catalog
        // degrades into the other one instead of into a blank.
        let text = "";
        if (Math.random() < root.curatedRatio) {
            text = root.selectCurated(ctx);
        } else if (root.grammar) {
            text = Grammar.generate(root.grammar, ctx, mem, 10);
        }
        if (text === "" && root.grammar) text = Grammar.generate(root.grammar, ctx, mem, 10);
        if (text === "") text = root.selectCurated(ctx);

        if (text !== "") {
            Grammar.ringPush(mem.messages, text, root.recentRingSize);
            state.recent = mem.messages.slice();
        }
        return text;
    }

    function selectMidnightMessage() {
        const pool = root.catalog.midnight;
        return root.fill(root.draw("midnight", pool), "", "");
    }

    // ---- night streak ----------------------------------------------------------
    // Which EVENING a moment belongs to -- anything before dayStart counts
    // as the previous day, so 01:00 on a Saturday is still Friday night.
    // Same remapping VeillePhase applies to its thresholds, at day
    // granularity instead of minutes. getTimezoneOffset() puts the day
    // boundary in local time rather than UTC; a DST change can misjudge
    // one night twice a year, which is not worth carrying a timezone
    // library for.
    function nightIndex(when) {
        const dayStartMinutes = root.phase ? root.phase.dayStartMinutes : 300;
        const localMs = when.getTime() - when.getTimezoneOffset() * 60000;
        return Math.floor((localMs - dayStartMinutes * 60000) / 86400000);
    }

    // Counted once per night, on the first message shown that night --
    // not per message, and not on a timer: the streak is "nights Veille
    // had something to say", which is the same thing as "nights the user
    // was still up", and only the first message of a night is evidence of
    // a new one.
    function noteNight() {
        const index = root.nightIndex(root.now);
        const seen = state.nights || { index: 0, count: 0 };
        if (seen.index === index) return;
        state.nights = {
            index: index,
            count: (seen.index === index - 1) ? seen.count + 1 : 1
        };
    }

    // ---- timing -----------------------------------------------------------
    readonly property real cooldownMs:
        (root.config ? root.config.messageIntervalMinutes : 20) * 60000
        * (root.phase ? root.phase.intervalFactor : 1.0)

    readonly property bool dueForMessage: (root.now.getTime() - state.lastShownAt) >= root.cooldownMs

    Timer {
        id: hideTimer
        interval: (root.config ? root.config.messageHoldSeconds : 25) * 1000
        onTriggered: root.text = ""
    }

    function present(msg) {
        if (msg === "") return;
        root.text = msg;
        state.lastShownAt = root.now.getTime();
        root.noteNight();
        hideTimer.restart();
    }

    // Message draws are now edge-triggered off the pulse itself, not a
    // continuous per-second poll: the overlay only exists on screen for
    // the ~10s pulse window (see VeillePhase.qml's `inPulse`), so "is a
    // message due" only needs asking once, right as a pulse begins --
    // there's no point re-checking every second while nothing is even
    // visible to show it on.
    Connections {
        target: root.phase

        function onInPulseChanged() {
            if (root.phase.inPulse) {
                if (!root.phase.messagesEnabled) return;
                if (!root.pastGrace) return;
                if (!root.dueForMessage) return;
                root.present(root.selectMessage());
            } else {
                // Pulse just ended -- clear so a stale message never
                // lingers (invisibly, since the window itself is
                // unmapped) into whatever the NEXT pulse turns out to
                // show, if that one doesn't happen to draw a new one.
                root.text = "";
                hideTimer.stop();
            }
        }

        // Bypasses the cooldown entirely -- the calendar-day rollover is
        // its own event, asked to fire "immédiatement", not whenever the
        // regular interval next allows it. In practice this always fires
        // inside the 00:00 pulse anyway (that pulse's window covers the
        // rollover instant by construction), so there's no separate
        // visibility concern here -- just the cooldown bypass. Still
        // re-arms the normal cooldown afterward (present() always does),
        // so this doesn't cause a second message to land right on top of
        // it.
        function onMidnightCrossed() {
            if (!root.phase || !root.phase.messagesEnabled) return;
            root.present(root.selectMidnightMessage());
        }
    }
}
