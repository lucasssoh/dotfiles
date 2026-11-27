import QtQuick
import Quickshell
import Quickshell.Io

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

    // Glass: the drawers' inks on black. Ink: the shell theme's, in the
    // desktop's mode. hypr/scripts/shell-theme.py sync writes both modes
    // to fontview-theme.json (null in glass); the file is watched, so a
    // theme change shows at once, as the mode does.
    property var themes: null
    property bool dark: true
    readonly property var theme: win.themes ? win.themes[win.dark ? "dark" : "light"] : null
    readonly property bool cartoon: !!win.theme
    readonly property color ink: win.cartoon ? win.theme.primary : "#f2f2f7"
    readonly property color ink2: win.cartoon ? win.theme.secondary : "#8e8e93"
    readonly property color ink3: win.cartoon ? win.theme.muted : "#636366"
    readonly property string uiFont: win.cartoon ? win.themes.font : "sans-serif"

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/coucou-shell/theme/fontview-theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { win.themes = JSON.parse(text()); } catch (e) { win.themes = null; }
        }
        onLoadFailed: win.themes = null
    }
    component Scheme: Process {
        running: true
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("prefer-") !== -1) win.dark = line.indexOf("prefer-dark") !== -1; }
        }
    }
    Scheme { command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"] }
    Scheme { command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"] }

    readonly property string sample:
        "The quick brown fox jumps over the lazy dog. Portez ce vieux whisky au juge blond qui fume."

    title: "fontview — " + file.split("/").pop()
    color: win.cartoon ? win.theme.panel : "#000000"
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
            anchors { fill: parent; margins: 32; bottomMargin: win.cartoon ? 68 : 56 }
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
                            font.family: win.uiFont
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
                font.family: win.uiFont
                font.pixelSize: 16
            }
        }

        // In Ink, the status sits in an inked pill, like the bar's islands.
        Rectangle {
            visible: win.cartoon
            anchors.fill: status
            anchors.margins: -8
            anchors.leftMargin: -14
            anchors.rightMargin: -14
            radius: height / 2
            color: win.cartoon ? win.theme.card : "transparent"
            border.width: win.cartoon ? win.themes.outline : 0
            border.color: win.cartoon ? win.theme.outline : "transparent"
        }
        Text {
            id: status
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
            anchors.leftMargin: win.cartoon ? 34 : 20
            anchors.rightMargin: win.cartoon ? 34 : 20
            anchors.bottomMargin: win.cartoon ? 22 : 20
            elide: Text.ElideMiddle
            color: win.cartoon ? win.ink2 : win.ink3
            font.family: win.uiFont
            font.pixelSize: 12
            text: (win.index + 1) + " / " + win.files.length + "    " + win.file.split("/").pop()
                + "    ←/→ font   +/− size   q quit"
        }
    }
}
