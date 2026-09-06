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

    readonly property color accent: "#a8b4c4"

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
            color: backArea.containsMouse ? Surfaces.cardRaised : Surfaces.card
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                // Nudged up-left by the glyph's own bearing so it reads
                // optically centred in the square.
                anchors.horizontalCenterOffset: -1
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "‹"
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 17
                font.bold: true
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
            color: "#f2f2f7"
            font.family: Fonts.ui
            font.pixelSize: 17
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            id: scanLabel
            visible: root.showScan
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: "Scan"
            color: scanArea.containsMouse ? "#f2f2f7" : root.accent
            font.family: Fonts.ui
            font.pixelSize: 13

            MouseArea {
                id: scanArea
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.scanRequested()
            }
        }
    }

    Rectangle {
        id: masterCard
        visible: root.showMaster
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 14
        height: root.showMaster ? 54 : 0
        radius: 12
        color: masterArea.containsMouse ? Surfaces.cardHover : Surfaces.card
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
                color: "#f2f2f7"
                font.family: Fonts.ui
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.masterSubtitle !== ""
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.masterSubtitle
                color: "#8e8e93"
                font.family: Fonts.ui
                font.pixelSize: 11
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
            color: root.masterChecked ? root.accent : Qt.rgba(1, 1, 1, 0.18)
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: "#0c0c0e"
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
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: Fonts.ui
                font.pixelSize: 11
                font.bold: true
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
                color: Qt.rgba(1, 1, 1, 0.3)
                font.family: Fonts.ui
                font.pixelSize: 11
            }
        }

        Text {
            anchors.centerIn: parent
            visible: listView.count === 0
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.emptyText
            color: Qt.rgba(1, 1, 1, 0.4)
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
