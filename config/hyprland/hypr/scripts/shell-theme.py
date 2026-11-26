#!/usr/bin/env python3
"""The shell theme, outside Quickshell.

    shell-theme.py pick   choose the look in fuzzel (Super+Shift+W)
    shell-theme.py sync   colour WezTerm and Neovim from the selected theme

shell-theme.json only holds the selection; each theme is a JSON file in
~/.config/hypr/themes/. Quickshell watches both and runs `sync` when the
theme changes. `sync` writes Lua files under $XDG_STATE_HOME/coucou-shell/theme/,
both modes in each, and leaves a file alone when its content is the same,
so WezTerm and Neovim only reload on a real change.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HYPR = Path.home() / ".config/hypr"
SELECTOR = HYPR / "shell-theme.json"
THEMES = HYPR / "themes"
FALLBACK = "coucou"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "coucou-shell/theme"

SCHEMA = {
    "surfaces": ("panel", "card", "card-hover", "card-raised", "card-sunken"),
    "text": ("primary", "secondary", "muted", "faint", "on-accent"),
    "accents": ("active", "highlight", "success", "info", "warning", "danger"),
}
HEX = re.compile(r"#[0-9a-fA-F]{6}")
THEME_ID = re.compile(r"[A-Za-z0-9_-]+")


def read_json(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def write_atomic(path, text):
    """Replace `path` in one step, so a watcher never reads half a file.
    Returns False when the content was already the same."""
    try:
        if path.read_text(encoding="utf-8") == text:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    return True


def selection():
    data = read_json(SELECTOR) or {}
    style = "cartoon" if data.get("style") == "cartoon" else "default"
    theme = data.get("theme")
    if not isinstance(theme, str) or not THEME_ID.fullmatch(theme):
        theme = FALLBACK
    return style, theme


def valid(theme):
    if not theme or theme.get("schema") != "coucou-theme/1":
        return False
    modes = theme.get("modes")
    if not isinstance(modes, dict):
        return False
    for mode in ("dark", "light"):
        m = modes.get(mode)
        if not isinstance(m, dict):
            return False
        if not all(isinstance(m.get(k), str) and HEX.fullmatch(m[k]) for k in ("outline", "shadow")):
            return False
        for group, keys in SCHEMA.items():
            g = m.get(group)
            if not isinstance(g, dict):
                return False
            if not all(isinstance(g.get(k), str) and HEX.fullmatch(g[k]) for k in keys):
                return False
    return True


def load_theme(theme_id):
    """The selected theme, or the fallback while it is missing or invalid."""
    for candidate in (theme_id, FALLBACK):
        theme = read_json(THEMES / f"{candidate}.json")
        if valid(theme):
            return theme
    return None


# ---- sync ------------------------------------------------------------------

def mix(value, target, amount):
    c = [int(value[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(c[i] + (target[i] - c[i]) * amount):02x}" for i in range(3))


def lighten(value, amount=0.45):
    return mix(value, (255, 255, 255), amount)


def darken(value, amount=0.35):
    return mix(value, (0, 0, 0), amount)


def nvim_palette(mode):
    s, t, a = mode["surfaces"], mode["text"], mode["accents"]
    return {
        "bg": s["card-sunken"],
        "surface": s["panel"],
        "overlay": s["card-hover"],
        "pill": s["card-raised"],
        "border": s["card-raised"],
        "muted": t["muted"],
        "subtle": t["secondary"],
        "text": t["primary"],
        "cyan": a["active"],
        "cyan_light": lighten(a["active"]),
        "blue": a["info"],
        "azure": lighten(a["info"], 0.3),
        "green": a["success"],
        "green_dim": darken(a["success"], 0.25),
        "yellow": a["highlight"],
        "red_soft": a["danger"],
        "red": darken(a["danger"], 0.2),
    }


def wezterm_mode(mode):
    s, t, a = mode["surfaces"], mode["text"], mode["accents"]
    background = s["card-sunken"]
    ansi = [background, a["danger"], a["success"], a["highlight"],
            a["info"], a["warning"], a["active"], t["primary"]]
    brights = [t["muted"]] + [lighten(c) for c in ansi[1:7]] + [lighten(t["primary"], 0.1)]
    return {
        "background": background,
        "tab_inks": [t["primary"], t["muted"], t["secondary"]],
        "colors": {
            "foreground": t["primary"],
            "background": background,
            "cursor_bg": a["active"],
            "cursor_fg": t["on-accent"],
            "cursor_border": a["active"],
            "selection_fg": t["primary"],
            "selection_bg": s["card-hover"],
            "split": background,
            "ansi": ansi,
            "brights": brights,
        },
    }


def lua(value, indent=0):
    """A Lua literal for the dicts, lists and strings above."""
    pad = "  " * indent
    if isinstance(value, dict):
        rows = [f"{pad}  {k} = {lua(v, indent + 1)}," for k, v in value.items()]
        return "{\n" + "\n".join(rows) + f"\n{pad}}}"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v) for v in value) + " }"
    return json.dumps(value)


def sync():
    _, theme_id = selection()
    theme = load_theme(theme_id)
    if theme is None:
        print(f"shell-theme: no valid theme in {THEMES}", file=sys.stderr)
        return 1
    modes = theme["modes"]
    header = "-- Written by shell-theme.py sync from the selected shell theme.\nreturn "
    write_atomic(STATE / "wezterm-theme.lua",
                 header + lua({m: wezterm_mode(modes[m]) for m in ("dark", "light")}) + "\n")
    write_atomic(STATE / "nvim-palette.lua",
                 header + lua({m: nvim_palette(modes[m]) for m in ("dark", "light")}) + "\n")
    return 0


# ---- pick ------------------------------------------------------------------

def theme_name(path):
    data = read_json(path)
    name = data.get("name") if data else None
    return name if isinstance(name, str) else path.stem


def pick():
    style, theme_id = selection()
    # Glass first, then the cartoon themes: coucou, then by name.
    paths = [p for p in THEMES.glob("*.json") if THEME_ID.fullmatch(p.stem)]
    named = sorted(((theme_name(p), p.stem) for p in paths),
                   key=lambda e: (e[1] != FALLBACK, e[0].lower()))
    entries = [("default", theme_id, "Glass")] + [("cartoon", tid, name) for name, tid in named]

    lines = []
    for i, (e_style, e_theme, label) in enumerate(entries):
        active = e_style == style and (style == "default" or e_theme == theme_id)
        lines.append(f"{i}\t{'*' if active else ' '} {label}")

    proc = subprocess.run(
        ["fuzzel", "--dmenu", "--with-nth", "2", "--only-match", "--prompt", "Theme  "],
        input="\n".join(lines), text=True, capture_output=True,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return 0
    try:
        new_style, new_theme, _ = entries[int(proc.stdout.split("\t", 1)[0])]
    except (ValueError, IndexError):
        return 0
    # Glass keeps the theme it had: switching back to cartoon finds it again.
    write_atomic(SELECTOR, json.dumps({"style": new_style, "theme": new_theme}, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "sync":
        sys.exit(sync())
    if command == "pick":
        sys.exit(pick())
    print("usage: shell-theme.py pick | sync", file=sys.stderr)
    sys.exit(2)
