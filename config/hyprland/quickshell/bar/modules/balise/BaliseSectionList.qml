import QtQuick
import Qt5Compat.GraphicalEffects
import ".."
import "../../theme"

// Shared shell for the WiFi/Bluetooth/Ethernet section lists. Layout
// follows the user's own "Centre de contrôle" mockup, in this bar's
// monochrome palette rather than its purple/green accents ("utilise ce
// type de disposition mais plus monochrome"): a rounded-square back
// button + title + right-hand text action, an optional master radio
// toggle card, then small-caps group headers carrying a count on the
// right, then the rows themselves.
//
// "‹" (U+2039, a normal Inter punctuation glyph) rather than a Phosphor
// caret-left icon -- no verified codepoint for one in this bar, and
// guessing one is exactly the mistake this codebase's own history warns
// against (see NotificationCard.qml's hand-drawn X for the same
// reasoning applied to a close button).
Item {
    id: root

    property string title: ""
    property alias model: listView.model
    property Component rowDelegate: null
    property bool showScan: false
    // A scan running: "Scan" turns into a spinning ring and "Scanning",
    // and can't be clicked again until the results are in.
    property bool scanning: false
    property string emptyText: "No results"
    // Whether `model`'s items carry a `_group` field to render small-caps
    // section headers off (BaliseHome.qml's groupedWifiNetworks/
    // groupedBluetoothDevices) -- off by default (Ethernet's plain
    // profile list has no such grouping).
    property bool grouped: false
    // Master radio switch at the top of the page (the mockup's own
    // "Wi-Fi / Recherche automatique des réseaux" card) -- lets the radio
    // be flipped without going back to the home grid. Ethernet has no
    // radio, so it simply leaves this off.
    property bool showMaster: false
    property string masterTitle: ""
    property string masterSubtitle: ""
    property bool masterChecked: false
    signal masterToggled(bool value)
    signal backRequested()
    signal scanRequested()

    readonly property color accent: DrawerTheme.accent

    // Fixed, like NotificationCenter.qml's own 600px -- a nice-to-have
    // follow-up to make this content-driven is deferred the same way
    // that file's own header already documents.
    implicitHeight: 480

    // No inset of its own -- asked for: "reduit les paddings dans les sous
    // contexte de niveau 2 et niveau 3, ils ne matchent pas l'UI main".
    // Every page in this drawer is loaded into BaliseHome's `pageArea`,
    // which ALREADY applies 20px on all four sides; the level-2 and
    // level-3 pages were each adding their own 20 on top, so their content
    // sat 40 from the pane edge where the home grid sits at 20 -- the two
    // levels visibly failed to line up with each other, which is what the
    // mismatch was. Only the 14px gap below this header survives, since
    // that is spacing between two blocks rather than padding against an
    // edge.
    Item {
        id: header
        RevealPop { item: header; index: 0 }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 30

        Rectangle {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: 9

            // Same glass edge every other block in this bar now carries --
            // see GlassChip.qml. Only the block itself goes through the lens;
            // any icon tile nested inside it is left plain, or the two
            // rims would sit 4px apart and read as noise.
            // Only while this is HOVERED or ON -- asked for: the glass is a
            // state cue, not decoration, so a zone nobody is touching and
            // nothing has switched on carries no edge at all. It also means
            // the layer is allocated only for the one element in play.
            color: backArea.containsMouse ? DrawerTheme.cardRaised : DrawerTheme.card
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                // Nudged up-left by the glyph's own bearing so it reads
                // optically centred in the square.
                anchors.horizontalCenterOffset: -1
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "‹"
                color: DrawerTheme.primary
                font.family: Fonts.ui
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.backRequested()
            }
        }

        Text {
            anchors.left: backBtn.right
            anchors.leftMargin: 12
            anchors.right: scanLabel.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.title
            color: DrawerTheme.primary
            font.family: Fonts.ui
            font.pixelSize: 17
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Row {
            id: scanLabel
            visible: root.showScan
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            // A three-quarter ring turning on the render thread
            // (RotationAnimator), only while a scan runs.
            Canvas {
                id: spinner
                visible: root.scanning
                width: 12
                height: 12
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = DrawerTheme.secondary;
                    ctx.beginPath();
                    ctx.arc(6, 6, 4.8, 0, Math.PI * 1.5);
                    ctx.stroke();
                }
                RotationAnimator on rotation {
                    running: root.scanning && spinner.visible
                    from: 0; to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.scanning ? "Scanning" : "Scan"
                color: root.scanning ? DrawerTheme.secondary
                    : (scanArea.containsMouse ? DrawerTheme.primary : root.accent)
                font.family: Fonts.ui
                font.pixelSize: 13
            }
        }

        // Outside the Row, which would otherwise lay it out as one more
        // item; same 8 px of slack around the label as before.
        MouseArea {
            id: scanArea
            visible: root.showScan
            anchors.fill: scanLabel
            anchors.margins: -8
            enabled: !root.scanning
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.scanRequested()
        }
    }

    Rectangle {
        id: masterCard
        RevealPop { item: masterCard; index: 1 }
        visible: root.showMaster
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 14
        height: root.showMaster ? 54 : 0
        radius: 12

        // Same glass edge every other block in this bar now carries --
        // see GlassCard.qml. Only the block itself goes through the lens;
        // any icon tile nested inside it is left plain, or the two
        // rims would sit 4px apart and read as noise.
        // Only while this is HOVERED or ON -- asked for: the glass is a
        // state cue, not decoration, so a zone nobody is touching and
        // nothing has switched on carries no edge at all. It also means
        // the layer is allocated only for the one element in play.
        color: masterArea.containsMouse ? DrawerTheme.cardHover : DrawerTheme.card
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: masterTrack.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.masterTitle
                color: DrawerTheme.primary
                font.family: Fonts.ui
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.masterSubtitle !== ""
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.masterSubtitle
                color: DrawerTheme.secondary
                font.family: Fonts.ui
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        // Same track+thumb switch NotificationCenter.qml's own DND toggle
        // uses, so every switch in this bar is literally the same control.
        Rectangle {
            id: masterTrack
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 22
            radius: 11
            color: root.masterChecked ? root.accent : DrawerTheme.ink(0.18)
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: DrawerTheme.onInk
                anchors.verticalCenter: parent.verticalCenter
                x: root.masterChecked ? parent.width - width - 2 : 2
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: masterArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.masterToggled(!root.masterChecked)
        }
    }

    ListView {
        id: listView
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.showMaster ? masterCard.bottom : header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 14
        clip: true
        spacing: 8
        delegate: root.rowDelegate

        // Soft top/bottom edges once the list outruns the pane -- asked
        // for alongside the notification history's ("dans les notifs et
        // balise aussi, puisqu'on a scroll, il ne faut pas couper les
        // elements brutement"). A saturated WiFi scan is the longest list
        // in this drawer, so this is the one that shows it most.
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: listMask }

        section.property: root.grouped ? "_group" : ""
        section.criteria: ViewSection.FullString
        section.delegate: Item {
            id: sectionHeader
            // Fades without zooming (fromScale 1.0), same as the home
            // page's small-caps labels: NativeRendering glyphs crawl
            // while scaled. Pinned to the first row's slot rather than
            // tracking its own position -- a group header sits directly
            // above its group, so the difference is invisible.
            RevealPop { item: sectionHeader; index: 2; fromScale: 1.0 }
            required property string section
            width: listView.width
            // Taller above every header except the very first one (no
            // divider to read against yet there) -- ListView.previousSection
            // is "" only for that first header, the standard Qt Quick way
            // to tell first-from-rest apart in a section.delegate.
            height: sectionHeader.ListView.previousSection === "" ? 26 : 34

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: sectionHeader.section.toUpperCase()
                color: DrawerTheme.ink(0.4)
                font.family: Fonts.ui
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }

            // Per-group count on the right (the mockup's own "4 trouvés")
            // -- counted off the same array the ListView is showing rather
            // than passed in, so it can never disagree with what's
            // actually rendered under this header.
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: {
                    const items = root.model;
                    if (!items || items.length === undefined) return "";
                    let n = 0;
                    for (let i = 0; i < items.length; i++) if (items[i]._group === sectionHeader.section) n++;
                    return n > 0 ? n : "";
                }
                color: DrawerTheme.ink(0.3)
                font.family: Fonts.ui
                font.pixelSize: 12
            }
        }

        Text {
            anchors.centerIn: parent
            visible: listView.count === 0
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.emptyText
            color: DrawerTheme.ink(0.4)
            font.family: Fonts.ui
            font.pixelSize: 13
        }
    }

    // Size mirrors `listView`; position is irrelevant (see
    // ScrollFadeMask.qml).
    ScrollFadeMask {
        id: listMask
        view: listView
        width: listView.width
        height: listView.height
    }
}
