import QtQuick
import ".."          // DrawerHandle
import "../balise"   // RevealPop
import "../../theme"
import "../../services"

// The only drawer on launchersIsland -- what a Launchers chip opens on a
// right click. See LauncherActionsState.qml for WHY an app chip needed
// more than the focus it had (short version: Discord hides its window on
// close and this session hosts no tray, so a hidden Discord had no way
// back and no way out).
//
// Same DrawerIsland contract the four TOOLS drawers satisfy: `drawerOpen`
// bound from outside, `implicitHeight` computed here, `Behavior on height`
// kept equal to the island's `revealDuration`. Width is not set here --
// the island forces every entry to its own `fixedDrawerWidth`, so
// everything below sizes off `parent.width`.
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
Item {
    id: root

    property bool drawerOpen: false

    implicitHeight: handle.implicitHeight + 8 + content.implicitHeight + 10
    // Kept equal to DrawerIsland's `revealDuration` -- the island waits
    // out exactly this long before fading content in.
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    // Same kick PowerHome/MixerHome give the shared cascade: this content
    // is built once, so without it the reveal would play at bar startup,
    // invisibly, and never again.
    onDrawerOpenChanged: {
        if (root.drawerOpen) BaliseReveal.replay();
    }

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

        property int revealIndex: 0
        RevealPop { item: arow; index: arow.revealIndex }

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

            RevealPop { item: header; index: 0; fromScale: 1.0 }

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
            revealIndex: 1
            glyph: "\uE426"   // lu-app-window
            label: "Focus window"
            onActivated: LauncherActionsState.focusWindow()
        }

        ActionRow {
            revealIndex: 2
            glyph: "\uE175"   // lu-square-x
            label: "Close window"
            onActivated: LauncherActionsState.closeWindow()
        }

        ActionRow {
            revealIndex: 3
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
            revealIndex: 4
            visible: LauncherActionsState.forceOffered
            glyph: "\uE221"   // lu-skull
            label: "Force quit"
            hint: "SIGKILL"
            destructive: true
            onActivated: LauncherActionsState.forceQuit()
        }
    }
}
