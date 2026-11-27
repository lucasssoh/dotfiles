#!/usr/bin/env python3
"""The shell theme, outside Quickshell.

    shell-theme.py pick   choose the look in fuzzel (Super+Shift+W)
    shell-theme.py sync   colour the apps from the selected theme

shell-theme.json only holds the selection; each theme is a JSON file in
~/.config/hypr/themes/. Quickshell watches both and runs `sync` when the
theme or the look changes. `sync` writes under $XDG_STATE_HOME/coucou-shell/theme/,
both modes in each case, and leaves a file alone when its content is the
same, so nothing reloads without a real change:

    wezterm-theme.lua, nvim-palette.lua   always, from the theme
    gtk-ink-dark.css, gtk-ink-light.css   Nemo and GTK3 dialogs, in Ink;
                                          a comment in glass
    swayimg-theme.lua                     swayimg, in Ink; nil in glass
    fontview-theme.json                   fontview, in Ink; null in glass
    zathura-ink-dark, zathura-ink-light   Liseuse's zathura, in Ink;
                                          empty in glass

GTK3 reads its theme again only when the theme's name changes, so after
a new GTK sheet `sync` moves gtk-theme to the twin of the current name
(Adwaita-dark <-> Coucou-dark, the same files; see
config/nemo/theme/build-themes.py). swayimg and zathura read theirs when
they open, fontview watches its file.
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
# The repo's config/ folder, through the ~/.config/hypr link.
CONFIG = Path(__file__).resolve().parents[3]
INK_CSS = CONFIG / "nemo/theme/ink.css"
GTK_TWINS = {"Adwaita-dark": "Coucou-dark", "Coucou-dark": "Adwaita-dark",
             "Adwaita-light": "Coucou-light", "Coucou-light": "Adwaita-light"}


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


def outline_width(theme):
    w = (theme.get("geometry") or {}).get("outline-width", 3)
    return max(1, min(6, round(w))) if isinstance(w, (int, float)) else 3


def alpha(value, a):
    c = [int(value[i:i + 2], 16) for i in (1, 3, 5)]
    return f"rgba({c[0]},{c[1]},{c[2]},{a})"


def gtk_ink(theme, mode, template):
    """The Ink sheet for one mode: the palette's names in the theme's
    colours, then ink.css with its width and font filled in."""
    s, t, a = mode["surfaces"], mode["text"], mode["accents"]
    names = {
        "c_chrome": s["panel"], "c_well": s["card-sunken"], "c_wellrim": alpha(t["primary"], 0.08),
        "c_deep": s["card-sunken"], "c_ink": t["primary"], "c_ink2": t["secondary"],
        "c_muted": t["muted"], "c_faint": t["faint"], "c_hover": alpha(t["primary"], 0.07),
        "c_act": s["card"], "c_actedge": mode["outline"], "c_on": a["active"],
        "c_onink": t["on-accent"], "c_field": s["card-sunken"], "c_fieldrim": mode["outline"],
        "c_card": s["card"], "c_cardh": s["card-hover"], "c_menu": s["card"],
        "c_menurim": mode["outline"], "c_hair": alpha(t["faint"], 0.6), "c_gtrack": s["card-sunken"],
        "c_danger": a["danger"], "c_dsoft": mix(a["danger"], [int(s["panel"][i:i + 2], 16) for i in (1, 3, 5)], 0.82),
        "c_warning": a["warning"], "c_tip": s["card-raised"], "c_tipink": t["primary"],
        "c_shadow": alpha(mode["shadow"], 0.5),
        "k_outline": mode["outline"], "k_active": a["active"], "k_onaccent": t["on-accent"],
        "k_card": s["card"],
    }
    font = theme.get("font") if isinstance(theme.get("font"), str) else "Fredoka"
    # Without the template's own header, which names the placeholders.
    if template.startswith("/*") and "*/" in template:
        template = template[template.index("*/") + 2:].lstrip("\n")
    body = (template.replace("@ow", f"{outline_width(theme)}px")
            .replace("@font", json.dumps(font)))
    return ("/* Written by shell-theme.py sync from the selected shell theme"
            " and config/nemo/theme/ink.css. */\n"
            + "".join(f"@define-color {k} {v};\n" for k, v in names.items())
            + body
            # Nemo paints its disk gauges with these, opaque: the accent
            # in a groove of the outline.
            + "\n.places-treeview {\n"
            f"    -NemoPlacesTreeView-disk-full-bg-color: {mode['outline']};\n"
            f"    -NemoPlacesTreeView-disk-full-fg-color: {a['active']};\n}}\n"
            ".places-treeview:selected {\n"
            f"    -NemoPlacesTreeView-disk-full-bg-color: {mode['outline']};\n"
            f"    -NemoPlacesTreeView-disk-full-fg-color: {a['active']};\n}}\n")


def argb(value):
    """swayimg's colours: opaque 0xAARRGGBB numbers."""
    return 0xff000000 | int(value[1:], 16)


