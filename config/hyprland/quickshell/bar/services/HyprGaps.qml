pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Where Hyprland stops tiled windows at the bottom of the screen: its
// bottom `gaps_out` plus the window border. The notification centre runs
// down to exactly that line (asked for: "en bas ne dépasse pas les
// fenêtres tiles hyprland"), so its bottom edge lines up with the windows
// beside it.
//
// Read from `hyprctl getoption` rather than copied from hyprland.lua, so
// changing the gaps or the border moves the drawer with them: once at
// startup and again on every `configreloaded` event.
Singleton {
    id: root

    property int gapBottom: 6
    property int border: 2
    readonly property int bottomInset: root.gapBottom + root.border

    function refresh() {
        if (!query.running) query.running = true;
    }

    Process {
        id: query
        command: ["sh", "-c", "hyprctl -j getoption general:gaps_out; echo; hyprctl -j getoption general:border_size"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                // Two JSON objects, one per line.
                const parts = this.text.trim().split(/\n(?=\{)/);
                try {
                    const gaps = JSON.parse(parts[0]);
                    // "css" is "top right bottom left".
                    const css = (gaps.css || "").trim().split(/\s+/).map(Number);
                    if (css.length === 4 && !isNaN(css[2])) root.gapBottom = css[2];
                    else if (gaps.int !== undefined) root.gapBottom = gaps.int;
                } catch (e) {}
                try {
                    const b = JSON.parse(parts[1]);
                    if (b.int !== undefined) root.border = b.int;
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.refresh();
        }
    }
}
