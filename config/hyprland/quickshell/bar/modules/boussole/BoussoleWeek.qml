import QtQuick
import "../../theme"
import "../../services"

// The week ahead, day by day, in the same rows as Today. Days without a
// session say so in a line rather than taking a card.
Column {
    id: root

    spacing: 16
    readonly property var b: BoussoleState

    BoussoleText {
        visible: root.b.week.length === 0
        text: "…"
        color: DrawerTheme.secondary
    }

    Repeater {
        model: root.b.week
        delegate: Column {
            id: day
            required property var modelData
            width: root.width
            spacing: 8
            readonly property var sessions: modelData.rows.filter(r => r.type !== "course")

            BoussoleText {
                text: day.modelData.label
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            BoussoleText {
                visible: day.sessions.length === 0
                text: root.b.tr("Nothing planned.", "Rien de prévu.")
                color: DrawerTheme.secondary
                font.pixelSize: 13
            }
            BoussoleDay {
                width: parent.width
                // Courses would crowd a week: sessions and offers only.
                rows: day.sessions
            }
        }
    }
}
