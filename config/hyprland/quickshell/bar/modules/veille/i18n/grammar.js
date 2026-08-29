.pragma library

// Veille's sentence GENERATOR -- language-agnostic engine. The catalogs
// (fr.js / en.js) hold whole hand-written sentences; the grammars
// (fr-grammar.js) hold the pieces this file assembles into new ones.
//
// Why a grammar at all, when the catalogs already exist: the flat pools
// got *narrower* the better the context matched. At 23:30 in a terminal
// the eligible pool was byFamily.terminal.serious plus .reflective --
// four sentences, drained in forty minutes at the default 20-minute
// interval, while an unrecognized window fell back to `generic` and got
// thirty-two. The system was at its most repetitive exactly when it was
// at its most relevant. Widening the flat pools would only have moved
// that ceiling: every line still had the same shape (a statement, a
// verdict, a full stop), so the MOULD stayed recognizable even when the
// sentence didn't.
//
// So a message is drawn at three independent levels instead:
//   1. a PATTERN  -- the rhetorical shape, "<constat>. <verdict>."
//   2. a FRAGMENT per <bank> the pattern names, filtered by tone/facets/
//      conditions
//   3. SLOT values -- {app}, {token}, {heuresApp}... substituted last
// The family no longer owns a pool of its own; it contributes facets and
// vocabulary that the whole grammar can use, so eight families inherit
// the entire grammar rather than two lines each.
//
// Two delimiters, deliberately different so they can never collide:
// patterns reference banks with <angle>, fragments reference slots with
// {brace}.
//
// Fragment contract (enforced by tools/veille-lint.mjs, run it after
// editing a grammar): a complete clause, lowercase initial, NO trailing
// punctuation. The pattern supplies the capitals and the full stops --
// that's what lets the same fragment open one sentence and close
// another.

// ---- condition language -----------------------------------------------
// `when: { streak: ">=3", weekend: false }` -- every key must hold. Specs
// are a comparator string (">=3", "<2", "=1"), a bare number (equality),
// or a boolean. An unknown context key is treated as unsatisfied rather
// than as zero, so a typo in a grammar silently drops that fragment
// instead of silently making it always-eligible.
function compare(value, spec) {
    if (typeof spec === "boolean") return value === spec;
    if (typeof spec === "number") return value === spec;
    if (typeof spec !== "string") return false;

    const m = /^(>=|<=|>|<|=)?\s*(-?\d+(?:\.\d+)?)$/.exec(spec.trim());
    if (!m) return false;
    if (typeof value !== "number") return false;

    const op = m[1] || "=";
    const n = parseFloat(m[2]);
    switch (op) {
    case ">=": return value >= n;
    case "<=": return value <= n;
    case ">":  return value > n;
    case "<":  return value < n;
    default:   return value === n;
    }
}

function satisfies(when, ctx) {
    if (!when) return true;
    for (const key in when) {
        if (!(key in ctx)) return false;
        if (!compare(ctx[key], when[key])) return false;
    }
    return true;
}

// ---- slots ---------------------------------------------------------------
// Builds the table of what {slots} are RESOLVABLE right now. A fragment
// naming a slot that isn't in here is ineligible -- which is the whole
// context mechanism: writing "ça fait {heuresApp} h que tu es dans {app}"
// is all it takes for that line to appear only when both facts exist. No
// per-fragment condition to declare, nothing to keep in sync.
function slotValues(grammar, ctx) {
    const v = {};

    v.time = ctx.time;
    if (grammar.days && typeof ctx.dayIndex === "number")
        v.jour = grammar.days[ctx.dayIndex];

    if (ctx.family) {
        const label = grammar.appLabels ? grammar.appLabels[ctx.family] : null;
        if (label) v.app = label;
        const words = grammar.vocab ? grammar.vocab[ctx.family] : null;
        if (words) {
            if (words.verbe) v.verbe = words.verbe;
            if (words.activite) v.activite = words.activite;
            if (words.objet) v.objet = words.objet;
        }
    }

    if (ctx.token) v.token = ctx.token;

    // Only offered once they'd read as true. {hours} counts from the
    // `late` threshold (VeillePhase.minutesSince), so it's meaningless
    // below 1; {heuresApp} is a real single-app session and is a weak
    // claim under two hours.
    if (ctx.hours >= 1) v.hours = String(ctx.hours);
    if (ctx.sameFamilyMinutes >= 120) v.heuresApp = String(Math.floor(ctx.sameFamilyMinutes / 60));
    if (ctx.streak >= 2) v.soirs = String(ctx.streak);

    return v;
}

const SLOT_RE = /\{(\w+)\}/g;

function slotsResolvable(text, slots) {
    SLOT_RE.lastIndex = 0;
    let m;
    while ((m = SLOT_RE.exec(text)) !== null) {
        if (slots[m[1]] === undefined) return false;
    }
    return true;
}

