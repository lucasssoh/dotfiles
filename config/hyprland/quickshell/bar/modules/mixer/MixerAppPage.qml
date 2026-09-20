import QtQuick
import ".."          // DrawerGroupLabel / GlassCard
import "../balise"   // RevealPop
import "../../theme"
import "../../services"

// One application's equalizer, on a page of its own. Reached by the
// chevron on its row in the mixer's home page, and built on the same
// navigation Balise uses for a WiFi network or a bluetooth device: the
// list stays a list, and everything that would have bloated it lives one
// level down.
//
// That is the whole reason this file exists. The five faders, a preset
// picker and a switch came to about 260px, which on the home page sat
// between INPUT and PLAYING and pushed the application list off the
// bottom of any reasonable drawer -- for a control that is adjusted once
// per application and then left alone for weeks.
//
// `node` is looked up LIVE by the page that loads this, not snapshotted,
// so an application that stops and restarts while the page is open keeps
// working. It can legitimately be null -- the application quit while you
// were looking at its equalizer -- and everything below survives that:
// the profile is keyed on the NAME, which is still here.
Item {
    id: page

    // The live stream node, or null if it went away.
    property var node: null
    // The name the profile is filed under. Survives `node` going null,
    // which is exactly why it is a separate property and not read off the
    // node.
    property string appLabel: ""
    property string glyph: ""

    signal backRequested()

    readonly property var profile: MixerState.profileFor(page.appLabel)
    readonly property bool enabled: page.profile.enabled
    readonly property var gains: page.profile.gains
    readonly property bool custom: page.profile.preset === ""

    implicitHeight: content.implicitHeight

    // Writes go through the node when there is one. With the application
    // gone there is nothing to route and nothing to hear, but the profile
    // is still worth editing -- it is what will be applied when it comes
    // back -- so the setters are given the name instead.
    function setEnabled(on) { MixerState.setAppEqNamed(page.appLabel, on); }
    function setPreset(id)  { MixerState.setAppPresetNamed(page.appLabel, id); }
    function setBand(i, db) { MixerState.setAppBandNamed(page.appLabel, i, db); }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 14

        // ---- header: back, icon, name -------------------------------
        Item {
            id: header
            width: parent.width
            height: 34

            RevealPop { item: header; index: 0; fromScale: 1.0 }

            Text {
                id: back
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "\uE06E"   // lu-chevron-left
                color: backHit.containsMouse ? Ink.primary : Ink.secondary
                font.family: Fonts.iconPhosphor
                font.pixelSize: 18

                MouseArea {
                    id: backHit
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.backRequested()
                }
            }

            Text {
                id: appIcon
                anchors.left: back.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: page.glyph
                color: Ink.secondary
                font.family: Fonts.iconPhosphor
                font.pixelSize: 15
            }

            Text {
                anchors.left: appIcon.right
                anchors.leftMargin: 8
                anchors.right: eqSwitch.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: page.appLabel
                color: Ink.primary
                font.family: Fonts.ui
                font.pixelSize: 15
                font.bold: true
                elide: Text.ElideRight
            }

            // The switch for THIS application. There is no global one any
            // more: with a curve per application, a master would be a
            // fourth thing that can be off while three others say they are
            // on.
            MixerSwitch {
                id: eqSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: page.enabled
                onToggled: (v) => page.setEnabled(v)
            }
        }

        // ---- the chains are full ------------------------------------
        //
        // Only ever seen with four applications equalized at once. Said
        // plainly rather than by leaving a switch that turns on and does
        // nothing audible -- see 50-equalizer.conf for why the number is
        // finite at all.
        Text {
            id: fullWarning
            width: parent.width
            visible: page.enabled && MixerState.eqOverflow > 0
                     && MixerState._slotOf[page.appLabel] === undefined
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "All " + MixerState.slotCount + " equalizer chains are in use — "
                  + "turn one off on another application"
            color: Ink.danger
            font.family: Fonts.ui
            font.pixelSize: 11
            wrapMode: Text.WordWrap

            RevealPop { item: fullWarning; index: 1; fromScale: 1.0 }
        }

        // ---- the faders -----------------------------------------------
        Rectangle {
            id: eqCard
            width: parent.width
            height: 132
            radius: 14
            color: Surfaces.card

            RevealPop { item: eqCard; index: 2 }

            Row {
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.bottomMargin: 10
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Repeater {
                    model: MixerState.bandLabels
                    delegate: EqBand {
                        required property var modelData
                        required property int index
                        width: (eqCard.width - 16) / MixerState.bandLabels.length
                        height: parent.height
                        label: modelData
                        value: page.gains[index]
                        range: MixerState.bandRange
                        active: page.enabled
                        onMoved: (db) => page.setBand(index, db)
                    }
                }
            }
        }

        // ---- presets, at the bottom, always shown ---------------------
        //
        // A plain list, not a picker that unfolds. It was a picker -- a
        // chevron and a twenty-eight entry flow -- and that is precisely
        // what made this page restless: opening it changed the page height
        // by a couple of hundred pixels, and the drawer animated every one
        // of them. With ten entries the list fits, so it is simply here,
        // and nothing about this page moves except the faders.
        //
        // Below the faders rather than above them, asked for ("juste liste
        // en bas"), and it reads correctly that way too: the curve is the
        // subject and the presets are ways of setting it.
        Item {
            id: presetHeader
            width: parent.width
            height: 18

            DrawerGroupLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "PRESET"
                revealIndex: 3
            }

            // The only thing in the header, and it is text in a fixed-height
            // row, so it appearing changes nothing about the layout. With
            // the list below, a matching preset needs no label -- its chip
            // is lit. Custom has no chip to light, so it says so.
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: page.custom
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "Custom"
                color: Ink.muted
                font.family: Fonts.ui
                font.pixelSize: 11
            }
        }

        // Ten chips over a fixed number of rows, so this block is the same
        // height on every application and on every visit.
        Flow {
            id: presetFlow
            width: parent.width
            spacing: 6

            Repeater {
                model: MixerState.presets
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    required property int index
                    readonly property bool current:
                        page.profile.preset === chip.modelData.id

                    RevealPop { item: chip; index: 4 + chip.index; fromScale: 1.0 }

                    width: chipLabel.implicitWidth + 18
                    height: 24
                    radius: 12
                    color: chip.current
                        ? Surfaces.accentStrong
                        : (chipHit.containsMouse ? Surfaces.cardHover : Surfaces.card)
                    border.width: 1
                    border.color: chip.current ? Ink.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: chip.modelData.name
                        color: chip.current ? Ink.accent : Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: chipHit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.setPreset(chip.modelData.id)
                    }
                }
            }
        }
    }
}
