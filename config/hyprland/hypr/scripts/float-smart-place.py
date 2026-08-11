#!/usr/bin/env python3
"""
float-smart-place.py — Context-row placement for new floating windows.

Problem: Hyprland always centers new floating windows, so opening several
at once stacks them exactly on top of each other. This daemon listens to
Hyprland's event socket (socket2) and arranges floating windows into
"context rows" instead:

  - A "context" is a floating window and whatever further floating
    windows it spawns afterwards (its "subcontexts") -- e.g. open a
    panel, then a dialog from that panel, then a picker from that
    dialog. They're laid out left to right on one row, root first,
    deepest last -- detected purely by focus: whichever floating window
    had focus right before a new one opens is treated as its parent.
    No app-specific knowledge needed.
  - Unrelated floating windows (nothing focused, or focus was on a
    tiled window) start a new row/context of their own.
  - Every row is horizontally centered on its own; all rows are stacked
    and the whole block is vertically centered as a group. A lone
    context therefore lands exactly where Hyprland's native `center`
    would put it -- no visible change for the common single-dialog
    case.
  - A row wider than the screen wraps onto an extra line, still grouped
    under the same context, instead of overflowing.

This is purely *initial* placement: the whole tracked group reflows
whenever a tracked window opens or closes (so the block stays centered
as the context count changes), but nothing stops a window from being
dragged in between -- Hyprland's normal drag/resize keeps working, this
daemon just never fights it outside of an open/close event.

Exemption rule (size threshold, no extra list to maintain):
  Windows smaller than SMALL_W x SMALL_H (confirm/cancel, error, save-as,
  and other small dialogs) are left exactly where Hyprland/windowrules.lua
  put them -- usually centered via an explicit `center = true` rule
  (system dialogs, xdg-desktop-portal, etc.). They never join a row and
  are never repositioned by this daemon.

Safety guard: pinned windows (e.g. the PiP video window from
pip-daemon.sh) and fullscreen floats are never tracked -- pinning is a
deliberate fixed position this daemon must not fight.

Started once for the whole session from hyprland.lua's autostart block
(see socket2_path() below -- a single persistent connection, no polling).
"""

import json
import os
import socket
import subprocess
import time

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
SMALL_W, SMALL_H = 450, 350   # below this size -> a fixed dialog, never tracked
WIN_MARGIN = 12                # gap between windows on the same context line (px)
LINE_MARGIN = 10               # gap between wrapped lines of the same context (px)
CONTEXT_MARGIN = 30            # gap between different contexts/rows (px)
SETTLE_DELAY = 0.06            # extra wait (s) after a window appears, for its size to settle
CLOSE_SETTLE_DELAY = 0.05      # extra wait (s) before reflowing on a close event
MAX_WAIT = 1.0                 # max time (s) to wait for a just-opened window to appear

DEBUG = bool(os.environ.get("FSP_DEBUG"))


def log(*args):
    if DEBUG:
        import sys
        print("DEBUG", *args, file=sys.stderr, flush=True)


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def move_window(address, x, y):
    # This machine runs a custom Hyprland build with a Lua config API
    # (hl.*, see hyprland.lua/windowrules.lua). It intercepts the legacy
    # `hyprctl dispatch movewindowpixel ...` syntax and fails to parse it
    # ("hl.dispatch(...) shorthand" error) -- exact placement has to go
    # through `hyprctl eval` calling hl.dsp.window.move({x, y, window})
    # instead, same pattern as compact-workspaces.sh.
    subprocess.run(
        [
            "hyprctl", "eval",
            "hl.dispatch(hl.dsp.window.move({ x = %d, y = %d, window = 'address:%s' }))"
            % (x, y, address),
        ],
        capture_output=True, text=True,
    )


def find_client(clients, address):
    for c in clients:
        if c["address"] == address:
            return c
    return None


def wait_for_client(address):
    """New windows can take a beat to appear in `hyprctl clients` with
    their final size (GTK/Qt dialogs often resize right after mapping).
    Poll until it shows up, then wait a bit more and re-read once."""
    deadline = time.monotonic() + MAX_WAIT
    while time.monotonic() < deadline:
        c = find_client(hyprctl_json("clients"), address)
        if c is not None:
            time.sleep(SETTLE_DELAY)
            return find_client(hyprctl_json("clients"), address)
        time.sleep(0.03)
    return None


def work_area(monitor):
    """Monitor area minus reserved space (bars/panels). Hyprland reports
    `reserved` as [left, top, right, bottom]."""
    l, t, r, b = monitor["reserved"]
    return (
        monitor["x"] + l,
        monitor["y"] + t,
        monitor["x"] + monitor["width"] - r,
        monitor["y"] + monitor["height"] - b,
    )


# ---------------------------------------------------------------------------
# Context tracking
# ---------------------------------------------------------------------------
rows = []                # list[list[address]] -- each row = one context, root first
last_focused_address = None


def find_row(address):
    if not address:
        return None
    for row in rows:
        if address in row:
            return row
    return None


