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
import math
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
NAUTILUS_CSS = CONFIG / "nautilus/ink.css"
# The folder icons: Adwaita's, recoloured into a theme of ours that
# inherits it; two names for one folder, as for the GTK themes.
ADWAITA_PLACES = Path("/usr/share/icons/Adwaita/scalable/places")
ICONS = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "icons"
ICON_TWINS = {"Coucou": "Coucou-twin", "Coucou-twin": "Coucou"}
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


def extra(accents, key, fallback):
    """An optional accent (blue, magenta, cyan), or `fallback`."""
    value = accents.get(key)
    return value if isinstance(value, str) and HEX.fullmatch(value) else fallback


def wezterm_mode(mode):
    s, t, a = mode["surfaces"], mode["text"], mode["accents"]
    background = s["card-sunken"]
    # blue, magenta and cyan are optional in a theme: without them, info,
    # warning and active stand in, as before they existed.
    ansi = [background, a["danger"], a["success"], a["highlight"],
            extra(a, "blue", a["info"]), extra(a, "magenta", a["warning"]),
            extra(a, "cyan", a["active"]), t["primary"]]
    # Brights lift each colour off a dark ground; on a light one, lightened
    # colours faded into it, so there they deepen a little instead.
    if contrast(background, "#000000") > contrast(background, "#ffffff"):
        brights = [t["muted"]] + [darken(c, 0.15) for c in ansi[1:7]] + [darken(t["primary"], 0.2)]
    else:
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
    write_atomic(STATE / "nautilus-ink.css",
                 nautilus_ink(theme) if ink else nautilus_glass())
    if write_folder_icons(folder_colour(theme) if ink else None):
        reload_icons()
    write_atomic(STATE / "swayimg-theme.lua",
                 header + (lua({m: swayimg_mode(theme, modes[m]) for m in ("dark", "light")}) if ink else "nil") + "\n")
    if gtk_changed:
        reload_gtk()
    return 0


# ---- Nautilus --------------------------------------------------------------

def nautilus_ink(theme):
    """Nautilus's Ink sheet: both modes' colours as CSS variables (the dark
    ones under a prefers-color-scheme query, which GTK4 follows live), then
    config/nautilus/ink.css. The coucou_ink extension loads it and reads it
    again when it changes."""
    def block(mode, indent):
        s, t, a = mode["surfaces"], mode["text"], mode["accents"]
        # The places and buttons are read in the secondary ink: where a
        # theme's is too faint on its panel (Everforest, Kanagawa and
        # Tokyo Night in light), it moves toward the primary until it reads.
        secondary = t["secondary"]
        for step in range(1, 11):
            if contrast(secondary, s["panel"]) >= 4.5:
                break
            secondary = mix(t["secondary"], [int(t["primary"][i:i + 2], 16) for i in (1, 3, 5)], step / 10)
        names = {"panel": s["panel"], "card": s["card"], "cardh": s["card-hover"],
                 "sunken": s["card-sunken"], "primary": t["primary"], "secondary": secondary,
                 "muted": t["muted"], "faint": t["faint"], "onaccent": t["on-accent"],
                 "active": a["active"], "outline": mode["outline"], "hair": alpha(t["faint"], 0.6)}
        return "".join(f"{indent}--ink-{k}: {v};\n" for k, v in names.items())
    try:
        body = NAUTILUS_CSS.read_text(encoding="utf-8")
    except OSError:
        return "/* No config/nautilus/ink.css. */\n"
    font = theme.get("font") if isinstance(theme.get("font"), str) else "Fredoka"
    modes = theme["modes"]
    return ("/* Written by shell-theme.py sync from the selected shell theme"
            " and config/nautilus/ink.css. */\n"
            ":root {\n" + block(modes["light"], "    ")
            + f"    --ink-w: {outline_width(theme)}px;\n}}\n"
            "@media (prefers-color-scheme: dark) {\n  :root {\n" + block(modes["dark"], "    ") + "  }\n}\n"
            + body.replace("Fredoka, sans-serif", f"{json.dumps(font)}, sans-serif"))


def contrast(a, b):
    """WCAG contrast ratio of two #rrggbb colours."""
    def lum(value):
        c = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


GLASS_NAMES = {"panel": "c_chrome", "card": "c_card", "cardh": "c_cardh", "sunken": "c_gtrack",
               "primary": "c_ink", "secondary": "c_ink2", "muted": "c_muted", "faint": "c_faint",
               "onaccent": "c_onink", "active": "c_on", "outline": "c_actedge", "hair": "c_hair"}


