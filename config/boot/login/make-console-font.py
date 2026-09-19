#!/usr/bin/env python3
"""make-console-font.py -- JetBrains Mono, as a Linux console font.

The greeter runs on VT1, and a VT does not render with fontconfig: it
draws from a PSF bitmap font handed to the kernel by setfont. So "the same
typeface as the boot splash" needs the outlines rasterised, once, into
fixed cells.

Written against the PSF2 format directly rather than piped through
otf2bdf | bdf2psf. Those exist and are packaged, but they are two
conversions and two chances to lose control of the one decision that
decides whether a 1-bit rasterisation is legible: where the threshold
sits. Here it is a flag, and `--preview` renders the result back to a PNG
so the answer is looked at rather than assumed.

    ./make-console-font.py                 # write console/<name>.psfu
    ./make-console-font.py --preview out.png
    ./make-console-font.py --threshold 110 --size 24

PSF2 is a 32-byte header, then one bitmap per glyph, then a table mapping
each glyph to the Unicode it covers:

    magic 72 b5 4a 86 | version | headersize | flags
    length | charsize | height | width

Cell is 16x32. The kernel accepts up to 32x32 and up to 512 glyphs; this
uses ~370, which leaves the 512-glyph mode and therefore the full
box-drawing range that tuigreet's border needs.
"""

import argparse
import pathlib
import struct
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

# The cell, in pixels. 2:1 is the ratio a 0.6em-advance monospace wants
# once its full line height is allowed for. The kernel accepts up to
# 32x32; Terminus ships 12x24, 14x28 and 16x32 at these proportions, which
# is the evidence that non-multiple-of-8 widths are fine for fbcon.
# On a 1920x1200 panel: 8x16 gives 240x75 cells, 10x20 gives 192x60,
# 12x24 gives 160x50, 14x28 gives 137x42, 16x32 gives 120x37. 8x16 is the
# size a Linux console has always been, which is what 'normal' means here.
CELL_W, CELL_H = 8, 16
FAMILY, STYLE = "JetBrains Mono", "Regular"
OUT = pathlib.Path(__file__).resolve().parent / "console"

PSF2_MAGIC = b"\x72\xb5\x4a\x86"
PSF2_HAS_UNICODE = 0x01


# ---------------------------------------------------------------------
# Line drawing, synthesised rather than rasterised.
#
# JetBrains Mono's own box-drawing glyphs cannot be used here, and the
# measurement says why. At 24px its advance is 14.4 and its line height
# 33, but U+2502 draws 37 rows of ink and U+2500 draws 16 columns: the box
# glyphs deliberately overhang, so they tile on a cell of roughly
# 0.6em x 1.54em -- a 2.57 aspect ratio. A 16-wide cell would need 41
# rows to match, and the kernel accepts at most 32. There is no legal cell
# where those glyphs join, so rasterising them produces exactly what a
# first attempt produced: a border in disconnected fragments.
#
# Drawing them instead is what real console fonts do, and it is strictly
# better here: the arms land on the cell edges by construction, so they
# join perfectly at any size.
#
# Arms are (up, right, down, left), each 0 none / 1 light / 2 heavy.
# ---------------------------------------------------------------------
LIGHT, HEAVY = 1, 2
ARMS = {
    0x2500: (0, 1, 0, 1), 0x2502: (1, 0, 1, 0),
    0x250C: (0, 1, 1, 0), 0x2510: (0, 0, 1, 1),
    0x2514: (1, 1, 0, 0), 0x2518: (1, 0, 0, 1),
    0x251C: (1, 1, 1, 0), 0x2524: (1, 0, 1, 1),
    0x252C: (0, 1, 1, 1), 0x2534: (1, 1, 0, 1),
    0x253C: (1, 1, 1, 1),
    0x2501: (0, 2, 0, 2), 0x2503: (2, 0, 2, 0),
    0x250F: (0, 2, 2, 0), 0x2513: (0, 0, 2, 2),
    0x2517: (2, 2, 0, 0), 0x251B: (2, 0, 0, 2),
    0x2523: (2, 2, 2, 0), 0x252B: (2, 0, 2, 2),
    0x2533: (0, 2, 2, 2), 0x253B: (2, 2, 0, 2),
    0x254B: (2, 2, 2, 2),
}
# Rounded corners: same arms, drawn with a quarter arc at the join.
ROUNDED = {0x256D: (0, 1, 1, 0), 0x256E: (0, 0, 1, 1),
           0x256F: (1, 0, 0, 1), 0x2570: (1, 1, 0, 0)}

