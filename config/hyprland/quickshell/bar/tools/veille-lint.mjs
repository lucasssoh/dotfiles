#!/usr/bin/env node
// Checks a Veille grammar against the fragment contract documented in
// i18n/grammar.js. Run it after editing any *-grammar.js:
//
//   node quickshell/bar/tools/veille-lint.mjs           # every language
//   node quickshell/bar/tools/veille-lint.mjs --lang fr
//
// The contract exists because a broken fragment doesn't produce an
// obviously broken sentence -- it produces one that reads almost right
// ("Il est 00:34. Il est tard.", "tu es encore dans le terminal.."), which
// is the kind of thing you stop noticing after the third time and never
// fix. Everything checked here is mechanical; taste is the sampler's job.

import { loadEngine, loadGrammar, parseArgs } from "./veille-load.mjs";

const TONES = ["serious", "reflective", "provocative", "humorous", "tender"];

// Every slot slotValues() in grammar.js can produce. A fragment naming
// anything else would be silently ineligible forever -- the single most
// expensive typo available here, since nothing at runtime reports it.
const SLOTS = ["time", "jour", "app", "verbe", "activite", "objet", "token",
               "hours", "heuresApp", "soirs"];

// Every key buildContext()/VeilleMessages.qml actually puts in the context.
const CTX_KEYS = ["tone", "phase", "family", "facets", "token", "level", "time",
                  "dayIndex", "hours", "sameFamilyMinutes", "churn", "streak",
                  "weekend", "midnightPassed"];

function lintGrammar(lang) {
    const grammar = loadGrammar(lang);
    const problems = [];
    const note = (where, message) => problems.push(`${lang}: ${where}: ${message}`);

    const knownFacets = new Set();
    for (const family in grammar.facets)
        for (const facet of grammar.facets[family]) knownFacets.add(facet);

    // ---- banks -----------------------------------------------------------
    const bankNames = Object.keys(grammar.banks);
    const seen = new Map();

    for (const bankName of bankNames) {
        const bank = grammar.banks[bankName];
        if (!Array.isArray(bank) || bank.length === 0) {
            note(bankName, "empty or not an array");
            continue;
        }

        bank.forEach((frag, i) => {
            const where = `${bankName}[${i}]`;
            if (typeof frag.t !== "string" || frag.t.length === 0) {
                note(where, "missing `t`");
                return;
            }
            const t = frag.t;

            if (seen.has(t)) note(where, `duplicate of ${seen.get(t)}`);
            else seen.set(t, where);

            if (!t.startsWith("{") && /^[A-ZÀ-Þ]/.test(t))
                note(where, `starts with a capital -- the pattern capitalizes: "${t}"`);
            if (/[.!?…,;:]$/.test(t))
                note(where, `ends with punctuation -- the pattern punctuates: "${t}"`);
            if (/[.!?…]\s/.test(t))
                note(where, `contains a sentence break -- that's a pattern, not a fragment: "${t}"`);
            if (/\s\s|^\s|\s$/.test(t))
                note(where, `stray whitespace: "${t}"`);

            for (const m of t.matchAll(/\{(\w+)\}/g))
                if (!SLOTS.includes(m[1]))
                    note(where, `unknown slot {${m[1]}} -- would never be eligible`);

            for (const tone of frag.tone || [])
                if (!TONES.includes(tone)) note(where, `unknown tone "${tone}"`);

            for (const facet of [...(frag.needs || []), ...(frag.not || [])])
                if (!knownFacets.has(facet))
                    note(where, `facet "${facet}" belongs to no family -- would never be eligible`);

            for (const key in frag.when || {})
                if (!CTX_KEYS.includes(key))
                    note(where, `unknown context key "${key}" in \`when\` -- always unsatisfied`);
        });
    }

    // ---- patterns ---------------------------------------------------------
    grammar.patterns.forEach((pattern, i) => {
        const where = `patterns[${i}]`;
        if (typeof pattern.shape !== "string") { note(where, "missing `shape`"); return; }

        const refs = [...pattern.shape.matchAll(/<(\w+)>/g)].map(m => m[1]);
        if (refs.length === 0) note(where, `references no bank: "${pattern.shape}"`);
        for (const ref of refs)
            if (!bankNames.includes(ref)) note(where, `unknown bank <${ref}>`);

        for (const tone of pattern.tone || [])
            if (!TONES.includes(tone)) note(where, `unknown tone "${tone}"`);
    });

    // ---- coverage ---------------------------------------------------------
    // A (bank, tone) pair with nothing in it makes every pattern using that
    // bank fail for that tone, which silently pushes those draws onto the
    // curated catalog. Only reported when some pattern REACHABLE at that
    // tone actually references the bank -- `imperatif` is empty for
    // `humorous` on purpose, and every pattern using it is tone-gated to
    // serious/tender, so that's not a gap, it's the design.
    const thin = [];
    for (const bankName of bankNames) {
        for (const tone of TONES) {
            const reachable = grammar.patterns.some(p =>
                (!p.tone || p.tone.includes(tone)) &&
                [...p.shape.matchAll(/<(\w+)>/g)].some(m => m[1] === bankName));
            if (!reachable) continue;

            const n = grammar.banks[bankName]
                .filter(f => !f.tone || f.tone.includes(tone)).length;
            if (n < 3) thin.push(`${bankName}/${tone}: ${n}`);
        }
    }

    return { problems, thin, grammar };
}

const args = parseArgs(process.argv.slice(2));
const languages = args.lang ? [args.lang] : ["fr"];

let failed = false;
for (const lang of languages) {
    const { problems, thin, grammar } = lintGrammar(lang);

    const fragments = Object.values(grammar.banks).reduce((n, b) => n + b.length, 0);
    console.log(`${lang}: ${grammar.patterns.length} patterns, ` +
                `${Object.keys(grammar.banks).length} banks, ${fragments} fragments`);

    if (thin.length > 0)
        console.log(`  thin (bank/tone with <3 fragments): ${thin.join(", ")}`);

    if (problems.length === 0) {
        console.log("  contract: ok");
    } else {
        failed = true;
        for (const p of problems) console.log(`  ${p}`);
    }
}

process.exit(failed ? 1 : 0);
