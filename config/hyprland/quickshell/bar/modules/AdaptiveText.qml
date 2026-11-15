import QtQuick
import "../theme"

// A Text whose colour follows what is behind each part of it: drawn once
// per run of one ink (IslandGlass.runs), each copy clipped to its run, so
// a title across a dark trunk on a white sky reads light over the trunk
// and dark beside it. Without a glass it is a plain Text in `fallback`.
Item {
    id: root

    property alias text: probe.text
    property alias font: probe.font
    property int elide: Text.ElideNone
    // IslandGlass, or null.
    property QtObject glass: null
    // Which ink tier: "primary", "secondary", "faint".
    property string tier: "primary"
    property color fallback: "white"

    implicitWidth: probe.implicitWidth
    implicitHeight: probe.implicitHeight

    Text { id: probe; visible: false; font.hintingPreference: Font.PreferNoHinting }

    readonly property var runs: root.glass && root.glass.runs
        ? (root.x, root.width, root.parent ? root.parent.x : 0, root.glass.runs(root))
        : [{ x0: 0, x1: root.width, dark: false }]

    Repeater {
        model: root.runs

        Item {
            required property var modelData
            x: modelData.x0
            width: Math.max(0, modelData.x1 - modelData.x0)
            height: root.height
            clip: true

            Text {
                x: -parent.x
                width: root.width
                text: probe.text
                font: probe.font
                elide: root.elide
                renderType: Text.NativeRendering
                color: root.glass && root.glass.runs
                    ? (parent.modelData.dark ? root.glass._darkSet[root.tier] : root.glass._lightSet[root.tier])
                    : root.fallback
            }
        }
    }
}
