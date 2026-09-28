#!/usr/bin/env python3
"""Build ~/.local/share/themes/Adwaita-dark/gtk-3.0 in the bar's palette.

Why a generated theme and not a user gtk.css: GTK3 ships Adwaita compiled
into libgtk-3 as a gresource, and that stylesheet is almost entirely
LITERAL colours -- `grep -c @theme_ gtk-contained-dark.css` is 1. So the
old approach, redefining @theme_bg_color & co. in ~/.config/gtk-3.0/gtk.css,
repainted only what an app's own CSS reads (a handful of Nemo rules) and
left every stock widget on Adwaita's blue: the active-tab underline,
switches, checks, focus rings, the rename box, progress bars, the
rubberband. That is the "indicators are still wrong" of the Nemo rework.

Why the name "Adwaita-dark": it is what the bar's appearance toggle
(quickshell/bar/services/AppearanceState.qml) already writes to
org.gnome.desktop.interface gtk-theme, and GTK3 has no built-in theme by
that name -- it only has "Adwaita" plus a variant flag -- so until this
file exists the name resolves to nothing and GTK3 silently falls back to
LIGHT Adwaita (measured: Nemo's properties dialog drew a #ffffff page).
Giving the name a real theme makes the toggle work for GTK3 live, with no
change on the QML side: dark -> this theme, light -> stock Adwaita.

What it does, once, at install time (zero runtime cost -- GTK reads a
static file):
  1. extracts Adwaita's own dark stylesheet from libgtk-3, so the result
     tracks whatever GTK version is installed instead of a vendored copy;
  2. remaps its literal colours onto DrawerTheme.qml: neutral greys onto
     the drawers' grey ramp (piecewise-linear, so Adwaita's ordering of
     surfaces is kept), and the blue accent family onto neutral greys of
     the same lightness -- the drawers have no accent hue, "on" is an
     inversion, drawn by overlay.css;
  3. rewrites asset urls to absolute resource:// paths (they are relative
     to the gresource and would break from a file on disk);
  4. writes gtk.css = that base + an @import of overlay.css, which holds
     the hand-written rules. overlay.css is imported from the repo, so
     editing it needs a Nemo restart, not a rebuild.

Usage: build-adwaita-dark.py [DEST_DIR]
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

# ---- palette: copies of quickshell/bar/theme/DrawerTheme.qml ------------
# The drawers' palette since the HyperOS pass: neutral greys, no blue
# tint, and "on" carried by inversion rather than by an accent colour.
# Adwaita-dark grey -> drawer grey. Anchors are Adwaita's own surface
# roles (read off @define-color at the end of gtk-contained-dark.css).
# The ramp stays MONOTONIC on purpose: Adwaita draws hover/pressed states
# as small steps up or down from these greys, and an inverted ramp would
# turn those steps around. The drawers' black pane is applied to Nemo's
# chrome by overlay.css instead, where it breaks nothing.
GREY_ANCHORS = [
    (0x00, (0x00, 0x00, 0x00)),
    (0x1b, (0x05, 0x05, 0x06)),  # borders           -> near black
    (0x20, (0x0b, 0x0b, 0x0d)),  # unfocused borders -> cardDeep
    (0x2d, (0x17, 0x17, 0x1a)),  # base / view       -> card
    (0x35, (0x1c, 0x1c, 0x20)),  # window bg         -> accentSoft
    (0x5b, (0x48, 0x48, 0x4a)),  # unfocused insens. -> Ink faint
    (0x91, (0x8e, 0x8e, 0x93)),  # insensitive fg    -> secondary
    (0xee, (0xf2, 0xf2, 0xf7)),  # fg                -> primary
    (0xff, (0xff, 0xff, 0xff)),
]

# DrawerTheme's accent IS the primary ink -- there is no hue left to map
# Adwaita's blues onto. They become neutral greys at their own lightness,
# so every contrast Adwaita tuned survives; the controls that mean "on"
# get the inverted ink fill from overlay.css.


def map_grey(v):
    for (x0, c0), (x1, c1) in zip(GREY_ANCHORS, GREY_ANCHORS[1:]):
        if x0 <= v <= x1:
            t = (v - x0) / (x1 - x0)
            return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
    return (v, v, v)


def map_rgb(r, g, b):
    if max(r, g, b) - min(r, g, b) <= 6:
        return map_grey(round((r + g + b) / 3))
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if 195 / 360 <= h <= 235 / 360 and s > 0.2:
        return map_grey(round(l * 255))
    return (r, g, b)  # reds, greens, oranges: state colours, left alone


HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
RGBA = re.compile(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(,\s*[\d.]+\s*)?\)")


def remap_values(text):
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


def remap(css):
    """Recolour declaration blocks and @define-color lines, never selectors
    (`#id` selectors would otherwise look like colours)."""
    out, depth, i, n = [], 0, 0, len(css)
    while i < n:
        if depth == 0:
            j = css.find("{", i)
            head = css[i:] if j < 0 else css[i:j]
            head = re.sub(r"(?m)^(@define-color\s+\S+\s+)(.*)$",
                          lambda m: m.group(1) + remap_values(m.group(2)), head)
            out.append(head)
            if j < 0:
                break
            out.append("{")
            depth, i = 1, j + 1
        else:
            j = css.find("}", i)
            out.append(remap_values(css[i:j]))
            out.append("}")
            depth, i = 0, j + 1
    return "".join(out)


def main():
    dest = Path(sys.argv[1] if len(sys.argv) > 1 else
                os.path.expanduser("~/.local/share/themes/Adwaita-dark/gtk-3.0"))
    base = subprocess.run(["gresource", "extract", LIBGTK, f"{RES}/gtk-contained-dark.css"],
                          check=True, capture_output=True, text=True).stdout
    base = base.replace('url("assets/', f'url("resource://{RES}/assets/')
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "base.css").write_text(
        "/* GENERATED by config/nemo/theme/build-adwaita-dark.py -- do not edit. */\n"
        + remap(base))
    (dest / "gtk.css").write_text(
        "/* GENERATED by config/nemo/theme/build-adwaita-dark.py -- do not edit. */\n"
        '@import url("base.css");\n'
        f'@import url("file://{HERE / "overlay.css"}");\n')
    # GTK looks for gtk-dark.css first when gtk-application-prefer-dark-theme
    # is set; this theme only has one variant, so both names serve it.
    dark = dest / "gtk-dark.css"
    if dark.is_symlink() or dark.exists():
        dark.unlink()
    dark.symlink_to("gtk.css")
    print(dest)


if __name__ == "__main__":
    main()
