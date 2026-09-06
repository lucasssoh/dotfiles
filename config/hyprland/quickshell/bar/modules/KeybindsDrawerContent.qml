import QtQuick
import "../theme"

// Keybinds cheatsheet -- second consumer of DrawerIsland's drawer slot,
// asked for explicitly to prove out "un widget qui se déclenche dans cet
// endroit sans que ça ne soit forcement Veille": holding SUPER (see
// hypr/keybinds.lua's own "Super_L" bind, press = show / release = hide)
// drops this open instead of Veille's clock. Same contract as
// VeilleDrawerContent.qml -- sized by plain `width` (set externally by
// DrawerIsland), folds its own padding into `implicitHeight`.
//
// The list below is a hand-picked SUBSET of hypr/keybinds.lua (the ones
// used often enough to be worth a cheatsheet, not the full ~35), copied
// as plain data -- Quickshell can't execute/parse that Lua file at
// runtime, so there's no way to generate this automatically. Keep the
// two in sync by hand if a bind listed here ever changes over there.
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

    readonly property int hPad: 20
    readonly property int topGap: 10
    readonly property int bottomGap: 14
    readonly property int columns: 3
    readonly property int rowSpacing: 10
    readonly property int columnSpacing: 28
    readonly property int keySize: 13
    readonly property int labelSize: 13

    readonly property var binds: [
        { key: "⌘ Enter",     label: "Terminal" },
        { key: "⌘ E",         label: "Files" },
        { key: "⌘ B",         label: "Browser" },
        { key: "⌘ Space",     label: "Launcher" },
        { key: "⌘ V",         label: "Clipboard" },
        { key: "⌘ S",         label: "Screenshot" },
        { key: "⌘ Q",         label: "Close window" },
        { key: "⌘ F",         label: "Fullscreen" },
        { key: "⌘ ⇧ Space",   label: "Toggle floating" },
        { key: "⌘ HJKL",      label: "Move focus" },
        { key: "⌘ ⇧ HJKL",    label: "Move window" },
        { key: "⌘ R",         label: "Resize mode" },
        { key: "⌘ 1-0",       label: "Go to workspace" },
        { key: "⌘ ⇧ 1-0",     label: "Send to workspace" },
        { key: "⌘ U",         label: "Scratchpad" },
        { key: "⌘ Z",         label: "Zen mode" },
        { key: "⌘ Del",       label: "Power wheel" },
        { key: "⌘ O",         label: "Display wheel" }
    ]

    implicitHeight: root.topGap + grid.implicitHeight + root.bottomGap

    Grid {
        id: grid
        anchors.left: parent.left
        anchors.leftMargin: root.hPad
        anchors.top: parent.top
        anchors.topMargin: root.topGap
        width: Math.max(0, root.width - root.hPad * 2)
        columns: root.columns
        rowSpacing: root.rowSpacing
        columnSpacing: root.columnSpacing

        Repeater {
            model: root.binds

            Row {
                required property var modelData
                spacing: 10

                // Key and label are separated by WEIGHT (Semibold vs
                // Medium) as well as colour. The label was Light, which
                // is what Veille's message uses -- but that message is
                // set ~30px and this list is 13px, and Clash Grotesk
                // Light at 13px rendered with NativeRendering and no
                // hinting comes out too thin to read. Medium is the
                // lightest weight that holds up at this size; the key
                // moved up to Semibold to keep the two distinct now that
                // the label is no longer the thin one.
                Text {
                    text: modelData.key
                    color: "#f2ecd9"
                    font.family: Fonts.clockSemibold
                    font.pixelSize: root.keySize
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                }
                Text {
                    text: modelData.label
                    color: "#d5d0c0"
                    font.family: Fonts.clock
                    font.pixelSize: root.labelSize
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                }
            }
        }
    }
}
