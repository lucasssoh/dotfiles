import QtQuick
import "../../theme"

// Boussole's text: the drawers' font and ink, wrapped.
Text {
    renderType: Text.NativeRendering
    font.hintingPreference: Font.PreferNoHinting
    font.family: Fonts.ui
    font.pixelSize: 14
    color: DrawerTheme.primary
    wrapMode: Text.WordWrap
}
