import QtQuick
import "../../theme"
import ".."   // GlassCard/GlassChip live one level up

// One row of the Ethernet section list. `modelData` is exactly one
// balise-src `WiredProfile` (dbus/types.rs) as JSON. Same one-action
// anatomy as the WiFi/Bluetooth rows: the row opens this profile's
// detail page, connect/disconnect lives there.
Rectangle {
    id: row

    // Entrance cascade -- see RevealPop.qml. `index` is the ListView's,
    // injected because it is declared required; +2 because the section
    // list's own header and master card take the first two slots ahead of
    // any row (BaliseSectionList.qml). RevealPop caps the accumulated
    // delay, so a thirty-network list does not turn into a queue.
    required property int index
    RevealPop { item: row; index: row.index + 2 }
    required property var modelData
    signal rowActivated()

    readonly property bool connected: !!modelData.is_active
    readonly property color accent: Ink.accent

    width: ListView.view ? ListView.view.width : 0
    height: 58
    radius: 14

    // Same glass edge every other block in this bar now carries --
    // see GlassCard.qml. Only the block itself goes through the lens;
    // any icon tile nested inside it is left plain, or the two
    // rims would sit 4px apart and read as noise.
    // Only while this is HOVERED or ON -- asked for: the glass is a
    // state cue, not decoration, so a zone nobody is touching and
    // nothing has switched on carries no edge at all. It also means
    // the layer is allocated only for the one element in play.
    layer.enabled: row.connected || rowArea.containsMouse
    layer.effect: GlassCard { radius: 14 }
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
            // ph-plugs-connected / ph-plugs, both already verified in
            // Ethernet.qml.
            text: row.connected ? String.fromCharCode(0xedde) : String.fromCharCode(0xedda)   // ph-network / ph-network-x
            color: row.connected ? row.accent : Ink.primary
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
            text: row.modelData.name || row.modelData.device_name || ""
            color: Ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: row.connected
                ? ("Connected" + (row.modelData.ip4_address ? " · " + row.modelData.ip4_address : ""))
                : (row.modelData.has_carrier ? "Cable plugged in" : "Unplugged")
            color: row.connected ? row.accent : Ink.secondary
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