# Block elements, as fractions of the cell. Shades are dither patterns.
BLOCKS = {0x2580: ("top", 0.5), 0x2584: ("bottom", 0.5), 0x2588: ("full", 1.0),
          0x258C: ("left", 0.5), 0x2590: ("right", 0.5),
          0x2591: ("shade", 0.25), 0x2592: ("shade", 0.5), 0x2593: ("shade", 0.75)}


def stroke(weight):
    """Light is 2px in a 16-wide cell, heavy is 4. Both even, so a stroke
    centred on the cell's midpoint stays symmetric and two cells side by
    side line up."""
    return 2 if weight == LIGHT else 4


def draw_arms(arms, rounded=False):
    img = Image.new("L", (CELL_W, CELL_H), 0)
    d = ImageDraw.Draw(img)
    cx, cy = CELL_W // 2, CELL_H // 2
    up, right, down, left = arms

    if rounded:
        # One quarter arc joining the two arms. The radius has to leave a
        # stub of straight arm on each side, or the arc runs past the cell
        # edge and the corner stops meeting its neighbours.
        r = min(CELL_W, CELL_H) // 2 - 2
        w = stroke(LIGHT)
        box = {
            (0, 1, 1, 0): (cx, cy, cx + 2 * r, cy + 2 * r, 180, 270),
            (0, 0, 1, 1): (cx - 2 * r, cy, cx, cy + 2 * r, 270, 360),
            (1, 0, 0, 1): (cx - 2 * r, cy - 2 * r, cx, cy, 0, 90),
            (1, 1, 0, 0): (cx, cy - 2 * r, cx + 2 * r, cy, 90, 180),
        }[arms]
        d.arc(box[:4], box[4], box[5], fill=255, width=w)
        if up:    d.rectangle([cx - w // 2, 0, cx + w // 2 - 1, cy - r], fill=255)
        if down:  d.rectangle([cx - w // 2, cy + r, cx + w // 2 - 1, CELL_H - 1], fill=255)
        if left:  d.rectangle([0, cy - w // 2, cx - r, cy + w // 2 - 1], fill=255)
        if right: d.rectangle([cx + r, cy - w // 2, CELL_W - 1, cy + w // 2 - 1], fill=255)
        return img

    # Each arm runs from the cell edge to the far side of the centre, so
    # opposite arms of different weights still overlap cleanly.
    for weight, rect in (
        (up,    lambda w: [cx - w // 2, 0, cx + w // 2 - 1, cy + w // 2 - 1]),
        (down,  lambda w: [cx - w // 2, cy - w // 2, cx + w // 2 - 1, CELL_H - 1]),
        (left,  lambda w: [0, cy - w // 2, cx + w // 2 - 1, cy + w // 2 - 1]),
        (right, lambda w: [cx - w // 2, cy - w // 2, CELL_W - 1, cy + w // 2 - 1]),
    ):
        if weight:
            d.rectangle(rect(stroke(weight)), fill=255)
    return img


def draw_block(kind, amount):
    img = Image.new("L", (CELL_W, CELL_H), 0)
    d = ImageDraw.Draw(img)
    if kind == "full":
        d.rectangle([0, 0, CELL_W - 1, CELL_H - 1], fill=255)
    elif kind == "top":
        d.rectangle([0, 0, CELL_W - 1, int(CELL_H * amount) - 1], fill=255)
    elif kind == "bottom":
        d.rectangle([0, CELL_H - int(CELL_H * amount), CELL_W - 1, CELL_H - 1], fill=255)
    elif kind == "left":
        d.rectangle([0, 0, int(CELL_W * amount) - 1, CELL_H - 1], fill=255)
    elif kind == "right":
        d.rectangle([CELL_W - int(CELL_W * amount), 0, CELL_W - 1, CELL_H - 1], fill=255)
    elif kind == "shade":
        # An ordered 4x4 dither, so the three shades are visibly distinct
        # and stay stable when tiled across a run of cells.
        matrix = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        px = img.load()
        for y in range(CELL_H):
            for x in range(CELL_W):
                if matrix[y % 4][x % 4] < amount * 16:
                    px[x, y] = 255
    return img


def glyph_plan():
    """One entry per glyph slot: the codepoint it draws, or None for blank.

    THE INDEX IS THE CONTRACT for the first 256 slots, and getting that
    wrong produced the most confusing screen of this whole module: a
    greeter whose background was a solid field of "@".

    The console's screen buffer stores GLYPH INDICES, not characters. Text
    painted before a font swap keeps its indices and is re-rendered with
    the new font. tuigreet had painted its background with spaces under
    the kernel's built-in font, where space is glyph 32; this font's
    glyph 32 was "@", because ASCII started at index 0 here
    (chars[32] = 0x20 + 32 = 0x40). Every space on screen turned into an
    at-sign.

    Fedora's own fonts do not have this problem: latarcyrheb-sun32 maps
    glyph 32 to U+0020, glyph 65 to U+0041, glyph 97 to U+0061. Identity
    for Latin-1, extras above. That is the convention, and it exists
    exactly so a direct index lands on the right character.

    So: slots 0..255 draw codepoint == index, and everything else goes
    above 255. Control ranges stay blank with no Unicode entry, so
    nothing can map onto them. That pushes the count past 256 and up to
    512, which is the other legal size; the cost is that 512-glyph mode
    spends the intensity bit on glyph selection, leaving eight background
    colours. The greeter draws named ANSI colours on black, so it never
    notices.
    """
    plan = [None] * 256
    for cp in list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)):
        plan[cp] = cp

    plan += sorted(ARMS) + sorted(ROUNDED) + sorted(BLOCKS)
    plan += [0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026,
             0x20AC, 0x2190, 0x2191, 0x2192, 0x2193, 0x25CF, 0x2713]
    # Deliberately NOT the whole U+2500 block. The dashed and double-line
    # variants would each need their own construction, nothing on this
    # machine draws with them (ratatui's four border styles are the light,
    # heavy and rounded sets above), and a glyph that is absent shows as
    # the kernel's fallback -- which is honest -- where a glyph built
    # wrong shows as a border that almost lines up.

    if len(plan) > 512:
        raise SystemExit(f"{len(plan)} glyphs: over the 512 the console allows")
    return plan + [None] * ((256 if len(plan) <= 256 else 512) - len(plan))


def font_file(family, style):
    """fc-match answers with its nearest match and never fails, so what
    came back is checked: a missing family would otherwise be rasterised
    silently in some other typeface."""
    out = subprocess.run(
        ["fc-match", "-f", "%{family[0]}\t%{file}", f"{family}:style={style}"],
        capture_output=True, text=True, check=True).stdout
    got, _, path = out.partition("\t")
    if got.strip().lower() != family.lower():
        raise SystemExit(
            f"fontconfig has no '{family}' -- it answered '{got.strip()}'. "
            "Install jetbrains-mono-fonts and try again."
        )
    return path.strip()


def render(face, cp, size, threshold, baseline):
    """One glyph, thresholded to 1 bit, centred in the cell."""
    img = Image.new("L", (CELL_W, CELL_H), 0)
    draw = ImageDraw.Draw(img)
    ch = chr(cp)
    advance = draw.textlength(ch, font=face)
    # Horizontal centring on the advance rather than on the ink: a
    # monospaced face is a rhythm, and centring each glyph on its own ink
    # would destroy the alignment of columns of text.
    x = (CELL_W - advance) / 2
    draw.text((x, baseline), ch, font=face, fill=255, anchor="ls")
    return img.point(lambda v: 255 if v >= threshold else 0, mode="1")


def pack(img):
    """A glyph as PSF2 bitmap rows: ceil(width/8) bytes per row, MSB first."""
    stride = (CELL_W + 7) // 8
    out = bytearray(stride * CELL_H)
    px = img.load()
    for y in range(CELL_H):
        for x in range(CELL_W):
            if px[x, y]:
                out[y * stride + (x >> 3)] |= 0x80 >> (x & 7)
    return bytes(out)


def build(size, threshold, baseline):
    face = ImageFont.truetype(font_file(FAMILY, STYLE), size)
    plan = glyph_plan()
    blank = bytes(((CELL_W + 7) // 8) * CELL_H)
    glyphs, table = [], bytearray()

    for cp in plan:
        if cp is None:
            glyphs.append(blank)
            table += b"\xff"                  # mapped to nothing
            continue
        if cp in ARMS:
            bitmap = draw_arms(ARMS[cp])
        elif cp in ROUNDED:
            bitmap = draw_arms(ROUNDED[cp], rounded=True)
        elif cp in BLOCKS:
            bitmap = draw_block(*BLOCKS[cp])
        else:
            glyphs.append(pack(render(face, cp, size, threshold, baseline)))
            table += chr(cp).encode("utf-8") + b"\xff"
            continue
        # The drawn glyphs are already black and white; thresholding at 1
        # keeps the arc's antialiased edge from being thrown away.
        glyphs.append(pack(bitmap.point(lambda v: 255 if v >= 1 else 0, mode="1")))
        table += chr(cp).encode("utf-8") + b"\xff"

    stride = (CELL_W + 7) // 8
    header = PSF2_MAGIC + struct.pack(
        "<7I", 0, 32, PSF2_HAS_UNICODE, len(glyphs), stride * CELL_H, CELL_H, CELL_W)
    return header + b"".join(glyphs) + bytes(table), plan


def preview(blob, chars, path, sample):
    """Read the PSF back and draw a sample line from its own bitmaps.

    Deliberately parsed from the produced bytes rather than from the PIL
    images still in memory: this is the only check that the packing, the
    header and the glyph order are right, rather than just the rendering.
    """
    length, charsize, height, width = struct.unpack("<4I", blob[16:32])
    stride = (width + 7) // 8
    index = {cp: i for i, cp in enumerate(chars) if cp is not None}

    # Multi-line, because a single row cannot show whether a border joins.
    # Horizontal continuity is obvious from one line; vertical continuity
    # across the cell boundary is the half that actually breaks, and it
    # only shows when two rows sit on top of each other.
    lines = sample.split("\n")
    cols = max(len(l) for l in lines)
    scale = 2
    img = Image.new("RGB", (cols * width * scale, len(lines) * height * scale), (0, 0, 0))
    px = img.load()
    for row, line in enumerate(lines):
        for n, ch in enumerate(line):
            i = index.get(ord(ch))
            if i is None:
                continue
            glyph = blob[32 + i * charsize: 32 + (i + 1) * charsize]
            for y in range(height):
                for x in range(width):
                    if glyph[y * stride + (x >> 3)] & (0x80 >> (x & 7)):
                        gx, gy = (n * width + x) * scale, (row * height + y) * scale
                        for dy in range(scale):
                            for dx in range(scale):
                                px[gx + dx, gy + dy] = (230, 230, 235)
    img.save(path)


def main():
    global CELL_W, CELL_H

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cell", metavar="WxH",
                    help=f"cell size in pixels (default: {CELL_W}x{CELL_H}). "
                         "The output filename follows it, so vconsole.conf's "
                         "FONT= has to follow too.")
    ap.add_argument("--size", type=int, default=0,
                    help="pixel size to rasterise at (default: derived from the cell)")
    ap.add_argument("--threshold", type=int, default=128,
                    help="grey level above which a pixel is set (default: 128)")
    ap.add_argument("--baseline", type=int, default=0,
                    help="baseline row inside the cell (default: 78%% of its height)")
    ap.add_argument("--preview", metavar="PNG",
                    help="also render a sample line back from the PSF")
    ap.add_argument("--sample", default="coucou — lucas ┌─┐│└┘ éèàçù 0O1lI")
    args = ap.parse_args()

    if args.cell:
        CELL_W, CELL_H = (int(v) for v in args.cell.lower().split("x"))
        if CELL_W > 32 or CELL_H > 32:
            raise SystemExit("the console accepts at most 32x32")
    # Derived rather than fixed: the largest rasterisation whose ascent and
    # descent still fit the cell. JetBrains Mono's line height is about
    # 1.32em, so the cell height divided by that is the size that fills it.
    size = args.size or max(8, round(CELL_H / 1.32))
    baseline = args.baseline or round(CELL_H * 0.78)

    blob, chars = build(size, args.threshold, baseline)
    mapped = sum(1 for c in chars if c is not None)
    OUT.mkdir(parents=True, exist_ok=True)
    name = OUT / f"jetbrains-mono-{CELL_W}x{CELL_H}.psfu"
    name.write_bytes(blob)
    import struct as _s
    total = _s.unpack("<I", blob[16:20])[0]
    print(f"  {name.name}  {mapped} mapped + {total - mapped} blank "
          f"= {total} glyphs, {CELL_W}x{CELL_H}, {len(blob)} bytes")

    if args.preview:
        preview(blob, chars, args.preview, args.sample)
        print(f"  preview: {args.preview}")


if __name__ == "__main__":
    main()
