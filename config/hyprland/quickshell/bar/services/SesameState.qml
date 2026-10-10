pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The password card. The asks come from the `sesame` daemon
// (config/hyprland/sesame-src): the polkit agent, ssh and git through
// SSH_ASKPASS, gpg through its pinentry. This file connects to its socket
// ($XDG_RUNTIME_DIR/sesame.sock, JSON lines, same shape as Manette's),
// shows the first ask and sends the answer back. The daemon takes the
// shell's own process as the only one allowed to answer.
//
// Nothing is kept here: the typed secret goes out in one message and the
// field is cleared (SesameCard.qml).
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sesame.sock"

    // [{ id, kind, title, message, echo, confirm, error, chain: [..] }],
    // in the daemon's order. kind: "ssh" | "git" | "gpg" | "polkit".
    property var asks: []
    // Made-up asks, to look at the card without asking for anything real:
    // `qs -c bar ipc call bar sesameDemo ssh`. Answering one does nothing.
    property var demoAsks: []

    readonly property var current: {
        const all = root.asks.concat(root.demoAsks);
        return all.length > 0 ? all[0] : null;
    }
    readonly property bool open: root.current !== null
    // True while the card is on screen or fading out (see shell.qml).
    readonly property bool shown: root.open || lingerTimer.running
    // What the card shows, kept through the fade-out once answered.
    property var card: null
    property string screenName: ""

    onCurrentChanged: {
        if (root.current) {
            if (!root.card || lingerTimer.running || !root.shown)
                root.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            lingerTimer.stop();
            root.card = root.current;
        } else {
            lingerTimer.restart();
        }
    }

    function answer(secret) {
        const a = root.current;
        if (!a) return;
        if (a.demo) {
            root.demoAsks = root.demoAsks.filter(d => d.id !== a.id);
            return;
        }
        root._send({ cmd: "answer", id: a.id, secret: secret });
        root.asks = root.asks.filter(x => x.id !== a.id);
    }

    function cancel() {
        const a = root.current;
        if (!a) return;
        if (a.demo) {
            root.demoAsks = root.demoAsks.filter(d => d.id !== a.id);
            return;
        }
        root._send({ cmd: "cancel", id: a.id });
        root.asks = root.asks.filter(x => x.id !== a.id);
    }

    property int _demoSeq: 0
    function demo(kind) {
        const samples = {
            ssh: { kind: "ssh", title: "Unlock SSH key", message: "Enter passphrase for key '~/.ssh/id_ed25519'", echo: false, confirm: false, error: "",
                   chain: ["claude", "git push origin master", "ssh git@github.com git-receive-pack 'lucasssoh/dotfiles.git'"] },
            polkit: { kind: "polkit", title: "Authentication required", message: "Authentication is needed to run `/usr/bin/dnf' as the super user", echo: false, confirm: false, error: "",
                      chain: ["cc-pkg-mng upgrade", "pkexec /usr/bin/dnf upgrade --refresh"] },
            gpg: { kind: "gpg", title: "Unlock GPG key", message: "Please enter the passphrase to unlock the OpenPGP secret key:\n\"Lucas <lucas@example.org>\"\n255-bit EDDSA key, ID 4E2A91C0", echo: false, confirm: false, error: "",
                   chain: ["bash packaging/make-repo.sh", "gpg --detach-sign --armor repomd.xml"] },
            retry: { kind: "ssh", title: "Unlock SSH key", message: "Enter passphrase for key '~/.ssh/id_ed25519'", echo: false, confirm: false, error: "Wrong passphrase. Try again.",
                     chain: ["git push", "ssh git@github.com git-receive-pack 'lucasssoh/wallpapers.git'"] },
            confirm: { kind: "ssh", title: "Unknown host", message: "The authenticity of host 'github.com' can't be established.\nED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.\nAre you sure you want to continue connecting (yes/no/[fingerprint])?", echo: true, confirm: false, error: "",
                       chain: ["git clone git@github.com:lucasssoh/dotfiles.git", "ssh git@github.com git-upload-pack 'lucasssoh/dotfiles.git'"] }
        };
        const s = samples[kind] || samples.ssh;
        root._demoSeq++;
        root.demoAsks = root.demoAsks.concat([Object.assign({ id: -root._demoSeq, demo: true }, s)]);
    }

    // Outlives the answer by the fade, so the card is not cut mid-animation.
    Timer {
        id: lingerTimer
        interval: 200
    }

    function _handleLine(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.event === "asks") {
            const list = msg.asks || [];
            if (JSON.stringify(list) !== JSON.stringify(root.asks)) root.asks = list;
        }
    }

    function _send(obj) {
        const sock = socketLoader.item;
        if (!sock || !sock.connected) return false;
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
        return true;
    }

    readonly property bool daemonConnected: socketLoader.item ? socketLoader.item.connected : false
    onDaemonConnectedChanged: {
        if (root.daemonConnected) root._send({ cmd: "hello" });
        // The daemon cancels what was waiting when the bar goes; the
        // other way round, nothing is left to answer.
        else root.asks = [];
    }

    // Rebuilt rather than reconnected, for the reason BaliseState.qml gives:
    // a Quickshell Socket never comes back once it has failed.
    Loader {
        id: socketLoader
        active: true
        sourceComponent: Component {
            Socket {
                path: root.socketPath
                connected: true
                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => root._handleLine(line)
                }
            }
        }
    }

    Timer {
        id: reconnectTimer
        property int tries: 0
        interval: Math.min(30000, 2000 * Math.pow(2, Math.min(tries, 4)))
        repeat: true
        running: !root.daemonConnected
        onRunningChanged: if (!running) tries = 0
        onTriggered: {
            tries++;
            socketLoader.active = false;
            socketLoader.active = true;
        }
    }
}
