// Copies ../docs/*.md into Starlight's content folder, so docs/ stays the
// single source: the page title comes from the first "# " heading, links
// between pages become site routes, and links into the repo point at GitHub.
//
// modules.md is split into one page per module ("### " heading), grouped by
// its "## " sections; the grouping is written to .generated/sidebar.json for
// astro.config.mjs.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, posix, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BASE, BRANCH, REPO } from '../site.config.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, '../../docs');
const out = resolve(here, '../src/content/docs/docs');
const generated = resolve(here, '../.generated');

mkdirSync(join(out, 'modules'), { recursive: true });
mkdirSync(generated, { recursive: true });

// Files are only rewritten when their content changes, and stale ones are
// removed at the end: a running `astro dev` then sees edits, never a folder
// that vanishes and comes back.
const written = new Set();
function writeIfChanged(path, text) {
  written.add(path);
  if (existsSync(path) && readFileSync(path, 'utf8') === text) return;
  writeFileSync(path, text);
}
function removeStale(dir) {
  for (const f of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, f.name);
    if (f.isDirectory()) removeStale(p);
    else if (!written.has(p)) rmSync(p);
  }
}

// Same ids as the headings Starlight renders (github-slugger).
const slug = (text) =>
  text.toLowerCase().trim().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
const plain = (text) => text.replace(/`/g, '').trim();

// "<doc>#<anchor>" → site route, filled in as pages are laid out.
const anchors = new Map();
const route = (page) => `${BASE}/docs/${page}/`;

function rewriteLink(target) {
  if (/^[a-z]+:/i.test(target)) return target;
  let [path, anchor = ''] = target.split('#');
  if (path === '' || /^[\w-]+\.md$/.test(path)) {
    const doc = path === '' ? current : path.slice(0, -3);
    const moved = anchor && anchors.get(`${doc}#${anchor}`);
    if (moved) return moved;
    return `${route(doc)}${anchor ? `#${anchor}` : ''}`;
  }
  const repoPath = posix.normalize(posix.join('docs', path)).replace(/\/$/, '');
  return `${REPO}/blob/${BRANCH}/${repoPath}${anchor ? `#${anchor}` : ''}`;
}

let current = '';
const withLinks = (body) => body.replace(/\]\(([^)\s]+)\)/g, (_, t) => `](${rewriteLink(t)})`);

function page(file, title, body, extra = '') {
  const fm = `---\ntitle: ${JSON.stringify(title)}\n${extra}---\n\n`;
  writeIfChanged(join(out, file), fm + withLinks(body).trim() + '\n');
}

function splitTitle(name, text) {
  const heading = text.match(/^# (.+)$/m);
  if (!heading) throw new Error(`docs/${name}: no "# " title`);
  return [plain(heading[1]), text.replace(heading[0], '')];
}

const editUrl = (name) => `editUrl: ${REPO}/edit/${BRANCH}/docs/${name}\n`;

// ── modules.md: overview + one page per module ────────────────────────────
const modulesText = readFileSync(join(src, 'modules.md'), 'utf8');
const [modulesTitle, modulesBody] = splitTitle('modules.md', modulesText);
const chunks = modulesBody.split(/^(?=## |### )/m);
const overview = [];
const groups = [];
let group = null;
let modules = [];

chunks.forEach((chunk, i) => {
  const h2 = chunk.match(/^## (.+)$/m);
  const h3 = chunk.match(/^### (.+)$/m);
  if (chunk.startsWith('### ') && group) {
    const label = plain(h3[1]);
    const file = slug(label.replace(/\//g, ' ').replace(/·/g, ' ')).replace(/-+/g, '-');
    const entry = { label, file, body: chunk.replace(h3[0], '').replace(/^#### /gm, '## ') };
    group.items.push(entry);
    modules.push(entry);
    anchors.set(`modules#${slug(h3[1].replace(/`/g, ''))}`, route(`modules/${file}`));
    for (const sub of entry.body.matchAll(/^## (.+)$/gm)) {
      anchors.set(`modules#${slug(sub[1])}`, `${route(`modules/${file}`)}#${slug(sub[1])}`);
    }
  } else if (chunk.startsWith('## ') && chunks[i + 1]?.startsWith('### ')) {
    // A "## " followed by modules is a sidebar group.
    group = { label: plain(h2[1]), anchor: slug(h2[1]), items: [] };
    groups.push(group);
    // Text directly under a group heading (none today) stays on the overview.
    const rest = chunk.replace(h2[0], '').replace(/^---\s*$/gm, '').trim();
    if (rest) overview.push(`## ${group.label}\n\n${rest}\n`);
  } else {
    group = null;
    overview.push(chunk);
  }
});
for (const g of groups) {
  if (g.items.length) anchors.set(`modules#${g.anchor}`, route(`modules/${g.items[0].file}`));
}
// The overview keeps "## Order" etc.; those anchors stay on it.
for (const h of overview.join('').matchAll(/^## (.+)$/gm)) anchors.delete(`modules#${slug(h[1])}`);

current = 'modules';
const index = groups
  .map((g) => `### ${g.label}\n\n${g.items.map((m) => `- [${m.label}](${route(`modules/${m.file}`)})`).join('\n')}\n`)
  .join('\n');
page(
  'modules/index.md',
  modulesTitle,
  overview.join('').replace(/^---\s*$/gm, '') + '\n## All modules\n\n' + index,
  editUrl('modules.md'),
);
for (const m of modules) page(`modules/${m.file}.md`, m.label, m.body.replace(/^---\s*$/gm, ''), editUrl('modules.md'));

writeIfChanged(
  join(generated, 'sidebar.json'),
  JSON.stringify(
    groups.map((g) => ({ label: g.label, items: g.items.map((m) => `docs/modules/${m.file}`) })),
    null,
    2,
  ),
);

// ── every other page, one to one ──────────────────────────────────────────
for (const name of readdirSync(src).filter((f) => f.endsWith('.md') && f !== 'modules.md')) {
  current = name.slice(0, -3);
  const [title, body] = splitTitle(name, readFileSync(join(src, name), 'utf8'));
  page(name, title, body, editUrl(name));
}

removeStale(out);
