import QtQuick
import "../../theme"
import "../../services"

// Calendars: the timetable's iCal link, and the groups found in it to
// tick (TD 1, TP 1, group B…) -- never a pattern to write. Personal events
// come from khal on their own.
Column {
    id: root

    spacing: 12
    readonly property var b: BoussoleState
    readonly property var groups: root.b.settings.groups || ({})
    readonly property var cal: root.b.status.calendar || ({})

    BoussoleText {
        text: root.b.tr("Calendars", "Calendriers")
        font.pixelSize: 18
        font.weight: Font.Bold
    }

    BoussoleText {
        text: root.b.tr("Timetable link (iCal)", "Lien de l'emploi du temps (iCal)")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
    BoussoleField {
        id: url
        text: root.b.settings.calendar_url || ""
        placeholder: "https://…anonymous_cal.jsp?…"
        onAccepted: root.b.setSettings({ calendar_url: url.text.trim() || null })
    }
    BoussoleText {
        width: parent.width
        text: root.cal.error
            ? root.b.tr("Last download failed (", "Dernière récupération en échec (") + root.cal.error
              + root.b.tr("): the previous timetable is kept. A link that asks to log in will not work: take the export link from ADE's « Export » menu.",
                          ") : l'emploi du temps précédent est gardé. Un lien qui demande une connexion ne marche pas : prends le lien d'export du menu « Exporter » d'ADE.")
            : root.cal.age_minutes !== undefined && root.cal.age_minutes !== null
              ? root.b.tr("Seen ", "Vu il y a ") + root.cal.age_minutes + root.b.tr(" min ago, refreshed every hour from 6:00 to 20:00.", " min, relu toutes les heures de 6:00 à 20:00.")
              : root.b.tr("Enter saves the link and downloads it.", "Entrée enregistre le lien et le télécharge.")
        color: root.cal.error ? DrawerTheme.danger : DrawerTheme.secondary
        font.pixelSize: 12
    }

    BoussoleText {
        visible: root.b.families.length > 0
        width: parent.width
        text: root.b.tr("Your groups: tick yours in each family. A family left untouched keeps everything.",
                        "Tes groupes : coche le tien dans chaque famille. Une famille laissée telle quelle garde tout.")
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
            BoussoleText { text: fam.modelData.name; color: DrawerTheme.secondary; font.pixelSize: 12; font.weight: Font.Bold }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: fam.modelData.values
                    delegate: BoussoleChip {
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
            BoussoleText {
                width: parent.width
                text: fam.modelData.examples.join(" · ")
                color: DrawerTheme.muted
                font.pixelSize: 11
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
    }

    BoussoleText {
        width: parent.width
        text: root.b.tr("Your personal agenda (Super + A) counts as busy. Sessions go to khal's « etude » calendar, your courses to « cours »: both show in the calendar drawer.",
                        "Ton agenda perso (Super + A) compte comme occupé. Les séances vont dans le calendrier khal « etude », tes cours dans « cours » : les deux apparaissent dans le tiroir calendrier.")
        color: DrawerTheme.secondary
        font.pixelSize: 12
    }
}
