import QtQuick
import "../theme"
import "balise"   // RevealPop

// Small-caps group label above a block of tiles or rows -- the
// "CONNECTIVITÉ"/"OPTIONS"/"CONSOMMATION" rhythm, same typography
// BaliseSectionList.qml's own section headers use.
//
// Extracted from BaliseHome.qml's inline `component GroupLabel` alongside
// DrawerTile.qml, for the same reason: PowerHome.qml is a second drawer
// that needs the identical label, and two copies of a type face are two
// things to keep in step. BaliseHome aliases this now
// (`component GroupLabel: DrawerGroupLabel {}`); its call sites did not
// change.
Text {
    id: glabel

    property int revealIndex: 0
    RevealPop { item: glabel; index: glabel.revealIndex; fromScale: 1.0 }

    renderType: Text.NativeRendering
    font.hintingPreference: Font.PreferNoHinting
    color: Qt.rgba(1, 1, 1, 0.4)
    font.family: Fonts.ui
    font.pixelSize: 11
    font.bold: true
    font.letterSpacing: 1
}
