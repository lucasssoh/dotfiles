import QtQuick
import "../theme"
import "../services"
import "balise"   // RevealPop

// Keybinds sheet -- an entry of the central island's drawer: holding SUPER
// (see hypr/keybinds.lua's "Super_L" bind, press = show / release = hide)
// opens it as a glass pane under the middle of the bar. Same contract as
// VeilleDrawerContent.qml -- sized by plain `width` (set externally by
// DrawerIsland), folds its own padding into `implicitHeight`.
//
// A drawn keyboard rather than a list, in the ACTIVE layout: the labels
// are the `description`s written next to each bind in keybinds.lua, the
// glyphs and positions come from libxkbcommon, and KeybindsState joins
// the two. So BÉPO moves H to the bottom row and the sheet moves "Focus
// left" with it; AZERTY prints & on the first workspace key and QWERTY 1.
//
// The compact board ("C", picked 2026-11-10 because the full ISO board
// was too heavy): only the keys that do something are drawn, each where
// it sits on the keyboard, and the block is packed against its leftmost
// one. Keys outside the letters (Esc, Del, Space, Enter, Copilot) come
// down into one low row, with Shift among them as the way to the second
// layer.
//
// Two layers, and the sheet shows the one the hands are on: SUPER alone,
// or SUPER+SHIFT once Shift joins (`shiftHeld`, fed by keybinds.lua's
// raw key watcher through shell.qml). A key with nothing on the current
// layer but something on the other dims instead of vanishing, so the
// board keeps its shape while it flips.
Item {
    id: root

    // DrawerIsland's drawer-entry contract -- see VeilleDrawerContent's
    // identical pair, and DrawerIsland's own header.
    property bool drawerOpen: false
    // Set by DrawerIsland while its drop reveal is moving: the pane does
    // the revealing then, and a stretch under it would fight it.
    property bool dropSnap: false
    Behavior on height {
        enabled: !root.dropSnap
        NumberAnimation { duration: 320; easing.type: Easing.InOutCubic }
    }
    // The keys land row by row as the pane zooms in.
    onDrawerOpenChanged: if (root.drawerOpen) BaliseReveal.replay()

    property bool shiftHeld: false

    // ---- geometry ------------------------------------------------------
    // One key unit is `pitch` px, `gap` of it being the space between
    // caps. 66 is what fits the longest label ("Programme") on a 1-unit
    // cap at 10 px.
    readonly property int pitch: 66
    readonly property int gap: 4
    readonly property int shortHeight: 26
    readonly property int hPad: 14
    readonly property int topGap: 12
    readonly property int bottomGap: 18

    // The width this entry asks the island for while it shows (see
    // DrawerIsland's `entryWidthWanted`).
    readonly property int drawerWidth: Math.ceil(root.boardWidth) + root.hPad * 2

    implicitHeight: root.topGap + root.layout.height + root.bottomGap

    // Keys drawn by name rather than by what the layout prints.
    readonly property var names: ({
        ESC: "Esc", DELE: "Del", BKSP: "⌫", TAB: "⇥", RTRN: "↵", LFSH: "⇧", SPCE: "", COPI: "Copilot",
        F1: "F1", F2: "F2", F3: "F3", F4: "F4", F5: "F5", F6: "F6",
        F7: "F7", F8: "F8", F9: "F9", F10: "F10", F11: "F11", F12: "F12"
    })

    // The printable block, row by row: [offset in units, keys]. ISO
    // stagger, the same on every layout.
    readonly property var letterRows: [
        [0, ["TLDE", "AE01", "AE02", "AE03", "AE04", "AE05", "AE06", "AE07", "AE08", "AE09", "AE10", "AE11", "AE12"]],
        [1.5, ["AD01", "AD02", "AD03", "AD04", "AD05", "AD06", "AD07", "AD08", "AD09", "AD10", "AD11", "AD12"]],
        [1.75, ["AC01", "AC02", "AC03", "AC04", "AC05", "AC06", "AC07", "AC08", "AC09", "AC10", "AC11", "BKSL"]],
        [1.25, ["LSGT", "AB01", "AB02", "AB03", "AB04", "AB05", "AB06", "AB07", "AB08", "AB09", "AB10"]]
    ]
    // The low row: [key, width in units]. Shift is always there; the
    // others only when bound. A bind on a key not listed here (F5, Tab)
    // joins the end of the row.
    readonly property var lowRow: [["ESC", 1.5], ["DELE", 2], ["LFSH", 1.5], ["SPCE", 2.5], ["RTRN", 1.5], ["COPI", 1.75]]
    readonly property var lowExtras: ["TAB", "BKSP", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]

    // The number row says one thing ten times ("Workspace 1" ... "Workspace
    // 10"). When every key of it shares one action but for its number, the
    // row goes half height, the caps keep only their glyphs, and the action
    // is written once after them. "" when they differ: the row is then
    // drawn like the others.
    readonly property var numberIds: ["AE01", "AE02", "AE03", "AE04", "AE05", "AE06", "AE07", "AE08", "AE09", "AE10"]
    function numberLabel(layer) {
        let label = null;
        for (const id of root.numberIds) {
            const a = KeybindsState.sheet[id];
            const text = a ? (a[layer] || "") : "";
            if (text === "") return "";
            const stem = text.replace(/\s*\d+$/, "");
            if (label === null) label = stem;
            else if (label !== stem) return "";
        }
        return label || "";
    }
    readonly property string numberLabelSuper: root.numberLabel("super")
    readonly property string numberLabelShift: root.numberLabel("shift")
    readonly property bool numberRowShort: root.numberLabelSuper !== ""

    // Every drawn cap with its rectangle, the board's size, and where the
    // number row's label starts. Recomputed only when the binds or the
    // layout change, never while SUPER is held.
    readonly property var layout: {
        const sheet = KeybindsState.sheet;
        const P = root.pitch, G = root.gap;
        const caps = [];
        let y = 0, minX = Infinity;
        for (let r = 0; r < root.letterRows.length; r++) {
            const isShort = r === 0 && root.numberRowShort;
            const h = isShort ? root.shortHeight : P - G;
            let x = root.letterRows[r][0];
            for (const id of root.letterRows[r][1]) {
                if (sheet[id]) {
                    caps.push({ id: id, x: x * P, y: y, w: P - G, h: h, isShort: isShort, bare: isShort, row: r });
                    minX = Math.min(minX, x * P);
                }
                x += 1;
            }
            y += h + G;
        }
        if (minX === Infinity) minX = 0;
        let width = 0, labelX = 0;
        for (const c of caps) {
            c.x -= minX;
            width = Math.max(width, c.x + c.w);
            if (c.row === 0) labelX = Math.max(labelX, c.x + c.w);
        }
        const low = root.lowRow.slice();
        for (const id of root.lowExtras) {
            if (sheet[id]) low.push([id, 1.5]);
        }
        let x = 0;
        for (const [id, w] of low) {
            if (id !== "LFSH" && !sheet[id]) continue;
            caps.push({ id: id, x: x * P, y: y, w: w * P - G, h: root.shortHeight, isShort: true, bare: false, row: root.letterRows.length });
            x += w;
        }
        width = Math.max(width, x * P - G);
        return { caps: caps, width: width, height: y + root.shortHeight, labelX: labelX };
    }
    // Wide enough for the longer of the two labels, so the pane does not
    // change width when Shift joins.
    readonly property real boardWidth: Math.max(root.layout.width, root.numberRowShort
        ? root.layout.labelX + 8 + Math.max(labelSuperMeasure.implicitWidth, labelShiftMeasure.implicitWidth) : 0)

    Text { id: labelSuperMeasure; visible: false; text: root.numberLabelSuper; font.family: Fonts.ui; font.pixelSize: 11 }
    Text { id: labelShiftMeasure; visible: false; text: root.numberLabelShift; font.family: Fonts.ui; font.pixelSize: 11 }

    // ---- the board -----------------------------------------------------
    Item {
        id: board
        anchors.top: parent.top
        anchors.topMargin: root.topGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.boardWidth
        height: root.layout.height

        Text {
            id: numberLabelText
            visible: root.numberRowShort
            x: root.layout.labelX + 8
            height: root.shortHeight
            verticalAlignment: Text.AlignVCenter
            text: root.shiftHeld ? root.numberLabelShift : root.numberLabelSuper
            color: DrawerTheme.islandMuted
            font.family: Fonts.ui
            font.pixelSize: 11
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            RevealPop { item: numberLabelText; index: 0; fromScale: 1.0 }
        }

        Repeater {
            model: root.layout.caps

            // The slot is what the cascade pops; the cap inside keeps its
            // own opacity for the dimmed keys.
            Item {
                id: slot
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h

                RevealPop { item: slot; index: slot.modelData.row * 2 }

                Rectangle {
                    id: cap
                    anchors.fill: parent
                    readonly property string keyId: slot.modelData.id
                    readonly property bool isShort: slot.modelData.isShort
                    readonly property var printed: KeybindsState.keys[cap.keyId] || null
                    readonly property var actions: KeybindsState.sheet[cap.keyId] || null
                    // Shift, in the low row: the way to the second layer,
                    // and the one key drawn pressed once it is held.
                    readonly property bool isShift: cap.keyId === "LFSH"
                    readonly property bool held: cap.isShift && root.shiftHeld
                    readonly property string action: cap.isShift ? (cap.held ? "" : "More")
                        : cap.actions ? ((root.shiftHeld ? cap.actions.shift : cap.actions.super) || "") : ""
                    readonly property bool lit: cap.action !== "" && !cap.isShift
                    // Bound on the other layer only: dimmed, so the board
                    // keeps its shape while it flips.
                    readonly property bool elsewhere: !cap.lit && !cap.isShift

                    radius: 9
                    // A bound key is a veil of light on the glass, with no
                    // outline; the held Shift inverts, the one small
                    // light area on the sheet. Everything else is a
                    // hairline.
                    color: cap.held ? DrawerTheme.cream
                        : cap.lit ? DrawerTheme.islandKey : DrawerTheme.clear(DrawerTheme.cream)
                    border.width: cap.lit || cap.held ? 0 : 1
                    border.color: DrawerTheme.creamInk(0.12)
                    opacity: cap.elsewhere ? 0.5 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    readonly property color ink: cap.held ? "#0c0c0e"
                        : cap.lit ? DrawerTheme.cream
                        : cap.isShift ? DrawerTheme.cream2 : DrawerTheme.islandFaint

                    // What the key prints: its name for the fixed keys,
                    // the layout's glyph otherwise -- letters upper-cased
                    // like a real cap, the Shift glyph beside it when it
                    // is not just that upper case (& and 1, é and 2...).
                    readonly property bool named: cap.keyId in root.names
                    readonly property string glyph: {
                        if (cap.named) return root.names[cap.keyId];
                        if (!cap.printed) return "";
                        const b = cap.printed.base;
                        return b.toUpperCase() !== b ? b.toUpperCase() : b;
                    }
                    readonly property string glyph2: {
                        if (cap.named || !cap.printed || !cap.printed.shift) return "";
                        const b = cap.printed.base, s = cap.printed.shift;
                        return s === b.toUpperCase() ? "" : s;
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.top: cap.isShort ? undefined : parent.top
                        anchors.topMargin: 6
                        anchors.verticalCenter: cap.isShort ? parent.verticalCenter : undefined
                        spacing: 5

                        Text {
                            id: glyphText
                            visible: cap.glyph !== ""
                            text: cap.glyph
                            color: cap.ink
                            font.family: Fonts.ui
                            font.pixelSize: cap.named ? 11 : 13
                            font.weight: cap.named ? Font.Medium : Font.DemiBold
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            visible: cap.glyph2 !== ""
                            anchors.baseline: glyphText.baseline
                            text: cap.glyph2
                            color: cap.ink
                            opacity: 0.6
                            font.family: Fonts.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                        }
                        // On a low cap the action sits beside the name
                        // ("Esc  Lock") -- there is no room under it. The
                        // number row prints none: its label says it once.
                        Text {
                            visible: cap.isShort && !slot.modelData.bare && cap.action !== ""
                            text: cap.action
                            color: cap.ink
                            font.family: Fonts.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }

                    // One size for every cap and one line: keep the
                    // descriptions in keybinds.lua to a word or two.
                    Text {
                        visible: !cap.isShort && cap.lit
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 5
                        anchors.bottomMargin: 7
                        text: cap.action
                        color: cap.ink
                        font.family: Fonts.ui
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }
        }
    }
}
