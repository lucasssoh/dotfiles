import QtQuick
import ".."          // DrawerHandle
import "../../theme"
import "../../services"

// The only drawer on launchersIsland -- what a Launchers chip opens on a
// right click. See LauncherActionsState.qml for WHY an app chip needed
// more than the focus it had (short version: Discord hides its window on
// close and this session hosts no tray, so a hidden Discord had no way
// back and no way out).
//
// Same DrawerIsland contract the four TOOLS drawers satisfy: `drawerOpen`
// bound from outside, `implicitHeight` computed here. Width is not set
// here -- the island forces every entry to its own `fixedDrawerWidth`, so
// everything below sizes off `parent.width`. The contract's third clause,
// a `Behavior on height` matching the island's `revealDuration`, is the
// one this entry opts out of -- see the note on it below.
//
// Three actions, and the ORDER is the point: they run from the one that
// changes nothing (focus) to the one that ends the process (quit), so the
// destructive end is the far end rather than the nearest thing to the
// pointer. The fourth, SIGKILL, is not in the list at all until a SIGTERM
// has visibly failed -- see `forceOffered`.
//
// FLAT, and deliberately the lightest thing in this bar. The first pass
// built it out of the same parts Balise and the power drawer use -- a
// card per row (own fill, own GlassCard edge), a rounded badge behind the
// app icon, a small-caps "ACTIONS" header, a gradient pane behind all of
// it. That is the right weight for a drawer you sit in and read; it is
// the wrong weight for three verbs you open for half a second. Every one
// of those layers is gone here: the rows are bare text on the pane, the
// pane itself is one flat colour (see shell.qml's drawerFillTop/Bottom
// for this island), and the only thing that ever fills is the row under
// the pointer. Which is also why the pane stays fully opaque where TOOLS'
// is allowed some translucency -- the cards that made that readable are
// exactly what was removed.
//
// The per-row RevealPop cascade went the same way, and for the same
// reason the island's staged reveal did (see `instantDrawer` in
// DrawerIsland.qml): a staggered pop is an entrance, and this panel opens
// on a hover now. One quick fade of the whole pane, nothing staged --
// asked for ("pas d'effet tiroir, juste un fade rapide"). The rows keep
// their own hover tint, which is the only motion left in here.
Item {
    id: root

    property bool drawerOpen: false

    implicitHeight: handle.implicitHeight + 8 + content.implicitHeight + 10
    // NO `Behavior on height`, and that is the whole of this island's
    // `instantDrawer` on the entry's side: the pane reaches full height on
    // the frame it opens and only its opacity moves. Asked for ("pas
    // d'effet tiroir, juste un fade rapide").
    //
    // The contract at the top of DrawerIsland.qml asks entries for a
    // height Behavior matching `revealDuration`, and this one deliberately
    // opts out -- that clause exists so the island's PauseAnimation can
    // wait out the stretch, and in `instantDrawer` there is no pause and
    // no stretch to wait for.

    // Keeps the panel alive while the pointer is inside it, and arms its
    // close when it leaves -- the other half of the hover open in
    // Launchers.qml (see LauncherActionsState's hover section for the whole
    // state machine, including why leaving arms rather than closes).
    //
    // A HoverHandler and NOT a MouseArea: a MouseArea over this whole item
    // would sit on top of every ActionRow's own MouseArea and eat the
    // clicks the panel exists for. Handlers are passive about buttons.
    //
    // Bounded by this item, which the island sizes to `drawerContentWidth`
    // -- so the pane's own 6px margin on each side is outside it. Leaving
    // through that strip starts the grace period a frame or two early,
    // which is 240ms of slack against 6px of travel.
    HoverHandler {
        onHoveredChanged: {
            if (hovered) LauncherActionsState.hoverKeep();
            else LauncherActionsState.hoverExit();
        }
    }

    // The `BaliseReveal.replay()` kick that used to be here is gone with
    // the cascade it drove -- see the RevealPop note below.

    // ---- one action row ---------------------------------------------
    //
    // Inline, not a file of its own: it is four instances in one drawer
    // and nothing else in the bar has this shape (DrawerTile is the
    // square toggle card, which is a different object -- these are a
    // list, read top to bottom, each one a verb).
    //
    // No fill at rest and no glass edge: a row IS its glyph and its
    // label, and the hover tint is the only surface in the whole panel.
    component ActionRow: Rectangle {
        id: arow

        property string glyph: ""
        property string label: ""
        property string hint: ""
        // Destructive rows carry the danger ink, and ONLY the ink -- the
        // red-tinted fill this had at rest read as a pressed button
        // sitting in the panel permanently.
        property bool destructive: false
        signal activated()

        width: parent ? parent.width : 0
        height: 30
        radius: 8
        color: rowArea.containsMouse
            ? (arow.destructive ? Surfaces.destructiveSoft : Surfaces.cardHover)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }

        readonly property color fg: arow.destructive ? Ink.danger : Ink.primary

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arow.activated()
        }

        // Fixed-width gutter, not a glyph the label is anchored behind:
        // lu-app-window, lu-square-x, lu-power and lu-skull do not share
        // an advance width, so anchoring to the glyph's own right edge
        // left the four labels starting at four different x. Invisible
        // under a card; the only structure this flat list has.
        Text {
            id: rowGlyph
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: arow.glyph
            color: arow.fg
            font.family: Fonts.iconPhosphor
            font.pixelSize: 14
        }

        Text {
            anchors.left: rowGlyph.right
            anchors.leftMargin: 8
            anchors.right: rowHint.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: arow.label
            color: arow.fg
            font.family: Fonts.ui
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        Text {
            id: rowHint
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: arow.hint
            color: Ink.muted
            font.family: Fonts.ui
            font.pixelSize: 10
        }
    }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: LauncherActionsState.close()
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 8
        spacing: 1

        // ---- who this is about --------------------------------------
        //
        // One line, not a card: the app's own icon at the size it is in
        // the bar, its name, and the state line only when there is a
        // state worth reading. Without any of it the panel is three
        // anonymous verbs -- and with five chips sitting a few pixels
        // apart, "which app did I just right-click" is exactly the
        // question a destructive action must not leave open.
        Item {
            id: header
            width: parent.width
            height: 24

            // Both icon kinds the chips can carry (a Font Awesome Brands
            // glyph, or a real SVG for Lutris/Heroic, which no icon font
            // has a logo for), same split as Launchers.qml -- and at the
            // chip's own 11/12px rather than blown up into a badge.
            Text {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                // Same 14px gutter the rows use below, so the app's name
                // starts exactly where their labels do.
                width: 14
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                visible: LauncherActionsState.image === ""
                text: LauncherActionsState.icon
                color: Ink.primary
                font.family: Fonts.iconBrand
                font.pixelSize: 12
            }

            Image {
                id: appImage
                anchors.left: parent.left
                anchors.leftMargin: 8 + (14 - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                // Same optical nudge the chip applies, at the same size
                // -- see Launchers.qml's knownApps.
                anchors.verticalCenterOffset: LauncherActionsState.iconYOffset
                visible: LauncherActionsState.image !== ""
                source: LauncherActionsState.image
                width: 11
                height: 11
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                id: appName
                anchors.left: appIcon.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: LauncherActionsState.label
                color: Ink.primary
                font.family: Fonts.ui
                font.pixelSize: 12
                font.bold: true
            }

            // Right-aligned and quiet, so the name keeps the line. The
            // window count earns its place because the two middle
            // actions differ on exactly that: "close window" is one of
            // n, "quit" is all of them. The pid does not -- it was there
            // to prove the panel knew what it was about, which the icon
            // and the name already do.
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: {
                    if (LauncherActionsState.quitSent)
                        return LauncherActionsState.forceOffered ? "no answer" : "quitting…";
                    const n = LauncherActionsState.windowCount;
                    return n > 1 ? n + " windows" : "";
                }
                color: LauncherActionsState.forceOffered ? Ink.danger : Ink.muted
                font.family: Fonts.ui
                font.pixelSize: 10
            }
        }

        ActionRow {
            glyph: "\uE426"   // lu-app-window
            label: "Focus window"
            onActivated: LauncherActionsState.focusWindow()
        }

        ActionRow {
            glyph: "\uE175"   // lu-square-x
            label: "Close window"
            onActivated: LauncherActionsState.closeWindow()
        }

        ActionRow {
            glyph: "\uE140"   // lu-power
            label: "Quit app"
            hint: "SIGTERM"
            destructive: true
            onActivated: LauncherActionsState.quit()
        }

        // Appears only once a SIGTERM has been sent and the window is
        // still on Hyprland's client list `escalation` ms later -- an app
        // that took the signal has already closed this panel by vanishing
        // (LauncherActionsState.syncTarget). SIGKILL is state loss, so it
        // is a second deliberate click and never an automatic follow-up.
        ActionRow {
            visible: LauncherActionsState.forceOffered
            glyph: "\uE221"   // lu-skull
            label: "Force quit"
            hint: "SIGKILL"
            destructive: true
            onActivated: LauncherActionsState.forceQuit()
        }
    }
}
