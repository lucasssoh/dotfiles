#!/usr/bin/env python3
"""The coucou wallpapers: one cream light rising from the lower left, on
three surfaces (folds, draped silk, contour lines), each in a light and a
dark version -- `coucou-aube-relief.jxl` and `coucou-aube-relief-dark.jxl`,
the pair that follows the desktop's light/dark mode.

    python3 wallpapers/coucou/make.py [--size 5120x3200] [--out wallpapers] [--format jxl|png|jpg]

JPEG XL by default (needs `cjxl`, package libjxl-utils: only to make the
files, never at install): Plis and Soie at distance 1.0, Relief at 0.5 --
its fine lines are the detail a lossy encoder would soften, and it is the
default wallpaper, the one screenshots show.

Deterministic: the same size always gives the same images. Rendered at
5120x3200 (16:10) by default, large enough to be fitted down to any screen
up to 5K. Every length is relative to the image height, so a different size
gives the same picture.
"""
import argparse
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image

INK = np.array([11, 11, 12], np.float32)
CREAM = np.array([233, 220, 195], np.float32)

# The light versions: a sand ground that dims toward the far corner, the
# same light turned warm, and the lines drawn in a gilded brown.
DUSK = np.array([212, 207, 199], np.float32)
DAWN = np.array([243, 236, 222], np.float32)
SUN = np.array([250, 238, 212], np.float32)
TAN = np.array([150, 128, 96], np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--size', default='5120x3200')
    ap.add_argument('--out', default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument('--format', default='jxl', choices=['jxl', 'png', 'jpg'])
    args = ap.parse_args()
    w, h = (int(v) for v in args.size.split('x'))

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = xx / w, yy / h
    aspect = w / h
    px_scale = h / 2400                       # the look was tuned at 2400 px tall

    def light(r=0.80):
        d = np.sqrt(((nx - 0.12) * aspect) ** 2 + (ny - 1.05) ** 2)
        return np.exp(-(d / r) ** 2)

    def grain(img, seed, sigma=2.0):
        noise = np.random.default_rng(seed).normal(0, sigma, (h, w)).astype(np.float32)
        return img + noise[..., None]

    distance = {'coucou-aube-relief': '0.5', 'coucou-aube-relief-dark': '0.5'}   # others: 1.0

    def save(img, name):
        im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB')
        path = os.path.join(args.out, f'{name}.{args.format}')
        if args.format == 'jpg':
            im.save(path, quality=95, subsampling=0, optimize=True)
        elif args.format == 'png':
            im.save(path, optimize=True)
        else:
            with tempfile.NamedTemporaryFile(suffix='.png') as tmp:
                im.save(tmp.name)
                subprocess.run(['cjxl', '-d', distance.get(name, '1.0'), '-e', '7', tmp.name, path],
                               check=True, capture_output=True)
        print(path)

    L = light()[..., None]
    ground = DUSK + (DAWN - DUSK) * light(1.25)[..., None]

    # ── Plis: soft folds, their rims lit near the light ─────────────────
    folds = [(0.60, 0.10, 1.1, 0.4, 16), (0.69, 0.08, 1.4, 2.1, 22),
             (0.78, 0.07, 0.9, 4.0, 28), (0.88, 0.05, 1.7, 1.2, 36)]
    dark, lite = np.broadcast_to(INK, (h, w, 3)).copy(), ground.copy()
    for n, (base, amp, freq, phase, shade) in enumerate(folds):
        edge = base + amp * np.sin(2 * np.pi * freq * nx + phase) + 0.02 * np.sin(9 * nx + phase)
        below = (ny > edge)[..., None]
        depth = np.clip((ny - edge) / 0.30, 0, 1)[..., None]
        rim = np.exp(-((ny - edge) * h / (2.6 * px_scale)) ** 2)[..., None]
        # dark: each fold a little lighter, brightest under its rim
        fill = (shade + 14 * (1 - depth) ** 2) * np.array([1.0, 0.99, 0.97], np.float32)
        dark = np.where(below, fill, dark)
        a = rim * (0.12 + 0.55 * L)
        dark = dark * (1 - a) + CREAM * a
        # light: each fold a little deeper, with a soft shadow under its rim
        fill = (ground - 6 * (n + 1) - 14 * np.exp(-depth * 9) + 6 * depth) * np.array([1.0, 0.995, 0.985], np.float32)
        lite = np.where(below, fill, lite)
        a = rim * (0.18 + 0.50 * L)
        lite = lite * (1 - a) + TAN * a
    dark = dark * (1 - 0.30 * L) + CREAM * 0.30 * L
    lite = lite * (1 - 0.30 * L) + SUN * 0.30 * L
    save(grain(lite, 1, 1.6), 'coucou-aube-plis')
    save(grain(dark, 1), 'coucou-aube-plis-dark')

    # ── Soie: long diagonal drapery folds, shaded, satin on the crests ──
    lx, ly = nx * aspect, ny
    ang = np.deg2rad(-28)
    along = lx * np.cos(ang) + ly * np.sin(ang)
    across = -lx * np.sin(ang) + ly * np.cos(ang)
    warp = 0.10 * np.sin(2.1 * along * np.pi + 0.7) + 0.05 * np.sin(4.3 * along * np.pi + 2.0)
    u = (across + warp) * 5.2
    f = np.sin(u * np.pi) * (0.6 + 0.4 * np.sin(1.3 * along * np.pi + 0.3)) + 0.25 * np.sin(u * 2.3 * np.pi + 1.1)
    gy, gx = np.gradient(f)
    k = 260.0 * px_scale                      # same relief at any size
    nrm = np.stack([-gx * k, -gy * k, np.ones_like(f)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    ldir = np.array([-0.6, 0.45, 0.66], np.float32)
    ldir /= np.linalg.norm(ldir)
    half = ldir + np.array([0, 0, 1], np.float32)
    half /= np.linalg.norm(half)
    diffuse = np.clip(nrm @ ldir, 0, 1)
    sheen = np.clip(nrm @ half, 0, 1) ** 60
    Ls = np.exp(-(np.sqrt(((nx - 0.12) * aspect) ** 2 + (ny - 1.05) ** 2) / 0.85) ** 2)
    lum = (0.06 + 0.60 * diffuse ** 1.6) * (0.18 + 0.82 * Ls) + 0.55 * sheen * Ls
    img = INK + (CREAM - INK) * np.clip(lum, 0, 1)[..., None] * 0.62
    save(grain(img, 5), 'coucou-aube-soie-dark')
    # light: unbleached linen, greige in the hollows, near white on the crests
    shadow, high = np.array([176, 169, 158], np.float32), np.array([250, 245, 234], np.float32)
    lum = (0.22 + 0.62 * diffuse ** 1.4) * (0.55 + 0.45 * Ls) + 0.35 * sheen * Ls
    img = shadow + (high - shadow) * np.clip(lum, 0, 1)[..., None]
    img = img * (1 - 0.38 * Ls[..., None]) + SUN * 0.38 * Ls[..., None]
    save(grain(img, 5, 1.6), 'coucou-aube-soie')

    # ── Relief: contour lines that light up in the glow ─────────────────
    rng = np.random.default_rng(23)
    f = np.zeros((h, w), np.float32)
    for _ in range(6):
        a, kk, ph = rng.uniform(0, np.pi), rng.uniform(0.6, 1.6) * 1.2, rng.uniform(0, 2 * np.pi)
        f += (1 / kk) * np.sin(kk * (np.cos(a) * lx + np.sin(a) * ly) * 2 * np.pi + ph)
    f /= np.abs(f).max()
    t = f * 34
    frac = np.abs(t - np.round(t))
    gy, gx = np.gradient(t)
    width = np.sqrt(gx ** 2 + gy ** 2) * 0.9 * px_scale + 1e-6
    line = np.clip(1 - frac / width, 0, 1)
    img = INK + (np.array([30, 29, 27], np.float32) - INK) * (0.5 + 0.5 * f[..., None]) * 0.5
    img = img * (1 - 0.35 * L) + CREAM * 0.35 * L
    glow = (0.10 + 0.75 * L[..., 0]) * line
    img = img * (1 - glow[..., None]) + CREAM * glow[..., None]
    save(grain(img, 3), 'coucou-aube-relief-dark')
    # light: brown lines on cream paper, darker in the glow
    img = ground - np.array([7, 7, 8], np.float32) * (0.5 + 0.5 * f[..., None])
    ink = (0.16 + 0.55 * L[..., 0]) * line
    img = img * (1 - ink[..., None]) + TAN * ink[..., None]
    save(grain(img, 3, 1.6), 'coucou-aube-relief')


if __name__ == '__main__':
    main()
