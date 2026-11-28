#!/usr/bin/env python3
"""The Ink wallpapers: one set per shell theme, drawn in its colours with
the shell's cartoon ink -- black outlines, the cards' hard shadow, the rim
of light inside each shape -- each in a light and a dark version, the pair
that follows the desktop's light/dark mode.

    python3 wallpapers/coucou/ink.py [--size 5120x3200] [--out wallpapers/ink]
                                     [--theme-dir DIR] [--themes nord,gruvbox]
                                     [--only collines,soleil] [--format jxl|png] [--jobs N]

Seven pictures per theme, `ink-<theme>-<picture>[-dark].jxl`:

    collines         inked hills in steps of the accent, a sun, two clouds, the bird
    pastilles        the shell's tiles, pills and toggles as stickers
    coucou           the Coucou bird on halftone dots
    rayons           a comic-book sunburst
    soleil           after GNOME's Dithered Sun: rings of the theme's colours,
                     stepped by ordered dithering
    soleil-collines  that sun behind the inked hills
    soleil-points    the same rings in comic-print dots

The colours come from config/hyprland/hypr/themes/*.json: add a theme,
run this, and it has its set. `--theme-dir ~/.config/hypr/themes` draws
your own themes' instead, best with `--out` pointing at a folder listed in
prisme/wallpapers-extra.conf. Only the theme's colours are painted, a few
mixed from two of them; the dithered suns never blend two rings.

Deterministic. Every length is relative to the image height. Rendered at
5120x3200 by default and fitted down to each screen like the other
wallpapers. JPEG XL, lossless (flat colours and outlines compress better
that way than lossy, and keep their edges): needs `cjxl`, package
libjxl-utils, only to make the files, never at install. Also needs
pycairo, numpy and Pillow.
"""
import argparse
import glob
import json
import math
import os
import random
import subprocess
import sys
import tempfile
from multiprocessing import Pool

import cairo
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
THEMES = os.path.join(REPO, 'config', 'hyprland', 'hypr', 'themes')
PICTURES = ['collines', 'pastilles', 'coucou', 'rayons', 'soleil', 'soleil-collines', 'soleil-points']
WHITE = (1.0, 1.0, 1.0)


# ── colours ─────────────────────────────────────────────────────────────

def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


