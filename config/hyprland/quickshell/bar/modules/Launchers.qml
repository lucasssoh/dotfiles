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

    // Horizontal centre of the chip the actions drawer is currently about,
    // in THIS item's coordinates, or -1 when no chip on this screen owns
    // it. Written by the one chip whose `menuOpen` is true, through the
    // Binding in the delegate below.
    //
    // shell.qml feeds it to the island's `drawerAnchorX` (plus the row's
    // own inset, which is the island's to publish, not this file's) so the
    // pane comes out centred under the icon it is about instead of glued
    // to the island's right edge -- asked for.
    //
    // Keyed on the OPEN chip and not on the hovered one, deliberately:
    // travelling from the chip down into the panel means leaving the chip,
    // and a pointer-keyed anchor would snap the pane sideways at exactly
    // that moment. It also means the anchor follows its chip when a
    // neighbour appears or disappears and the row re-lays-out underneath
    // an open panel.
    property real anchorX: -1

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

                // See root.anchorX. `row.x` is in there because the Row is
                // not pinned to 0 -- it is the sum this file can state
                // exactly, where a mapToItem would be a function call
                // rather than a binding and would not re-run when the
                // chips beside this one come and go.
                Binding {
                    target: root
                    property: "anchorX"
                    when: chip.menuOpen
                    value: row.x + chip.x + chip.width / 2
                    // No restore, and that is the point. Retargeting from
                    // one chip to the next flips two of these in the same
                    // frame -- one off, one on -- in an order QML does not
                    // promise, and a restoring Binding that happens to go
                    // last would put the -1 back over the value the other
                    // one just wrote, dropping the pane back to
                    // right-aligned. So the last chip to have owned the
                    // panel keeps the anchor after it closes: nothing
                    // reads it while the pane is invisible, and reopening
                    // the same chip then starts already in place.
                    restoreMode: Binding.RestoreNone
                }

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
                // an open menu.
                //
                // A light translucent wash, NOT the `Surfaces.accentStrong`
                // a DrawerTile carries when it is on -- asked for ("juste
                // un highlight leger"). Two things made that one read far
                // heavier here than on a tile: it is opaque, so on this
                // translucent band it painted a solid plate where every
                // neighbouring chip shows the wallpaper through, and it now
                // fires on a plain hover rather than on a deliberate right
                // click. 10% white is the same wash BatteryRing's track and
                // the OSD's own surfaces use -- it marks the chip without
                // becoming an object sitting on the bar.
                color: chip.menuOpen ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
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
                    // Plain hover opens the drawer now -- asked for. All
                    // of the debouncing this needs (the open delay that
                    // keeps a pointer merely crossing the row from
                    // flashing five panels, the grace period that lets it
                    // cross the 7px gap down into the pane, the refusal to
                    // steal another island's open drawer) lives in
                    // LauncherActionsState's hover section rather than
                    // here: there is one state machine and five chips per
                    // screen feeding it, and `containsMouse` on any one of
                    // them knows nothing about the other four.
                    hoverEnabled: true
                    onEntered: LauncherActionsState.hoverEnter(root.screen, chip.modelData)
                    onExited: LauncherActionsState.hoverExit()
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
