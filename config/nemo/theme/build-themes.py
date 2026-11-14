#!/usr/bin/env python3
"""Build the two GTK3 themes the bar's appearance toggle switches between,
in ~/.local/share/themes, in the shell's palette:

  Adwaita-dark   Adwaita's dark sheet, its colours remapped onto the
                 drawers' greys (DrawerTheme.qml, dark side).
  Adwaita-light  Adwaita's light sheet, remapped onto the light cream.

Why generated themes and not a user gtk.css: GTK3 ships Adwaita compiled
into libgtk-3 as a gresource, and that stylesheet is almost entirely
LITERAL colours, so redefining @theme_bg_color & co. in a user sheet
repaints only what an app's own CSS reads and leaves every stock widget
on Adwaita's blue (tab underline, switches, checks, focus rings,
progress bars, the rubberband). A user sheet is also loaded in both
modes, so it cannot hold a palette at all.

Why these two names: GTK3 resolves a theme name against its built-in
resources BEFORE ~/.local/share/themes, so "Adwaita" always means the
compiled light Adwaita and can never be restyled. Neither "Adwaita-dark"
nor "Adwaita-light" is built in, so both resolve to the files written
here. The bar's toggle (quickshell/bar/services/AppearanceState.qml)
writes one or the other to org.gnome.desktop.interface gtk-theme.

What it does, at install time (no runtime cost, GTK reads static files):
  1. extracts Adwaita's own sheet for each mode from libgtk-3, so the
     result tracks the installed GTK instead of a vendored copy;
  2. remaps its literal colours: neutral greys onto the shell's ramp
     (piecewise-linear, so Adwaita's ordering of surfaces survives), the
     blue accent family onto neutral greys of the same lightness (the
     shell has no accent hue: "on" is an inversion, drawn by overlay.css);
  3. rewrites asset urls to absolute resource:// paths;
  4. writes gtk.css = that base + the mode's palette + overlay.css. The
     palette and overlay are imported from the repo, so editing them
     needs a Nemo restart (`nemo -q`), not a rebuild.

Usage: build-themes.py [THEMES_DIR]
"""

import colorsys
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIBGTK = "/usr/lib64/libgtk-3.so.0"
RES = "/org/gtk/libgtk/theme/Adwaita"

# ---- grey ramps: copies of quickshell/bar/theme/DrawerTheme.qml ---------
# Adwaita lightness -> shell colour. Anchors are Adwaita's own surface
# roles (read off @define-color at the end of each sheet). Both ramps stay
# MONOTONIC on purpose: Adwaita draws hover/pressed states as small steps
# up or down from these greys, and a ramp that turned around would turn
# those steps around too.
DARK_ANCHORS = [
    (0x00, (0x00, 0x00, 0x00)),
    (0x1b, (0x05, 0x05, 0x06)),  # borders           -> near black
    (0x20, (0x0b, 0x0b, 0x0d)),  # unfocused borders -> cardDeep
    (0x2d, (0x17, 0x17, 0x1a)),  # base / view       -> card
    (0x35, (0x1c, 0x1c, 0x20)),  # window bg         -> accentSoft
    (0x5b, (0x48, 0x48, 0x4a)),  # unfocused insens. -> faint
    (0x91, (0x8e, 0x8e, 0x93)),  # insensitive fg    -> secondary
    (0xee, (0xf2, 0xf2, 0xf7)),  # fg                -> primary
    (0xff, (0xff, 0xff, 0xff)),
]
# The light side is a warm cream, never pure white: Adwaita's white base
# lands a step above the window cream rather than on #ffffff.
LIGHT_ANCHORS = [
    (0x00, (0x00, 0x00, 0x00)),
    (0x32, (0x1c, 0x1c, 0x1e)),  # fg #2e3436        -> primary
    (0x93, (0x86, 0x86, 0x8b)),  # insensitive fg    -> muted
    (0xb8, (0xb5, 0xb3, 0xac)),  # dark borders      -> between faint and onInk2
    (0xc8, (0xc9, 0xc7, 0xc0)),  # borders #cdc7c2   -> onInk2
    (0xd2, (0xd9, 0xd7, 0xd0)),  # unfocused borders -> accentStrong
    (0xe9, (0xe8, 0xe6, 0xe0)),  # #eeeeec           -> accentSoft
    (0xf5, (0xf5, 0xf3, 0xee)),  # window bg         -> panelTop
    (0xf9, (0xf7, 0xf5, 0xf0)),  # insensitive bg    -> onLight
    (0xff, (0xf9, 0xf8, 0xf4)),  # base / white      -> a lighter cream
]

