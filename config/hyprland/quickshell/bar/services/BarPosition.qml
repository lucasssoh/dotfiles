pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The bar's settings live in ~/.config/hypr/bar.json (bar-position.json
// while bar.json is missing). Any change to that file restarts the bar:
// Wayland fixes a layer's namespace and anchors when it is first mapped,
// and the restart script reads the file again to export the position.
Singleton {
    id: root

    readonly property string barPath: Quickshell.env("HOME") + "/.config/hypr/bar.json"
    readonly property string legacyPath: Quickshell.env("HOME") + "/.config/hypr/bar-position.json"
    readonly property string restartScript: Quickshell.env("HOME")
        + "/.config/hypr/scripts/restart-quickshell-bar.sh"
    // The launcher exports this before any layer surface is created.
    property string position: Quickshell.env("QUICKSHELL_BAR_POSITION") === "bottom"
        ? "bottom" : "top"
    readonly property bool bottom: position === "bottom"
    property bool configLoaded: false
    // The bars slide out on `leaving`, then unmap on `restartPending`.
    property bool leaving: false
    property bool restartPending: false
    // False until the first read lands, so startup does not restart when
    // the launcher already started the bar on the right edge.
    property bool ready: false
    // bar.json wins; the old file is only read when bar.json is missing.
    // The flag also stops the legacy watcher's initial miss from being
    // mistaken for a settings change at startup.
    property bool usingLegacy: false

    Timer {
        id: leaveTimer
        interval: 180
        onTriggered: {
            root.restartPending = true;
            Quickshell.execDetached(["bash", root.restartScript, "--force"]);
        }
    }

    FileView {
        id: barFile
        path: root.barPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.usingLegacy = false;
            root.adopt(text(), root.barPath);
        }
        onLoadFailed: (error) => {
            root.usingLegacy = true;
            if (error === FileViewError.FileNotFound) {
                legacyFile.reload();
                if (root.ready) root.requestRestart();
                return;
            }
            root.configLoaded = true;
            console.warn("[bar] failed to read " + root.barPath + ": "
                         + FileViewError.toString(error));
            if (root.ready) root.requestRestart();
        }
    }

    FileView {
        id: legacyFile
        path: root.legacyPath
        watchChanges: true
        printErrors: false
        onFileChanged: if (root.usingLegacy) reload()
        onLoaded: if (root.usingLegacy) root.adopt(text(), root.legacyPath)
        onLoadFailed: (error) => {
            if (root.usingLegacy && error === FileViewError.FileNotFound)
                // No settings file at all: the default is a top bar.
                root.adopt("{}", root.barPath);
        }
    }

    function adopt(raw, path) {
        const first = !root.ready;
        root.ready = true;
        root.configLoaded = true;
        let wanted = "top";
        try {
            const config = JSON.parse(raw);
            if (config && typeof config === "object" && !Array.isArray(config)) {
                const value = config.position;
                if (value === "top" || value === "bottom") wanted = value;
                else if (value !== undefined)
                    console.warn("[bar] position must be \"top\" or \"bottom\" in "
                                 + path + "; using top");
            }
        } catch (error) {
            console.warn("[bar] invalid JSON in " + path + ": " + error);
        }
        // On the first read, only a position mismatch needs a restart.
        // Afterwards, every save restarts: the script re-reads the file.
        if (!first || wanted !== root.position) {
            console.warn("[bar] " + path + (first ? ": position " + wanted
                         + " differs from " + root.position : " changed")
                         + "; restarting");
            root.requestRestart();
        }
    }

    function requestRestart() {
        if (root.leaving) return;
        root.leaving = true;
        leaveTimer.start();
    }
}
