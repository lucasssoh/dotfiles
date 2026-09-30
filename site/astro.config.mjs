import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { BASE, REPO, SITE } from './site.config.mjs';

// Written by scripts/sync-docs.mjs, which runs before every dev/build.
const sidebarFile = fileURLToPath(new URL('./.generated/sidebar.json', import.meta.url));
const moduleGroups = JSON.parse(readFileSync(sidebarFile, 'utf8'));

// In `astro dev`, re-run the sync whenever ../docs changes; restart when the
// list of modules (and so the sidebar) changed.
const docsDir = fileURLToPath(new URL('../docs', import.meta.url));
const watchDocs = {
  name: 'watch-docs',
  hooks: {
    'astro:server:setup': ({ server }) => {
      server.watcher.add(docsDir);
      server.watcher.on('all', (_event, file) => {
        if (!file.startsWith(docsDir)) return;
        const before = readFileSync(sidebarFile, 'utf8');
        execFileSync(process.execPath, [fileURLToPath(new URL('./scripts/sync-docs.mjs', import.meta.url))], { stdio: 'inherit' });
        if (readFileSync(sidebarFile, 'utf8') !== before) server.restart();
      });
    },
  },
};

export default defineConfig({
  site: SITE,
  base: BASE,
  integrations: [
    watchDocs,
    starlight({
      title: 'coucou-shell',
      description: 'A Fedora + Hyprland desktop, installed and kept up to date by its own manager.',
      social: [{ icon: 'github', label: 'GitHub', href: REPO }],
      customCss: ['./src/styles/custom.css'],
      sidebar: [
        {
          label: 'Getting started',
          items: ['docs/installation', 'docs/cc-pkg-mng', 'docs/configuration'],
        },
        {
          label: 'Reference',
          items: ['docs/hardware', 'docs/keybindings'],
        },
        {
          label: 'Units',
          items: [
            { label: 'Overview', slug: 'docs/modules' },
            ...moduleGroups.map((g) => ({ ...g, collapsed: false })),
          ],
        },
      ],
    }),
  ],
});
