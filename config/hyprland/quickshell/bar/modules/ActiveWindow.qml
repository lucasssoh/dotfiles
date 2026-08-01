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
        // Just enough to clear the wrapping Block's own border (1px) --
        // any more and it's a visible gap again, any less (0) and the
        // chip's fill paints straight over the border since children
        // aren't inset from a parent's border area automatically.
        anchors.leftMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: appLabel.implicitWidth + 16
        height: 18
        radius: 2   // same corner rounding as the active workspace pill, not a full pill/stadium shape
        color: "#1f98ab"   // style.css "accent" (the blue one, not accent2)

        Text {
            id: appLabel
            anchors.centerIn: parent
            text: root.appName
            color: "#141414"
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            font.bold: true
        }
    }

    Text {
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
