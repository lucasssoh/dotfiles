import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// Settings: language, objective, the game lock, the course folder.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property var s: root.b.settings

    component Section: BoussoleText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    BoussoleText {
        text: root.b.tr("Settings", "Réglages")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    Section { text: root.b.tr("Language", "Langue") }
    Row {
        spacing: 6
        BoussoleChip { text: "Français"; on: root.s.lang === "fr"; onClicked: root.b.setSettings({ lang: "fr" }) }
        BoussoleChip { text: "English"; on: root.s.lang !== "fr"; onClicked: root.b.setSettings({ lang: "en" }) }
    }

    Section { text: root.b.tr("Objective", "Objectif") }
    Row {
        spacing: 6
        BoussoleChip { text: root.b.tr("Pass", "Valider"); on: root.s.objective === "pass"; onClicked: root.b.setSettings({ objective: "pass" }) }
        BoussoleChip { text: root.b.tr("Ranked", "Bien classé"); on: root.s.objective === "ranked"; onClicked: root.b.setSettings({ objective: "ranked" }) }
        BoussoleChip { text: "Podium"; on: root.s.objective === "podium" || root.s.objective === undefined; onClicked: root.b.setSettings({ objective: "podium" }) }
    }
    BoussoleText {
        width: parent.width
        text: root.s.objective === "pass"
            ? root.b.tr("Exam-type subjects from 2 weeks before, no margin kept.", "Sujets type examen dès 2 semaines avant, pas de marge gardée.")
            : root.s.objective === "ranked"
              ? root.b.tr("Exam-type subjects from 3 weeks before, one session of margin.", "Sujets type examen dès 3 semaines avant, une séance de marge.")
              : root.b.tr("Same hours, but a sheet is acquired only with its exercises solved alone; exam-type subjects from 4 weeks before; two sessions of margin before each exam.",
                          "Autant d'heures, mais une fiche n'est acquise qu'avec ses exercices réussis seul ; sujets type examen dès 4 semaines avant ; deux séances de marge avant chaque examen.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }

    Section { text: root.b.tr("Games during a session", "Jeux pendant une séance") }
    Row {
        spacing: 6
        BoussoleChip { text: root.b.tr("Ask first", "Demander d'abord"); on: root.s.gate !== false; onClicked: root.b.setSettings({ gate: true }) }
        BoussoleChip { text: root.b.tr("Never ask", "Ne jamais demander"); on: root.s.gate === false; onClicked: root.b.setSettings({ gate: false }) }
    }

    Section { text: root.b.tr("Course folder", "Dossier de cours") }
    BoussoleField {
        id: folder
        text: root.s.courses || ""
        placeholder: "~/courses/…"
        onAccepted: root.b.setSettings({ courses: folder.text.trim().replace(/^~/, Quickshell.env("HOME")) })
    }
    BoussoleText {
        width: parent.width
        text: root.b.tr("Read only: Boussole never writes in it.", "En lecture seule : Boussole n'y écrit jamais.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
}
