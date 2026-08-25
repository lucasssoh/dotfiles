#!/usr/bin/env python3
"""
monitor-grid.py — Turns a role-based grid layout into pixel positions.

Reads one JSON object on stdin:

    {
      "grid":     [["external", "internal"], [null, "external2"]],
      "align":    "center" | "start" | "end",
      "dims":     {"<connector>": {"w": 2560, "h": 1440}, ...},
      "active":   {"<connector>": true, ...},
      "role_map": {"internal": "eDP-2", "external": "DP-9", ...}
    }

`grid` is a list of rows, each a list of role names (or null for an
empty cell) -- a single row is a horizontal strip, a single column is
vertical, anything wider is a real grid. Column widths / row heights are
each the max size of the (active) monitors placed in them, so mismatched
resolutions still line up; `align` controls where a smaller monitor sits
within its row's height / column's width ("start" = top/left, "end" =
bottom/right, "center" = centered -- the default).

Prints one JSON object on stdout: {"<connector>": {"x": .., "y": ..}, ...}
-- only for monitors that are both active AND placed in the grid. Called
from workspace-manager.sh, which positions any active monitor missing
from the result at (0, 0) as a visible-but-unconfigured fallback.
"""
import json
import sys


def cell_name(role, role_map, active):
    if not role:
        return None
    name = role_map.get(role)
    if not name or not active.get(name):
        return None
    return name


def align_offset(total, size, align):
    if align == "start":
        return 0
    if align == "end":
        return total - size
    return (total - size) // 2


def main():
    data = json.load(sys.stdin)
    grid = data.get("grid") or []
    align = data.get("align", "center")
    dims = data.get("dims", {})
    active = data.get("active", {})
    role_map = data.get("role_map", {})

    nrows = len(grid)
    ncols = max((len(row) for row in grid), default=0)
    col_w = [0] * ncols
    row_h = [0] * nrows

    for r, row in enumerate(grid):
        for c, role in enumerate(row):
            name = cell_name(role, role_map, active)
            if name is None or name not in dims:
                continue
            col_w[c] = max(col_w[c], dims[name]["w"])
            row_h[r] = max(row_h[r], dims[name]["h"])

    col_x = [0] * ncols
    for c in range(1, ncols):
        col_x[c] = col_x[c - 1] + col_w[c - 1]
    row_y = [0] * nrows
    for r in range(1, nrows):
        row_y[r] = row_y[r - 1] + row_h[r - 1]

    out = {}
    for r, row in enumerate(grid):
        for c, role in enumerate(row):
            name = cell_name(role, role_map, active)
            if name is None or name not in dims:
                continue
            w, h = dims[name]["w"], dims[name]["h"]
            out[name] = {
                "x": col_x[c] + align_offset(col_w[c], w, align),
                "y": row_y[r] + align_offset(row_h[r], h, align),
            }

    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
