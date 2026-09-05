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
// from that old map (U+E5E8 bell-ringing, U+E0CE bell, U+E5EE bell-z),
// not re-picked from scratch.
Item {
    id: root

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

    implicitWidth: Math.max(label.implicitWidth + 20, 40)
    implicitHeight: 24

    readonly property string iconGlyph: {
        if (root.dnd) return "";                          // bell-z (sleeping)
        return root.hasUnseen ? "" : "";             // bell-ringing / plain bell
    }
    readonly property color iconColor: {
        if (root.hasUnseen) return "#a8b4c4";
        return root.dnd ? "#48484a" : "#f2f2f7";
    }

    Text {
        id: label
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        anchors.centerIn: parent
        text: root.iconGlyph
        color: root.iconColor
        font.family: Fonts.iconPhosphor
        font.pixelSize: 15
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) NotificationState.toggleDnd();
            else NotificationState.toggleNotificationCenter(root.screen);
        }
    }
}
