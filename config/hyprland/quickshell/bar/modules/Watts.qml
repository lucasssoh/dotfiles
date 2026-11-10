import QtQuick
import "../theme"
import "../services"

// What the machine draws, from Pouls (it reads the battery every 3 s and
// averages over ~15 s). On battery only: hidden on mains, where the battery
// reports its charge rate rather than the machine's draw.

Item {
    id: root

    // See Memory.qml.
    property QtObject ink: Ink

    implicitWidth: row.implicitWidth + 12
    implicitHeight: 24
    visible: SystemStats.hasWatts

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        StatReadout {
            value: SystemStats.watts.toFixed(1)
            widest: "99.9"
            unit: "W"
            valueColor: root.ink.primary
        }
    }
}