def nautilus_glass():
    """Nautilus in the glass look: the same sheet in Nemo's glass palette
    (config/nemo/theme/palette-*.css), hairlines for outlines, the inverted
    ink for what is on, and the system font."""
    def block(name, indent):
        try:
            text = (CONFIG / "nemo/theme" / f"palette-{name}.css").read_text(encoding="utf-8")
        except OSError:
            return ""
        found = dict(re.findall(r"@define-color\s+(\w+)\s+([^;]+);", text))
        return "".join(f"{indent}--ink-{k}: {found[v].strip()};\n" for k, v in GLASS_NAMES.items() if v in found)
    try:
        body = NAUTILUS_CSS.read_text(encoding="utf-8")
    except OSError:
        return "/* No config/nautilus/ink.css. */\n"
    return ("/* Written by shell-theme.py sync: the glass look, from config/nemo/theme"
            " and config/nautilus/ink.css. */\n"
            ":root {\n" + block("light", "    ") + "    --ink-w: 1px;\n}\n"
            "@media (prefers-color-scheme: dark) {\n  :root {\n" + block("dark", "    ") + "  }\n}\n"
            + body.replace("font-family: Fredoka, sans-serif;", "font-family: inherit;"))


# ---- folder icons ----------------------------------------------------------
# OKLab, to move a colour's hue and chroma without touching how light it
# looks (https://bottosson.github.io/posts/oklab/).

def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def oklch(value):
    r, g, b = (_lin(int(value[i:i + 2], 16) / 255) for i in (1, 3, 5))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, (A * A + B * B) ** 0.5, math.atan2(B, A)


def from_oklch(L, C, H):
    """The nearest sRGB colour: chroma is lowered until it fits."""
    for _ in range(40):
        A, B = C * math.cos(H), C * math.sin(H)
        l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
        m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
        s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3
        rgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
               -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        if all(-1e-4 <= c <= 1.0001 for c in rgb):
            break
        C *= 0.92
    return "#" + "".join(f"{round(max(0, min(1, _gam(max(0, c)))) * 255):02x}" for c in rgb)


# Adwaita's folder ramp, darkest to lightest; #62a0ea is the main face.
ADWAITA_FOLDER = ("#438de6", "#62a0ea", "#a4caee", "#afd4ff", "#c0d5ea")
ADWAITA_BASE = "#62a0ea"


def folder_colour(theme):
    """The theme's own folder colour, else its dark mode's info accent."""
    value = theme.get("folder")
    if isinstance(value, str) and HEX.fullmatch(value):
        return value
    return theme["modes"]["dark"]["accents"]["info"]


def folder_ramp(colour):
    """Adwaita's five folder colours turned to `colour`: its hue, its
    chroma in proportion, and half of its lightness gap, so a pale or a
    deep colour still reads as a folder on light and dark grounds."""
    bl, bc, _ = oklch(ADWAITA_BASE)
    fl, fc, fh = oklch(colour)
    ramp = {}
    for src in ADWAITA_FOLDER:
        l, c, _ = oklch(src)
        ramp[src] = from_oklch(min(0.97, max(0.25, l + (fl - bl) / 2)), c * fc / bc, fh)
    return ramp


def write_folder_icons(colour):
    """The Coucou icon theme: Adwaita's folder icons in `colour`, or none
    (pure Adwaita) when there is no colour. Returns True on a change."""
    root = ICONS / "Coucou"
    places = root / "scalable/places"
    changed = False
    sources = sorted(ADWAITA_PLACES.glob("folder*.svg")) + [ADWAITA_PLACES / n for n in ("user-desktop.svg", "user-home.svg")]
    if colour:
        ramp = folder_ramp(colour)
        for src in sources:
            try:
                svg = src.read_text(encoding="utf-8")
            except OSError:
                continue
            for old, new in ramp.items():
                svg = re.sub(re.escape(old), new, svg, flags=re.IGNORECASE)
            changed |= write_atomic(places / src.name, svg)
    elif places.exists():
        for f in places.glob("*.svg"):
            f.unlink()
            changed = True
    changed |= write_atomic(root / "index.theme",
                            "[Icon Theme]\nName=Coucou\nComment=Adwaita, folders in the shell theme's colour\n"
                            "Inherits=Adwaita,hicolor\nDirectories=scalable/places\n\n"
                            "[scalable/places]\nSize=128\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Places\n")
    twin = ICONS / "Coucou-twin"
    if not twin.is_symlink():
        try:
            twin.symlink_to("Coucou")
        except OSError:
            pass
    return changed


def reload_icons():
    """GTK reads an icon theme again only when its name changes: move
    icon-theme to the twin of the current name. A name not ours stays."""
    try:
        current = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
                                 capture_output=True, text=True, timeout=5).stdout.strip().strip("'")
        if current in ICON_TWINS:
            subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme",
                            ICON_TWINS[current]], timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


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