def swayimg_mode(theme, mode):
    s, t, a = mode["surfaces"], mode["text"], mode["accents"]
    return {
        "window": argb(s["card-sunken"]),
        "text": argb(t["muted"]),
        "chess": [argb(s["card"]), argb(s["card-hover"])],
        "mark": argb(a["active"]),
        # The thumbnail fills its tile, so the selection shows as its
        # border: the accent, the outline's width.
        "border": argb(a["active"]),
        "border_size": outline_width(theme),
        "selected": argb(a["active"]),
        "unselected": argb(s["card"]),
    }


def zathura_ink(mode):
    """Liseuse appends this after its own colours: the chrome and the
    dark reader's page in the theme's, recolor itself left to Liseuse."""
    s, t, a = mode["surfaces"], mode["text"], mode["accents"]
    ground = s["card-sunken"]
    page_ink = mix(t["primary"], [int(ground[i:i + 2], 16) for i in (1, 3, 5)], 0.12)
    rows = [
        ("recolor-lightcolor", ground), ("recolor-darkcolor", page_ink),
        ("default-bg", ground), ("default-fg", t["primary"]),
        ("statusbar-bg", s["panel"]), ("statusbar-fg", t["secondary"]),
        ("inputbar-bg", s["panel"]), ("inputbar-fg", t["primary"]),
        ("notification-bg", s["card"]), ("notification-fg", t["primary"]),
        ("notification-error-bg", s["card"]), ("notification-error-fg", a["danger"]),
        ("notification-warning-bg", s["card"]), ("notification-warning-fg", a["warning"]),
        ("completion-bg", s["card"]), ("completion-fg", t["primary"]),
        ("completion-highlight-bg", a["active"]), ("completion-highlight-fg", t["on-accent"]),
        ("completion-group-bg", s["panel"]), ("completion-group-fg", t["muted"]),
        ("highlight-color", alpha(a["active"], 0.35)),
        ("highlight-active-color", alpha(a["active"], 0.6)),
        ("render-loading-bg", ground), ("render-loading-fg", t["muted"]),
    ]
    return ("\n# ---- written by shell-theme.py sync: the Ink theme's colours ----\n"
            + "".join(f'set {k} "{v}"\n' for k, v in rows))


def reload_gtk():
    """Move gtk-theme to the twin of the current name, so running GTK3
    apps read the new sheet. A name that is not ours is left alone."""
    try:
        current = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
                                 capture_output=True, text=True, timeout=5).stdout.strip().strip("'")
        if current in GTK_TWINS:
            subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme",
                            GTK_TWINS[current]], timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


def sync():
    style, theme_id = selection()
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

    ink = style == "cartoon"
    try:
        template = INK_CSS.read_text(encoding="utf-8") if ink else ""
    except OSError:
        template, ink = "", False
    gtk_changed = False
    for m in ("dark", "light"):
        css = gtk_ink(theme, modes[m], template) if ink else "/* Glass: no Ink sheet. */\n"
        gtk_changed |= write_atomic(STATE / f"gtk-ink-{m}.css", css)
        write_atomic(STATE / f"zathura-ink-{m}", zathura_ink(modes[m]) if ink else "")
    fontview = {m: {"panel": modes[m]["surfaces"]["panel"], "card": modes[m]["surfaces"]["card"],
                    "primary": modes[m]["text"]["primary"], "secondary": modes[m]["text"]["secondary"],
                    "muted": modes[m]["text"]["muted"], "outline": modes[m]["outline"]}
                for m in ("dark", "light")}
    fontview["font"] = theme.get("font") if isinstance(theme.get("font"), str) else "Fredoka"
    fontview["outline"] = outline_width(theme)
    write_atomic(STATE / "fontview-theme.json", (json.dumps(fontview, indent=1) if ink else "null") + "\n")
    write_atomic(STATE / "swayimg-theme.lua",
                 header + (lua({m: swayimg_mode(theme, modes[m]) for m in ("dark", "light")}) if ink else "nil") + "\n")
    if gtk_changed:
        reload_gtk()
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
