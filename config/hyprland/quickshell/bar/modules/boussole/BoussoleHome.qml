import QtQuick
import ".."          // DrawerHandle
import "../../theme"
import "../../services"

// Boussole's drawer, a panel down the screen's left edge: tabs over one
// page at a time (Today, Week; Close while a session is being closed). A
// page taller than the screen scrolls inside it.
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

    readonly property var b: BoussoleState
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
        onCloseRequested: BoussoleState.close()
    }

    Row {
        id: tabs
        visible: root.b.page !== "close" && root.b.page !== "setup"
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.top: handle.bottom
        anchors.topMargin: 12
        height: 32
        spacing: 6
        Repeater {
            model: [
                { id: "today", label: root.b.tr("Today", "Aujourd'hui") },
                { id: "week", label: root.b.tr("Week", "Semaine") },
                { id: "progress", label: root.b.tr("Progress", "Progrès") },
                { id: "files", label: root.b.tr("Files", "Fichiers") },
                { id: "plus", label: root.b.tr("More", "Plus") }
            ]
            delegate: BoussoleChip {
                required property var modelData
                text: modelData.label
                on: root.b.page === modelData.id
                onClicked: root.b.show(modelData.id)
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
                           : root.b.page === "progress" ? progress
                           : root.b.page === "files" ? files
                           : root.b.page === "plus" ? plus
                           : root.b.page === "setup" ? setup
                           : (root.b.page === "close" && root.b.closing) ? closing : today
            onLoaded: flick.contentY = 0
        }
    }

    Component { id: today; BoussoleToday {} }
    Component { id: week; BoussoleWeek {} }
    Component { id: closing; BoussoleClose {} }
    Component { id: progress; BoussoleProgress {} }
    Component { id: files; BoussoleFiles {} }
    Component { id: plus; BoussolePlus {} }
    Component { id: setup; BoussoleSetup {} }
}