function fill(text, slots) {
    return text.replace(SLOT_RE, function (whole, name) {
        return slots[name] !== undefined ? slots[name] : whole;
    });
}

// ---- eligibility ---------------------------------------------------------
function hasAll(list, facets) {
    for (let i = 0; i < list.length; i++)
        if (facets.indexOf(list[i]) === -1) return false;
    return true;
}

function hasAny(list, facets) {
    for (let i = 0; i < list.length; i++)
        if (facets.indexOf(list[i]) !== -1) return true;
    return false;
}

// `needs`/`not` are checked against the facets the FAMILY carries (see
// each grammar's own `facets` table) -- that's what stops "le code
// compile" landing on an episode of a series. An unrecognized window has
// no facets at all, so anything with a `needs` is out and only the
// context-free fragments remain, which is the correct degradation.
function eligible(frag, ctx, slots) {
    if (frag.tone && frag.tone.indexOf(ctx.tone) === -1) return false;
    if (frag.needs && !hasAll(frag.needs, ctx.facets)) return false;
    if (frag.not && hasAny(frag.not, ctx.facets)) return false;
    if (frag.when && !satisfies(frag.when, ctx)) return false;
    if (!slotsResolvable(frag.t, slots)) return false;
    return true;
}

// ---- memory ---------------------------------------------------------------
// A shuffle bag per pool no longer works: the eligible subset of a bank
// changes from draw to draw (a different family, a session that just
// crossed two hours), so a deck built for one context is wrong for the
// next. A per-bank recency RING is the version of the same idea that
// survives that -- reject anything seen in the last ~60% of the bank's
// eligible size, and fall back to the full set when that leaves nothing.
function newMemory() {
    return { banks: {}, patterns: [], messages: [] };
}

function ringPush(ring, value, max) {
    const at = ring.indexOf(value);
    if (at !== -1) ring.splice(at, 1);
    ring.push(value);
    while (ring.length > max) ring.shift();
}

function pickIndex(n) {
    return Math.floor(Math.random() * n);
}

// Draws one fragment. `state` collects what this render used so far:
// nothing repeats a fragment or a TOPIC inside one sentence (that's what
// stops "tu es encore dans le terminal. le terminal ne dort jamais.").
// Nothing is committed to `mem` here -- the caller commits only once the
// whole sentence renders, so a discarded attempt doesn't burn fragments.
function topicsOf(frag) {
    if (!frag.topic) return [];
    return (typeof frag.topic === "string") ? [frag.topic] : frag.topic;
}

function pick(bankName, bank, ctx, slots, mem, state) {
    if (!bank || bank.length === 0) return null;

    const candidates = [];
    for (let i = 0; i < bank.length; i++) {
        const frag = bank[i];
        if (!eligible(frag, ctx, slots)) continue;
        if (state.texts.indexOf(frag.t) !== -1) continue;
        if (hasAny(topicsOf(frag), state.topics)) continue;
        candidates.push(frag);
    }
    if (candidates.length === 0) return null;

    const ring = mem.banks[bankName] || (mem.banks[bankName] = []);
    const fresh = [];
    for (let i = 0; i < candidates.length; i++)
        if (ring.indexOf(candidates[i].t) === -1) fresh.push(candidates[i]);

    const pool = fresh.length > 0 ? fresh : candidates;
    const chosen = pool[pickIndex(pool.length)];

    state.commits.push({ bank: bankName, text: chosen.t,
                         max: Math.max(3, Math.floor(candidates.length * 0.6)) });
    state.texts.push(chosen.t);
    const topics = topicsOf(chosen);
    for (let i = 0; i < topics.length; i++) state.topics.push(topics[i]);
    return chosen;
}

// ---- rendering ------------------------------------------------------------
// Fragments are written lowercase with no final punctuation, so the
// capitals belong to whoever assembled them: the first letter, and the
// first letter after any sentence terminator. Digits are left alone, so
// a pattern opening on "{time}" still reads "00:34." correctly.
function capitalize(text) {
    return text.replace(/(^|[.!?…]\s+)([a-zà-öø-ÿ])/g, function (m, lead, ch) {
        return lead + ch.toUpperCase();
    });
}

// French spacing: a space stays before ? ! : ; (that's correct French and
// matches the hand-written catalogs), but never before . or , -- a
// fragment ending on a slot that resolved to "" would otherwise leave one.
function tidy(text) {
    return text.replace(/\s+/g, " ").replace(/\s+([.,])/g, "$1").trim();
}

// Language-specific cleanups the engine can't know about, declared by the
// grammar as [RegExp, replacement] pairs. French needs elision: a
// fragment reads "tu es en train de {activite}", and {activite} may
// resolve to "enchaîner des commandes" -- "de enchaîner" is wrong and no
// amount of care in writing the fragment can fix it, because the choice
// depends on a value substituted later. Runs before capitalize(), so an
// elision at the head of a sentence still gets its capital.
function applyTypography(text, grammar) {
    const rules = grammar.typography;
    if (!rules) return text;
    let out = text;
    for (let i = 0; i < rules.length; i++)
        out = out.replace(rules[i][0], rules[i][1]);
    return out;
}

