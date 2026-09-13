#!/usr/bin/env python3
"""
border-tint.py — Content-aware light source on the active window's border.

The border gradient in hyprland.lua is a fixed greyscale bevel: a bright
highlight where the (virtual) light hits the curve, fading to near-black
where the curve rolls away. It reads as a lit edge, but the light it
reflects is always the same neutral white, whatever is behind it -- which
is exactly what a real glossy edge does *not* do. A chrome rim next to a
warm amber terminal picks up amber; next to a blue video it goes blue.

This daemon keeps the bevel's luminance/alpha ramp exactly as configured
(same "feel", same shape, same angle) and only injects a *hue* sampled
from the window's own content, at the end of the gradient where that
content actually sits. Light from the top of the window tints the top
stop, light from the bottom tints the bottom stop.

Why only the active window: hyprland.lua sets col.inactive_border fully
transparent on purpose (the active border is the single focus cue), so an
inactive window's border is invisible and never worth computing. That
means one sample per focus change instead of one per window -- the whole
reason this is cheap.

How the sampling avoids being expensive:
  - `grim -T <stableId>` captures the *toplevel's own buffer*, not the
    output. No output screencopy means fullscreen direct scanout is never
    broken (this machine deliberately wraps games with
    no-direct-scanout-wrap.sh -- a periodic full-screen grab would fight
    that), and the capture contains the window content alone: no border,
    no shadow, no occluding window to subtract.
  - It runs on events (focus change, title change), never per frame.
    REFRESH_INTERVAL is 0 by default: no polling at all.
  - Fullscreen windows are skipped entirely -- see SKIP_FULLSCREEN.

Cost measured on this machine: ~20 ms for the grim capture of a
1269x1416 Firefox window, ~5 ms for the decode + tint math. Rendering
cost is strictly zero: Hyprland's border shader runs identically whatever
the gradient stops are, so nothing changes per frame.

Started from hyprland.lua's autostart block, same as float-smart-place.py.
"""

import argparse
import io
import json
import math
import os
import socket
import subprocess
import sys
import time

import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# The bevel ramp, in gradient order (stop 0 first), copied from
# hyprland.lua's general:col.active_border. Each entry is (value, alpha):
# `value` is the greyscale level 0-255 the stop has with no tint applied,
# `alpha` its opacity 0-1. Keeping these untouched is what preserves the
# existing look -- this script only ever adds hue, never changes the ramp.
BASE_STOPS = [
    (40, 0.5),
    (20, 0.5),
    (90, 0.5),
]

# Must match the angle used in hyprland.lua, otherwise the tint lands on
# the wrong end of the window. Convention (verified empirically, see
# gradient_axis): progress increases toward (cos A, sin A) in *screen*
# coords, y pointing down. 270 -> progress 0 at the bottom, 1 at the top.
ANGLE = 270

# How much of the sampled saturation to carry into the border, applied
# after the coverage scaling below. 0.7 puts solid saturated content at
# the TINT_MAX_SAT ceiling while leaving a dark UI barely tinted; raise it
# toward 1.5 to make the effect obvious on ordinary windows, drop it to 0
# for a no-op that reproduces hyprland.lua's ramp byte for byte.
TINT_STRENGTH = 0.7

# Hard ceiling on the injected saturation, whatever the content. Stops a
# saturated red video from turning the rim into a neon outline.
TINT_MAX_SAT = 0.45

# Per-stop saturation multiplier, same order/length as BASE_STOPS. A real
# specular highlight desaturates toward white at its brightest, while the
# mid-tones carry most of the reflected color -- that is what these weights
# express. Set them all to 1.0 for a uniformly tinted ramp.
STOP_SAT_WEIGHT = [1.0, 0.8, 0.55]

# Hard floor: below this mean chroma the band is treated as pure greyscale
# and contributes no hue at all, rather than amplifying a hue out of
# compression noise. Measured on this machine: a black terminal edge sits
# at 0.0002, so this only ever catches genuinely achromatic content.
MIN_CHROMA_WEIGHT = 0.004

