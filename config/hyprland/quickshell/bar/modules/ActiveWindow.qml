import QtQuick
import Quickshell.Hyprland

// Native port of waybar's `hyprland/window` module -- shows both halves
// of its original format ("{initialTitle} · {title}"): app name + what's
// actually running in it. HyprlandToplevel itself only exposes `title`,
// so `initialTitle` is pulled from `activeToplevel.lastIpcObject` (raw
// hyprctl JSON), same escape hatch used elsewhere in this bar
// (workspaceEmpty logic, Hdr.qml's currentFormat). `initialTitle` is a
// long-standing hyprctl clients -j field, but not independently
// re-verified here.
//
// Style: app name sits in a rounded accent "chip" floating on the left
// (like the workspace pill / HDR badge -- 18px tall inset in the 24px
// block). Corner radius matches the active workspace pill exactly (4px)
// -- rounded corners on an otherwise-rectangular chip, not a fully
// rounded pill/stadium shape. The title continues immediately after it
// on the block's own plain background, no gap, no border between them.

Item {
    id: root

    readonly property var toplevel: Hyprland.activeToplevel
    readonly property bool hasWindow: root.toplevel !== null
    readonly property string appName: {
        if (!root.toplevel) return "";
        const ipc = root.toplevel.lastIpcObject;
        return (ipc && ipc.initialTitle) ? ipc.initialTitle : "";
    }
    readonly property string windowTitle: root.toplevel ? root.toplevel.title : ""

    readonly property int maxWidth: 380

    implicitWidth: root.hasWindow
        ? Math.min(Math.max(chip.width + titleLabel.implicitWidth + 26, 120), maxWidth)
        : 0
    implicitHeight: 24
    clip: true

    Rectangle {
        id: chip
        visible: root.hasWindow
        anchors.left: parent.left
        // 1px is just enough to clear the wrapping Block's own border --
        // below that the chip's fill paints straight over the border
        // since children aren't inset from a parent's border area
        // automatically. The extra few px on top of that are a
        // deliberate small gap/offset, not the minimum-clearance value.
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: appLabel.implicitWidth + 22
        height: 18
        radius: 2   // same corner rounding as the active workspace pill, not a full pill/stadium shape
        // Same ghost-ring treatment as the active workspace pill now,
        // instead of a solid accent fill -- see Workspaces.qml.
        color: "#2c2c2e"
        border.width: 1
        border.color: "#4fefff"

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            id: appLabel
            anchors.centerIn: parent
            text: root.appName
            color: "#4fefff"
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            font.bold: true
        }
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: titleLabel
        text: root.windowTitle
        visible: root.hasWindow
        color: "#f2f2f7"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        anchors.left: chip.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }
}
