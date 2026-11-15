---
name: doc-a-jour
description: Keeps coucou-shell's documentation, website and screenshots in step with the code. Use it before committing any change a user can see or act on - interface text, a key binding, an option, a setting or settings file, a command, a new screen, a new unit - and when writing a changelog line. It tells which page of docs/ to update, how to write it, and which checks to run (site build, links, scripts/pellicule check).
---

# Docs in step with the code

`docs/` is the single source. The website copies it (`site/scripts/sync-docs.mjs`), the README links into it. A visible change isn't finished until the page that describes it says the same thing.

## 1. Does this change need the docs?

Yes, if a person could see it or act on it:

| You changed | Update |
|---|---|
| Text shown in the interface | The guide that quotes it, and the screenshot's scene |
| A key binding | `docs/keybindings.md`, and the tool's guide |
| An option, a command, a flag | The tool's guide; `docs/cc-pkg-mng.md` for the manager |
| A setting, or a settings file (a key, a default, its path) | The tool's guide, with the key, its values and its default; `docs/configuration.md` if a file was added, moved, or changed owner |
| A file an upgrade must never replace | The *Files that are yours* table in `docs/configuration.md` |
| A new screen, drawer or tool | A new guide, its screenshot scene, the sidebar, `docs/units.md`, the README's tool table if it's one of the main tools |
| A unit added, removed or renamed | `docs/units.md`, `docs/installation.md` if `init` asks about it |
| Anything users will notice | A line in `CHANGELOG.md` (see `CONTRIBUTING.md`) |

No, for a refactor, a build tweak or an internal fix nobody sees. Design notes go in `docs/design/`, which the site leaves out.

## 2. Where pages live

| Folder | Holds |
|---|---|
| `docs/*.md` | Installation, cc-pkg-mng, your settings, key bindings, units, hardware, writing a unit |
| `docs/bar/` | One guide per part of the bar |
| `docs/tools/` | Roue, Prisme, Manette, Sésame, Liseuse, launcher, Screenshot, font viewer |
| `docs/session/` | Hyprland, displays, wallpapers, theme, audio, lock, boot splash, login |
| `docs/apps/` | One guide per application, and extras |

A new page also goes in the sidebar, in `site/astro.config.mjs`. Never edit `site/src/content/docs/docs/`: it's generated.

## 3. How a guide is written

In English. Each guide answers, in this order and only where there is something to say: what the tool does (one sentence), how to open it, how to use it (keys and clicks, in a table), where it is set, its limits.

- **Black box.** Describe the component and its configuration, never its design or how a script works inside.
- **Usable without an agent.** A setting that lives in a file gets the file's path, an example, and a table of keys, values and defaults. Say whether the file is the person's own or the checkout's.
- **Check before you write.** Read the code for each claim: the key, the default, the label as it shows on screen. Don't describe a behaviour you inferred from a name.
- **Apply the `microcopie` skill.** No justification of choices, no plumbing, no selling, nothing said twice. One idea per sentence.
- **Screenshots** come in a light and dark pair:

  ```html
  <picture><source media="(prefers-color-scheme: dark)" srcset="../screenshots/NAME-dark.webp"><img src="../screenshots/NAME.webp" alt="What it shows"></picture>
  ```

## 4. Screenshots

They're retaken by `scripts/pellicule` from `docs/screenshots/scenes.toml`. When you rename or change an `IpcHandler` function of the bar, or a command or option a scene runs, update the scenes in the same commit. A new screen gets a scene, with `doc =` pointing at its guide.

Pellicule takes over the screen while it shoots: ask the maintainer before a take. `scripts/pellicule check` touches nothing and can run any time.

## 5. Before you commit

```bash
scripts/pellicule check          # every scene still matches the shell
cd site && npm run build         # fails on a link to a page that doesn't exist
```

Then check that the links you added resolve, anchors included, and commit the docs with the change they describe, or right after it as `Docs : …`.

Report what you checked and what you couldn't.
