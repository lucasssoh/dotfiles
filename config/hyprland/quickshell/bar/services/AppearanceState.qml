pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The desktop-wide light/dark preference -- the one APPLICATIONS read,
// deliberately not this bar's own ink.
//
// Scope, because it is the whole point and is easy to get wrong:
// quickshell's own colours come from BandTint.qml sampling the wallpaper,
// and Hyprland's from hyprland.lua. Neither reads any of this, and
// nothing here touches them. This singleton speaks only to the
// freedesktop appearance preference that external apps follow.
//
// TWO keys, not one, because GTK3 and GTK4 never agreed:
//
//   color-scheme  org.freedesktop.appearance's backing store. Read
//                 through the portal (xdg-desktop-portal-gtk is the
//                 settings backend here) by GTK4/libadwaita, Firefox and
//                 anything Chromium/Electron. Verified live: setting it
//                 moves the portal's own answer from 0 to 1/2 instantly,
//                 no restart, no logout.
//   gtk-theme     GTK3 apps do NOT read color-scheme at all -- nemo,
//                 which hyprland.lua autostarts as a service, is linked
//                 against libgtk-3. They follow the theme NAME, so
//                 Adwaita/Adwaita-dark has to be written alongside or
//                 half the desktop stays light while the other half
//                 turns dark.
//
// Qt is knowingly NOT covered: QT_QPA_PLATFORMTHEME is qt6ct, which
// applies its own fixed palette and ignores the freedesktop preference
// entirely (there is not even a ~/.config/qt6ct/ on this machine). Making
// Qt follow means either generating and swapping qt6ct configs or
// repointing that variable at the portal -- a visible change to every Qt
// app, which is a decision rather than a detail. Out of scope here.
//
// "prefer-light" rather than "default" for the off state: `default`
// means "no preference stated", which apps resolve to light only by
// convention. A toggle that says light should say light.
Singleton {
    id: root

    readonly property string darkValue: "prefer-dark"
    readonly property string lightValue: "prefer-light"
    readonly property string darkTheme: "Adwaita-dark"
    readonly property string lightTheme: "Adwaita"

    // Whether the desktop currently asks apps for a dark palette.
    property bool dark: false
    // False until the first read lands, so a toggle rendered during
    // startup does not flash the wrong state for a frame.
    property bool ready: false

    // ---- initial read ----
    // `gsettings get` prints the value quoted, e.g. 'prefer-dark'. Only
    // the dark case needs recognising; every other value (prefer-light,
    // default, or something a future GNOME adds) means "not dark", which
    // is the safe reading for a two-state toggle.
    Process {
        id: reader
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.dark = this.text.indexOf(root.darkValue) !== -1;
                root.ready = true;
            }
        }
    }

    // ---- live follow ----
    // `gsettings monitor` blocks and prints one line per change
    // ("color-scheme: 'prefer-dark'"), so the toggle stays honest when
    // the preference is changed from anywhere else -- another tool, a
    // script, or a second Balise panel on another monitor. Same
    // event-driven shape as AudioOutput.qml's `pactl subscribe` watcher,
    // and for the same reason: no polling for something that announces
    // itself. `exec` so the bash wrapper replaces itself rather than
    // lingering as a second process for the lifetime of the bar.
    Process {
        id: monitor
        command: ["bash", "-c", "exec gsettings monitor org.gnome.desktop.interface color-scheme"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.indexOf("color-scheme") === -1) return;
                root.dark = line.indexOf(root.darkValue) !== -1;
                root.ready = true;
            }
        }
    }

    // ---- write ----
    // Both keys in one command so the desktop never sits in a half-applied
    // state where GTK4 has flipped and GTK3 has not. `dark` is NOT set
    // optimistically here: the monitor above reports the real value back
    // within a frame or two, so letting it be the single source of truth
    // keeps the toggle from ever showing a state the system did not
    // actually reach.
    Process { id: writer }

    function setDark(on) {
        const scheme = on ? root.darkValue : root.lightValue;
        const theme = on ? root.darkTheme : root.lightTheme;
        writer.command = ["bash", "-c",
            "gsettings set org.gnome.desktop.interface color-scheme '" + scheme + "'; "
          + "gsettings set org.gnome.desktop.interface gtk-theme '" + theme + "'"];
        writer.running = true;
    }

    function toggle() { root.setDark(!root.dark); }
}
