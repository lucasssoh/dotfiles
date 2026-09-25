pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Month calendar drawer, opened by a click on the tools pill's clock.
// Fifth occupant of TOOLS' drawer band, so it follows the same
// togglePanel/close contract as the other four and closes them on the
// way in (and each of them closes this one -- see their togglePanel).
//
// Everything here is computed, nothing is fetched: French (metropolitan)
// public holidays are 8 fixed dates plus 3 that hang off Easter, and
// Easter itself is plain integer arithmetic. No network, no process, no
// cache file -- a year's table is built once, on first look, and kept.
//
// Personal events live in khal (added with Super+A, see
// hypr/scripts/agenda.py). They are read through `agenda.py export`,
// one ~0.3s khal run, on startup, on every drawer open, after every add
// or delete (the script pokes `reloadEvents` over IPC) and hourly for
// anything changed behind our back. Reminders are fired from here, off
// the wall clock -- see REMINDERS below.

Singleton {
    id: root

    property bool panelOpen: false
    property var activeScreen: null

    function togglePanel(screen) {
        if (root.panelOpen && root.activeScreen === screen) {
            root.close();
            return;
        }
        NotificationState.close();
        BaliseState.close();
        PowerState.close();
        MixerState.close();
        LauncherActionsState.close();
        root.activeScreen = screen;
        // Always reopen on the current month, wherever it was left.
        root.monthOffset = 0;
        root.panelOpen = true;
        root.reloadEvents();
    }

    function close() {
        root.panelOpen = false;
    }

    // ---- today --------------------------------------------------------
    //
    // Hours, not Minutes: the only thing that matters here is the day
    // rolling over, and an hourly tick catches midnight within the hour
    // at a sixtieth of the wakeups.
    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }

    readonly property int todayYear: clock.date.getFullYear()
    readonly property int todayMonth: clock.date.getMonth()
    readonly property int todayDay: clock.date.getDate()

    // Hourly refresh rides the same tick.
    onTodayHourChanged: root.reloadEvents()
    readonly property int todayHour: clock.date.getHours()

    // ---- shown month --------------------------------------------------

    property int monthOffset: 0

    readonly property int viewYear: {
        const d = new Date(root.todayYear, root.todayMonth + root.monthOffset, 1);
        return d.getFullYear();
    }
    readonly property int viewMonth: {
        const d = new Date(root.todayYear, root.todayMonth + root.monthOffset, 1);
        return d.getMonth();
    }

    function shiftMonth(delta) { root.monthOffset += delta; }
    function resetMonth() { root.monthOffset = 0; }

    // ---- holidays (France metropolitaine) -----------------------------

    // Month is 0-based throughout, like Date.
    function key(y, m, d) { return y + "-" + m + "-" + d; }

    // Anonymous Gregorian algorithm (Meeus/Jones/Butcher). Returns
    // { m, d } with a 0-based month.
    function easter(y) {
        const a = y % 19;
        const b = Math.floor(y / 100);
        const c = y % 100;
        const d = Math.floor(b / 4);
        const e = b % 4;
        const f = Math.floor((b + 8) / 25);
        const g = Math.floor((b - f + 1) / 3);
        const h = (19 * a + b - d - g + 15) % 30;
        const i = Math.floor(c / 4);
        const k = c % 4;
        const l = (32 + 2 * e + 2 * i - h - k) % 7;
        const m = Math.floor((a + 11 * h + 22 * l) / 451);
        const n = h + l - 7 * m + 114;
        return { m: Math.floor(n / 31) - 1, d: (n % 31) + 1 };
    }

    // year -> { key: name }. A plain JS object, not a property: filled
    // lazily and never needs to notify anything, since a given year's
    // table never changes.
    readonly property var _cache: ({})

    function holidaysOf(y) {
        if (root._cache[y] !== undefined) return root._cache[y];

        const t = {};
        const fixed = [
            [0, 1, "New Year's Day"],
            [4, 1, "Labour Day"],
            [4, 8, "Victory in Europe Day"],
            [6, 14, "Bastille Day"],
            [7, 15, "Assumption Day"],
            [10, 1, "All Saints' Day"],
            [10, 11, "Armistice Day"],
            [11, 25, "Christmas Day"]
        ];
        for (const f of fixed) t[root.key(y, f[0], f[1])] = f[2];

        const e = root.easter(y);
        const movable = [
            [1, "Easter Monday"],
            [39, "Ascension Day"],
            [50, "Whit Monday"]
        ];
        for (const mv of movable) {
            const d = new Date(y, e.m, e.d + mv[0]);
            t[root.key(d.getFullYear(), d.getMonth(), d.getDate())] = mv[1];
        }

        root._cache[y] = t;
        return t;
    }

    // Name of the holiday on that date, or "".
    function holiday(y, m, d) {
        return root.holidaysOf(y)[root.key(y, m, d)] || "";
    }

    // First holiday from today onward (today included), as
    // { date, name, days }. Scans at most this year and the next, which
    // always holds one -- Jan 1 is never more than a year away.
    readonly property var nextHoliday: {
        const today = new Date(root.todayYear, root.todayMonth, root.todayDay);
        let best = null;
        for (const y of [root.todayYear, root.todayYear + 1]) {
            const t = root.holidaysOf(y);
            for (const k in t) {
                const p = k.split("-");
                const d = new Date(parseInt(p[0]), parseInt(p[1]), parseInt(p[2]));
                if (d < today) continue;
                if (best === null || d < best.date) best = { date: d, name: t[k] };
            }
            if (best !== null) break;
        }
        // Round, not floor: a DST change makes one day 23 or 25 hours.
        best.days = Math.round((best.date - today) / 86400000);
        return best;
    }

    // ---- events (khal) ------------------------------------------------

    // [{ uid, title, allDay, start, end, alarms: [ms] }], ms epochs.
    property var events: []

    function reloadEvents() {
        if (exportProc.running) {
            root._reloadAgain = true;
            return;
        }
        exportProc.running = true;
    }
    property bool _reloadAgain: false

    Process {
        id: exportProc
        command: ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/agenda.py", "export"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.events = JSON.parse(this.text);
                } catch (e) {
                    // Keep the last good list rather than blanking it.
                }
            }
        }
        onRunningChanged: {
            if (!running && root._reloadAgain) {
                root._reloadAgain = false;
                root.reloadEvents();
            }
        }
    }

    Component.onCompleted: root.reloadEvents()

    // "y-m-d" (0-based month) -> [event], for the grid's dots and the
    // footer. An event is listed on every day it touches.
    readonly property var eventsByDay: {
        const out = {};
        for (const e of root.events) {
            const s = new Date(e.start);
            // End is exclusive: an event ending at 00:00 does not touch
            // that day.
            const last = new Date(e.end - 1);
            const d = new Date(s.getFullYear(), s.getMonth(), s.getDate());
            while (d <= last) {
                const k = root.key(d.getFullYear(), d.getMonth(), d.getDate());
                (out[k] = out[k] || []).push(e);
                d.setDate(d.getDate() + 1);
            }
        }
        return out;
    }

    function eventsOn(y, m, d) {
        return root.eventsByDay[root.key(y, m, d)] || [];
    }

    // First event that has not ended yet, or null.
    readonly property var nextEvent: {
        const now = minuteClock.date.getTime();
        for (const e of root.events) if (e.end > now) return e;
        return null;
    }

    // ---- REMINDERS ----------------------------------------------------
    //
    // No Timer armed to the next alarm: a Qt Timer counts monotonic time,
    // which stops while the machine is suspended, so it would ring late
    // by however long the lid was shut. Instead every minute tick asks
    // "which alarms fell in (lastCheck, now]?" against the WALL clock.
    // After a resume the first tick sees the whole suspended window and
    // catches up on it -- minus alarms for events already over by then.
    //
    // lastCheck starts at load time, so a restart of the bar never
    // replays alarms that were due before it. The minute clock always
    // runs: pausing it while nothing is pending would leave lastCheck
    // stale, and the first tick after an add would then ring every alarm
    // of the new event that already lay in the past. One wakeup a minute
    // is what the bar's own clock already costs.
    property real lastCheck: Date.now()

    SystemClock {
        id: minuteClock
        precision: SystemClock.Minutes
        onDateChanged: root.checkAlarms()
    }

    function checkAlarms() {
        const now = Date.now();
        const from = root.lastCheck;
        root.lastCheck = now;
        for (const e of root.events) {
            if (e.end <= now) continue;
            for (const a of e.alarms) {
                if (a > from && a <= now) root.ring(e);
            }
        }
    }

    function ring(e) {
        const start = new Date(e.start);
        const loc = Qt.locale("fr_FR");
        const mins = Math.round((e.start - Date.now()) / 60000);
        let when;
        if (e.allDay) {
            const today = new Date(root.todayYear, root.todayMonth, root.todayDay);
            const days = Math.round((start - today) / 86400000);
            when = days <= 0 ? "Aujourd'hui" : days === 1 ? "Demain"
                : start.toLocaleDateString(loc, "dddd d MMMM");
        } else {
            const hhmm = start.toLocaleTimeString(loc, "HH:mm");
            if (mins <= 0) when = "Maintenant · " + hhmm;
            else if (mins < 60) when = "Dans " + mins + " min · " + hhmm;
            else if (mins < 1440 && start.getDate() === new Date().getDate())
                when = "Aujourd'hui · " + hhmm;
            else when = start.toLocaleDateString(loc, "dddd d MMMM") + " · " + hhmm;
        }
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Agenda",
            "-i", "x-office-calendar", e.title, when]);
    }
}
