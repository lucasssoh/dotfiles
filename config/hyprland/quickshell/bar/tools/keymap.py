#!/usr/bin/env python3
"""Print the main keyboard's active layout as JSON, for the keybinds sheet.

The sheet draws a physical keyboard and needs to know what each key prints
in whatever layout is active right now -- & on AZERTY's first number key, 1
on QWERTY's, " on BÉPO's -- and which key a keysym like `h` lands on (BÉPO
moves it to the bottom row). Hyprland knows the layout but not the glyphs,
so this asks libxkbcommon directly, through ctypes: the same library
Hyprland itself compiles the keymap with, so the two cannot disagree. No
xkbcomp, no text parsing, and it runs in ~20 ms.

Run by services/KeybindsState.qml at startup and whenever Hyprland reports a
layout switch or a config reload -- never while SUPER is being held.

Output:
  {"name": "French (AZERTY)",
   "keys": {"AE01": {"code": 10, "sym": "ampersand", "base": "&", "shift": "1"}, ...}}

`code` is the xkb keycode (what Hyprland's `code:NN` binds use), `sym` the
level-1 keysym name (what a keysym bind like "SUPER+ H" matches against,
case-insensitively), `base`/`shift` the two printed glyphs.
"""

import ctypes
import json
import subprocess
import sys

# The printable block of an ISO keyboard -- the only keys whose glyphs
# depend on the layout. Esc, Enter, Space, the modifiers... are drawn by
# name in KeybindsDrawerContent.qml.
PRINTABLE = (
    ["TLDE"] + ["AE%02d" % i for i in range(1, 13)]
    + ["AD%02d" % i for i in range(1, 13)]
    + ["AC%02d" % i for i in range(1, 12)] + ["BKSL"]
    + ["LSGT"] + ["AB%02d" % i for i in range(1, 11)]
)


class RuleNames(ctypes.Structure):
    _fields_ = [(f, ctypes.c_char_p) for f in ("rules", "model", "layout", "variant", "options")]


def main_keyboard():
    """layout/variant/options of the main keyboard, and its keymap name.

    A multi-layout setup ("fr,us") is narrowed to the ACTIVE entry: the
    sheet shows what the keys do now, not a union of every layout.
    """
    try:
        out = subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True, timeout=5).stdout
        kbs = json.loads(out)["keyboards"]
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        return None
    kb = next((k for k in kbs if k.get("main")), kbs[0] if kbs else None)
    if kb is None:
        return None
    idx = kb.get("active_layout_index", 0) or 0
    layouts = (kb.get("layout") or "us").split(",")
    variants = (kb.get("variant") or "").split(",")
    pick = lambda xs: xs[idx] if idx < len(xs) else xs[0]
    return {
        "rules": kb.get("rules") or "",
        "model": kb.get("model") or "",
        "layout": pick(layouts) or "us",
        "variant": pick(variants),
        "options": kb.get("options") or "",
        "name": kb.get("active_keymap") or pick(layouts),
    }


def main():
    kb = main_keyboard() or {"rules": "", "model": "", "layout": "us", "variant": "", "options": "", "name": "English (US)"}

    xkb = ctypes.CDLL("libxkbcommon.so.0")
    xkb.xkb_context_new.restype = ctypes.c_void_p
    xkb.xkb_context_new.argtypes = [ctypes.c_int]
    xkb.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    xkb.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(RuleNames), ctypes.c_int]
    xkb.xkb_keymap_key_by_name.restype = ctypes.c_uint32
    xkb.xkb_keymap_key_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    xkb.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    xkb.xkb_keymap_key_get_syms_by_level.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
    xkb.xkb_keysym_to_utf8.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    xkb.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]

    ctx = xkb.xkb_context_new(0)
    enc = lambda s: s.encode() if s else None
    names = RuleNames(enc(kb["rules"]), enc(kb["model"]), enc(kb["layout"]), enc(kb["variant"]), enc(kb["options"]))
    keymap = xkb.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0) if ctx else None
    if not keymap:
        print(json.dumps({"name": kb["name"], "keys": {}}))
        return

    def sym_at(code, level):
        out = ctypes.POINTER(ctypes.c_uint32)()
        n = xkb.xkb_keymap_key_get_syms_by_level(keymap, code, 0, level, ctypes.byref(out))
        return out[0] if n > 0 else 0

    def utf8(sym):
        buf = ctypes.create_string_buffer(16)
        n = xkb.xkb_keysym_to_utf8(sym, buf, 16)
        return buf.value.decode("utf-8", "replace") if n > 0 else ""

    def sym_name(sym):
        buf = ctypes.create_string_buffer(64)
        n = xkb.xkb_keysym_get_name(sym, buf, 64)
        return buf.value.decode() if n > 0 else ""

    # Dead keys (^ ¨ on AZERTY) have no UTF-8 of their own; show the
    # accent they add instead of a blank cap.
    DEAD = {"dead_circumflex": "^", "dead_diaeresis": "¨", "dead_grave": "`",
            "dead_acute": "´", "dead_tilde": "~", "dead_cedilla": "¸"}

    def glyph(sym):
        return (utf8(sym) or DEAD.get(sym_name(sym), "")) if sym else ""

    keys = {}
    for name in PRINTABLE:
        code = xkb.xkb_keymap_key_by_name(keymap, name.encode())
        if not code:
            continue
        base, shift = sym_at(code, 0), sym_at(code, 1)
        keys[name] = {"code": code, "sym": sym_name(base), "base": glyph(base), "shift": glyph(shift)}

    print(json.dumps({"name": kb["name"], "keys": keys}, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