# Mean chroma considered "fully colored", used to scale the tint by how
# much of the edge band is actually colored rather than by how saturated
# its colored pixels happen to be. Without this, a black terminal showing
# three green glyphs tints exactly as hard as a full-frame green video --
# the mean saturation of the *colored* pixels is high in both cases. With
# it, the tint tracks how much light the content would really throw.
# Measured references: black terminal edge 0.0002, terminal with colored
# text 0.043, Firefox's dark chrome 0.013-0.018, a solid saturated fill
# ~0.6. 0.25 puts solid content at full tint and leaves dark UI subtle.
CHROMA_FULL = 0.25

# Window content is box-downscaled to this grid before any math. Small
# enough that the tint math is microseconds, large enough that the edge
# bands below still average a meaningful number of source pixels.
SAMPLE_GRID = 96

# Depth, on that grid, of the band along the window's edge that is treated
# as "the content the border reflects". 10/96 ~= the outer 10% of the
# window, i.e. what actually sits next to the rim.
EDGE_DEPTH = 10

# Fraction of the gradient axis at each end that feeds a stop's hue.
# Pixels with progress < 0.25 tint the first stop, > 0.75 the last one.
AXIS_BAND = 0.25

# Seconds to coalesce bursts of events (focus storms when a workspace
# switches, a title updating character by character, ...).
DEBOUNCE = 0.25

# Optional slow re-sample of the focused window, in seconds, for content
# that changes without firing any event (a video playing, a build
# scrolling). 0 disables polling entirely, which is the default: every
# tick is a real capture, and capturing a playing video every second is a
# lot of work for a rim nobody is looking at. Set to e.g. 2.0 if you want
# the rim to follow video content.
REFRESH_INTERVAL = 0.0

# Fullscreen windows are skipped: they are games/video 99% of the time,
# their border is not visible anyway (no gaps), and capturing them is
# exactly what would hurt.
SKIP_FULLSCREEN = True

# Classes never sampled, whatever their state. gamescope and the launcher
# already carry explicit no_blur rules in windowrules.lua for the same
# "do not touch this window's rendering path" reason.
EXCLUDE_CLASSES = {"gamescope", "steam_app", "Rockstar Games Launcher"}

DEBUG = bool(os.environ.get("BORDER_TINT_DEBUG"))


def log(*args):
    if DEBUG:
        print("border-tint:", *args, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Hyprland plumbing
# ---------------------------------------------------------------------------
# Every subprocess below is parsed, so LC_ALL=C is mandatory: this session
# runs fr_FR.UTF-8 and a localized number/message format has already broken
# CLI parsing elsewhere in this repo.
ENV_C = {**os.environ, "LC_ALL": "C"}


def hyprctl_json(*args):
    out = subprocess.run(
        ["hyprctl", "-j", *args], capture_output=True, text=True, check=True, env=ENV_C
    )
    return json.loads(out.stdout)


def set_border(address, gradient):
    """Push a gradient onto one window's active border.

    Two things are load-bearing here and were both established the hard
    way against a live compositor:
      - this build's Lua config API intercepts the legacy
        `hyprctl setprop <win> <prop> <val>` syntax, so the call has to go
        through `hyprctl eval` + hl.dsp.window.set_prop, same as
        float-smart-place.py does for moves;
      - set_prop only accepts *scalar* values. Passing a Lua table
        ({ colors = {...}, angle = ... }) is rejected with "'value' is
        required"; the gradient has to be the flat string form,
        "rgba(RRGGBBAA) rgba(RRGGBBAA) ... <N>deg". The table form is what
        hl.window_rule takes, which is a different code path.
    Only `active_border_color` is ever written, and only with a string
    built by build_gradient(), which cannot produce anything but that
    shape -- set_prop will hard-crash Hyprland on a mistyped value, so
    nothing dynamic is allowed to reach it.
    """
    subprocess.run(
        [
            "hyprctl", "eval",
            "hl.dispatch(hl.dsp.window.set_prop({ prop = 'active_border_color',"
            " value = '%s', window = 'address:%s' }))" % (gradient, address),
        ],
        capture_output=True, text=True, env=ENV_C,
    )


def socket2_path():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime_dir}/hypr/{sig}/.socket2.sock"


# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------
def capture(client):
    """Window content as an (H, W, 3) uint8 array, or None.

    Preferred path is grim's foreign-toplevel capture (-T <stableId>),
    which reads the window's own buffer: no output screencopy, no border
    or shadow in the frame, and correct even when the window is partly
    covered. The -g fallback exists for a window without a usable handle;
    it grabs the output region instead, so it has to be inset past the
    border and the rounded corners to avoid sampling the rim we are about
    to recolor (which would feed back on itself).
    """
    out = subprocess.run(
        ["grim", "-T", str(client["stableId"]), "-t", "ppm", "-"],
        capture_output=True, env=ENV_C,
    )
    if out.returncode != 0 or not out.stdout:
        x, y = client["at"]
        w, h = client["size"]
        inset = 16
        if w <= 2 * inset or h <= 2 * inset:
            return None
        geom = "%d,%d %dx%d" % (x + inset, y + inset, w - 2 * inset, h - 2 * inset)
        log("toplevel capture failed, falling back to region", geom)
        out = subprocess.run(
            ["grim", "-g", geom, "-t", "ppm", "-"], capture_output=True, env=ENV_C
        )
        if out.returncode != 0 or not out.stdout:
            return None

    try:
        img = Image.open(io.BytesIO(out.stdout)).convert("RGB")
    except Exception:
        return None
    # BOX is a plain area average, which is exactly the reduction we want
    # (every source pixel weighted equally) and it is done in C.
    img = img.resize((SAMPLE_GRID, SAMPLE_GRID), Image.BOX)
    return np.asarray(img, dtype=np.float32) / 255.0


# ---------------------------------------------------------------------------
# Tint extraction
# ---------------------------------------------------------------------------
def rgb_to_hsv(arr):
    """Vectorized RGB->HSV on an (..., 3) float array in 0..1.

    Written out rather than pulled from colorsys/matplotlib: colorsys is
    scalar-only (96*96 Python-level calls per update) and matplotlib is
    not a dependency worth adding for fifteen lines of arithmetic.
    """
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = arr.max(axis=-1)
    mn = arr.min(axis=-1)
    d = mx - mn

    h = np.zeros_like(mx)
    safe = d > 1e-6
    # Standard piecewise hue, guarded so a grey pixel (d == 0) stays at 0
    # instead of dividing by zero.
    with np.errstate(invalid="ignore", divide="ignore"):
        rm = (mx == r) & safe
        gm = (mx == g) & safe & ~rm
        bm = safe & ~rm & ~gm
        h[rm] = ((g[rm] - b[rm]) / d[rm]) % 6.0
        h[gm] = (b[gm] - r[gm]) / d[gm] + 2.0
        h[bm] = (r[bm] - g[bm]) / d[bm] + 4.0
    h = h / 6.0

    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def gradient_axis(angle_deg):
    """Unit vector of increasing gradient progress, in screen coords (y down).

    Verified against this Hyprland build twice, not assumed:
      - hyprland.lua already records that at angle 45, progress 0 sits at
        the top-left and 1 at the bottom-right -- direction (+x, +y),
        which is (cos 45, sin 45) with y down.
      - Pushing "red green blue 270deg" onto a live window put blue (the
        last stop) at the top and red at the bottom -- progress increasing
        upward, which is (cos 270, sin 270) = (0, -1) with y down.
    Both agree on d = (cos A, sin A), y down.
    """
    a = math.radians(angle_deg)
    return math.cos(a), math.sin(a)


