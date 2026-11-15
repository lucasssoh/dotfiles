import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { BASE, REPO, SITE } from './site.config.mjs';

// In `astro dev`, re-run the sync whenever ../docs changes.
const docsDir = fileURLToPath(new URL('../docs', import.meta.url));
const watchDocs = {
  name: 'watch-docs',
  hooks: {
    'astro:server:setup': ({ server }) => {
      server.watcher.add(docsDir);
      server.watcher.on('all', (_event, file) => {
        if (!file.startsWith(docsDir)) return;
        execFileSync(process.execPath, [fileURLToPath(new URL('./scripts/sync-docs.mjs', import.meta.url))], { stdio: 'inherit' });
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
      expressiveCode: { styleOverrides: { borderRadius: '14px' } },
      sidebar: [
        {
          label: 'Getting started',
          items: ['docs/installation', 'docs/cc-pkg-mng', 'docs/configuration', 'docs/keybindings'],
        },
        {
          label: 'The bar',
          items: [
            { label: 'Overview', slug: 'docs/bar' },
            'docs/bar/clock-agenda', 'docs/bar/metrics', 'docs/bar/island', 'docs/bar/launchers',
            'docs/bar/balise', 'docs/bar/mixer', 'docs/bar/power', 'docs/bar/notifications',
            'docs/bar/indicators', 'docs/bar/key-sheet', 'docs/bar/veille', 'docs/bar/programme',
          ],
        },
        {
          label: 'Tools',
          items: [
            'docs/tools/roue', 'docs/tools/prisme', 'docs/tools/manette', 'docs/tools/sesame',
            'docs/tools/liseuse', 'docs/tools/launcher', 'docs/tools/screenshot', 'docs/tools/fontview',
          ],
        },
        {
          label: 'Session',
          items: [
            'docs/session/hyprland', 'docs/session/displays', 'docs/session/wallpapers',
            'docs/session/theme', 'docs/session/audio', 'docs/session/lock',
            'docs/session/boot-splash', 'docs/session/login',
          ],
        },
        {
          label: 'Applications',
          items: [
            'docs/apps/wezterm', 'docs/apps/firefox', 'docs/apps/nemo', 'docs/apps/neovim',
            'docs/apps/mpv', 'docs/apps/swayimg', 'docs/apps/games', 'docs/apps/extras',
          ],
        },
        {
          label: 'Reference',
          items: ['docs/units', 'docs/hardware', 'docs/writing-a-unit'],
        },
      ],
    }),
  ],
});
