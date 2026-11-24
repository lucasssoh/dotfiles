#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

# bar.json: the bar's position and look. Built from bar-position.json and
# bar-island.json when they are there, which are then kept as *.old.
dir="$REPO/config/hyprland/hypr"
config="$dir/bar.json"
if [[ -e "$config" || -L "$config" ]]; then
    ok "existing bar.json kept"
    exit 0
fi

python3 - "$dir" <<'PY'
import json, os, sys
d = sys.argv[1]

def read(name):
    try:
        with open(os.path.join(d, name), encoding="utf-8") as f:
            v = json.load(f)
            return v if isinstance(v, dict) else {}
    except (OSError, ValueError):
        return {}

pos, isl = read("bar-position.json"), read("bar-island.json")
shape = isl.get("shape") if isinstance(isl.get("shape"), dict) else {}
fill = isl.get("fill") if isinstance(isl.get("fill"), dict) else {}
text = isl.get("text") if isinstance(isl.get("text"), dict) else {}
style = isl.get("style") if isinstance(isl.get("style"), str) else None
out = {
    "position": pos.get("position") if pos.get("position") in ("top", "bottom") else "top",
    "style": "floating",
    "center": shape.get("style") or style or "island",
    "sides": "none",
    "fill": {
        "colour": fill.get("colour", isl.get("background", "#2c2c2e")),
        "opacity": fill.get("opacity", isl.get("opacity", 0.2)),
        "blur": fill.get("blur", isl.get("blur", False)),
    },
    "text": {
        "mode": text.get("mode", isl.get("mode", "dynamic")),
        "colour": text.get("colour", isl["text"] if isinstance(isl.get("text"), str) else "#f2f2f7"),
    },
}
with open(os.path.join(d, "bar.json"), "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2)
    f.write("\n")
for name in ("bar-position.json", "bar-island.json"):
    p = os.path.join(d, name)
    if os.path.isfile(p):
        os.replace(p, p + ".old")
PY
ok "bar.json written"
