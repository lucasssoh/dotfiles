import QtQuick
import Quickshell
import Quickshell.Io
import "i18n/fr.js" as CatalogFr
import "i18n/en.js" as CatalogEn

// Picks WHEN and WHAT to show under the clock. Never renders anything
// itself -- Veille.qml owns the fade/hold animation, this just exposes
// `text` (empty string = nothing to show right now).
//
// Anti-repetition is a shuffle bag per pool, not a plain random pick: a
// uniform random draw visibly repeats far sooner than it "should" (the
// birthday-paradox feeling of the same line twice in an evening), which
// is exactly what turns a message system from "feels alive" into "is
// reciting a list" -- the one thing this feature was explicitly asked
// not to do. Drawing without replacement and reshuffling only once the
// pool empties, with a check that the reshuffle's first card isn't the
// same one that just came out, is the standard fix.
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
    readonly property date startedAt: new Date()
    readonly property int graceMs: 60000

    readonly property var catalog: (root.config && root.config.language === "en") ? CatalogEn.catalog : CatalogFr.catalog

    property string text: ""

    // ---- persisted cooldown -------------------------------------------
    // Survives a quickshell restart (bar crash/reload) -- without this,
    // every restart would immediately re-fire a message regardless of how
    // recently one was actually shown, since in-memory state resets to
    // zero. Quickshell.statePath() is the documented spot for exactly
    // this kind of small durable state (see its own header in
    // quickshell-core.qmltypes); separate from veille.json, which the
    // user hand-edits and this file never writes to.
    FileView {
        id: stateFile
        path: Quickshell.statePath("veille-state.json")
        printErrors: false
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: state
            property real lastShownAt: 0
        }
    }

    // ---- shuffle bags ---------------------------------------------------
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

    // ---- tone weighting by phase ---------------------------------------
    // late: only serious/reflective, matching the tone escalation asked
    // for. midnight: all four become available. veryLate: still all
    // four, but weighted toward the explicit ones (provocative/humorous)
    // -- "les quatre, pondérés vers l'explicite".
    readonly property var toneWeights: ({
        late:     { serious: 0.5,  reflective: 0.5,  provocative: 0,    humorous: 0    },
        midnight: { serious: 0.25, reflective: 0.25, provocative: 0.25, humorous: 0.25 },
        veryLate: { serious: 0.15, reflective: 0.15, provocative: 0.35, humorous: 0.35 }
    })

    function pickTone(phaseName) {
        const weights = root.toneWeights[phaseName] || root.toneWeights.late;
        const tones = Object.keys(weights);
        let r = Math.random();
        for (let i = 0; i < tones.length; i++) {
            r -= weights[tones[i]];
            if (r <= 0) return tones[i];
        }
        return tones[tones.length - 1];
    }

    // ---- slot substitution ----------------------------------------------
    function fill(template, appLabel, token) {
        const hours = Math.max(1, Math.floor((root.phase ? root.phase.minutesSince("late") : 0) / 60));
        const time = Qt.formatDateTime(root.now, "HH:mm");
        return template
            .replace(/\{app\}/g, appLabel || "")
            .replace(/\{token\}/g, token || "")
            .replace(/\{time\}/g, time)
            .replace(/\{hours\}/g, String(hours));
    }

    // ---- selection --------------------------------------------------------
    // Chooses ONE template string given the current context level and
    // tone, with graceful fallback at every step so a thin catalog entry
    // (a family with no `provocative` array, say) never surfaces a blank
    // message -- it just falls back to the next broader pool instead.
    function selectMessage() {
        const family = root.context ? root.context.family : "";
        const level = root.context ? root.context.level : 0;
        const tone = root.pickTone(root.phase ? root.phase.phaseName : "late");
        const appLabel = family ? (root.catalog.appLabels[family] || family) : "";

        // Level 2: drawn a minority of the time on purpose ("rester
        // subtil", not every message) -- the rest of level-2 draws fall
        // through to level 1 below, same as a family with no token pool.
        if (level === 2 && Math.random() < (1 / 3)) {
            const tokenPool = (root.catalog.withToken || {})[family];
            const picked = root.draw("withToken:" + family, tokenPool);
            if (picked !== "") return root.fill(picked, appLabel, root.context.token);
        }

        // Level 1 (or a level-2 draw that didn't land above): family
        // pool for this tone, falling back to a different tone in the
        // same family, then to generic, if the family's catalog entry is
        // thin.
        if (level >= 1 && family !== "") {
            const familyPools = (root.catalog.byFamily || {})[family];
            if (familyPools) {
                let pool = familyPools[tone];
                if (!pool || pool.length === 0) {
                    const anyTone = Object.keys(familyPools).find(t => familyPools[t] && familyPools[t].length > 0);
                    pool = anyTone ? familyPools[anyTone] : null;
                }
                const picked = root.draw("byFamily:" + family + ":" + tone, pool);
                if (picked !== "") return root.fill(picked, appLabel, "");
            }
        }

        // Level 0, or nothing usable above: generic pool for this tone.
        const genericPool = root.catalog.generic[tone] || root.catalog.generic.serious;
        return root.fill(root.draw("generic:" + tone, genericPool), appLabel, "");
    }

    function selectMidnightMessage() {
        const pool = root.catalog.midnight;
        return root.fill(root.draw("midnight", pool), "", "");
    }

    // ---- timing -----------------------------------------------------------
    readonly property real cooldownMs:
        (root.config ? root.config.messageIntervalMinutes : 20) * 60000
        * (root.phase ? root.phase.intervalFactor : 1.0)

    readonly property bool pastGrace: (root.now - root.startedAt) >= root.graceMs
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
