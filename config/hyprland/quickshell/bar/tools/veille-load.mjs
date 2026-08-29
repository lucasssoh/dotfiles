// Loads Veille's QML JavaScript libraries into plain node, so the grammar
// can be linted and sampled without a running compositor.
//
// A `.pragma library` file is ordinary JavaScript with a QML-only
// directive on the first line (and possibly `.import` lines) -- neither is
// valid JS, so they're stripped before evaluation. Everything the file
// declares at top level lands on the returned context object, which is
// how `grammar` / `catalog` / `generate` come back out.
//
// This is deliberately a loader and not a copy: the linter and the
// sampler read the SAME files quickshell reads, so a grammar that samples
// well cannot drift from the one that ships.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const HERE = dirname(fileURLToPath(import.meta.url));
export const I18N_DIR = join(HERE, "..", "modules", "veille", "i18n");

export function loadQmlJs(file) {
    const source = readFileSync(join(I18N_DIR, file), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/gm, "")
        .replace(/^\s*\.import\s+.*$/gm, "");

    const context = vm.createContext({ console });
    vm.runInContext(source, context, { filename: file });
    return context;
}

export function loadEngine() {
    return loadQmlJs("grammar.js");
}

export function loadGrammar(lang) {
    const ctx = loadQmlJs(`${lang}-grammar.js`);
    if (!ctx.grammar) throw new Error(`${lang}-grammar.js declares no \`grammar\``);
    return ctx.grammar;
}

export function loadCatalog(lang) {
    const ctx = loadQmlJs(`${lang}.js`);
    if (!ctx.catalog) throw new Error(`${lang}.js declares no \`catalog\``);
    return ctx.catalog;
}

// Rebuilds what VeilleMessages.qml passes to the engine, so a sample is
// generated under exactly the conditions the real thing would face.
// Anything omitted takes the "no such signal" value, which is what an
// unrecognized window / first night / fresh session actually looks like.
export function buildContext(grammar, opts = {}) {
    const family = opts.family || "";
    const now = opts.now instanceof Date ? opts.now : new Date();

    return {
        tone: opts.tone || "serious",
        phase: opts.phase || "late",
        family,
        facets: (grammar.facets && grammar.facets[family]) || [],
        token: opts.token || "",
        level: opts.level !== undefined ? opts.level : (opts.token ? 2 : (family ? 1 : 0)),
        // Defaults to a late hour rather than to wall-clock now: Veille
        // only ever speaks after 23:00, so sampling it at 15:16 reviews
        // sentences that can't occur.
        time: opts.time || "01:24",
        dayIndex: opts.dayIndex !== undefined ? opts.dayIndex : now.getDay(),
        hours: opts.hours !== undefined ? opts.hours : 2,
        sameFamilyMinutes: opts.sameFamilyMinutes !== undefined ? opts.sameFamilyMinutes : 0,
        churn: opts.churn !== undefined ? opts.churn : 0,
        streak: opts.streak !== undefined ? opts.streak : 1,
        weekend: opts.weekend !== undefined ? opts.weekend : false,
        midnightPassed: opts.midnightPassed !== undefined
            ? opts.midnightPassed
            : (opts.phase === "midnight" || opts.phase === "veryLate")
    };
}

export function parseArgs(argv) {
    const out = {};
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (!arg.startsWith("-")) continue;
        const key = arg.startsWith("--") ? arg.slice(2) : arg.slice(1);
        const next = argv[i + 1];
        if (next === undefined || next.startsWith("--")) { out[key] = true; continue; }
        out[key] = /^-?\d+$/.test(next) ? parseInt(next, 10)
                 : next === "true" ? true
                 : next === "false" ? false
                 : next;
        i++;
    }
    return out;
}
