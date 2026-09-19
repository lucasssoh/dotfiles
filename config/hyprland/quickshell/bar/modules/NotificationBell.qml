import QtQuick
import "../theme"
import "../services"

// Bell icon for the TOOLS island's top row -- replaces the old
// StreamModule instance that shelled out to `swaync-client
// --subscribe-waybar` and parsed its waybar-JSON stream for icon state.
// Bound directly to NotificationState now: no external process, no
// polling, no JSON. Lives in TOOLS (moved from METRICS, asked for: "c'est
// là que se trouve le bouton notification" -- TOOLS is also where Balise
// lives, and TOOLS is now a DrawerIsland whose drawer hosts
// NotificationCenter, so the trigger and its drawer share one block).
//
// Same 4 icon/color states StreamModule's old classIcons/classColors
// map carried (minus "inhibited" -- an app-side "block all
// notifications" flag swaync surfaced that NotificationServer has no
// equivalent for; dnd already covers the "quieted" case that matters
// here). Glyphs are the exact same Phosphor codepoints reused verbatim
// from that old map (U+E0CE bell, U+E5EE bell-z), not re-picked from
// scratch. The UNSEEN state is the one exception: it was U+E5E8
// bell-ringing and is now U+E0D0 bell-simple (asked for) -- the ringing
// arcs were the loudest thing in TOOLS for a state the accent colour
// below already announces on its own.
Item {
    id: root

    // The ink ramp this module draws with. Points at the dark-material
    // singleton by default, which is what every call site below used
    // directly before this property existed -- so this changes nothing on
    // its own. It exists so the band's islands can hand a LIGHT ramp to
    // the modules sitting on them, per island, without touching any of
    // those call sites again. See theme/Ink.qml's MATERIAL note for why
    // the material flips rather than the ink alone.
    property QtObject ink: Ink

    property var screen: null

    // No `maxWidth` hint here (unlike Media.qml) -- DrawerIsland.qml's
    // `maxRowWidth` SUMS every top-row child's own maxWidth/implicitWidth
    // (it's "how wide could the whole row ever get", not "how wide does
    // one drawer need to be"), so inflating just this icon's own number
    // would blow the row out far past what's actually needed. TOOLS'
    // drawer (NotificationCenter.qml) is sized responsively to whatever
    // width the row's own real content naturally settles on instead.

    // UntypedObjectModel (trackedNotifications' real type) only declares
    // `values` (a plain QObjectList) -- no `count` property of its own
    // outside of a view's synthetic one (ListView.count etc.), so
    // `.count` here resolved to undefined. `.values.length` is the real,
    // always-defined property.
    readonly property int count: NotificationState.trackedNotifications.values.length
    readonly property bool hasUnseen: NotificationState.hasUnseen
    readonly property bool dnd: NotificationState.dnd

    // 6px of padding a side, matching Clock/Performance/ScriptModule in
    // this row -- asked for, after those two ("aligne la bell aussi").
    //
    // The `Math.max(..., 40)` this replaces was pure inflation: 40 always
    // won (label is 15 + 20 = 35), putting 12.5px a side here, the widest
    // in TOOLS, and the hole between the clock and this bell is what made
    // it visible. Nothing was riding on the floor either -- Phosphor is
    // monospaced, so all three bell glyphs below measure exactly the same
    // and this width never moves anyway. Still true under the Lucide test:
    // every Lucide glyph advances a flat 1em too (checked, not assumed).
    implicitWidth: label.implicitWidth + 12
    implicitHeight: 24

    readonly property string iconGlyph: {
        if (root.dnd) return "\uE05A";                        // lu-bell-off (sleeping)
        return root.hasUnseen ? "\uE42B" : "\uE059";   // lu-bell-dot (unseen) / lu-bell (idle)
    }
    // Unread used to ride the WEIGHT: solid while unread, outline once
    // read (asked for), which carried the state far harder than the glyph
    // choice did -- Phosphor's bell-simple and idle bell differ by a flat
    // bar versus a clapper, nearly nothing at 15px, whereas filled versus
    // hollow is unmissable. Lucide has no fill weight (no weights at all,
    // see Fonts.qml), so `iconFamily` now resolves to the same face both
    // ways and the state moved into the glyph instead: lu-bell-dot puts
    // a filled dot on the bell's shoulder, which is the one thing in
    // Lucide's bell family that reads at 15px. The branch below is kept
    // rather than collapsed so that reverting the Lucide test restores
    // the filled/hollow version with nothing else to put back.
    readonly property string iconFamily: root.hasUnseen
        ? Fonts.iconPhosphorFill
        : Fonts.iconPhosphor

    readonly property color iconColor: {
        if (root.hasUnseen) return root.ink.accent;
        return root.dnd ? root.ink.faint : root.ink.primary;
    }

    Text {
        id: label
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.centerIn: parent
        text: root.iconGlyph
        color: root.iconColor
        font.family: root.iconFamily
        font.pixelSize: 15
    }

    MouseArea {
        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) NotificationState.toggleDnd();
            else NotificationState.toggleNotificationCenter(root.screen);
        }
    }
}