def sample_tints(arr):
    """Representative (hue, saturation) at each end of the gradient axis.

    Only pixels inside the edge band are considered -- a border reflects
    what is next to it, not the average of the whole window -- and within
    that band each pixel is weighted by saturation * value, so vivid,
    bright content decides the hue while black chrome and grey padding are
    ignored rather than dragging the result toward mud.

    Returns (h0, s0), (h1, s1) for the first and last stop, with
    saturation 0 meaning "no tint, keep the stop neutral".
    """
    n = SAMPLE_GRID
    h, s, v = rgb_to_hsv(arr)
    weight = s * v

    yy, xx = np.mgrid[0:n, 0:n]
    edge = (
        (xx < EDGE_DEPTH) | (xx >= n - EDGE_DEPTH)
        | (yy < EDGE_DEPTH) | (yy >= n - EDGE_DEPTH)
    )

    dx, dy = gradient_axis(ANGLE)
    # Progress of each pixel along the gradient axis, renormalized to 0..1
    # over the window so the bands below mean the same thing at any angle.
    proj = (xx / (n - 1.0)) * dx + (yy / (n - 1.0)) * dy
    lo, hi = proj.min(), proj.max()
    proj = (proj - lo) / max(hi - lo, 1e-6)

    def tint(mask):
        m = mask & edge
        w = weight[m]
        if w.size == 0:
            return 0.0, 0.0
        # Mean, not sum, so the thresholds below mean the same thing
        # regardless of how many pixels the band happens to hold.
        mean_chroma = float(w.mean())
        if mean_chroma < MIN_CHROMA_WEIGHT:
            return 0.0, 0.0
        total = float(w.sum())
        angles = h[m] * 2.0 * math.pi
        # Hue is circular: 0.99 and 0.01 are both red and must not average
        # to cyan, so take the mean on the unit circle.
        x = float((np.cos(angles) * w).sum())
        y = float((np.sin(angles) * w).sum())
        hue = (math.atan2(y, x) / (2.0 * math.pi)) % 1.0
        # Saturation of the colored pixels tells us *which* color the
        # content is; coverage tells us how much of it there is. Only the
        # product behaves like reflected light -- see CHROMA_FULL.
        sat = float((s[m] * w).sum() / total)
        coverage = min(mean_chroma / CHROMA_FULL, 1.0)
        return hue, sat * coverage

    return tint(proj <= AXIS_BAND), tint(proj >= 1.0 - AXIS_BAND)


def lerp_hue(h0, h1, t):
    """Interpolate around the shorter arc of the hue circle."""
    d = (h1 - h0 + 0.5) % 1.0 - 0.5
    return (h0 + d * t) % 1.0


def hsv_to_rgb255(h, s, v):
    i = int(h * 6.0) % 6
    f = h * 6.0 - int(h * 6.0)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    return tuple(max(0, min(255, int(round(c * 255)))) for c in (r, g, b))


def build_gradient(tint0, tint1):
    """Render BASE_STOPS as a Hyprland gradient string, hue injected.

    The `value` of each stop is carried over untouched, so the ramp's
    luminance -- the thing that makes it read as a curved lit edge -- is
    bit-for-bit what hyprland.lua configures. Only saturation is added.
    """
    (h0, s0), (h1, s1) = tint0, tint1
    n = len(BASE_STOPS)
    parts = []
    for i, (value, alpha) in enumerate(BASE_STOPS):
        t = i / (n - 1.0) if n > 1 else 0.0
        # A stop takes its hue from the end of the axis it sits at, and
        # crossfades through the middle ones.
        hue = lerp_hue(h0, h1, t) if (s0 > 0 and s1 > 0) else (h0 if s0 > 0 else h1)
        sat = s0 * (1 - t) + s1 * t
        sat = min(sat * TINT_STRENGTH, TINT_MAX_SAT)
        weight = STOP_SAT_WEIGHT[i] if i < len(STOP_SAT_WEIGHT) else 1.0
        r, g, b = hsv_to_rgb255(hue, sat * weight, value / 255.0)
        parts.append("rgba(%02x%02x%02x%02x)" % (r, g, b, round(alpha * 255)))
    return " ".join(parts) + " %ddeg" % ANGLE


def neutral_gradient():
    """The configured ramp with no tint -- what an achromatic window gets."""
    parts = [
        "rgba(%02x%02x%02x%02x)" % (v, v, v, round(a * 255)) for v, a in BASE_STOPS
    ]
    return " ".join(parts) + " %ddeg" % ANGLE


# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------
last_applied = {}


def should_skip(client):
    if client["class"] in EXCLUDE_CLASSES:
        return "excluded class"
    if SKIP_FULLSCREEN and client.get("fullscreen"):
        return "fullscreen"
    w, h = client["size"]
    if w < 2 * EDGE_DEPTH or h < 2 * EDGE_DEPTH:
        return "too small"
    return None


def update(address):
    if not address:
        return
    try:
        clients = hyprctl_json("clients")
    except Exception:
        return
    client = next((c for c in clients if c["address"] == address), None)
    if client is None or not client["mapped"]:
        return

    reason = should_skip(client)
    if reason:
        log("skip", client["class"], "--", reason)
        return

    arr = capture(client)
    if arr is None:
        log("capture failed for", client["class"])
        return

    t0, t1 = sample_tints(arr)
    gradient = neutral_gradient() if (t0[1] == 0 and t1[1] == 0) else build_gradient(t0, t1)

    # Pushing an identical string would be a pointless round trip through
    # the compositor on every title change of a static window.
    if last_applied.get(address) == gradient:
        return
    last_applied[address] = gradient
    set_border(address, gradient)
    log("%-28s h0=%.2f/s=%.2f h1=%.2f/s=%.2f -> %s"
        % (client["class"], t0[0], t0[1], t1[0], t1[1], gradient))


