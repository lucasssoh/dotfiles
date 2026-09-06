import QtQuick
import "../../theme"

// One row of the Ethernet section list. `modelData` is exactly one
// balise-src `WiredProfile` (dbus/types.rs) as JSON. Same one-action
// anatomy as the WiFi/Bluetooth rows: the row opens this profile's
// detail page, connect/disconnect lives there.
Rectangle {
    id: row
    required property var modelData
    signal rowActivated()

    readonly property bool connected: !!modelData.is_active
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
            // ph-plugs-connected / ph-plugs, both already verified in
            // Ethernet.qml.
            text: row.connected ? String.fromCharCode(0xeb5a) : String.fromCharCode(0xeb56)
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
            text: row.modelData.name || row.modelData.device_name || ""
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
            text: row.connected
                ? ("Connected" + (row.modelData.ip4_address ? " · " + row.modelData.ip4_address : ""))
                : (row.modelData.has_carrier ? "Cable plugged in" : "Unplugged")
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
