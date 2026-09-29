pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// What the keybinds sheet draws: which physical key does what under SUPER
// and under SUPER+SHIFT, in the layout that is active right now. Joined
// ONCE here and read by every screen's KeybindsDrawerContent, so nothing
// is recomputed per bar and nothing at all runs while SUPER is held.
//
// Two sources, both pushed rather than polled:
//   - the binds: hypr/keybinds.lua exports every bind that has a
//     `description` to $XDG_RUNTIME_DIR/hypr-keybinds.json on each config
//     load (see its SHEET EXPORT block). Watched with inotify, so a
//     reload after an edit there is all it takes.
//   - the layout: tools/keymap.py asks libxkbcommon what each printable
//     key prints and which keysym it carries. Re-run at startup, on
//     Hyprland's `activelayout` (a layout switch) and whenever the binds
//     file changes (a config reload, which is also where kb_layout
//     itself would change). ~70 ms each time.
Singleton {
    id: root

    // [{mods: ["SUPER", "SHIFT"], key: "H", description: "Move left"}]
    property var binds: []
    // The layout's own name, e.g. "French (AZERTY)".
    property string layoutName: ""
    // Physical key name -> {code, sym, base, shift}, printable keys only.
    property var keys: ({})

    // Physical key name -> {super: "Focus left", shift: "Move left"}.
    // Either side may be missing. Keys that are not printable (Enter,
    // Space, Esc, Del, the Copilot key) are keyed by the names
    // KeybindsDrawerContent.qml draws them under.
    readonly property var sheet: {
        const byCode = {}, bySym = {};
        for (const id in root.keys) {
            const k = root.keys[id];
            byCode[k.code] = id;
            if (k.sym && !(k.sym.toLowerCase() in bySym)) bySym[k.sym.toLowerCase()] = id;
        }
        const out = {};
        for (const b of root.binds) {
            const mods = b.mods.map(m => m.toUpperCase()).sort().join("+");
            const layer = mods === "SUPER" ? "super" : (mods === "SHIFT+SUPER" ? "shift" : "");
            if (layer === "") continue;   // CTRL+F and the like: not on this sheet
            const id = root.physicalKey(b.key, byCode, bySym);
            if (id === "") continue;
            if (!out[id]) out[id] = {};
            out[id][layer] = b.description;
        }
        // The Copilot key sends SUPER+SHIFT+F23 on its own (see its bind);
        // pressed alone, so it reads the same on both layers.
        if (out.COPI && out.COPI.shift && !out.COPI.super) out.COPI.super = out.COPI.shift;
        return out;
    }

    readonly property var namedKeys: ({
        "return": "RTRN", "space": "SPCE", "escape": "ESC", "delete": "DELE",
        "backspace": "BKSP", "tab": "TAB", "f23": "COPI"
    })

    function physicalKey(key, byCode, bySym) {
        if (key.startsWith("code:")) return byCode[parseInt(key.slice(5), 10)] || "";
        const lower = key.toLowerCase();
        if (lower in root.namedKeys) return root.namedKeys[lower];
        if (/^f([1-9]|1[0-2])$/.test(lower)) return key.toUpperCase();
        return bySym[lower] || "";
    }

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-keybinds.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.binds = JSON.parse(text());
            } catch (e) {
                // Written by rename, so a half file should not happen;
                // if it does, keep the last good list.
            }
            root.refreshLayout();
        }
    }

    function refreshLayout() {
        if (keymapProc.running) {
            root._refreshAgain = true;
            return;
        }
        keymapProc.running = true;
    }
    property bool _refreshAgain: false

    Process {
        id: keymapProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/bar/tools/keymap.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    root.layoutName = d.name;
                    root.keys = d.keys;
                } catch (e) {
                    // Keep the last good layout rather than blanking the keys.
                }
            }
        }
        onRunningChanged: {
            if (!running && root._refreshAgain) {
                root._refreshAgain = false;
                root.refreshLayout();
            }
        }
    }

    // The binds file may not exist yet (Hyprland not reloaded since
    // boot); the layout is worth having regardless.
    Component.onCompleted: root.refreshLayout()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") root.refreshLayout();
        }
    }
}
