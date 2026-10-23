import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// Settings: language, objective, the course folder.
Column {
    id: root

    spacing: 12
    readonly property var b: ProgrammeState
    readonly property var s: root.b.settings

    component Section: ProgrammeText {
        color: DrawerTheme.secondary
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
    }

    ProgrammeText {
        text: root.b.tr("Settings", "Réglages")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    Section { text: root.b.tr("Language", "Langue") }
    Row {
        spacing: 6
        ProgrammeChip { text: "Français"; on: root.s.lang === "fr"; onClicked: root.b.setSettings({ lang: "fr" }) }
        ProgrammeChip { text: "English"; on: root.s.lang !== "fr"; onClicked: root.b.setSettings({ lang: "en" }) }
    }

    Section { text: root.b.tr("Objective", "Objectif") }
    Row {
        spacing: 6
        ProgrammeChip { text: root.b.tr("Pass", "Valider"); on: root.s.objective === "pass"; onClicked: root.b.setSettings({ objective: "pass" }) }
        ProgrammeChip { text: root.b.tr("Ranked", "Bien classé"); on: root.s.objective === "ranked"; onClicked: root.b.setSettings({ objective: "ranked" }) }
        ProgrammeChip { text: "Podium"; on: root.s.objective === "podium" || root.s.objective === undefined; onClicked: root.b.setSettings({ objective: "podium" }) }
    }
    ProgrammeText {
        width: parent.width
        text: root.s.objective === "pass"
            ? root.b.tr("A subject's work aims at its exam day.", "Le travail d'un module vise le jour de son examen.")
            : root.s.objective === "ranked"
              ? root.b.tr("A subject's work aims one session before its exam.", "Le travail d'un module vise une séance avant son examen.")
              : root.b.tr("A subject's work aims two sessions before its exam.", "Le travail d'un module vise deux séances avant son examen.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }

    Section { text: root.b.tr("Course folder", "Dossier de cours") }
    ProgrammeField {
        id: folder
        text: root.s.courses || ""
        placeholder: "~/courses/…"
        onAccepted: root.b.setSettings({ courses: folder.text.trim().replace(/^~/, Quickshell.env("HOME")) })
    }
    ProgrammeText {
        width: parent.width
        text: root.b.tr("One folder per subject, read only: {folder} in a subject's command.", "Un dossier par module, en lecture seule : {folder} dans la commande d'un module.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
}
