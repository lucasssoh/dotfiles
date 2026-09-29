#!/usr/bin/env node
// ============================================================
// tex2svg.js — TeX -> SVG, one JSON line in, one JSON line out
// ============================================================
// Shared by md2pdf.py (a batch: every formula of the document, then
// stdin closes) and nvim's bin/mdview (resident: started at the first
// formula, fed as you type, gone with the window). Same protocol both
// ways:
//
//     in   {"tex": "\\frac{a}{b}", "display": true, "scale": 1.23}
//     out  {"svg": "<svg ...>"}   or   {"error": "Missing close brace"}
//
// ---- Why MathJax in a resident node (measured on this machine) ------
//   MathJax 3, warm       3 ms a formula, 214 ms to load, ~45 MB
//   matplotlib mathtext   20 ms a formula, 860 ms to load, and no
//                         matrices (\begin{pmatrix} raises)
//   utftex                2.5 ms, but unicode art in monospace
// The load is the whole cost, hence one process that stays up rather
// than one per formula.
//
// ---- Sizes in em -------------------------------------------------------
// MathJax writes width/height in ex, computed with its own ex = 0.442em
// guess, and every consumer resolves ex differently (librsvg against a
// 12px default, WeasyPrint against the actual font's x-height). The
// viewBox is exact -- 1000 units to the em -- so the size is rewritten
// from it in em, and the depth below the baseline becomes the
// vertical-align. "scale" multiplies all three -- MathJax's glyphs have a
// smaller x-height than the body font, see MATH_SCALE in md2pdf.py. The
// colour stays currentColor: the caller decides.
// ============================================================
"use strict";

const readline = require("readline");
const { mathjax } = require("mathjax-full/js/mathjax.js");
const { TeX } = require("mathjax-full/js/input/tex.js");
const { SVG } = require("mathjax-full/js/output/svg.js");
const { liteAdaptor } = require("mathjax-full/js/adaptors/liteAdaptor.js");
const { RegisterHTMLHandler } = require("mathjax-full/js/handlers/html.js");
const { AllPackages } = require("mathjax-full/js/input/tex/AllPackages.js");

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const doc = mathjax.document("", {
    // Without noundefined, an unknown macro is an error rather than a
    // red word quietly set inside the formula: the caller shows the
    // source and the reason instead, as it does for a broken diagram.
    InputJax: new TeX({
        packages: AllPackages.filter((p) => p !== "noundefined"),
        formatError: (_jax, err) => { throw err; },
    }),
    // Glyphs as paths inside each SVG, no shared <defs> to reference:
    // every formula stands alone, which a cache per formula needs.
    OutputJax: new SVG({ fontCache: "none" }),
});

function render(tex, display, scale) {
    const em = (v) => +(v * scale / 1000).toFixed(3) + "em";
    const svg = adaptor.innerHTML(doc.convert(tex, { display }));
    const vb = svg.match(/viewBox="([-\d.]+) ([-\d.]+) ([\d.]+) ([\d.]+)"/);
    if (!vb) return svg;
    const [y, w, h] = [+vb[2], +vb[3], +vb[4]];
    return svg
        .replace(/ width="[^"]*"/, ` width="${em(w)}"`)
        .replace(/ height="[^"]*"/, ` height="${em(h)}"`)
        .replace(/ style="[^"]*"/, ` style="vertical-align: ${em(-(y + h))}"`);
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on("line", (line) => {
    let out;
    try {
        const req = JSON.parse(line);
        out = { svg: render(String(req.tex), !!req.display, +req.scale || 1) };
    } catch (err) {
        out = { error: String((err && err.message) || err) };
    }
    process.stdout.write(JSON.stringify(out) + "\n");
});
