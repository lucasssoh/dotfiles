import QtQuick
import ".."          // DrawerHandle
import "../../theme"
import "../../services"

// Programme's drawer, a panel down the screen's left edge: tabs over one
// page at a time (Today, Week, Plus). A page taller than the screen
// scrolls inside it.
//
// Same entry contract as the calendar's: `drawerOpen` from the caller, the
// island animates `height` to `implicitHeight`.
Item {
    id: root

    property bool drawerOpen: false
    // The most the page area may take; the rest scrolls.
    property int maxHeight: 900
    // Sized from outside (the full-height panel): the page area runs down
    // to the bottom, whatever the page holds.
    property bool fill: false

    readonly property var b: ProgrammeState
    // Handle and tabs, above the page.
    readonly property int header: handle.implicitHeight + 12 + (tabs.visible ? tabs.height + 14 : 0)
    readonly property int pageHeight: root.fill
        ? Math.max(0, root.height - root.header - 20)
        : Math.min(page.item ? page.item.implicitHeight : 0, root.maxHeight)

    implicitHeight: root.header + root.pageHeight + 20
    Behavior on height { enabled: !root.fill; NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: ProgrammeState.close()
    }

    // The pages, as one segmented rail like Balise's: the page shown
    // inverted, the highlight sliding from one to the next.
    Rectangle {
        id: tabs
        visible: root.b.page !== "setup"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.top: handle.bottom
        anchors.topMargin: 12
        height: 38
        radius: height / 2
        color: DrawerTheme.card
        border.width: 1
        border.color: DrawerTheme.faint

        readonly property var pages: [
            { id: "today", label: root.b.tr("Today", "Aujourd'hui") },
            { id: "week", label: root.b.tr("Week", "Semaine") },
            { id: "plus", label: root.b.tr("More", "Plus") }
        ]
        readonly property int current: Math.max(0, tabs.pages.findIndex(p => p.id === root.b.page))
        readonly property real slot: (tabs.width - 8) / tabs.pages.length

        Rectangle {
            x: 4 + tabs.current * tabs.slot
            y: 4
            width: tabs.slot
            height: tabs.height - 8
            radius: height / 2
            color: DrawerTheme.on
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        Row {
            x: 4
            y: 4
            Repeater {
                model: tabs.pages
                delegate: Item {
                    id: seg
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === tabs.current
                    width: tabs.slot
                    height: tabs.height - 8
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: !seg.selected && segHit.containsMouse ? DrawerTheme.cardHover : DrawerTheme.clear(DrawerTheme.cardHover)
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    ProgrammeText {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        text: seg.modelData.label
                        color: seg.selected ? DrawerTheme.onInk : DrawerTheme.secondary
                        Behavior on color { ColorAnimation { duration: 160 } }
                        font.pixelSize: 12
                        font.weight: seg.selected ? Font.Bold : Font.DemiBold
                    }
                    MouseArea {
                        id: segHit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.b.show(seg.modelData.id)
                    }
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.top: tabs.visible ? tabs.bottom : handle.bottom
        anchors.topMargin: tabs.visible ? 14 : 12
        height: root.pageHeight
        contentHeight: page.item ? page.item.implicitHeight : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Loader {
            id: page
            width: flick.width
            sourceComponent: root.b.page === "week" ? week
                           : root.b.page === "plus" ? plus
                           : root.b.page === "setup" ? setup : today
            onLoaded: flick.contentY = 0
        }
    }

    // In the right margin, beside the page.
    ThinScrollBar {
        target: flick
        anchors.left: flick.right
        anchors.leftMargin: 4
        anchors.top: flick.top
        anchors.bottom: flick.bottom
    }

    Component { id: today; ProgrammeToday {} }
    Component { id: week; ProgrammeWeek {} }
    Component { id: plus; ProgrammePlus {} }
    Component { id: setup; ProgrammeSetup {} }
}
