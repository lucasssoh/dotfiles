#!/usr/bin/env node
// Prints what Veille would actually say, in bulk, without waiting for the
// clock. This is the only honest way to review a generative catalog: no
// one can hold twenty thousand possible compositions in their head, so the
// review has to happen on samples, and the bad ones get culled from the
// grammar by hand.
//
//   node quickshell/bar/tools/veille-sample.mjs
//   node quickshell/bar/tools/veille-sample.mjs --phase veryLate --family terminal -n 200
//   node quickshell/bar/tools/veille-sample.mjs --family ide --token Main.qml --streak 4
//   node quickshell/bar/tools/veille-sample.mjs --sweep            # every family x phase
//
//   --lang fr            catalog/grammar language (default fr)
//   --phase              late | midnight | veryLate (default veryLate)
//   --tone               force one tone; default draws from the phase weights
//   --family             terminal|ide|editor|browser|reader|media|chat|game, or "" for none
//   --token              a level-2 token, e.g. Main.qml
//   --hours N            hours since the `late` threshold (default 2)
//   --sameFamilyMinutes  minutes in the same app (>=120 unlocks {heuresApp})
//   --churn N            window switches in the last 15 min (>=5 unlocks those lines)
//   --streak N           consecutive late nights (>=3 unlocks those, and softens the tone)
//   --time HH:MM         clock shown in {time}
//   -n / --count N       how many to print (default 60)
//   --stats              add a distribution report instead of just the lines
//   --curated            include the hand-written catalog in the mix, as the bar does
//
// The generator's memory is carried across the whole run, exactly as it is
// across an evening, so what you see includes the anti-repetition -- a
// sample that repeats here would repeat on screen.

import { loadEngine, loadGrammar, loadCatalog, buildContext, parseArgs } from "./veille-load.mjs";

const args = parseArgs(process.argv.slice(2));
const lang = args.lang || "fr";
const engine = loadEngine();
const grammar = loadGrammar(lang);
const catalog = args.curated ? loadCatalog(lang) : null;

const FAMILIES = ["", "terminal", "ide", "editor", "browser", "reader", "media", "chat", "game"];
const PHASES = ["late", "midnight", "veryLate"];

// A plausible clock for each phase, so {time} never contradicts the phase
// being sampled ("il est 01:24" inside `late` reviews a sentence that
// can't occur). Overridden by --time.
const PHASE_TIME = { late: "23:40", midnight: "00:05", veryLate: "01:24" };

function contextFor(family, phase) {
    return buildContext(grammar, {
        family,
        phase,
        token: args.token || "",
        hours: args.hours,
        sameFamilyMinutes: args.sameFamilyMinutes,
        churn: args.churn,
        streak: args.streak,
        time: args.time || PHASE_TIME[phase],
        dayIndex: args.dayIndex
    });
}

// Mirrors VeilleMessages.qml's curated side closely enough to review the
// MIX, not just the grammar: a line that only ever appears next to the
// hand-written ones has to be read next to them. That includes the
// shuffle bag -- an unbagged uniform draw would show the curated pools
// repeating *less* than they really do, which is the wrong direction for
// a review tool to be wrong in.
const bags = {};

function drawBagged(id, pool) {
    if (!pool || pool.length === 0) return "";
    if (pool.length === 1) return pool[0];

    let bag = bags[id];
    if (!bag) bag = bags[id] = { deck: [], last: "" };
    if (bag.deck.length === 0) {
        const fresh = pool.slice();
        for (let i = fresh.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [fresh[i], fresh[j]] = [fresh[j], fresh[i]];
        }
        if (bag.last && fresh[0] === bag.last) {
            const at = 1 + Math.floor(Math.random() * (fresh.length - 1));
            [fresh[0], fresh[at]] = [fresh[at], fresh[0]];
        }
        bag.deck = fresh;
    }
    bag.last = bag.deck.shift();
    return bag.last;
}

const THIN_POOL = 4;

function familyDeck(family, tone) {
    const pools = (catalog.byFamily || {})[family];
    if (!pools) return null;
    const exact = pools[tone];
    if (exact && exact.length >= THIN_POOL) return { id: `byFamily:${family}:${tone}`, pool: exact };
    let merged = [];
    for (const t in pools) if (pools[t]) merged = merged.concat(pools[t]);
    return merged.length ? { id: `byFamily:${family}:*`, pool: merged } : null;
}

const CURATED_FAMILY_SHARE = 0.5;

function curatedLine(ctx) {
    if (!catalog) return "";
    const deck = (ctx.family && Math.random() < CURATED_FAMILY_SHARE)
        ? familyDeck(ctx.family, ctx.tone) : null;
    const picked = deck
        ? drawBagged(deck.id, deck.pool)
        : drawBagged(`generic:${ctx.tone}`, catalog.generic[ctx.tone] || catalog.generic.serious);
    if (!picked) return "";
    return picked
        .replace(/\{app\}/g, (grammar.appLabels || {})[ctx.family] || "")
        .replace(/\{token\}/g, ctx.token || "")
        .replace(/\{time\}/g, ctx.time)
        .replace(/\{hours\}/g, String(ctx.hours));
}

function sample(family, phase, count, memory) {
    const lines = [];
    const tones = {};
    let curatedCount = 0;
    let empties = 0;

    for (let i = 0; i < count; i++) {
        const ctx = contextFor(family, phase);
        ctx.tone = args.tone || engine.pickTone(phase, ctx);
        tones[ctx.tone] = (tones[ctx.tone] || 0) + 1;

        let text = "";
        if (catalog && Math.random() < 0.35) { text = curatedLine(ctx); curatedCount++; }
        if (!text) text = engine.generate(grammar, ctx, memory, 10);
        if (!text && catalog) { text = curatedLine(ctx); curatedCount++; }
        if (!text) { empties++; continue; }

        // Same ring the bar keeps, so the sample shows the real repetition
        // behaviour rather than an optimistic version of it.
        engine.ringPush(memory.messages, text, 40);
        lines.push({ text, tone: ctx.tone });
    }

    return { lines, tones, curatedCount, empties };
}

function report(label, result) {
    console.log(`\n\x1b[1m── ${label} ──\x1b[0m`);
    for (const line of result.lines)
        console.log(args.stats ? `  \x1b[2m${line.tone.padEnd(11)}\x1b[0m ${line.text}`
                               : `  ${line.text}`);

    if (args.stats) {
        const unique = new Set(result.lines.map(l => l.text)).size;
        const tones = Object.entries(result.tones)
            .sort((a, b) => b[1] - a[1]).map(([t, n]) => `${t} ${n}`).join(", ");
        console.log(`  \x1b[2m${unique}/${result.lines.length} unique | ${tones}` +
                    (catalog ? ` | curated ${result.curatedCount}` : "") +
                    (result.empties ? ` | \x1b[31m${result.empties} empty\x1b[0m` : "") +
                    "\x1b[0m");
    }
}

if (args.sweep) {
    const perCell = args.count || args.n || 6;
    for (const phase of PHASES)
        for (const family of FAMILIES)
            report(`${phase} / ${family || "(no window)"}`,
                   sample(family, phase, perCell, engine.newMemory()));
} else {
    const family = args.family !== undefined ? (args.family === true ? "" : args.family) : "terminal";
    const phase = args.phase || "veryLate";
    const count = args.count || args.n || 60;
    report(`${phase} / ${family || "(no window)"}${args.tone ? ` / ${args.tone}` : ""}`,
           sample(family, phase, count, engine.newMemory()));
}
