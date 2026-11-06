# Agents

Read [CONTRIBUTING.md](CONTRIBUTING.md) before committing: it covers commit messages, versions, the changelog and releases, and the project's conventions. It applies to agents as much as to people.

Before writing or reviewing text shown in the interface, apply the `microcopie` skill (`.claude/skills/microcopie`, a local link to `~/code/ai-skills/redaction/microcopie`).

The documentation's screenshots are retaken by `scripts/pellicule`, from the scenes in [`docs/screenshots/scenes.toml`](docs/screenshots/scenes.toml). When you rename or change an `IpcHandler` function in the bar, or a command or option a scene runs (Roue, Prisme, fuzzel, `wallpaper-set`…), update the scenes in the same commit and run `scripts/pellicule check`: it fails on any scene the change broke. A scene for a new screen goes in the same file.
