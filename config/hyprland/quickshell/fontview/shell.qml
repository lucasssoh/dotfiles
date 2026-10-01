import QtQuick
import Quickshell

// fontview: imv for fonts. Shows one font file; the arrows step through
// the fonts in its folder. Started by the `fontview` launcher next to this
// file, which passes the file and its neighbours through the environment.

FloatingWindow {
    id: win

    readonly property var files: (Quickshell.env("FONTVIEW_FILES") || "")
        .split("\n").filter(f => f.length > 0)
    property int index: Math.max(0, files.indexOf(Quickshell.env("FONTVIEW_FILE")))
    readonly property string file: files.length > 0 ? files[index] : ""
    property real zoom: 1

    readonly property color ink: "#f2f2f7"
    readonly property color ink2: "#8e8e93"
    readonly property color ink3: "#636366"

    readonly property string sample:
        "The quick brown fox jumps over the lazy dog. Portez ce vieux whisky au juge blond qui fume."

    title: "fontview — " + file.split("/").pop()
    color: "#000000"
    implicitWidth: 960
    implicitHeight: 680

    FontLoader {
        id: loader
        // Each path segment encoded: a '#' or '?' in a file name would
        // otherwise end the URL early.
        source: win.file ? "file://" + win.file.split("/").map(encodeURIComponent).join("/") : ""
    }

    function step(by) {
        if (win.files.length > 0)
            win.index = (win.index + by + win.files.length) % win.files.length;
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Right: case Qt.Key_L: case Qt.Key_J: case Qt.Key_Space: case Qt.Key_N:
                win.step(1); break;
            case Qt.Key_Left: case Qt.Key_H: case Qt.Key_K: case Qt.Key_Backspace: case Qt.Key_P:
                win.step(-1); break;
            case Qt.Key_Plus: case Qt.Key_Equal:
                win.zoom = Math.min(4, win.zoom * 1.25); break;
            case Qt.Key_Minus:
                win.zoom = Math.max(0.25, win.zoom / 1.25); break;
            case Qt.Key_0:
                win.zoom = 1; break;
            case Qt.Key_Q: case Qt.Key_Escape:
                Qt.quit(); break;
            default:
                return;
            }
            event.accepted = true;
        }

        Flickable {
            id: flick
            anchors { fill: parent; margins: 32; bottomMargin: 56 }
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: body
                width: flick.width
                spacing: 18
                visible: loader.status === FontLoader.Ready

                component Specimen: Text {
                    width: body.width
                    wrapMode: Text.Wrap
                    color: win.ink
                    font.family: loader.font.family
                    font.styleName: loader.font.styleName
                }

                Specimen {
                    text: loader.font.family + (loader.font.styleName ? " " + loader.font.styleName : "")
                    font.pixelSize: 44 * win.zoom
                }
                Specimen { text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; font.pixelSize: 28 * win.zoom }
                Specimen { text: "abcdefghijklmnopqrstuvwxyz"; font.pixelSize: 28 * win.zoom }
                Specimen { text: "0123456789 &@#%?!.,;:'\"()[]{}«»"; font.pixelSize: 28 * win.zoom }

                Repeater {
                    model: [12, 16, 20, 28, 40, 56, 80]
                    delegate: Row {
                        required property int modelData
                        width: body.width
                        spacing: 16

                        Text {
                            width: 28
                            text: modelData
                            color: win.ink3
                            font.pixelSize: 11
                            topPadding: 4
                        }
                        Specimen {
                            width: body.width - 44
                            text: win.sample
                            font.pixelSize: modelData * win.zoom
                        }
                    }
                }
            }

            Text {
                visible: loader.status === FontLoader.Error || win.files.length === 0
                anchors.centerIn: parent
                text: win.files.length === 0 ? "No font to show" : "Can't read this font"
                color: win.ink2
                font.pixelSize: 16
            }
        }

        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
            elide: Text.ElideMiddle
            color: win.ink3
            font.pixelSize: 12
            text: (win.index + 1) + " / " + win.files.length + "    " + win.file.split("/").pop()
                + "    ←/→ font   +/− size   q quit"
        }
    }
}