def handle_new(address):
    client = wait_for_client(address)
    if client is None or not client["floating"] or client["pinned"] or client["fullscreen"]:
        return

    w, h = client["size"]
    if w < SMALL_W and h < SMALL_H:
        return  # small dialog -> leave it wherever it was put (usually centered)

    monitor_id = client["monitor"]
    workspace_id = client["workspace"]["id"]
    if monitor_id < 0 or workspace_id < 0:
        return  # no monitor yet / special workspace -> don't touch

    row = find_row(last_focused_address)
    if row is not None:
        row.append(address)
        log("appended", address, "to existing context", row)
    else:
        rows.append([address])
        log("new context", address)

    reflow()


def reflow():
    """Recomputes every tracked context's position from scratch: prunes
    closed/no-longer-floating windows, then lays surviving rows out as
    centered, wrapped lines, grouped per (monitor, workspace)."""
    clients_by_addr = {c["address"]: c for c in hyprctl_json("clients")}

    global rows
    pruned = []
    for row in rows:
        alive = [
            a for a in row
            if a in clients_by_addr
            and clients_by_addr[a]["floating"]
            and not clients_by_addr[a]["pinned"]
            and not clients_by_addr[a]["fullscreen"]
        ]
        if alive:
            pruned.append(alive)
    rows = pruned
    if not rows:
        return

    monitors = {m["id"]: m for m in hyprctl_json("monitors")}

    groups = {}
    for row in rows:
        c0 = clients_by_addr[row[0]]
        key = (c0["monitor"], c0["workspace"]["id"])
        groups.setdefault(key, []).append(row)

    for (monitor_id, workspace_id), group_rows in groups.items():
        monitor = monitors.get(monitor_id)
        if monitor is None:
            continue
        ax0, ay0, ax1, ay1 = work_area(monitor)
        area_w = ax1 - ax0

        row_blocks = []  # list of (lines, block_height)
        for row in group_rows:
            members = [
                (a, *clients_by_addr[a]["size"])
                for a in row
                if clients_by_addr[a]["monitor"] == monitor_id
                and clients_by_addr[a]["workspace"]["id"] == workspace_id
            ]
            if not members:
                continue

            lines, cur, cur_w = [], [], 0
            for a, w, h in members:
                add_w = w if not cur else w + WIN_MARGIN
                if cur and cur_w + add_w > area_w:
                    lines.append(cur)
                    cur, cur_w, add_w = [], 0, w
                cur.append((a, w, h))
                cur_w += add_w
            if cur:
                lines.append(cur)

            block_h = sum(max(h for _, _, h in line) for line in lines) + LINE_MARGIN * (len(lines) - 1)
            row_blocks.append((lines, block_h))

        if not row_blocks:
            continue

        total_h = sum(bh for _, bh in row_blocks) + CONTEXT_MARGIN * (len(row_blocks) - 1)
        y = max((ay0 + ay1) / 2 - total_h / 2, ay0)

        for lines, block_h in row_blocks:
            for line in lines:
                line_w = sum(w for _, w, _ in line) + WIN_MARGIN * (len(line) - 1)
                line_h = max(h for _, _, h in line)
                x = max((ax0 + ax1) / 2 - line_w / 2, ax0)
                for a, w, h in line:
                    wy = y + (line_h - h) / 2
                    log("place", a, "at", (int(x), int(wy)))
                    move_window(a, int(x), int(wy))
                    x += w + WIN_MARGIN
                y += line_h + LINE_MARGIN
            y += CONTEXT_MARGIN


def socket2_path():
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime_dir}/hypr/{sig}/.socket2.sock"


def run():
    global last_focused_address
    try:
        active = hyprctl_json("activewindow")
        last_focused_address = active.get("address")
    except Exception:
        pass

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(socket2_path())
        buf = ""
        while True:
            chunk = sock.recv(4096).decode(errors="ignore")
            if not chunk:
                break
            buf += chunk
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                try:
                    if line.startswith("openwindow>>"):
                        # A brand-new window -- covers apps that open
                        # floating from the start (dialogs, utility
                        # panels, ...).
                        address = "0x" + line.split(">>", 1)[1].split(",", 1)[0]
                        handle_new(address)
                    elif line.startswith("changefloatingmode>>"):
                        # Tiled -> floating (SUPER+SHIFT+Space, or a
                        # windowrule) doesn't fire openwindow again, and
                        # floating -> tiled should drop out of its row.
                        addr_part, floating_part = line.split(">>", 1)[1].rsplit(",", 1)
                        address = "0x" + addr_part
                        if floating_part.strip() == "1":
                            handle_new(address)
                        else:
                            reflow()
                    elif line.startswith("closewindow>>"):
                        time.sleep(CLOSE_SETTLE_DELAY)
                        reflow()
                    elif line.startswith("activewindowv2>>"):
                        addr = line.split(">>", 1)[1].strip()
                        last_focused_address = ("0x" + addr) if addr else None
                except Exception:
                    pass  # never let a single bad event kill the daemon


def main():
    while True:
        try:
            run()
        except Exception:
            pass
        time.sleep(1)  # socket dropped (e.g. Hyprland restarting) -> retry


if __name__ == "__main__":
    main()