# ---------------------------------------------------------------------------
# Event loop
# ---------------------------------------------------------------------------
def run():
    focused = None
    pending = None      # address waiting out the debounce window
    pending_at = 0.0
    last_update = 0.0

    try:
        focused = hyprctl_json("activewindow").get("address")
        pending, pending_at = focused, time.monotonic()
    except Exception:
        pass

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(socket2_path())
        sock.setblocking(False)
        buf = ""
        while True:
            # The timeout is what makes the debounce and the optional
            # refresh fire without a busy loop: select wakes us either on
            # an event or when something is due.
            import select
            timeout = 0.2 if (pending or REFRESH_INTERVAL) else None
            select.select([sock], [], [], timeout)

            try:
                chunk = sock.recv(65536).decode(errors="ignore")
                if chunk == "":
                    break
                buf += chunk
            except BlockingIOError:
                chunk = None
            except OSError:
                break

            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                try:
                    if line.startswith("activewindowv2>>"):
                        addr = line.split(">>", 1)[1].strip()
                        focused = ("0x" + addr) if addr else None
                        pending, pending_at = focused, time.monotonic()
                    elif line.startswith("windowtitlev2>>"):
                        # Content changed enough for the app to rename
                        # itself -- a new page, a new buffer, a new video.
                        addr = "0x" + line.split(">>", 1)[1].split(",", 1)[0]
                        if addr == focused:
                            pending, pending_at = addr, time.monotonic()
                    elif line.startswith("fullscreen>>"):
                        pending, pending_at = focused, time.monotonic()
                except Exception:
                    pass  # never let one malformed event kill the daemon

            now = time.monotonic()
            if pending and now - pending_at >= DEBOUNCE:
                addr, pending = pending, None
                last_update = now
                try:
                    update(addr)
                except Exception as exc:
                    log("update failed:", exc)
            elif REFRESH_INTERVAL and focused and now - last_update >= REFRESH_INTERVAL:
                last_update = now
                try:
                    update(focused)
                except Exception as exc:
                    log("refresh failed:", exc)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--once", action="store_true",
                    help="compute and apply for the active window, then exit")
    ap.add_argument("--dump", action="store_true",
                    help="print the gradient for the active window without applying it")
    ap.add_argument("--strength", type=float, metavar="F",
                    help="override TINT_STRENGTH for this run (tuning aid)")
    ap.add_argument("--max-sat", type=float, metavar="F",
                    help="override TINT_MAX_SAT for this run (tuning aid)")
    ap.add_argument("--flat", action="store_true",
                    help="ignore STOP_SAT_WEIGHT, tint every stop equally")
    args = ap.parse_args()

    global TINT_STRENGTH, TINT_MAX_SAT, STOP_SAT_WEIGHT
    if args.strength is not None:
        TINT_STRENGTH = args.strength
    if args.max_sat is not None:
        TINT_MAX_SAT = args.max_sat
    if args.flat:
        STOP_SAT_WEIGHT = [1.0] * len(BASE_STOPS)

    if args.dump:
        client = hyprctl_json("activewindow")
        arr = capture(client)
        if arr is None:
            print("capture failed", file=sys.stderr)
            return 1
        t0, t1 = sample_tints(arr)
        print("class   :", client["class"])
        print("tint lo : h=%.3f s=%.3f" % t0)
        print("tint hi : h=%.3f s=%.3f" % t1)
        print("gradient:", neutral_gradient() if (t0[1] == 0 and t1[1] == 0)
              else build_gradient(t0, t1))
        return 0

    if args.once:
        update(hyprctl_json("activewindow").get("address"))
        return 0

    while True:
        try:
            run()
        except Exception as exc:
            log("loop died:", exc)
        time.sleep(1)  # socket dropped (Hyprland restarting) -> retry


if __name__ == "__main__":
    sys.exit(main() or 0)
