import QtQuick
import Quickshell
import Quickshell.Io

// Veille's config: read-only, hot-reloaded JSON (see quickshell/bar/
// veille.json). No app in this repo has a JSON config yet -- Balise's
// config.toml/style.css pair is the closest precedent, but Quickshell
// reads JSON natively (FileView + JsonAdapter) and can't parse TOML
// without writing a parser, so JSON is what actually gets hot-reload for
// free here. Every key below has a default, so a missing file, a partial
// edit, or invalid JSON never breaks the overlay -- same "config is an
// enrichment, never a requirement" spirit as balise-src/src/config.rs's
// #[serde(default = "...")] fields.
//
// Plain component, not a pragma-Singleton like theme/Fonts.qml: only
// Veille.qml's own tree reads this, passed down to VeillePhase/
// VeilleContext/VeilleMessages as an ordinary property (same pattern
// ActiveWindow.qml's `monitor` property uses) -- a singleton would add
// qmldir registration for a value nothing outside this folder needs.
Scope {
    id: root

    // Quickshell.shellPath() resolves relative to the running shell's own
    // directory (quickshell/bar/, wherever it's symlinked to) regardless
    // of how deep this file sits under modules/ -- so veille.json stays a
    // sibling of shell.qml, not buried under modules/veille/.
    readonly property string configPath: Quickshell.shellPath("veille.json")

    readonly property bool loaded: file.loaded
    readonly property bool loadFailed: loadError !== ""
    property string loadError: ""

    readonly property bool enabled: adapter.enabled
    readonly property string language: adapter.language
    readonly property string monitor: adapter.monitor
    readonly property real widthFraction: adapter.widthFraction
    readonly property bool showSeconds: adapter.showSeconds
    readonly property bool showDate: adapter.showDate
    readonly property int messageIntervalMinutes: adapter.messageIntervalMinutes
    readonly property int messageHoldSeconds: adapter.messageHoldSeconds
    readonly property var pulse: adapter.pulse
    readonly property bool muteWhileGaming: adapter.muteWhileGaming
    readonly property bool respectZenMode: adapter.respectZenMode
    readonly property var thresholds: adapter.thresholds
    readonly property var phases: adapter.phases
    readonly property var appFamilies: adapter.appFamilies
    readonly property var tokenPatterns: adapter.tokenPatterns
    readonly property bool debug: adapter.debug

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false   // handled below, so a missing file at first
                              // install doesn't spam stderr -- it's a
                              // completely normal, silently-defaulted case

        onFileChanged: reload()
        onLoaded: root.loadError = ""
        onLoadFailed: (error) => {
            // A missing file is normal (nothing shipped it yet, or the
            // user deleted it to fall back to defaults) -- only a real
            // parse/read failure on an EXISTING file is worth a warning,
            // so whoever edited it by hand notices their JSON is broken.
            if (error === FileViewError.FileNotFound) return;
            root.loadError = FileViewError.toString(error);
            console.warn("[veille] failed to load " + root.configPath + ": " + root.loadError);
        }

        JsonAdapter {
            id: adapter

            property bool enabled: true
            property string language: "fr"
            property string monitor: ""

            // Fraction of the SCREEN'S WIDTH the clock spans -- not a
            // raw pixel font size ("proportionnel à la taille de l'ecran
            // pas mesuré au pixel"), and the SAME value at every phase
            // now ("garde la même taille pour chaque heure" -- an
            // earlier pass escalated this 0.25->0.3333 across the 5
            // phases, dropped). Veille.qml turns this into an actual
            // font.pixelSize via TextMetrics (measures this exact font/
            // string once, then solves for the size that hits the
            // target width).
            property real widthFraction: 0.29

            property bool showSeconds: true
            property bool showDate: false

            property int messageIntervalMinutes: 20
            property int messageHoldSeconds: 25

            // Not permanently on screen -- a brief pulse around each
            // round hour instead (see VeillePhase.qml's `inPulse`).
            // leadSeconds: starts this many seconds BEFORE the hour.
            // durationSeconds: total length of the pulse (so it also
            // runs durationSeconds-leadSeconds seconds PAST the hour).
            property var pulse: ({ leadSeconds: 3, durationSeconds: 10 })

            property bool muteWhileGaming: false
            property bool respectZenMode: true

            property var thresholds: ({
                dayStart: "05:00",
                normal: "22:00",
                late: "23:00",
                midnight: "00:00",
                veryLate: "01:00"
            })

            // Only `visible` left per-phase now -- opacity (a 0.4->1.0
            // escalation) and widthFraction (0.25->0.3333) both got
            // dropped in later passes ("il faut enlever la dynamique
            // d'opacité", "garde la même taille pour chaque heure"): the
            // clock/quote are the same size and fully opaque at every
            // hour, only "day" stays hidden.
            property var phases: ({
                day:      { visible: false },
                evening:  { visible: true  },
                late:     { visible: true  },
                midnight: { visible: true  },
                veryLate: { visible: true  }
            })

            property var appFamilies: ({})
            property var tokenPatterns: ({})

            property bool debug: false
        }
    }
}
