import QtQuick
import "../../theme"

// One row of the Bluetooth section list. `modelData` is exactly one
// balise-src `BluetoothDevice` (dbus/bluez.rs) as JSON. Same one-action
// anatomy as BaliseNetworkRow.qml (badge / name / status / chevron):
// the row opens this device's detail page, and connect/disconnect/
// forget live there. No pairing anywhere yet -- that needs the BlueZ
// agent bridged to QML, a separate pass.
Rectangle {
    id: row
    required property var modelData
    signal rowActivated()

    readonly property bool connected: !!modelData.is_connected
    readonly property bool paired: !!modelData.is_paired
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
            // ph-bluetooth-connected / ph-bluetooth, both already verified
            // in Bluetooth.qml.
            text: row.connected ? String.fromCharCode(0xe0dc) : String.fromCharCode(0xe0da)
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
            text: row.modelData.name || ""
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
                if (row.connected) {
                    const pct = row.modelData.battery_percentage;
                    return pct !== null && pct !== undefined ? "Connected · " + pct + "%" : "Connected";
                }
                return row.paired ? "Paired" : "Not paired";
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
