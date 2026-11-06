pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The time the shell shows. Every clock on screen (the bar, the
// notification centre, the calendar, Veille) passes its own SystemClock's
// date through `at()`, so that a simulated time moves all of them at once
// instead of only the one it was set on.
//
// Each component keeps its own SystemClock and its own precision: Veille
// ticks every second, the bar every minute, the calendar every hour. A
// single shared clock would have to tick at the finest of them for
// everyone, all the time.
//
// Real time drives everything else: the agenda's alarms, notification
// stamps, Programme's sessions. A simulated time never rings a reminder.
//
//   qs -c bar ipc call clock set "02:00"            from 02:00 today, then ticking
//   qs -c bar ipc call clock freeze "02:00:00"      stuck at 02:00:00, for screenshots
//   qs -c bar ipc call clock freeze "2026-12-24 18:30"
//   qs -c bar ipc call clock reset                  back to the real time
//   qs -c bar ipc call clock now                    what the shell shows, as text
Singleton {
    id: root

    // Added to the real time while `frozenMs` is negative.
    property real offsetMs: 0
    // The shown time, in ms since the epoch, while it is frozen; -1 otherwise.
    property real frozenMs: -1

    readonly property bool simulated: root.offsetMs !== 0 || root.frozenMs >= 0

    // The time to show for a clock reading `real`. Read inside a binding,
    // it re-evaluates when the reading or the simulation changes.
    function at(real) {
        if (root.frozenMs >= 0) return new Date(root.frozenMs);
        return new Date(real.getTime() + root.offsetMs);
    }

    // The time to show right now, for code that runs once rather than
    // binding to a clock.
    function now() {
        return root.at(new Date());
    }

    // "HH:MM", "HH:MM:SS" (today), or "YYYY-MM-DD HH:MM[:SS]". -1 when the
    // text is none of them.
    function _parse(spec) {
        const m = /^\s*(?:(\d{4})-(\d{2})-(\d{2})\s+)?(\d{1,2}):(\d{2})(?::(\d{2}))?\s*$/.exec(spec);
        if (!m) return -1;
        const today = new Date();
        const d = m[1]
            ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0))
            : new Date(today.getFullYear(), today.getMonth(), today.getDate(),
                       +m[4], +m[5], +(m[6] || 0));
        return d.getTime();
    }

    readonly property string _usage: "expected HH:MM, HH:MM:SS or YYYY-MM-DD HH:MM[:SS]"

    // From `spec` on, then ticking. Returns "" or what was wrong.
    function setTime(spec) {
        const t = root._parse(spec);
        if (t < 0) return root._usage;
        root.frozenMs = -1;
        root.offsetMs = t - Date.now();
        return "";
    }

    // Stuck at `spec`. Returns "" or what was wrong.
    function freezeTime(spec) {
        const t = root._parse(spec);
        if (t < 0) return root._usage;
        root.offsetMs = 0;
        root.frozenMs = t;
        return "";
    }

    function reset() {
        root.offsetMs = 0;
        root.frozenMs = -1;
    }

    IpcHandler {
        target: "clock"

        function set(spec: string): string {
            return root.setTime(spec) || root.now().toString();
        }

        function freeze(spec: string): string {
            return root.freezeTime(spec) || root.now().toString();
        }

        function reset(): void {
            root.reset();
        }

        function now(): string {
            return root.now().toString();
        }
    }
}
