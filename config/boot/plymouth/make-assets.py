#!/usr/bin/env python3
"""make-assets.py -- regenerate the PNGs coucou.script draws.

Why a generator and committed PNGs, rather than either alone:

Plymouth's script plugin cannot draw a shape or a glyph. Everything on
screen is a PNG loaded from the theme directory -- so the word mark, the
progress track, the progress fill and the password bullets all have to
exist as files. Committing them alone would mean the typography (MiSans
Latin, the desktop's UI font, see config/fonts/) lives nowhere in the
repo; committing only the generator would mean a fresh install has to
have MiSans already on disk before the boot splash can be built, which
inverts the module order for no gain. So: this script owns the design,
the PNGs it produces are committed next to it, and it is re-run by hand
whenever the wording, the weight or the geometry changes.

    ./config/boot/plymouth/make-assets.py            # rewrite theme/*.png
    ./config/boot/plymouth/make-assets.py --word-only --word byebye --name logo-bye

Everything here is sized for a 1920-wide panel (REF_WIDTH in
coucou.script). On any other width the script scales at runtime, and
Plymouth's scaler is crude, so a machine with a different panel is
better served by re-running this with --width.
"""

import argparse
import pathlib
import subprocess

from PIL import Image, ImageDraw, ImageFont

# Supersampling factor. Plymouth gets a flat PNG; every curve here
# (the round bar caps, the bullets, the letterforms) is drawn at 4x and
# box-filtered down, which is the only antialiasing we get.
SS = 4

# JetBrains Mono, and from the system packages rather than from
# ~/.local/share/fonts: the same family the status line asks for at boot
# (see mono-fontconfig.conf) and the one the console greeter is matched
# to. A word mark in the desktop's proportional UI font would be the odd
# one out on a screen whose other two lines are monospaced.
FONT_FAMILY = "JetBrains Mono"
# Light rather than Regular: the logo pulses down to 35% opacity, and a
# heavier weight reads as a grey slab at the bottom of that curve, where
# Light keeps a drawn line. Thin breaks up entirely down there.
FONT_STYLE = "Light"

# The boot word. The farewell used on shutdown and reboot is generated
# separately, with --word/--name: saying "coucou" on the way out reads
# backwards, and Plymouth.GetMode() is what lets the theme pick.
WORD = "coucou"
# No tracking. The proportional cut needed 0.06em to stop "coucou" reading
# as running text; a monospaced face already carries that rhythm in its
# advance widths, and adding more on top makes it read as a countdown.
WORD_SIZE = 72
WORD_TRACKING = 0.0

# The macOS-style rule: one thin rounded bar, nothing else. 4px tall on a
# 1920 panel is the thinnest that still survives Plymouth's scaler.
BAR_W, BAR_H = 420, 4
TRACK_GREY = 48          # #303030 -- reads as ~19% white on a black panel

BULLET_D = 10            # password bullets, drawn as dots (see below)

OUT = pathlib.Path(__file__).resolve().parent / "theme"


def alpha_image(mask, color):
    """An RGBA image of one flat colour, shaped by a greyscale mask."""
    img = Image.new("RGBA", mask.size, color + (0,))
    img.putalpha(mask)
    return img


def font_file(family, style):
    """The exact face, via fontconfig rather than a hardcoded path.

    fc-match answers with its nearest match and never fails, so a missing
    family comes back as some other font rather than as an error -- which
    would silently ship a word mark in the wrong typeface. Hence the
    check on what came back.
    """
    try:
        out = subprocess.run(
            ["fc-match", "-f", "%{family[0]}\t%{file}", f"{family}:style={style}"],
            capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise SystemExit(f"fc-match failed: {exc}")

    got, _, path = out.partition("\t")
    if got.strip().lower() != family.lower():
        raise SystemExit(
            f"fontconfig has no '{family}' -- it answered '{got.strip()}'. "
            "Install it (jetbrains-mono-fonts on Fedora) and try again; "
            "config/boot/plymouth/install.sh does that for you."
        )
    return path.strip()


def render_word(size, tracking, text=WORD):
    """The word mark, letter by letter so the tracking is ours, not the font's."""
    font = ImageFont.truetype(font_file(FONT_FAMILY, FONT_STYLE), size * SS)
    space = int(size * SS * tracking)
    width = int(sum(font.getlength(c) for c in text) + space * (len(text) - 1))
    ascent, descent = font.getmetrics()

    mask = Image.new("L", (width + 2 * SS, ascent + descent), 0)
    draw = ImageDraw.Draw(mask)
    x = SS
    for char in text:
        draw.text((x, 0), char, font=font, fill=255)
        x += font.getlength(char) + space

    # Crop to the ink before downscaling: coucou.script centres the sprite
    # on its own box, so carrying the font's ascent and line gap around
    # would push the word off-centre by a few pixels.
    mask = mask.crop(mask.getbbox())
    return mask.resize((mask.width // SS, mask.height // SS), Image.LANCZOS)


def render_bar(w, h):
    mask = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, w * SS - 1, h * SS - 1], radius=(h * SS) // 2, fill=255
    )
    return mask.resize((w, h), Image.LANCZOS)


def render_dot(d):
    mask = Image.new("L", (d * SS, d * SS), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, d * SS - 1, d * SS - 1], fill=255)
    return mask.resize((d, d), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--width", type=int, default=1920,
        help="panel width to size the assets for (default: 1920, the reference)",
    )
    ap.add_argument("--word", default=WORD,
                    help="the word mark to render (default: %(default)s)")
    ap.add_argument("--name", default="logo",
                    help="basename for the word mark PNG (default: %(default)s). "
                         "Use --word byebye --name logo-bye for the farewell, "
                         "which coucou.script picks on shutdown and reboot.")
    ap.add_argument("--word-only", action="store_true",
                    help="only regenerate the word mark, leaving the bar and "
                         "bullets alone")
    args = ap.parse_args()
    k = args.width / 1920

    OUT.mkdir(parents=True, exist_ok=True)
    white = (255, 255, 255)

    word = render_word(max(8, round(WORD_SIZE * k)), WORD_TRACKING, args.word)
    alpha_image(word, white).save(OUT / f"{args.name}.png")

    if args.word_only:
        with Image.open(OUT / f"{args.name}.png") as im:
            print(f"  {args.name}.png     {im.width}x{im.height}  ({args.word!r})")
        return

    bar_w, bar_h = max(40, round(BAR_W * k)), max(2, round(BAR_H * k))
    bar = render_bar(bar_w, bar_h)
    alpha_image(bar, (TRACK_GREY,) * 3).save(OUT / "bar-track.png")
    alpha_image(bar, white).save(OUT / "bar-fill.png")

    dot = render_dot(max(4, round(BULLET_D * k)))
    alpha_image(dot, white).save(OUT / "bullet.png")

    for f in sorted(OUT.glob("*.png")):
        with Image.open(f) as im:
            print(f"  {f.name:<14} {im.width}x{im.height}")


if __name__ == "__main__":
    main()