THEMES = {
    "Adwaita-dark": {"sheet": "gtk-contained-dark.css", "anchors": DARK_ANCHORS, "palette": "palette-dark.css"},
    "Adwaita-light": {"sheet": "gtk-contained.css", "anchors": LIGHT_ANCHORS, "palette": "palette-light.css"},
}


def ramp(anchors, v):
    for (x0, c0), (x1, c1) in zip(anchors, anchors[1:]):
        if x0 <= v <= x1:
            t = (v - x0) / (x1 - x0)
            return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
    return (v, v, v)


def mapper(anchors):
    def map_rgb(r, g, b):
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        # Near-greys, including Adwaita's slightly blue #2e3436 and its warm
        # light surfaces, follow the ramp by lightness.
        if max(r, g, b) - min(r, g, b) <= 12 or s < 0.25:
            return ramp(anchors, round(l * 255))
        # The blue accent family becomes a grey of the same lightness.
        if 195 / 360 <= h <= 235 / 360 and s > 0.2:
            return ramp(anchors, round(l * 255))
        return (r, g, b)  # reds, greens, oranges: state colours, left alone
    return map_rgb


HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
RGBA = re.compile(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(,\s*[\d.]+\s*)?\)")


def remap_values(text, map_rgb):
    def hex_sub(m):
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        r, g, b = map_rgb(*(int(h[i:i + 2], 16) for i in (0, 2, 4)))
        return f"#{r:02x}{g:02x}{b:02x}"

    def rgba_sub(m):
        r, g, b = map_rgb(*(int(m.group(i)) for i in (1, 2, 3)))
        alpha = m.group(4)
        return f"rgba({r}, {g}, {b}{alpha})" if alpha else f"rgb({r}, {g}, {b})"

    return RGBA.sub(rgba_sub, HEX.sub(hex_sub, text))


def remap(css, map_rgb):
    """Recolour declaration blocks and @define-color lines, never selectors
    (`#id` selectors would otherwise look like colours)."""
    out, depth, i, n = [], 0, 0, len(css)
    while i < n:
        if depth == 0:
            j = css.find("{", i)
            head = css[i:] if j < 0 else css[i:j]
            head = re.sub(r"(?m)^(@define-color\s+\S+\s+)(.*)$",
                          lambda m: m.group(1) + remap_values(m.group(2), map_rgb), head)
            out.append(head)
            if j < 0:
                break
            out.append("{")
            depth, i = 1, j + 1
        else:
            j = css.find("}", i)
            out.append(remap_values(css[i:j], map_rgb))
            out.append("}")
            depth, i = 0, j + 1
    return "".join(out)


def build(themes_dir, name, spec):
    dest = themes_dir / name / "gtk-3.0"
    base = subprocess.run(["gresource", "extract", LIBGTK, f"{RES}/{spec['sheet']}"],
                          check=True, capture_output=True, text=True).stdout
    base = base.replace('url("assets/', f'url("resource://{RES}/assets/')
    dest.mkdir(parents=True, exist_ok=True)
    header = "/* GENERATED by config/nemo/theme/build-themes.py -- do not edit. */\n"
    (dest / "base.css").write_text(header + remap(base, mapper(spec["anchors"])))
    (dest / "gtk.css").write_text(
        header
        + '@import url("base.css");\n'
        + f'@import url("file://{HERE / spec["palette"]}");\n'
        + f'@import url("file://{HERE / "overlay.css"}");\n')
    # GTK looks for gtk-dark.css first when gtk-application-prefer-dark-theme
    # is set; each theme has one look, so both names serve it.
    dark = dest / "gtk-dark.css"
    if dark.is_symlink() or dark.exists():
        dark.unlink()
    dark.symlink_to("gtk.css")
    return dest


def main():
    themes_dir = Path(sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/share/themes"))
    for name, spec in THEMES.items():
        print(build(themes_dir, name, spec))


if __name__ == "__main__":
    main()
