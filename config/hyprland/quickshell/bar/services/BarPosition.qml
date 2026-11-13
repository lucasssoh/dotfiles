pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Optional ~/.config/hypr/bar-position.json: {"position":"bottom"}.
Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/hypr/bar-position.json"
    readonly property string restartScript: Quickshell.env("HOME")
        + "/.config/hypr/scripts/restart-quickshell-bar.sh"
    // The launcher exports this before any layer surface is created:
    // Wayland fixes a layer's namespace when it is first mapped.
    property string position: Quickshell.env("QUICKSHELL_BAR_POSITION") === "bottom"
        ? "bottom" : "top"
    readonly property bool bottom: position === "bottom"
    property bool configLoaded: false
    // The bars slide out on `leaving`, then unmap on `restartPending`.
    property bool leaving: false
    property bool restartPending: false

    Timer {
        id: leaveTimer
        interval: 180
        onTriggered: {
            root.restartPending = true;
            Quickshell.execDetached(["bash", root.restartScript]);
        }
    }

    FileView {
        id: file
        path: root.configPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.adopt(text())
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                root.configLoaded = true;
                if (root.position !== "top") root.requestRestart();
                return;
            }
            root.configLoaded = true;
            console.warn("[bar-position] failed to load " + root.configPath + ": "
                         + FileViewError.toString(error));
        }
    }

    function adopt(raw) {
        root.configLoaded = true;
        try {
            const config = JSON.parse(raw);
            if (config && (config.position === "top" || config.position === "bottom")) {
                if (config.position !== root.position) root.requestRestart();
                return;
            }
            console.warn("[bar-position] position must be \"top\" or \"bottom\"");
        } catch (error) {
            console.warn("[bar-position] invalid JSON in " + root.configPath + ": " + error);
        }
    }

    function requestRestart() {
        if (root.leaving) return;
        root.leaving = true;
        leaveTimer.start();
    }
}
