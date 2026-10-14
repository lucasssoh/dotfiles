import QtQuick
import "../theme"

// The drawers' glass pane, for the popups that float on their own (the
// OSD, the battery alert, Liseuse's picker, Sesame, the controller): the
// same veil and the same convex edge as DrawerIsland's drawerFill, so a
// popup and a drawer read as one material.
//
// Only the pane goes through the lens. The popup's content is a SIBLING
// laid over it, never a child, so its text and cards stay crisp, like the
// drawers' (see drawerFill there).
//
// The blur itself is the window's: whoever maps the popup asks Hyprland
// for it over this pane's bounds (shell.qml, BackgroundEffect.blurRegion).
// Without that the veil is 5% black over a sharp desktop.
Rectangle {
    id: pane

    // Thickness of the curved edge. The drawers' 14 suits anything from a
    // dial up; a 48px pill takes a thinner one.
    property real band: 14

    color: DrawerTheme.paneTop

    layer.enabled: pane.visible
    layer.effect: GlassLens {
        radius: pane.radius
        band: pane.band
        // The drawers' greyer, fainter edge.
        rimStrength: 0.22
        rimColor: "#8e8e93"
    }
}
