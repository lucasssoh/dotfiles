import QtQuick
import "../../theme"
import "../../services"

// Calendars: the timetable's iCal link, and the groups found in it to
// tick (TD 1, TP 1, group B…) -- never a pattern to write. Personal events
// come from khal on their own.
Column {
    id: root

    spacing: 12
    readonly property var b: ProgrammeState
    readonly property var groups: root.b.settings.groups || ({})
    readonly property var cal: root.b.status.calendar || ({})

    ProgrammeText {
        text: root.b.tr("Calendars", "Calendriers")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    ProgrammeText {
        text: root.b.tr("Timetable link (iCal)", "Lien de l'emploi du temps (iCal)")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
    ProgrammeField {
        id: url
        text: root.b.settings.calendar_url || ""
        placeholder: "https://…anonymous_cal.jsp?…"
        onAccepted: root.b.setSettings({ calendar_url: url.text.trim() || null })
    }
    ProgrammeText {
        width: parent.width
        text: root.cal.error
            ? root.b.tr("Download failed (", "Échec du téléchargement (") + root.cal.error
              + root.b.tr("). The previous timetable stays. If the link asks you to log in, use the one from ADE's Export menu.",
                          "). L'emploi du temps précédent reste. Si le lien demande de te connecter, prends celui du menu Exporter d'ADE.")
            : root.cal.age_minutes !== undefined && root.cal.age_minutes !== null
              ? root.b.tr("Updated ", "Mis à jour il y a ") + root.cal.age_minutes + root.b.tr(" min ago.", " min.")
              : root.b.tr("Press Enter to download it.", "Appuie sur Entrée pour le télécharger.")
        color: root.cal.error ? DrawerTheme.danger : DrawerTheme.secondary
        font.pixelSize: 12
    }

    ProgrammeText {
        visible: root.b.families.length > 0
        width: parent.width
        text: root.b.tr("Tick your group in each family. If you tick none, you keep all its courses.",
                        "Coche ton groupe dans chaque famille. Si tu n'en coches aucun, tu gardes tous ses cours.")
        font.weight: Font.Bold
    }
    Repeater {
        model: root.b.families
        delegate: Column {
            id: fam
            required property var modelData
            width: root.width
            spacing: 6
            readonly property var chosen: root.groups[modelData.name] || []
            ProgrammeText { text: fam.modelData.name; color: DrawerTheme.secondary; font.pixelSize: 12; font.weight: Font.Bold }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: fam.modelData.values
                    delegate: ProgrammeChip {
                        required property var modelData
                        text: modelData[0] + "  ·  " + modelData[1]
                        on: fam.chosen.indexOf(modelData[0]) !== -1
                        onClicked: {
                            const v = modelData[0];
                            const next = on ? fam.chosen.filter(x => x !== v) : fam.chosen.concat([v]);
                            const patch = { groups: {} };
                            patch.groups[fam.modelData.name] = next;
                            root.b.setSettings(patch);
                        }
                    }
                }
            }
            ProgrammeText {
                width: parent.width
                text: fam.modelData.examples.join(" · ")
                color: DrawerTheme.muted
                font.pixelSize: 11
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
    }

    ProgrammeText {
        width: parent.width
        text: root.b.tr("Nothing is planned during the events of your agenda (Super + A). Sessions and courses show in the calendar drawer.",
                        "Rien n'est prévu pendant les évènements de ton agenda (Super + A). Séances et cours apparaissent dans le tiroir calendrier.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
}
