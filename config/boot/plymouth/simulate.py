#!/usr/bin/env python3
"""simulate.py -- watch the splash's motion without a console, a reboot or
a VT switch.

preview.sh is the honest check: the real daemon, the real DRM renderer, a
real console. It costs the screen for its whole duration, which makes it a
poor way to answer "is the pulse too fast?" twenty times in a row. This
renders the same motion to a video instead.

What it simulates is coucou.script's ARITHMETIC, not Plymouth. The frames
are composited from the same PNGs, and every constant is read out of
coucou.script rather than copied here -- a simulator carrying its own copy
of PULSE_PERIOD would start lying the first time the theme was tuned. What
it cannot reproduce is Plymouth's own scaler, its refresh timing under
load, and how the panel actually renders near-black. For those, use
preview.sh.

    ./simulate.py                 14s of boot, opened full screen in mpv
    ./simulate.py --seconds 25 --boot-duration 20
    ./simulate.py --width 3840 --height 2160        a 4K panel
    ./simulate.py --heads 1920x1200,3840x2160       docked: what each screen shows
    ./simulate.py --no-open       just write the file

The progress model is Plymouth's: elapsed / previous-boot-duration, capped
at BAR_CEILING, then the same easing coucou.script applies. Past the boot
duration the simulation runs on_quit(), so the last second shows the frame
that stays on screen until the greeter takes over.
"""

import argparse
import math
import os
import pathlib
import random
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
THEME = HERE / "theme"
SCRIPT = THEME / "coucou.script"

# Only the bare `NAME = number;` assignments at the top of the theme, which
# is exactly the block coucou.script documents as "everything you would
# want to nudge".
CONST_RE = re.compile(r"^([A-Z_]+)\s*=\s*([0-9.]+)\s*;", re.MULTILINE)
FONT_RE = re.compile(
    r'^(STATUS_FONT(?:_XS|_M|_L)?)\s*=\s*"[^"]*?\s*([0-9]+)"\s*;', re.MULTILINE)

# What the boot log would say. Invented, but in the shape the feed really
# produces: systemd unit names, newest running job first, with the two
# messages Plymouth itself sends around switch-root at the front -- those
# are the only real ones, and they are the only thing on screen before
# coucou-splash-status.service can exist.
FAKE_UNITS = [
    "plymouth-switch-root.service",
    "systemd-journald.service",
    "systemd-udevd.service",
    "systemd-udev-trigger.service",
    "sysroot.mount",
    "systemd-remount-fs.service",
    "systemd-tmpfiles-setup.service",
    "dbus-broker.service",
    "systemd-logind.service",
    "NetworkManager.service",
    "firewalld.service",
    "bluetooth.service",
    "polkit.service",
    "upower.service",
    "user@1000.service",
    "greetd.service",
    "graphical.target",
]


def constants():
    text = SCRIPT.read_text()
    found = {k: float(v) for k, v in CONST_RE.findall(text)}
    found.update({k: float(v) for k, v in FONT_RE.findall(text)})
    missing = {
        "REF_WIDTH", "LOGO_CENTRE", "BAR_CENTRE", "PULSE_PERIOD",
        "PULSE_FLOOR", "BAR_EASE", "BAR_CEILING", "FPS",
        "STATUS_Y", "STATUS_FADE",
        "STATUS_FONT", "STATUS_FONT_XS", "STATUS_FONT_M", "STATUS_FONT_L",
        "STATUS_K_XS", "STATUS_K_M", "STATUS_K_L",
    } - found.keys()
    if missing:
        raise SystemExit(f"{SCRIPT.name}: cannot read {', '.join(sorted(missing))}")
    return found


def even(value):
    """yuv420p needs both dimensions even."""
    return int(value) // 2 * 2


def parse_heads(spec):
    heads = []
    for part in spec.split(","):
        w, _, h = part.strip().lower().partition("x")
        heads.append((int(w), int(h)))
    return heads