def deep(c, k):
    return tuple(x * k for x in c)


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    c = min(1.0, max(0.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def oklab(c):
    r, g, b = (_lin(v) for v in c)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def from_oklab(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (_gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            _gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            _gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076926715 * s))


def shine(c):
    """The cartoon rim's rule (CartoonGloss.qml): the colour lifted one
    step, softer on a dark surface, or full white on a pale one."""
    if lum(c) >= 0.72:
        return WHITE
    d = 0.14 if lum(c) < 0.3 else 0.22
    return tuple(min(1, x + d) for x in c)


ACCENTS = ('active', 'highlight', 'success', 'info', 'warning', 'danger', 'magenta', 'cyan', 'blue')
FALLBACK = {'magenta': 'warning', 'cyan': 'active', 'blue': 'info'}


def palette(theme, mode):
    """A theme mode's colours, by the schema's names. `<accent>-fill`: the
    accent for a large shape -- a light mode darkens its accents for text
    on a pale panel, too dark for a sun, so those are lifted in OKLab."""
    m = theme['modes'][mode]
    P = {k: rgb(v) for k, v in m['surfaces'].items()}
    P.update({k: rgb(v) for k, v in m['accents'].items()})
    for k, fb in FALLBACK.items():
        P.setdefault(k, P[fb])
    P['text'] = rgb(m['text']['primary'])
    P['outline'] = rgb(m.get('outline', '#000000'))
    P['shadow'] = rgb(m.get('shadow', '#000000'))
    P['dark'] = mode == 'dark'
    for k in ACCENTS:
        c = P[k]
        if not P['dark'] and lum(c) < 0.42:
            L, a, b = oklab(c)
            c = from_oklab(max(L, 0.80), a * 1.15, b * 1.15)
        P[k + '-fill'] = c
    return P


def vivid(theme, P, k):
    """For the dithered sun's light version: a light mode's accent when it
    is bright enough, else the theme's own bright one, from its dark mode."""
    c = P[k]
    if not P['dark'] and lum(c) < 0.6:
        acc = theme['modes']['dark']['accents']
        c = rgb(acc.get(k, acc[FALLBACK.get(k, k)]))
    return c


# ── ink ─────────────────────────────────────────────────────────────────

class Ink:
    """Draws shapes the way the shell's cartoon look does."""

    def __init__(self, cr, w, h, P):
        self.cr, self.w, self.h, self.P = cr, w, h, P
        self.u = h / 1000                       # one unit: a thousandth of the height
        self.line = 5.5 * self.u
        self.drop = (7 * self.u, 7 * self.u)

    def set(self, c):
        self.cr.set_source_rgb(*c)

    def shape(self, path, fill, shadow=True, gloss=True, outline=True):
        """`path(cr)` builds the path: its hard shadow, the fill, the rim
        near the top, then the outline."""
        cr = self.cr
        if shadow:
            cr.save()
            cr.translate(*self.drop)
            path(cr)
            self.set(self.P['shadow'])
            cr.fill()
            cr.restore()
        path(cr)
        self.set(fill)
        cr.fill_preserve()
        if gloss:
            cr.save()
            cr.clip_preserve()
            _, y0, _, y1 = cr.path_extents()
            g = cairo.LinearGradient(0, y0, 0, y0 + (y1 - y0) * 0.55)
            s = shine(fill)
            g.add_color_stop_rgba(0, *s, 1)
            g.add_color_stop_rgba(1, *s, 0)
            cr.set_source(g)
            cr.translate(0, 2.2 * self.u + self.line * 0.5)
            cr.new_path()
            path(cr)
            cr.set_line_width(2.6 * self.u)
            cr.stroke()
            cr.restore()
            path(cr)
        if outline:
            self.set(self.P['outline'])
            cr.set_line_width(self.line)
            cr.set_line_join(cairo.LINE_JOIN_ROUND)
            cr.stroke()
        else:
            cr.new_path()


def rrect(x, y, w, h, r):
    def p(cr):
        rr = min(r, w / 2, h / 2)
        cr.new_sub_path()
        cr.arc(x + w - rr, y + rr, rr, -math.pi / 2, 0)
        cr.arc(x + w - rr, y + h - rr, rr, 0, math.pi / 2)
        cr.arc(x + rr, y + h - rr, rr, math.pi / 2, math.pi)
        cr.arc(x + rr, y + rr, rr, math.pi, 1.5 * math.pi)
        cr.close_path()
    return p


def circle(x, y, r):
    def p(cr):
        cr.new_sub_path()
        cr.arc(x, y, r, 0, 2 * math.pi)
        cr.close_path()
    return p


def rotated(path, cx, cy, ang):
    def p(cr):
        cr.save()
        cr.translate(cx, cy)
        cr.rotate(ang)
        cr.translate(-cx, -cy)
        path(cr)
        cr.restore()
    return p


def cloud(ink, x, y, s, fill):
    """Three bumps on a pill, outlined as one shape: every part stroked
    twice as wide in ink, then all filled over, leaves only the outer line."""
    cr = ink.cr
    parts = [circle(x - 1.0 * s, y, 0.6 * s), circle(x, y - 0.35 * s, 0.85 * s),
             circle(x + 1.05 * s, y - 0.05 * s, 0.6 * s), rrect(x - 1.55 * s, y - 0.1 * s, 3.2 * s, 0.7 * s, 0.35 * s)]

    def union(cr):
        for p in parts:
            p(cr)
    cr.save()
    cr.translate(*ink.drop)
    union(cr)
    ink.set(ink.P['shadow'])
    cr.fill()
    cr.restore()
    for p in parts:
        p(cr)
        ink.set(ink.P['outline'])
        cr.set_line_width(ink.line * 2)
        cr.stroke()
    union(cr)
    ink.set(fill)
    cr.fill()
    ink.shape(parts[1], fill, shadow=False, outline=False)


def bird(ink, x, y, r, body, beak, eye):
    """The Coucou mark (site/src/assets/coucou-*.svg): a round body, an
    eye cut out, a triangle beak."""
    k = r / 14                                  # the svg's body radius

    def bx(v):
        return x + (v - 20) * k

    def by(v):
        return y + (v - 24) * k

    def beak_path(cr):
        cr.new_sub_path()
        cr.move_to(bx(31), by(17.6))
        cr.line_to(bx(43.5), by(23))
        cr.line_to(bx(31), by(28.4))
        cr.close_path()
    ink.shape(beak_path, beak, gloss=False)
    ink.shape(circle(x, y, r), body)
    ink.shape(circle(bx(26.1), by(18.5), 2.9 * k), eye, shadow=False, gloss=False)


FOLDS = [(0.60, 0.10, 1.1, 0.4), (0.69, 0.08, 1.4, 2.1),
         (0.78, 0.07, 0.9, 4.0), (0.88, 0.05, 1.7, 1.2)]   # Plis's folds


def crest(nx, fold, lift=0.0):
    b, amp, fr, ph = fold
    return b + lift + amp * math.sin(2 * math.pi * fr * nx + ph) + 0.02 * math.sin(9 * nx + ph)


def hill(w, h, fold, lift=0.0):
    def p(cr):
        cr.new_sub_path()
        for i in range(161):
            nx = -0.02 + 1.04 * i / 160
            (cr.move_to if i == 0 else cr.line_to)(nx * w, crest(nx, fold, lift) * h)
        cr.line_to(w * 1.05, h * 1.05)
        cr.line_to(-w * 0.05, h * 1.05)
        cr.close_path()
    return p


# ── the drawn pictures ──────────────────────────────────────────────────

def collines(cr, w, h, P, theme):
    """Plis turned cartoon: hills in steps of the accent, the far ones
    fading into the sky, a sun low on the left, two clouds, and the bird on
    the far crest."""
    ink = Ink(cr, w, h, P)
    sky = P['panel']
    ink.set(sky)
    cr.paint()
    ink.shape(circle(w * 0.22, h * 0.40, h * 0.13), P['highlight-fill'])
    puff = P['card-raised'] if P['dark'] else P['card']
    cloud(ink, w * 0.62, h * 0.24, h * 0.07, puff)
    cloud(ink, w * 0.86, h * 0.38, h * 0.05, puff)
    for n, fold in enumerate(FOLDS):
        ink.shape(hill(w, h, fold), mix(P['active'], sky, (0.70, 0.48, 0.24, 0.0)[n]))
        if n == 0:
            r = h * 0.035
            bird(ink, 0.80 * w, crest(0.80, fold) * h - r * 0.92, r,
                 P['highlight-fill'], P['warning-fill'], P['panel'])


def pastilles(cr, w, h, P, theme):
    """The shell's tiles, pills, dots and toggles as stickers in every
    accent, gathered in the lower left, the rest of the screen left calm."""
    ink = Ink(cr, w, h, P)
    ink.set(P['panel'])
    cr.paint()
    rng = random.Random(7)
    colours = [P[k + '-fill'] for k in ('active', 'highlight', 'success', 'info', 'warning', 'magenta', 'cyan', 'danger')]
    off = P['card-raised'] if P['dark'] else P['card']
    placed, tries = [], 0
    while len(placed) < 20 and tries < 8000:
        tries += 1
        x, y = rng.random() * w, rng.random() * h
        d = math.hypot(x / h, y / h - 1.0)
        if d > 0.9 or rng.random() > math.exp(-(d / 0.62) ** 2):
            continue
        s = h * (0.055 + 0.06 * rng.random()) * max(0.55, 1.3 - 0.6 * d)
        if any(math.hypot(x - px, y - py) < (s + ps) * 1.05 for px, py, ps in placed):
            continue
        placed.append((x, y, s))
    for i, (x, y, s) in enumerate(placed):
        kind = rng.choice(['tile', 'pill', 'dot', 'toggle', 'tile', 'pill'])
        col = colours[i % len(colours)]
        ang = rng.uniform(-0.35, 0.35)
        if kind == 'tile':
            ink.shape(rotated(rrect(x - s, y - s * 0.75, 2 * s, 1.5 * s, s * 0.32), x, y, ang), col)
            ink.shape(circle(x - s * 0.45, y, s * 0.2), P['panel'], shadow=False, gloss=False)
        elif kind == 'pill':
            ink.shape(rotated(rrect(x - s * 1.2, y - s * 0.42, 2.4 * s, 0.84 * s, s), x, y, ang), col)
        elif kind == 'dot':
            ink.shape(circle(x, y, s * 0.62), col)
        else:
            ink.shape(rotated(rrect(x - s, y - s * 0.5, 2 * s, s, s), x, y, ang), off)
            ink.shape(circle(x + math.cos(ang) * s * 0.5, y + math.sin(ang) * s * 0.5, s * 0.36), col, shadow=False)


def coucou(cr, w, h, P, theme):
    """The Coucou bird, large, on halftone dots that thin out toward the
    empty corner."""
    ink = Ink(cr, w, h, P)
    ink.set(P['panel'])
    cr.paint()
    ink.set(mix(P['panel'], P['card-raised'] if P['dark'] else P['card-sunken'], 0.9))
    step = h * 0.022
    j, y = 0, 0.0
    while y < h + step:
        x = step / 2 if j % 2 else 0.0
        while x < w + step:
            d = math.hypot((x / w - 0.70) * w / h, y / h - 0.64)
            r = step * 0.40 * max(0.0, 1.0 - d / 0.95)
            if r > 0.4:
                cr.arc(x, y, r, 0, 2 * math.pi)
                cr.fill()
            x += step
        y += step * 0.866
        j += 1
    bird(ink, w * 0.70, h * 0.64, h * 0.22, P['active-fill'], P['highlight-fill'], P['panel'])


def rayons(cr, w, h, P, theme):
    """A comic-book sunburst from the lower left, rays in two tones of the
    panel, a ringed sun in the highlight."""
    ink = Ink(cr, w, h, P)
    ink.set(P['panel'])
    cr.paint()
    cx, cy = w * 0.18, h * 0.92
    n, R = 28, math.hypot(w, h) * 1.2
    ink.set(mix(P['panel'], P['card-raised'] if P['dark'] else P['card-sunken'], 0.45))
    for i in range(0, n, 2):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        cr.move_to(cx, cy)
        cr.line_to(cx + R * math.cos(a0), cy + R * math.sin(a0))
        cr.line_to(cx + R * math.cos(a1), cy + R * math.sin(a1))
        cr.close_path()
        cr.fill()
    ink.shape(circle(cx, cy, h * 0.30), mix(P['highlight-fill'], P['panel'], 0.55), shadow=False)
    ink.shape(circle(cx, cy, h * 0.20), P['highlight-fill'])


# ── the dithered suns ───────────────────────────────────────────────────

BAYER8 = (np.array([
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]], np.float32) + 0.5) / 64


def rings(P, theme):
    """(radius, colour) from the heart outward. The radii are those of
    GNOME's Dithered Sun, measured on its file, in heights of a 16:9 screen;
    the colours are the theme's. Light: a white heart through yellow,
    orange and pink, a pale ring, cyan, to a pale green ground. Dark: a dark
    heart through red, the highlight and magenta, a pale ring, blue and
    violet, to a deep ground."""
    if not P['dark']:
        def v(k):
            return mix(vivid(theme, P, k), P['panel'], 0.06)
        hl, wa, mg, cy, bl, ok = v('highlight'), v('warning'), v('magenta'), v('cyan'), v('blue'), v('success')
        return [(0.00, mix(hl, WHITE, 0.85)), (0.10, mix(hl, WHITE, 0.45)), (0.16, hl), (0.23, wa),
                (0.30, mix(wa, mg, 0.5)), (0.35, mg), (0.42, mix(mg, WHITE, 0.2)), (0.50, mix(mg, WHITE, 0.5)),
                (0.55, mix(mg, WHITE, 0.75)), (0.60, mix(bl, WHITE, 0.6)), (0.67, cy), (0.79, mix(cy, ok, 0.5)),
                (0.95, mix(ok, WHITE, 0.45)), (1.15, mix(ok, P['panel'], 0.6))]
    dg, hl, mg, cy, bl, tx = P['danger'], P['highlight'], P['magenta'], P['cyan'], P['blue'], P['text']
    return [(0.00, deep(dg, 0.38)), (0.08, deep(dg, 0.62)), (0.15, dg), (0.23, hl), (0.31, mg), (0.40, mg),
            (0.48, mix(mg, tx, 0.45)), (0.54, mix(tx, mg, 0.15)), (0.59, mix(cy, tx, 0.35)), (0.65, bl),
            (0.75, mix(bl, mg, 0.5)), (0.88, deep(mix(mg, P['panel'], 0.25), 0.72)),
            (1.10, deep(mix(mg, P['panel'], 0.3), 0.45))]


def sun_field(w, h, cell, stops, plateau=0.3):
    """Per cell of the grid: the ring inside it and how far toward the next
    one (0..1), with a flat stretch around each ring as in GNOME's."""
    gw, gh = math.ceil(w / cell), math.ceil(h / cell)
    yy, xx = np.mgrid[0:gh, 0:gw].astype(np.float32)
    x, y = (xx + 0.5) * cell, (yy + 0.5) * cell
    # GNOME's is a square cropped to the screen: the heart sits at 70 % of
    # that square, so a 16:9 and a 16:10 screen both show it the same way.
    S = max(w, h)
    cx, cy = w * 0.5, h * 0.5 + 0.20 * S
    r = np.sqrt(((x - cx) / 1.05) ** 2 + (y - cy) ** 2) / (S * 0.5625)
    radii = np.array([s[0] for s in stops], np.float32)
    i = np.clip(np.searchsorted(radii, r, side='right') - 1, 0, len(radii) - 2)
    f = np.clip((r - radii[i]) / (radii[i + 1] - radii[i]), 0, 1)
    f = np.clip((f - plateau / 2) / (1 - plateau), 0, 1)
    return i, f, gw, gh


def sun_cell(h):
    return max(3, round(h / 220))               # ~6.5 px on a 1440p screen, like GNOME's


def soleil_image(w, h, P, theme):
    """Ordered dithering on a grid of square cells: each cell is one ring's
    colour or the next one's, never a blend."""
    cell = sun_cell(h)
    stops = rings(P, theme)
    cols = np.array([c for _, c in stops], np.float32)
    i, f, gw, gh = sun_field(w, h, cell, stops)
    th = np.tile(BAYER8, (gh // 8 + 1, gw // 8 + 1))[:gh, :gw]
    idx = np.clip(np.where(f > th, i + 1, i), 0, len(cols) - 1)
    small = Image.fromarray(np.round(cols[idx] * 255).astype(np.uint8))
    return small.resize((gw * cell, gh * cell), Image.NEAREST).crop((0, 0, w, h))


def paint_image(cr, img):
    """Paints a PIL picture as the background of a cairo context."""
    data = bytearray(img.convert('RGBA').tobytes('raw', 'BGRA'))
    src = cairo.ImageSurface.create_for_data(data, cairo.FORMAT_RGB24, img.width, img.height, img.width * 4)
    cr.set_source_surface(src, 0, 0)
    cr.paint()


def soleil(cr, w, h, P, theme):
    paint_image(cr, soleil_image(w, h, P, theme))


def soleil_collines(cr, w, h, P, theme):
    """The dithered sun as a sky, behind three inked hills: the print in
    the distance, the ink up front."""
    paint_image(cr, soleil_image(w, h, P, theme))
    ink = Ink(cr, w, h, P)
    for n, fold in enumerate(FOLDS[1:]):
        ink.shape(hill(w, h, fold, lift=0.04), mix(P['active-fill'], P['panel'], (0.55, 0.28, 0.0)[n]))


def soleil_points(cr, w, h, P, theme):
    """The same rings in comic-print dots: each cell takes the inner ring's
    colour, with a dot of the next one that grows until the cells merge."""
    cell = sun_cell(h) * 2
    stops = rings(P, theme)
    cols = [c for _, c in stops]
    i, f, gw, gh = sun_field(w, h, cell, stops)
    for gy in range(gh):
        for gx in range(gw):
            cr.set_source_rgb(*cols[i[gy, gx]])
            cr.rectangle(gx * cell, gy * cell, cell, cell)
            cr.fill()
    for gy in range(gh):
        for gx in range(gw):
            ff = float(f[gy, gx])
            if ff > 0.02:
                cr.set_source_rgb(*cols[min(len(cols) - 1, i[gy, gx] + 1)])
                cr.arc((gx + 0.5) * cell, (gy + 0.5) * cell, cell * 0.5 * math.sqrt(ff) * 1.42, 0, 2 * math.pi)
                cr.fill()


DRAW = {'collines': collines, 'pastilles': pastilles, 'coucou': coucou, 'rayons': rayons,
        'soleil': soleil, 'soleil-collines': soleil_collines, 'soleil-points': soleil_points}


# ── files ───────────────────────────────────────────────────────────────

def render(theme, mode, picture, w, h):
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, w, h)
    DRAW[picture](cairo.Context(surf), w, h, palette(theme, mode), theme)
    surf.flush()
    return Image.frombuffer('RGB', (w, h), bytes(surf.get_data()), 'raw', 'BGRX', surf.get_stride(), 1)


def job(args):
    path, theme, mode, picture, w, h, fmt = args
    img = render(theme, mode, picture, w, h)
    if fmt == 'png':
        img.save(path, optimize=True)
    else:
        with tempfile.NamedTemporaryFile(suffix='.ppm') as tmp:
            img.save(tmp.name)
            subprocess.run(['cjxl', '-d', '0', '-e', '9', tmp.name, path], check=True, capture_output=True)
    return path


def main():
    ap = argparse.ArgumentParser(description='Draw the Ink wallpapers of every shell theme.')
    ap.add_argument('--size', default='5120x3200')
    ap.add_argument('--out', default=os.path.join(REPO, 'wallpapers', 'ink'))
    ap.add_argument('--theme-dir', default=THEMES, help='folder of theme files (default: the shell\'s own)')
    ap.add_argument('--themes', default='', help='comma-separated theme ids, e.g. nord,gruvbox (default: all)')
    ap.add_argument('--only', default='', help='comma-separated pictures, e.g. collines,soleil (default: all)')
    ap.add_argument('--format', default='jxl', choices=['jxl', 'png'])
    ap.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 2) // 2))
    args = ap.parse_args()
    w, h = (int(v) for v in args.size.split('x'))
    wanted_themes = {t for t in args.themes.split(',') if t}
    pictures = [p for p in args.only.split(',') if p] or PICTURES
    unknown = [p for p in pictures if p not in DRAW]
    if unknown:
        sys.exit(f'unknown picture: {", ".join(unknown)} (known: {", ".join(PICTURES)})')
    os.makedirs(args.out, exist_ok=True)

    jobs = []
    files = sorted(glob.glob(os.path.join(os.path.expanduser(args.theme_dir), '*.json')))
    if not files:
        sys.exit(f'no theme in {args.theme_dir}')
    for f in files:
        tid = os.path.splitext(os.path.basename(f))[0]
        if wanted_themes and tid not in wanted_themes:
            continue
        theme = json.load(open(f))
        for picture in pictures:
            for mode in ('light', 'dark'):
                name = f'ink-{tid}-{picture}' + ('-dark' if mode == 'dark' else '')
                jobs.append((os.path.join(args.out, f'{name}.{args.format}'), theme, mode, picture, w, h, args.format))
    with Pool(args.jobs) as pool:
        for path in pool.imap_unordered(job, jobs):
            print(path)


if __name__ == '__main__':
    main()
