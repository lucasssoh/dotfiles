import QtQuick
import "../../theme"

// One row of the WiFi section list. `modelData` is exactly one
// balise-src `AccessPoint` (dbus/types.rs) as JSON -- snake_case fields
// read straight off it, no local wrapping type. Signal only (no
// BaliseState import here), same "presentation-only, consumer wires the
// action" split NotificationCard.qml already uses for its own
// domain-specific rows.
//
// Layout follows the user's own mockup, monochrome: icon badge, name (+
// a lock mark when secured), status line, and a chevron on the right.
// The row has ONE action -- open this network's detail page -- with
// connect/disconnect living there rather than as a second competing
// target on the row itself ("suivre la maquette : chevron seul").
Rectangle {
    id: row
    required property var modelData
    signal rowActivated()

    readonly property bool connected: !!modelData.is_connected
    readonly property bool secured: modelData.security !== "none"
    readonly property color accent: "#a8b4c4"

    width: ListView.view ? ListView.view.width : 0
    height: 58
    radius: 14
    color: row.connected
        ? rowArea.containsMouse ? Surfaces.accentStrong : Surfaces.accentSoft
        : (rowArea.containsMouse ? Surfaces.cardHover : Surfaces.card)
    border.width: 1
    border.color: row.connected ? Qt.rgba(0xa8 / 255, 0xb4 / 255, 0xc4 / 255, 0.55) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.rowActivated()
    }

    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        radius: 10
        color: row.connected ? Surfaces.accentStrong : Surfaces.cardHover

        Text {
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            // ph-wifi-low/medium/high, same 3 tiers + thresholds as
            // Network.qml's own icon() (Phosphor ships no more than 3).
            text: {
                const s = row.modelData.signal || 0;
                if (s < 33) return String.fromCharCode(0xe4ec);
                if (s < 66) return String.fromCharCode(0xe4ee);
                return String.fromCharCode(0xe4ea);
            }
            color: row.connected ? row.accent : "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 17
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: chevron.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            // "·" marks a secured network rather than a padlock glyph --
            // Phosphor's own lock codepoint isn't verified anywhere in
            // this bar yet, and the security type is spelled out on the
            // status line right below anyway.
            text: row.modelData.ssid || ""
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: {
                const sec = row.secured ? String(row.modelData.security || "").toUpperCase() : "Open";
                if (row.connected) return "Connected · " + sec;
                const saved = row.modelData.is_saved ? " · Saved" : "";
                return sec + " · " + (row.modelData.signal || 0) + "%" + saved;
            }
            color: row.connected ? row.accent : "#8e8e93"
            font.family: Fonts.ui
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    Text {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: "›"
        color: Qt.rgba(1, 1, 1, rowArea.containsMouse ? 0.6 : 0.3)
        font.family: Fonts.ui
        font.pixelSize: 17
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