def geometry(c, heads):
    """measure_screen(), in Python.

    Plymouth composites every sprite onto one virtual canvas as wide as
    the widest display and as tall as the tallest, with each display
    centred inside it (update_displays(), script-lib-sprite.c). So the
    rectangle every screen can show is the smallest width by the smallest
    height, centred -- and that, not the canvas, is what the theme lays
    out inside.
    """
    canvas_w = max(w for w, _ in heads)
    canvas_h = max(h for _, h in heads)
    area_w = min(w for w, _ in heads)
    area_h = min(h for _, h in heads)
    k = area_w / c["REF_WIDTH"]
    return {
        "canvas": (canvas_w, canvas_h),
        "area": (area_w, area_h),
        "origin": ((canvas_w - area_w) // 2, (canvas_h - area_h) // 2),
        "k": 1.0 if 0.99 < k < 1.01 else k,
    }


def status_size(c, k):
    """build_layout()'s font ladder, in the same order -- later rules win."""
    size = c["STATUS_FONT"]
    if k <= c["STATUS_K_XS"]:
        size = c["STATUS_FONT_XS"]
    if k >= c["STATUS_K_M"]:
        size = c["STATUS_FONT_M"]
    if k >= c["STATUS_K_L"]:
        size = c["STATUS_FONT_L"]
    return size


# Plymouth's own arithmetic: FT_Set_Char_Size(face, points * 64, 0, 96, 0).
POINTS_TO_PIXELS = 96 / 72


def status_font(points):
    """The face the real boot would use, at the size it would use.

    Both label plugins read the number as points at 96dpi, so it is
    converted here rather than passed through, PIL sizing in pixels.

    The face is resolved the way the boot resolves it, which is not the
    way this desktop does. STATUS_FONT names a family containing "Mono",
    which is what makes label-freetype take its monospace slot; that slot
    comes from `fc-match monospace` run AS ROOT at dracut time, so the
    query here drops this user's fontconfig rules to match. Once
    /etc/fonts/conf.d/70-mono-font.conf is installed the two agree on
    JetBrains Mono; before that they do not, and the family this returns
    is printed in the summary so the difference is visible rather than
    surprising.
    """
    env = dict(os.environ, XDG_CONFIG_HOME="/nonexistent", HOME="/root")
    pixels = max(1, round(points * POINTS_TO_PIXELS))
    try:
        out = subprocess.run(["fc-match", "-f", "%{file}\t%{family}", "monospace"],
                             env=env, capture_output=True, text=True,
                             check=True).stdout
        path, _, family = out.partition("\t")
        return ImageFont.truetype(path.strip(), pixels), family.strip()
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return ImageFont.load_default(), "(fallback)"


def status_schedule(seconds, rng):
    """(start time, line) pairs, paced like a real boot: dense at the start
    where udev and the mounts land, sparser once the long services run."""
    schedule, t = [], 0.25
    for i, unit in enumerate(FAKE_UNITS):
        schedule.append((t, unit))
        # Early lines replace each other several times a second; later ones
        # sit for most of a second. Seeded, so two runs are comparable.
        early = 1 - i / len(FAKE_UNITS)
        t += rng.uniform(0.12, 0.35) + (1 - early) * rng.uniform(0.1, 0.5)
    span = t - 0.25
    return [(0.25 + (ts - 0.25) * (seconds - 0.6) / span, u) for ts, u in schedule]


def main():
    c = constants()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seconds", type=float, default=14.0)
    ap.add_argument("--boot-duration", type=float, default=9.0,
                    help="what Plymouth thinks the last boot took (default: 9)")
    ap.add_argument("--width", type=int, default=int(c["REF_WIDTH"]))
    ap.add_argument("--height", type=int, default=1200)
    ap.add_argument("--heads", default=None,
                    help="comma-separated display list, e.g. 1920x1200,3840x2160 "
                         "— renders what each screen actually shows, stacked")
    ap.add_argument("--out", default="/tmp/coucou-splash.mp4")
    ap.add_argument("--no-open", action="store_true")
    ap.add_argument("--print-schedule", action="store_true",
                    help="print 'delay<TAB>unit' and exit — preview.sh replays "
                         "this through the real daemon, so the fake boot log "
                         "has one definition, not two")
    args = ap.parse_args()

    if args.print_schedule:
        previous = 0.0
        for when, unit in status_schedule(args.boot_duration, random.Random(7)):
            print(f"{when - previous:.2f}\t{unit}")
            previous = when
        return

    heads = parse_heads(args.heads) if args.heads else [(args.width, args.height)]
    g = geometry(c, heads)
    canvas_w, canvas_h = g["canvas"]
    area_w, area_h = g["area"]
    origin_x, origin_y = g["origin"]
    k = g["k"]

    def load(name):
        """scaled() from the theme -- same trunc-to-int, same skip at k == 1.

        With one difference worth knowing: this resamples with LANCZOS,
        while Plymouth uses whatever Image.Scale() does. On a panel that is
        not REF_WIDTH wide, the real splash may look coarser than this. The
        fix for that is not here, it is `make-assets.py --width`.
        """
        img = Image.open(THEME / name).convert("RGBA")
        if k == 1:
            return img
        return img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))),
                          Image.LANCZOS)

    logo, track, fill = load("logo.png"), load("bar-track.png"), load("bar-fill.png")
    fps = int(c["FPS"])
    # Every coordinate is the theme's: a fraction of the SAFE AREA, offset
    # by where that area sits on the canvas.
    logo_x = origin_x + area_w // 2 - logo.width // 2
    logo_y = origin_y + int(area_h * c["LOGO_CENTRE"] - logo.height / 2)
    bar_x = origin_x + area_w // 2 - track.width // 2
    bar_y = origin_y + int(area_h * c["BAR_CENTRE"] - track.height / 2)
    status_y = origin_y + int(area_h * c["STATUS_Y"])
    status_face, status_family = status_font(status_size(c, k))
    # The theme draws it at 0.55/0.55/0.57 of white.
    status_rgb = (140, 140, 145)
    schedule = status_schedule(args.boot_duration, random.Random(7))

    # --- what leaves this program -------------------------------------
    #
    # One display: the canvas IS the screen, so it goes out as it is. More
    # than one: each display shows its own centred crop of the canvas --
    # that is literally what Plymouth draws, (sprite.x - display.x) -- and
    # those crops are stacked into one clip so both screens can be watched
    # at once. Stacked output is scaled to a common width; a 4K head next
    # to a 1200p one is otherwise unwatchable in a window.
    if len(heads) == 1:
        def compose(canvas):
            return canvas
        out_w, out_h = canvas_w, canvas_h
    else:
        strip_w = 1280
        views = []
        for w, h in heads:
            scaled_h = even(h * strip_w / w)
            views.append({
                "crop": ((canvas_w - w) // 2, (canvas_h - h) // 2,
                         (canvas_w - w) // 2 + w, (canvas_h - h) // 2 + h),
                "size": (strip_w, scaled_h),
                "label": f"{w}x{h}",
            })
        band = 26
        out_w = strip_w
        out_h = even(sum(v["size"][1] + band for v in views))
        label_face = status_font(11)[0]

        def compose(canvas):
            sheet = Image.new("RGB", (out_w, out_h), (32, 32, 32))
            draw = ImageDraw.Draw(sheet)
            y = 0
            for view in views:
                draw.text((8, y + 5), view["label"], font=label_face,
                          fill=(190, 190, 190))
                y += band
                sheet.paste(canvas.crop(view["crop"]).resize(view["size"],
                                                            Image.LANCZOS),
                            (0, y))
                y += view["size"][1]
            return sheet

    # Output at half the script's refresh rate: the motion is identical,
    # the file is half the size, and nothing here moves fast enough for
    # 25fps to matter.
    step = 2
    out_fps = fps // step

    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is needed to encode the simulation")
    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-f", "rawvideo", "-pixel_format", "rgb24",
         "-video_size", f"{out_w}x{out_h}", "-framerate", str(out_fps), "-i", "-",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
         "-pix_fmt", "yuv420p", args.out],
        stdin=subprocess.PIPE,
    )

    shown = 0.0
    total = int(args.seconds * fps)
    quit_frame = int(args.boot_duration * fps)
    status_text, status_since, next_line = "", 0, 0

    for frame in range(total):
        t = frame / fps

        # --- pulse: coucou.script counts frames, so do we ---
        phase = (frame / (fps * c["PULSE_PERIOD"])) % 1.0
        wave = (1 + math.cos(phase * 2 * math.pi)) / 2
        opacity = c["PULSE_FLOOR"] + (1 - c["PULSE_FLOOR"]) * wave

        # --- progress: Plymouth's estimate, then the script's easing ---
        target = min(t / args.boot_duration, c["BAR_CEILING"])
        if target > shown:
            shown += (target - shown) * c["BAR_EASE"]
        # --- status line: replaced in place, faded in over STATUS_FADE ---
        while next_line < len(schedule) and t >= schedule[next_line][0]:
            status_text, status_since = schedule[next_line][1], frame
            next_line += 1

        if frame >= quit_frame:            # on_quit()
            shown, opacity = 1.0, 1.0
            status_text = ""               # nothing half-finished left frozen

        if frame % step:
            continue

        canvas = Image.new("RGB", (canvas_w, canvas_h), (0, 0, 0))
        faded = logo.copy()
        faded.putalpha(logo.getchannel("A").point(lambda v: int(v * opacity)))
        canvas.paste(faded, (logo_x, logo_y), faded)
        canvas.paste(track, (bar_x, bar_y), track)
        w = max(track.height, int(track.width * shown))
        scaled = fill.resize((w, fill.height), Image.LANCZOS)
        canvas.paste(scaled, (bar_x, bar_y), scaled)

        if status_text:
            fade = min(1.0, (frame - status_since + 1) / c["STATUS_FADE"])
            draw = ImageDraw.Draw(canvas)
            box = draw.textbbox((0, 0), status_text, font=status_face)
            draw.text(
                (origin_x + area_w // 2 - (box[2] - box[0]) // 2 - box[0],
                 status_y - (box[3] - box[1]) // 2 - box[1]),
                status_text, font=status_face,
                fill=tuple(int(v * fade) for v in status_rgb),
            )

        enc.stdin.write(compose(canvas).tobytes())

    enc.stdin.close()
    if enc.wait() != 0:
        raise SystemExit("ffmpeg failed")

    print(f"{args.out}  ({args.seconds:g}s, {out_w}x{out_h}, "
          f"quit at {args.boot_duration:g}s)")
    print(f"  heads         {', '.join(f'{w}x{h}' for w, h in heads)}")
    if len(heads) > 1:
        print(f"  canvas        {canvas_w}x{canvas_h}  "
              f"(safe area {area_w}x{area_h} at +{origin_x}+{origin_y})")
    print(f"  scale         {k:g}")
    print(f"  status font   {status_family} {status_size(c, k):g}pt "
          f"({round(status_size(c, k) * POINTS_TO_PIXELS)}px)")
    for name in ("PULSE_PERIOD", "PULSE_FLOOR", "BAR_EASE", "BAR_CENTRE",
                 "LOGO_CENTRE", "STATUS_Y"):
        print(f"  {name:<13} {c[name]:g}")

    if not args.no_open:
        if not shutil.which("mpv"):
            print("mpv not found — open it yourself", file=sys.stderr)
            return
        # Full screen on a black background is as close as a window gets to
        # the real thing on this panel. q quits.
        subprocess.Popen(
            ["mpv", "--fs", "--loop-file=inf", "--no-osc", "--really-quiet", args.out],
            start_new_session=True,
        )


if __name__ == "__main__":
    main()
