# Contributing

How commits, versions, the changelog and releases work in coucou-shell. These rules apply to everyone, people and AI agents alike.

## Commits

```
Component : what changes
```

- **In English**, with a space before the colon.
- **Component** is the part you touched: `Quickshell`, `Hyprland`, `mpv`, `swayimg`, `cc-pkg-mng 2`, `units`, `Docs`, `Site`… Narrow it down in brackets when that helps: `Quickshell : [bar] …`, `cc-pkg-mng 2 : [edge] …`.
- **The title says the result, not the action.** `workspace occupancy from Hyprland's window count` tells more than `fix bug`.
- **The body is optional.** Use it to say *why*, when the title alone doesn't make it obvious.
- **One subject per commit.** A fix, a feature, or the docs on their own. Don't mix a fix with a new feature.
- **Release commits** read `X.Y.Z : the changelog ready for the tag`.

Each `-m` is a paragraph: the first is the title, the next ones the body.

```
git commit -m "Quickshell : [bar] workspace occupancy from Hyprland's window count" \
           -m "A Java popup whose close event never reached the bar stayed counted, keeping its workspace lit while Hyprland reported 0 windows."
```

Examples from the history:

```
Quickshell : [bar] workspace occupancy from Hyprland's window count, not ghost toplevels
Hyprland : start the bar once workspace-manager.sh has placed the workspaces
swayimg : the image viewer in the shell's colours, e edits in satty
1.0.2 : the changelog ready for the tag
```

## Versions

Versions follow `MAJOR.MINOR.PATCH`.

| You did… | Bump | Example | Heading |
|---|---|---|---|
| A bug fix | PATCH | 1.0.2 → 1.0.3 | the version alone |
| A new feature or a visible change (theme, app, key binding, wallpaper) | MINOR | 1.0.x → 1.1.0 | the date |
| A change that breaks existing installs (config format, component removed, a manual step needed) | MAJOR | 1.x → 2.0.0 | a code name |

- The version and the code name are the maintainer's call. Propose them, don't decide them.
- A minor release may contain fixes. A patch release never contains a new feature.
- Bump a Rust crate's `version` (Roue, Prisme, Balise, cc-pkg-mng) only when that crate changed. The RPM version comes from the tag.
- **A pushed tag never moves.** If a release turns out broken, publish the next one.

## Changelog

[`CHANGELOG.md`](CHANGELOG.md) is filled in as you go, not at release time.

- Every change users will notice gets a line under `## Unreleased`, in one of `### Fixed`, `### Added`, `### Changed`, `### Removed`.
- **Written for users**, addressing them as "you": what they see or can now do. No file paths, no internals.
- One line per change, starting with **the part concerned in bold**:

  ```
  - **Bar, centre island:** right after login, the bar now shows every workspace.
  ```

- Leave out what users don't notice: refactors, internal docs, build tweaks.
- Release headings: `## 2.0.0 « Name »` for a major release, `## 1.1.0 (October 1 2026)` for a minor one, `## 1.0.3` alone for a patch. A patch's section is just its list of fixes.

## Releasing

1. Check that everything since the last release is in `Unreleased`:

   ```
   git fetch --tags
   git log $(git describe --tags --abbrev=0)..HEAD --oneline
   ```

2. Rename `## Unreleased` to `## 1.1.0 (October 1 2026)`, `## 1.0.3` or `## 2.0.0 « Name »`.
3. Commit, tag, push:

   ```
   git commit -am "1.1.0 : the changelog ready for the tag"
   git tag -a v1.1.0 -m "v1.1.0 (October 1 2026)"
   git push origin master v1.1.0
   ```

4. The tag starts the Release workflow: it builds and signs the RPMs, publishes the GitHub release from the changelog section, and updates the dnf repository. Check that it's green in the Actions tab.

**Channels:** a push to `master` reaches machines on **edge** at their next `cc-pkg-mng upgrade`. Only a tag reaches **stable** and fresh installs.

## Project conventions

- **Interface text** is in English. Veille is the exception, in French.
- **Colours** come from [`DrawerTheme.qml`](config/hyprland/quickshell/bar/theme/DrawerTheme.qml). Prefer outlines to large white areas.
- **A new application** is a replaceable unit in `units/apps/<name>/`, with a hook that makes it the default for its file types. Anything downloaded from outside a package is pinned to a version and checked by sha256.
- **Documentation** lives in [`docs/`](docs/). It describes the components and how to configure them, not their design or the inner workings of scripts. The website is generated from `docs/`: never edit `site/src/content/docs/docs/`.
- **Test on a real session before committing**: a screenshot for anything visual, `hyprctl configerrors` after touching the Hyprland config.

## AI agents

If you're an agent, everything above applies to you too. Also:

- Don't push, tag or publish a release unless you're asked to.
- **Every commit you write ends with your `Co-Authored-By:` line**, as its last paragraph. No exception.

  ```
  git commit -m "swayimg : the image viewer in the shell's colours" \
             -m "e opens the image in satty; the edit is saved next to the original, which is never touched." \
             -m "Co-Authored-By: <agent name> <its address>"
  ```
- Report what you verified and what you couldn't. Don't call something tested when it wasn't.
