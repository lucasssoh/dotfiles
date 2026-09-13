#!/usr/bin/env python3
"""
bar-tint.py — Content-aware ink for the bar's three exposed islands.

The bar's band is `#730c0c0e` (see quickshell/bar/shell.qml's barBand):
alpha 0x73, so it blocks only 45% of what is behind it and 55% of the
wallpaper comes straight through. Over a dark wallpaper the bar's white
ink scores 18:1 and nothing is wrong. Over a bright one the composite
lands around 145 and the same ink scores 2.81:1 -- below WCAG AA, and
measured on this machine rather than modelled: `monochrome-tree.jpg` in
the wallpaper cache does exactly that, and the prediction (145 / 2.81:1)
matched the real screen capture (144 / 2.83:1) to within 1%.

WHAT THIS DOES NOT DECIDE
--------------------------------
It does not choose a colour, or a material, or a threshold. It emits a
LUMINANCE PROFILE of the strip behind the bar -- N buckets of mean colour
across the monitor's width -- and stops there. Everything downstream is
QML's:

  - which buckets an island covers, because the islands RESIZE (metrics
    and tools follow their content, launchers follows the running apps),
    and a daemon that owned the rects would have to re-sample on every
    width change for a picture that did not move;
  - the compositing against the band's own alpha, because the band's
    colour lives in shell.qml and only one file should know it;
  - the contrast maths, the threshold and the hysteresis.

That split is the whole design: this side knows pixels, that side knows
layout. An island can resize sixty times a second and this never runs.

WHY THE WALLPAPER FILE, NOT A SCREEN CAPTURE
--------------------------------------------
The bar reserves `exclusiveZone: 24`, so no window can ever occupy the
strip behind it. What is back there IS the wallpaper, which means the
content only changes when the wallpaper changes -- and the wallpaper is
already an event we control (see below). Reading the file costs
~9 ms with PIL's JPEG draft mode and touches neither the compositor nor
the GPU.

`grim` stays as a fallback for the one case the file path is unknown
(a bare invocation with no argument, where `awww query` also failed). It is a real cost in a way
the file read is not: a screencopy forces the compositor to composite and
copy a frame, which on a laptop can pull the GPU out of a low-power
state, and this machine deliberately wraps games with
no-direct-scanout-wrap.sh. So the fallback skips any monitor with a
fullscreen window, same rule border-tint.py's SKIP_FULLSCREEN applies.

Cost, measured on this machine rather than assumed:
  - numpy+PIL import ................ 110 ms
  - JPEG decode via draft 1/8 ....... 8.9 ms
  - hyprctl monitors + bucket maths .. ~70 ms
  - grim -g "0,0 2560x30" ........... 20 ms wall, ~0 ms CPU (frame wait),
    fallback only
~190 ms in total, once per wallpaper change. The import dominates and is
now paid every time rather than once at login, which was the argument for
the daemon this used to be -- and it does not hold up: on a 120 s
slideshow that is 0.16% of one core, against an always-resident process
to avoid it. quickshell itself runs at 0.45% continuously, and the
slideshow's own `awww img` transition costs more than this does.
Whichever way the trade went, it stays far below anything measurable on
a battery.

NOT A DAEMON: THE SETTER CALLS THIS
-----------------------------------
This runs once per wallpaper change and exits. It is not resident, it
listens for nothing, and there is no protocol to get the path to it --
the setter passes it as an argument, because the setter is the only thing
that actually knows.

The first draft of this file WAS a daemon woken by SIGUSR1, with a
pidfile and a state file. All of that existed only to carry the path from
whoever changed the wallpaper to a process that was already running, and
none of it is needed once the change itself is the thing that runs us.
Gone with it: the signal race (a poke arriving during a sample), the
stale pidfile, and an always-resident process.

The four callers, which is why this is one script and not logic inside
any one of them:
  - scripts/wallpaper-slideshow.sh  (the frequent one, a bash loop)
  - scripts/restore_wallpaper.sh    (login -- also the startup case)
  - scripts/set_wallpaper.sh        (the legacy rofi picker)
  - prisme-src/src/apply.rs         (Prisme)
Prisme is not a privileged point here despite being the newest: its own
header says it is "a replacement UI, not a new backend", and it shells
out to `awww img` exactly like the three scripts do. Putting the maths in
Rust there would leave the other three needing a second implementation of
it, which is the one outcome worth avoiding.

The path is an ARGUMENT rather than read back from `awww query` because
query is not authoritative about what is on screen: observed on this
machine, it reported monochrome-tree.jpg while the screen still showed
the previous image, and only caught up minutes later. The file the setter
just applied is the truth; the compositor's idea of it lags. `awww query`
is kept only for a bare invocation with no argument, where it is the sole
source available.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import tempfile

import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# Height of the strip sampled, in layout pixels from the top of each
# monitor. The bar reserves 24 and its pills hang to 30; 32 covers both
# with a margin and the extra rows barely move a mean.
BAND_H = 32

# Buckets across the monitor's width. 64 over 2560 is a 40px bucket, and
# the narrowest island (launchers) is ~80px, so even it averages two.
# Raising this does not cost a re-sample, only a slightly longer JSON.
BUCKETS = 64

# Read by quickshell through a FileView with watchChanges (inotify). NOT
# under /sys -- OsdState.qml documents why that would not have worked:
# sysfs is kernfs, notified via poll()/uevent, and Qt's watcher is
# inotify-only. A regular file in the cache dir is exactly the case
# inotify does handle.
OUT_PATH = os.path.expanduser("~/.cache/bar-tint.json")


# ---------------------------------------------------------------------------
# Colour
# ---------------------------------------------------------------------------

def to_linear(a):
    """sRGB 0-255 -> linear light 0-1, the sRGB transfer function."""
    c = a / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    """linear light 0-1 -> sRGB 0-255."""
    c = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.clip(a, 0, 1) ** (1 / 2.4) - 0.055)
    return np.clip(c * 255.0, 0, 255)


def bucketise(strip):
    """(H, W, 3) uint8 strip -> BUCKETS x [r, g, b], averaged in LINEAR light.

    Averaging the 8-bit values directly would be wrong for the same
    reason resizing in sRGB is: the encoding is not linear in light, so a
    bucket spanning black and white would come back darker than the light
    actually arriving there. The mean has to happen in linear space and
    be re-encoded afterwards.
    """
    lin = to_linear(strip.astype(np.float32))
    edges = np.linspace(0, lin.shape[1], BUCKETS + 1).astype(int)
    out = []
    for i in range(BUCKETS):
        x0, x1 = edges[i], max(edges[i] + 1, edges[i + 1])
        mean = lin[:, x0:x1].reshape(-1, 3).mean(axis=0)
        out.append([round(float(v), 1) for v in to_srgb(mean)])
    return out


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

def hypr(*args):
    r = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True,
                       env={**os.environ, "LC_ALL": "C"})
    return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None


def monitors():
    m = hypr("monitors") or []
    return [{"name": d["name"], "x": d["x"], "y": d["y"],
             "w": int(d["width"] / d.get("scale", 1)),
             "h": int(d["height"] / d.get("scale", 1)),
             "ws": (d.get("activeWorkspace") or {}).get("id")} for d in m]


def fullscreen_workspaces():
    return {w["id"] for w in (hypr("workspaces") or []) if w.get("hasfullscreen")}


def strip_from_wallpaper(path, mon):
    """The monitor's top BAND_H rows, as awww's `crop` mode will lay the
    image out: scale to COVER the output, centre, crop.

    Kept in step with awww's own default (`--resize`, default `crop`,
    anchored centre). If that default is ever changed on the command
    line, this mapping is what has to follow.
    """
    try:
        im = Image.open(path)
        # draft() lets the JPEG decoder drop straight to a 1/8 scale
        # instead of decoding 2560x1440 and throwing it away: 8.9 ms
        # against 19.9 ms, measured. It is a no-op on PNG/WebP, which
        # simply decode in full. Asking for >= the output size keeps the
        # strip from being upscaled back out of a too-small draft.
        im.draft("RGB", (mon["w"], mon["h"]))
        im = im.convert("RGB")
    except Exception:
        return None
    iw, ih = im.size
    if iw < 1 or ih < 1:
        return None
    s = max(mon["w"] / iw, mon["h"] / ih)
    nw, nh = max(mon["w"], round(iw * s)), max(mon["h"], round(ih * s))
    im = im.resize((nw, nh), Image.BILINEAR)
    ox, oy = (nw - mon["w"]) // 2, (nh - mon["h"]) // 2
    return np.asarray(im.crop((ox, oy, ox + mon["w"], oy + BAND_H)))


def strip_from_grim(mon):
    """Fallback: the composited strip straight off the output.

    Skipped on a fullscreen workspace -- a screencopy there would break
    direct scanout, which is exactly what no-direct-scanout-wrap.sh
    exists to protect, and the bar is covered anyway so the answer would
    be useless.
    """
    if mon["ws"] in fullscreen_workspaces():
        return None
    geom = f"{mon['x']},{mon['y']} {mon['w']}x{BAND_H}"
    with tempfile.NamedTemporaryFile(suffix=".ppm", delete=False) as f:
        tmp = f.name
    try:
        r = subprocess.run(["grim", "-g", geom, "-t", "ppm", tmp],
                           capture_output=True)
        if r.returncode != 0:
            return None
        return np.asarray(Image.open(tmp).convert("RGB"))
    except Exception:
        return None
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def awww_paths():
    """Per-output wallpaper paths, for STARTUP only -- see the header on
    why this is not trusted for a live change."""
    try:
        r = subprocess.run(["awww", "query"], capture_output=True, text=True,
                           env={**os.environ, "LC_ALL": "C"})
    except FileNotFoundError:
        return {}
    out = {}
    for line in r.stdout.splitlines():
        if ": image: " not in line:
            continue
        head, _, path = line.partition("currently displaying: image: ")
        name = head.split(":")[1].strip() if head.count(":") >= 2 else None
        if name and path.strip():
            out[name] = path.strip()
    return out


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def emit(profiles):
    """Write the profile file quickshell watches.

    Written in ONE os.write to a pre-serialised buffer rather than
    streamed through json.dump: the reader is woken by inotify and will
    read whatever is on disk at that instant, so the window in which a
    half-written file could be parsed has to be as small as possible.
    `seq` lets the reader drop anything it has already applied.
    """
    # Horodatage en ms, PAS un compteur. Un compteur etait correct tant
    # que ce fichier etait un daemon qui vivait entre deux echantillons;
    # en one-shot il repartirait de 1 a chaque appel, et le lecteur -- qui
    # ignore un `seq` deja vu -- n'appliquerait plus jamais rien apres le
    # tout premier profil.
    seq = int(time.time() * 1000)
    blob = json.dumps({"seq": seq, "bandHeight": BAND_H,
                       "buckets": BUCKETS, "monitors": profiles},
                      separators=(",", ":")).encode()
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    fd = os.open(OUT_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    try:
        os.write(fd, blob)
    finally:
        os.close(fd)


def sample(explicit_path=None, verbose=False):
    startup_paths = {} if explicit_path else awww_paths()
    profiles = {}
    for mon in monitors():
        path = explicit_path or startup_paths.get(mon["name"])
        strip = strip_from_wallpaper(path, mon) if path else None
        src = "wallpaper"
        if strip is None:
            strip = strip_from_grim(mon)
            src = "grim"
        if strip is None:
            if verbose:
                print(f"{mon['name']}: pas de source (fullscreen ?)", file=sys.stderr)
            continue
        profiles[mon["name"]] = {"width": mon["w"], "cells": bucketise(strip)}
        if verbose:
            cells = np.array(profiles[mon["name"]]["cells"])
            print(f"{mon['name']}: {src}, {len(cells)} buckets, "
                  f"moyenne {cells.mean():.0f}/255", file=sys.stderr)
    if profiles:
        emit(profiles)
    return bool(profiles)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("image", nargs="?",
                    help="le wallpaper qui vient d'etre applique. Omis: "
                         "demande a `awww query` (moins fiable, voir l'en-tete)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    path = None
    if args.image:
        path = os.path.abspath(os.path.expanduser(args.image))
        if not os.path.isfile(path):
            # Pas une erreur fatale: on retombe sur awww query / grim
            # plutot que de laisser la barre sans profil du tout.
            print(f"bar-tint: {path} introuvable", file=sys.stderr)
            path = None
    try:
        return 0 if sample(explicit_path=path, verbose=args.verbose) else 1
    except Exception as e:      # jamais faire echouer le setter qui nous appelle
        print(f"bar-tint: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main() or 0)
