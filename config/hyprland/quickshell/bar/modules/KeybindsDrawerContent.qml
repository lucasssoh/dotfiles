import QtQuick
import "../theme"
import "../services"

// Keybinds sheet -- second consumer of DrawerIsland's drawer slot:
// holding SUPER (see hypr/keybinds.lua's "Super_L" bind, press = show /
// release = hide) drops it open under the central island. Same contract
// as VeilleDrawerContent.qml -- sized by plain `width` (set externally by
// DrawerIsland), folds its own padding into `implicitHeight`.
//
// A drawn keyboard rather than a list (the "Calque Shift" mockup, picked
// 2026-09-29): an ISO board in the ACTIVE layout, every bound key lit
// with what it does. Nothing here is hand-copied any more -- the labels
// are the `description`s written next to each bind in keybinds.lua, the
// glyphs and positions come from libxkbcommon, and KeybindsState joins
// the two. So BÉPO moves H to the bottom row and the sheet moves "Focus
// left" with it; AZERTY prints & on the first workspace key and QWERTY 1.
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
    // Kept equal to centerIsland's own `revealDuration` (its default,
    // 320 -- centerIsland overrides none of DrawerIsland's timings).
    Behavior on height {
        NumberAnimation { duration: 320; easing.type: Easing.InOutCubic }
    }

    property bool shiftHeld: false

    // ---- geometry ------------------------------------------------------
    // One key unit is `pitch` px, `gap` of it being the space between
    // caps; every row is 15 units wide (ISO). 70 is what fits
    // the longest label on a single 1-unit cap at 10 px.
    readonly property int pitch: 70
    readonly property int gap: 5
    readonly property int fnHeight: 30
    readonly property int hPad: 25
    readonly property int topGap: 12
    readonly property int headGap: 12
    readonly property int bottomGap: 22
    readonly property int boardWidth: 15 * root.pitch - root.gap
    readonly property int boardHeight: root.fnHeight + 5 * root.pitch

    // The width this entry asks the island for while it shows (see
    // DrawerIsland's `entryWidthFloor`). The island normally opens to its
    // row's widest, 520 to 760 px; the board needs its full 15 units.
    readonly property int drawerWidth: root.boardWidth + root.hPad * 2

    implicitHeight: root.topGap + header.height + root.headGap + root.boardHeight + root.bottomGap

    // [name, width in units] per row. RTRN reserves the ISO Enter's wide
    // top half in its row but is not drawn; RTRN2 is the Enter itself, one
    // cap spanning both rows. A true L was drawn as two overlapping caps
    // until the caps became outlines -- the overlap then showed as a seam.
    readonly property var rows: [
        [["ESC", 1], ["F1", 1], ["F2", 1], ["F3", 1], ["F4", 1], ["F5", 1], ["F6", 1], ["F7", 1],
         ["F8", 1], ["F9", 1], ["F10", 1], ["F11", 1], ["F12", 1], ["DELE", 2]],
        [["TLDE", 1], ["AE01", 1], ["AE02", 1], ["AE03", 1], ["AE04", 1], ["AE05", 1], ["AE06", 1],
         ["AE07", 1], ["AE08", 1], ["AE09", 1], ["AE10", 1], ["AE11", 1], ["AE12", 1], ["BKSP", 2]],
        [["TAB", 1.5], ["AD01", 1], ["AD02", 1], ["AD03", 1], ["AD04", 1], ["AD05", 1], ["AD06", 1],
         ["AD07", 1], ["AD08", 1], ["AD09", 1], ["AD10", 1], ["AD11", 1], ["AD12", 1], ["RTRN", 1.5]],
        [["CAPS", 1.75], ["AC01", 1], ["AC02", 1], ["AC03", 1], ["AC04", 1], ["AC05", 1], ["AC06", 1],
         ["AC07", 1], ["AC08", 1], ["AC09", 1], ["AC10", 1], ["AC11", 1], ["BKSL", 1], ["RTRN2", 1.25]],
        [["LFSH", 1.25], ["LSGT", 1], ["AB01", 1], ["AB02", 1], ["AB03", 1], ["AB04", 1], ["AB05", 1],
         ["AB06", 1], ["AB07", 1], ["AB08", 1], ["AB09", 1], ["AB10", 1], ["RTSH", 2.75]],
        [["LCTL", 1.5], ["LWIN", 1.25], ["LALT", 1.25], ["SPCE", 6.5], ["RALT", 1.25], ["COPI", 1.25], ["RCTL", 2]]
    ]

    // Keys drawn by name rather than by what the layout prints.
    readonly property var names: ({
        ESC: "Esc", DELE: "Del", BKSP: "⌫", TAB: "⇥", RTRN: "", RTRN2: "↵", CAPS: "Caps",
        LFSH: "⇧", RTSH: "⇧", LCTL: "Ctrl", LWIN: "Super", LALT: "Alt", SPCE: "",
        RALT: "AltGr", COPI: "Copilot", RCTL: "Ctrl",
        F1: "F1", F2: "F2", F3: "F3", F4: "F4", F5: "F5", F6: "F6",
        F7: "F7", F8: "F8", F9: "F9", F10: "F10", F11: "F11", F12: "F12"
    })

    // Flattened to one list of caps with their rectangles, once -- the
    // geometry never changes, only what is printed on it.
    readonly property var caps: {
        const out = [];
        let y = 0;
        for (let r = 0; r < root.rows.length; r++) {
            const h = r === 0 ? root.fnHeight - root.gap : root.pitch - root.gap;
            let x = 0;
            for (const [id, w] of root.rows[r]) {
                if (id === "RTRN") { x += w; continue; }
                const cap = { id: id, x: x * root.pitch, y: y, w: w * root.pitch - root.gap, h: h };
                // Enter starts in the row above and spans both.
                if (id === "RTRN2") { cap.y = y - root.pitch; cap.h = h + root.pitch; }
                out.push(cap);
                x += w;
            }
            y += h + root.gap;
        }
        return out;
    }

    // ---- header --------------------------------------------------------
    Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: root.topGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.boardWidth
        height: layoutLabel.implicitHeight

        Text {
            id: layoutLabel
            anchors.left: parent.left
            text: KeybindsState.layoutName
            color: DrawerTheme.cream2
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }
        Text {
            anchors.right: parent.right
            anchors.baseline: layoutLabel.baseline
            text: root.shiftHeld ? "Super + Shift" : "Super · hold ⇧ for the second layer"
            color: DrawerTheme.muted
            font.family: Fonts.ui
            font.pixelSize: 13
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    // ---- the board -----------------------------------------------------
    Item {
        id: board
        anchors.top: header.bottom
        anchors.topMargin: root.headGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.boardWidth
        height: root.boardHeight

        Repeater {
            model: root.caps

            Rectangle {
                id: cap
                required property var modelData
                readonly property string keyId: modelData.id
                readonly property var printed: KeybindsState.keys[cap.keyId] || null
                // Enter's two halves share one set of actions.
                readonly property var actions: KeybindsState.sheet[cap.keyId === "RTRN2" ? "RTRN" : cap.keyId] || null
                readonly property string action: cap.actions
                    ? ((root.shiftHeld ? cap.actions.shift : cap.actions.super) || "") : ""
                readonly property bool held: cap.keyId === "LWIN"
                    || (root.shiftHeld && (cap.keyId === "LFSH" || cap.keyId === "RTSH"))
                readonly property bool lit: cap.action !== ""
                // Bound on the other layer only: dimmed, so the board
                // keeps its shape while it flips.
                readonly property bool elsewhere: !cap.lit && cap.actions !== null
                readonly property bool isFn: modelData.y === 0

                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                radius: 10
                // A bound key is OUTLINED, not filled: 50-odd white caps
                // made the sheet a white slab over the screen ("le blanc
                // est un peu trop visible"). The contour still sorts bound
                // from unbound at a glance; the held modifiers take the
                // raised grey instead, so they read as pressed rather than
                // as one more bound key.
                color: cap.held ? DrawerTheme.cardRaised : DrawerTheme.card
                border.width: cap.lit ? 1.5 : 0
                border.color: DrawerTheme.creamInk(0.55)
                opacity: cap.elsewhere ? 0.55 : 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                // Cream like Veille's, the other drawer under the island.
                readonly property color ink: (cap.lit || cap.held) ? DrawerTheme.cream : DrawerTheme.faint

                // What the key prints: its name for the fixed keys, the
                // layout's glyph otherwise -- letters upper-cased like a
                // real cap, the Shift glyph beside it when it is not just
                // that upper case (& and 1, é and 2...).
                readonly property string glyph: {
                    if (cap.keyId in root.names) return root.names[cap.keyId];
                    if (!cap.printed) return "";
                    const b = cap.printed.base;
                    return b.toUpperCase() !== b ? b.toUpperCase() : b;
                }
                readonly property string glyph2: {
                    if (!cap.printed || !cap.printed.shift) return "";
                    const b = cap.printed.base, s = cap.printed.shift;
                    return s === b.toUpperCase() ? "" : s;
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.top: cap.isFn ? undefined : parent.top
                    anchors.topMargin: 6
                    anchors.verticalCenter: cap.isFn ? parent.verticalCenter : undefined
                    spacing: 5

                    Text {
                        id: glyphText
                        text: cap.glyph
                        color: cap.ink
                        font.family: Fonts.ui
                        font.pixelSize: (cap.keyId in root.names) ? 11 : 14
                        font.weight: (cap.keyId in root.names) ? Font.Medium : Font.DemiBold
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
                    // On the short function row the action sits beside
                    // the name ("Esc  Lock") -- there is no room under it.
                    Text {
                        visible: cap.isFn && cap.lit
                        anchors.baseline: glyphText.baseline
                        text: cap.action
                        color: cap.ink
                        font.family: Fonts.ui
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }

                Text {
                    visible: !cap.isFn && cap.lit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 7
                    anchors.rightMargin: 3
                    anchors.bottomMargin: 7
                    text: cap.action
                    color: cap.ink
                    font.family: Fonts.ui
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    lineHeight: 0.9
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    // One size for every cap, wrapping onto a second line
                    // ("Toggle split") -- shrinking the long ones to fit
                    // was tried and left the board in five sizes. A single
                    // word too wide for a 1-unit cap elides, so keep the
                    // descriptions in keybinds.lua short.
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                }
            }
        }
    }
}
