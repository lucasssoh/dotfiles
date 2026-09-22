import QtQuick
import Quickshell
import "../theme"
import "../services"

// Native replacement for waybar/scripts/apps.sh: instead of a pgrep-based
// script producing a flat icon string, this reads Hyprland.toplevels
// directly (already live/reactive, zero exec, zero poll) and keeps each
// matched app's window address around -- so unlike apps.sh, every icon
// here is its own clickable chip that raises/focuses that window.
//
// Icons: Steam/Discord/Vesktop keep their existing Nerd Font glyphs
// (real dedicated icons already). Lutris and Heroic Games Launcher
// don't have one -- Simple Icons has both, but Simple Icons isn't part
// of the Nerd Fonts glyph set at all (checked glyphnames.json directly,
// no "si-" prefix present), which is why apps.sh fell back to sharing
// a generic gamepad glyph between them. Real logos instead, as actual
// SVGs (assets/lutris.svg, assets/heroic.svg -- pulled from Simple
// Icons, CC0), rendered as Image rather than Text for those two.
//
// The matching itself (which classes count as which app, each one's
// window address and pid, and the refreshToplevels that has to happen
// before any of it can be read) moved to services/
// LauncherActionsState.qml -- see there, including the lastIpcObject
// staleness trap Hdr.qml hit first. What is left here is the drawing
// and the two click actions.

Item {
    id: root

    // The ink ramp this module draws with. Points at the dark-material
    // singleton by default, which is what every call site below used
    // directly before this property existed -- so this changes nothing on
    // its own. It exists so the band's islands can hand a LIGHT ramp to
    // the modules sitting on them, per island, without touching any of
    // those call sites again. See theme/Ink.qml's MATERIAL note for why
    // the material flips rather than the ink alone.
    property QtObject ink: Ink

    // Which screen this instance is on -- one Launchers exists per
    // monitor, and the actions drawer opens on the one whose chip was
    // clicked, same `screen` plumbing BaliseButton/NotificationBell
    // already carry for their own drawers.
    property var screen: null

    // The app list, the window addresses and the pids all live in
    // services/LauncherActionsState.qml now, not here. Moved rather than
    // copied when the actions drawer arrived: this module is
    // instantiated once PER MONITOR, so the toplevel scan (and the
    // refreshToplevels that has to precede it) was being done twice on a
    // two-screen setup to produce two identical lists -- and the drawer
    // needed the same list from outside this module anyway. Same
    // argument SystemStats.qml's header makes for centralizing the
    // samplers. Everything this file draws below is unchanged.
    readonly property var matches: LauncherActionsState.matches

    implicitWidth: row.implicitWidth
    // Animated width change, asked for -- even a single chip appearing/
    // disappearing (app opened/closed) now shifts this pill smoothly
    // instead of snapping. Same duration/curve as ActiveWindow.qml's own.
    Behavior on implicitWidth {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    implicitHeight: 24
    visible: root.matches.length > 0

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: root.matches

            delegate: Rectangle {
                id: chip
                required property var modelData

                // Which app's actions drawer is currently open, if any.
                // Compared on the ADDRESS rather than the index: the
                // matches list is rebuilt on every refresh and an app
                // closing a window reshuffles it, which would move the
                // highlight onto the neighbouring chip.
                readonly property bool menuOpen: LauncherActionsState.panelOpen
                    && LauncherActionsState.address === chip.modelData.address
                    && LauncherActionsState.activeScreen === root.screen

                width: 22
                height: 22   // was 18 -- more vertical padding around the icon inside the chip
                anchors.verticalCenter: parent.verticalCenter
                radius: 8   // 4 -> 8, matches Block.qml's more pronounced rounding (kept for the hit target's shape, not visible any more)
                // No fill any more -- redundant now that Launchers lives
                // inside the metrics pill (see shell.qml), which already
                // has its own background. Was #34383f, back when each chip
                // sat directly on the bar with no wrapping Block behind it.
                //
                // The ONE exception is the chip whose drawer is open: the
                // panel below names the app it is about, but the chip it
                // came out of is what the pointer is still sitting on, and
                // an unmarked chip leaves five identical candidates above
                // an open menu. Same accent fill a DrawerTile carries when
                // it is on, at the chip's own scale.
                color: chip.menuOpen ? Surfaces.accentStrong : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    anchors.centerIn: parent
                    visible: chip.modelData.image === ""
                    text: chip.modelData.icon
                    color: root.ink.primary
                    font.family: Fonts.iconBrand
                    font.pixelSize: 12   // 13 -> 11, asked for
                }

                Image {
                    anchors.centerIn: parent
                    // yOffset -- see knownApps' own comment: heroic.svg is
                    // mathematically centered in its viewBox but still
                    // reads as sitting low (optical centering, not a real
                    // offset), corrected per-icon rather than guessed here.
                    anchors.verticalCenterOffset: chip.modelData.yOffset
                    visible: chip.modelData.image !== ""
                    source: chip.modelData.image
                    width: 11    // 14 -> 11, same reduction as the Text glyph
                    height: 11
                    // Rasterize straight at the target size instead of
                    // scaling down from the SVG's native resolution --
                    // crisper for a thin-stroke shape like heroic's shield
                    // outline than the blurrier default scaling path.
                    // Tried first as a fix for the droop above, on its own
                    // it wasn't enough (kept anyway, strictly better).
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // hl.dsp.focus, not the plain `focuswindow`. The
                    // comment that used to sit here reasoned that
                    // pip-daemon.sh "already proves" address-targeted
                    // dispatchers work as vanilla hyprctl dispatch on
                    // this system -- but pip-daemon.sh's own dispatches
                    // were broken the whole time, so it proved nothing,
                    // and this chip never focused anything either.
                    // hyprland.lua configures this compositor in Lua, so
                    // `hyprctl dispatch` evaluates its argument AS LUA
                    // and a native dispatcher name is not a parse error
                    // away from working, it IS one:
                    //
                    //   error: [string "return hl.dispatch(focuswindow
                    //   address:0x5...)"]:1: ')' expected near 'address'
                    //
                    // Being Hyprland's own dispatcher is irrelevant: the
                    // Lua layer is in front of all of them.
                    //
                    // RIGHT click opens the actions drawer for this app
                    // instead -- focus is the common case and stays on
                    // the plain click, while "close this window" and
                    // "quit this app" live one level in, where a misfire
                    // costs nothing. See LauncherActionsState.qml for why
                    // an app chip needed those two at all.
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            LauncherActionsState.toggleFor(root.screen, chip.modelData);
                            return;
                        }
                        // An open panel is about ONE app, and a plain
                        // click here is the user moving on to another
                        // one -- so it closes, rather than being left
                        // behind naming the app they just navigated away
                        // from. shell.qml's event-based dismissal does
                        // not cover this case: focusing a window on the
                        // CURRENT workspace only emits `activewindow`,
                        // which is deliberately not in
                        // keybindsDismissEvents (it also fires on plain
                        // focus-follows-mouse -- see there).
                        LauncherActionsState.close();
                        Quickshell.execDetached(["hyprctl", "dispatch",
                            "hl.dsp.focus({ window = 'address:" + chip.modelData.address + "' })"]);
                    }
                }
            }
        }
    }
}
