// Copies ../docs/**/*.md into Starlight's content folder, so docs/ stays the
// single source: the page title comes from the first "# " heading, links
// between pages become site routes, and links into the repo point at GitHub.
// docs/design/ (design notes) stays out of the site.
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, posix, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BASE, BRANCH, REPO } from '../site.config.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, '../../docs');
const out = resolve(here, '../src/content/docs/docs');
const SKIP = new Set(['design', 'screenshots']);

// Screenshots are served as they are, from public/.
cpSync(join(src, 'screenshots'), resolve(here, '../public/screenshots'), { recursive: true });

// Files are only rewritten when their content changes, and stale ones are
// removed at the end: a running `astro dev` then sees edits, never a folder
// that vanishes and comes back.
const written = new Set();
function writeIfChanged(path, text) {
  written.add(path);
  mkdirSync(dirname(path), { recursive: true });
  if (existsSync(path) && readFileSync(path, 'utf8') === text) return;
  writeFileSync(path, text);
}
function removeStale(dir) {
  if (!existsSync(dir)) return;
  for (const f of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, f.name);
    if (f.isDirectory()) {
      removeStale(p);
      if (readdirSync(p).length === 0) rmSync(p, { recursive: true });
    } else if (!written.has(p)) rmSync(p);
  }
}

function pages(dir = src) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((f) => {
    if (f.isDirectory()) return SKIP.has(f.name) ? [] : pages(join(dir, f.name));
    return f.name.endsWith('.md') ? [relative(src, join(dir, f.name)).split('\\').join('/')] : [];
  });
}
const all = pages();
const known = new Set(all);

// "bar/index.md" → "/dotfiles/docs/bar/", "bar/balise.md" → "/dotfiles/docs/bar/balise/".
const route = (file) => `${BASE}/docs/${file.replace(/(^|\/)index\.md$/, '$1').replace(/\.md$/, '/')}`;

// A link as written in docs/<file>, resolved from that file's folder.
function rewriteLink(file, target) {
  if (/^[a-z]+:/i.test(target) || target.startsWith('#')) return target;
  const [path, anchor = ''] = target.split('#');
  const hash = anchor ? `#${anchor}` : '';
  const resolved = posix.normalize(posix.join(posix.dirname(file), path));
  if (known.has(resolved)) return route(resolved) + hash;
  if (resolved.startsWith('screenshots/')) return `${BASE}/${resolved}`;
  if (resolved.endsWith('.md') && !resolved.startsWith('..')) {
    throw new Error(`docs/${file}: link to docs/${resolved}, which does not exist`);
  }
  const repoPath = posix.normalize(posix.join('docs', resolved)).replace(/\/$/, '');
  return `${REPO}/blob/${BRANCH}/${repoPath}${hash}`;
}

for (const file of all) {
  const text = readFileSync(join(src, file), 'utf8');
  const heading = text.match(/^# (.+)$/m);
  if (!heading) throw new Error(`docs/${file}: no "# " title`);
  const title = heading[1].replace(/`/g, '').trim();
  // Markdown links and images, then the <picture> tags that pair a
  // screenshot with its dark version (src="…", srcset="…").
  const body = text
    .replace(heading[0], '')
    .replace(/\]\(([^)\s]+)\)/g, (_, t) => `](${rewriteLink(file, t)})`)
    .replace(/\b(src|srcset)="([^"]+)"/g, (_, attr, t) => `${attr}="${rewriteLink(file, t)}"`);
  const fm = `---\ntitle: ${JSON.stringify(title)}\neditUrl: ${REPO}/edit/${BRANCH}/docs/${file}\n---\n\n`;
  writeIfChanged(join(out, file), fm + body.trim() + '\n');
}

removeStale(out);