const BANK_RE = /<(\w+)>/g;

function renderPattern(pattern, grammar, ctx, slots, mem) {
    const state = { texts: [], topics: [], commits: [] };
    let failed = false;

    const raw = pattern.shape.replace(BANK_RE, function (whole, bankName) {
        if (failed) return "";
        const frag = pick(bankName, grammar.banks[bankName], ctx, slots, mem, state);
        if (!frag) { failed = true; return ""; }
        return fill(frag.t, slots);
    });

    if (failed) return null;
    return { text: capitalize(applyTypography(tidy(raw), grammar)), commits: state.commits };
}

function weightedPick(patterns) {
    let total = 0;
    for (let i = 0; i < patterns.length; i++) total += (patterns[i].weight || 1);
    let r = Math.random() * total;
    for (let i = 0; i < patterns.length; i++) {
        r -= (patterns[i].weight || 1);
        if (r <= 0) return patterns[i];
    }
    return patterns[patterns.length - 1];
}

// ---- tone weighting -------------------------------------------------------
// Lives here rather than in VeilleMessages.qml so the sampler
// (tools/veille-sample.mjs) draws tones exactly the way the running bar
// does -- a sample generated under a different distribution would be
// reviewing a system that doesn't ship.
//
// `late` stays free of the two mocking tones (that escalation was the
// original ask); `tender` joins it as the gentle counterweight, and takes
// over from provocative/humorous entirely once this is the third night in
// a row -- at that point the joke has been made and repeating it is just
// nagging.
var toneWeights = {
    late:     { serious: 0.30, reflective: 0.35, provocative: 0.00, humorous: 0.00, tender: 0.35 },
    midnight: { serious: 0.20, reflective: 0.20, provocative: 0.20, humorous: 0.20, tender: 0.20 },
    veryLate: { serious: 0.10, reflective: 0.15, provocative: 0.30, humorous: 0.30, tender: 0.15 }
};

function toneDistribution(phaseName, ctx) {
    const base = toneWeights[phaseName] || toneWeights.late;
    const w = {};
    for (const key in base) w[key] = base[key];

    if (ctx && ctx.streak >= 3) {
        const moved = (w.provocative + w.humorous) * 0.5;
        w.provocative *= 0.5;
        w.humorous *= 0.5;
        w.tender += moved;
    }
    return w;
}

function pickTone(phaseName, ctx) {
    const w = toneDistribution(phaseName, ctx);
    const tones = Object.keys(w);
    let total = 0;
    for (let i = 0; i < tones.length; i++) total += w[tones[i]];
    let r = Math.random() * total;
    for (let i = 0; i < tones.length; i++) {
        r -= w[tones[i]];
        if (r <= 0) return tones[i];
    }
    return "serious";
}

// ---- entry point ----------------------------------------------------------
// Returns "" when it can't build anything usable for this context -- the
// caller falls back to the curated catalog, which always has something.
// That's also why failure here is cheap and silent: a thin grammar, or a
// context nothing matches, degrades to hand-written sentences rather than
// to a blank message.
function generate(grammar, ctx, mem, tries) {
    if (!grammar || !grammar.patterns || !grammar.banks) return "";

    const slots = slotValues(grammar, ctx);
    const usable = [];
    for (let i = 0; i < grammar.patterns.length; i++) {
        const p = grammar.patterns[i];
        if (p.tone && p.tone.indexOf(ctx.tone) === -1) continue;
        if (p.when && !satisfies(p.when, ctx)) continue;
        usable.push(p);
    }
    if (usable.length === 0) return "";

    const attempts = tries || 10;
    for (let i = 0; i < attempts; i++) {
        // Patterns get their own recency ring too: without it the shape
        // repeats even when every fragment inside it is new, which is
        // exactly the "I recognize the mould" problem this file exists
        // to solve.
        let choices = [];
        for (let j = 0; j < usable.length; j++)
            if (mem.patterns.indexOf(usable[j].shape) === -1) choices.push(usable[j]);
        if (choices.length === 0) choices = usable;

        const pattern = weightedPick(choices);
        const built = renderPattern(pattern, grammar, ctx, slots, mem);
        if (!built) continue;
        if (mem.messages.indexOf(built.text) !== -1) continue;

        for (let k = 0; k < built.commits.length; k++) {
            const c = built.commits[k];
            ringPush(mem.banks[c.bank] || (mem.banks[c.bank] = []), c.text, c.max);
        }
        ringPush(mem.patterns, pattern.shape, Math.max(3, Math.floor(usable.length * 0.6)));
        return built.text;
    }

    return "";
}
