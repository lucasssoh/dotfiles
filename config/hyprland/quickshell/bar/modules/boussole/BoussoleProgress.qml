import QtQuick
import "../../theme"
import "../../services"

// Progress per subject: sheets studied, exercises solved alone, reviews
// waiting, and the next exam with the sessions to spare before it.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState

    BoussoleText {
        visible: root.b.progress.length === 0
        width: parent.width
        text: root.b.tr("Nothing planned yet: choose files in Files.", "Rien de planifié pour l'instant : choisis des fichiers dans Fichiers.")
        color: DrawerTheme.secondary
    }

    component Bar: Item {
        id: bar
        property real value: 0
        width: parent.width
        height: 6
        Rectangle { anchors.fill: parent; radius: 3; color: DrawerTheme.accentStrong }
        Rectangle { width: parent.width * Math.max(0, Math.min(1, bar.value)); height: parent.height; radius: 3; color: DrawerTheme.primary }
    }

    Repeater {
        model: root.b.progress
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var d: modelData
            width: root.width
            height: col.implicitHeight + 28
            radius: 18
            color: "transparent"
            border.width: 1
            border.color: DrawerTheme.faint

            Column {
                id: col
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 8

                Row {
                    width: parent.width
                    BoussoleText {
                        width: parent.width - studied.implicitWidth
                        text: card.d.domain
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                    BoussoleText {
                        id: studied
                        text: card.d.studied + " / " + card.d.total
                        color: DrawerTheme.secondary
                        font.features: { "tnum": 1 }
                    }
                }
                Bar { value: card.d.total > 0 ? card.d.studied / card.d.total : 0 }
                BoussoleText {
                    width: parent.width
                    text: (card.d.exercises > 0
                              ? root.b.tr("Exercises solved alone: ", "Exercices réussis seul : ") + card.d.exercises_solo + " / " + card.d.exercises
                              : "")
                          + (card.d.reviews_due > 0
                              ? (card.d.exercises > 0 ? " · " : "") + card.d.reviews_due + root.b.tr(" reviews waiting", " révisions en attente")
                              : "")
                    visible: text !== ""
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                }
                BoussoleText {
                    visible: card.d.exam !== null
                    width: parent.width
                    text: card.d.exam
                        ? card.d.exam.title + " · " + card.d.exam.date + " · " + card.d.exam.days + root.b.tr(" days · ", " j · ")
                          + (card.d.exam.margin >= 0
                              ? root.b.tr("margin ", "marge de ") + card.d.exam.margin + root.b.tr(" sessions", " séances")
                              : (-card.d.exam.margin) + root.b.tr(" sessions short", " séances de retard"))
                        : ""
                    color: card.d.exam && card.d.exam.margin < 0 ? DrawerTheme.danger : DrawerTheme.primary
                    font.pixelSize: 13
                }
            }
        }
    }
}
