pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "."

// Third drawer on toolsIsland, beside NotificationState, BaliseState and
// MixerState, and built to the same shape: panelOpen/activeScreen/
// togglePanel/close, with the other three closed pre-emptively so the
// four are mutually exclusive rather than stacking (see
// NotificationState.qml's own note on why that rule exists for this
// island and not for centerIsland's).
//
// What it adds over those two is a HISTORY, and the reason this file is
// short is that nothing here samples anything. upowerd already keeps a
// rate/charge/time-empty history for every battery it knows about, at 30s
// resolution, and exposes it on the device's own DBus interface:
//
//   org.freedesktop.UPower.Device.GetHistory(type, timespan, resolution)
//     -> a(uus): [(timestamp, value, state), ...], NEWEST FIRST
//
// It answers unprivileged, and `resolution` is the number of points to
// return -- upowerd buckets and averages down to that count itself, which
// is exactly what a fixed-width sparkline wants and saves this file from
// doing its own downsampling. Measured on this machine: 4820 points
// spanning 96.8h were already on disk before a line of this existed.
//
// TWO series are pulled, for two different jobs:
//
//   charge  the % over time, which is what the drawer DRAWS. Sparse by
//           nature -- upowerd writes a point when the level changes, not
//           on a clock -- so 24h is ~83 points and 3 days ~189, which is
//           plenty for a curve and nothing for a timer.
//   rate    the watts, NOT drawn any more, kept only as the 15-minute
//           window medianWatts is taken from. See that property.
//
// So: no Timer in SystemStats.qml, no ring buffer, no /sys/class/
// power_supply/BAT0/power_now poll of our own. Adding one would have been
// the obvious design and it would have duplicated, badly and only while
// the bar is running, a history the system keeps anyway. The live half
// (changeRate/timeToEmpty/energy) is DBus-pushed through
// UPower.displayDevice, which Battery.qml has been binding to all along.
//
// The one real cost is the two gdbus calls below, and they only run while
// the drawer is actually open -- see refreshTimer.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // open / close
    // ---------------------------------------------------------------

    property bool panelOpen: false
    property var activeScreen: null

    function togglePanel(screen) {
        if (root.panelOpen && root.activeScreen === screen) {
            root.close();
            return;
        }
        NotificationState.close();
        BaliseState.close();
        MixerState.close();
        // ...and the Launchers panel, which lives on its own island
        // but whose drawer band overlaps this one's -- see
        // LauncherActionsState.toggleFor.
        LauncherActionsState.close();
        CalendarState.close();
        root.activeScreen = screen;
        root.panelOpen = true;
        // Same "just opened" refresh BaliseState.togglePanel does, and for
        // the same reason: waiting out a 30s tick before the curve appears
        // would make the drawer look broken on open.
        root.refresh();
    }

    function close() {
        root.panelOpen = false;
    }

    // ---------------------------------------------------------------
    // live device state
    // ---------------------------------------------------------------
    //
    // Deliberately re-derived here rather than imported from Battery.qml:
    // that module is instantiated once PER MONITOR and carries its own
    // preview-override plumbing, while this is one singleton feeding one
    // drawer. Same UPower object underneath either way, no extra cost.

    readonly property var device: UPower.displayDevice
    readonly property bool present: device && device.isLaptopBattery && device.ready
    // *100: percentage is a 0..1 double, not an already-scaled percent --
    // the same trap documented at length in Battery.qml.
    readonly property real pct: root.present ? root.device.percentage * 100 : 0
    readonly property bool charging: root.present && root.device.state === UPowerDeviceState.Charging
    readonly property bool discharging: root.present && root.device.state === UPowerDeviceState.Discharging
    // Absolute: UPower reports changeRate unsigned, but be defensive --
    // a negative here would flip the whole curve below the axis.
    readonly property real watts: root.present ? Math.abs(root.device.changeRate) : 0
    readonly property real energy: root.present ? root.device.energy : 0
    readonly property real energyFull: root.present ? root.device.energyCapacity : 0

    // ---------------------------------------------------------------
    // displayed span
    // ---------------------------------------------------------------

    // 0 is the sentinel for "since boot" -- the shell script resolves it
    // against /proc/uptime at fetch time, because the answer changes every
    // second and pulling it into a property here would mean another
    // FileView re-read on a timer for a number only this one command ever
    // uses.
    property int spanSeconds: 86400
    // 1h and 6h are gone with the watts curve they were for: the level
    // moves a few percent an hour, so an hour of it is a flat line. What
    // is worth looking at on a % axis is a session, a day, or the shape
    // across several charge cycles.
    readonly property var spanOptions: [
        { label: "Active", value: "0" },
        { label: "24h", value: "86400" },
        { label: "3d", value: "259200" }
    ]

    function setSpan(seconds) {
        if (root.spanSeconds === seconds) return;
        root.spanSeconds = seconds;
        root.refresh();
    }

    // ---------------------------------------------------------------
    // history
    // ---------------------------------------------------------------

    // [{ t, pct, s }, ...], OLDEST FIRST (upower hands them back newest
    // first; _ingest reverses once here so every consumer can just walk
    // the array left to right). `s` is UPower's device state for that
    // point -- 1 charging, 2 discharging -- and it is what colours the
    // line, so it is carried through rather than filtered down to a
    // boolean.
    //
    // State 0 rows are dropped on the way in and dropping them is not
    // cosmetic: upowerd writes a 0.0 marker at daemon start and around
    // suspend, and on a 0-100 axis those plunge the curve to the floor
    // and back at every session boundary. Measured on this machine, the
    // 3-day window holds 11 of them against 189 real points.
    property var samples: []

    // Where the x axis begins and ends. The right edge is NOW rather than
    // the last sample: with a sparse series the newest point can be
    // several minutes old, and pinning the axis to it would make the
    // whole curve creep rightwards between refreshes.
    property real axisStart: 0
    property real axisEnd: 0

    // Above this, two consecutive points are not joined. Fixed rather
    // than derived from the span, because what it detects is physical --
    // the machine was suspended or off -- and that does not scale with
    // how much of it you are looking at.
    //
    // Six hours, arrived at by looking at what a shorter one did. An hour
    // was the first guess and it was wrong: upowerd writes a point when
    // the LEVEL changes, not on a clock, so a machine sitting on the
    // mains or idling barely under load legitimately goes hours between
    // points. Measured over 3 days, the gaps run median 404s, p90 1229s,
    // then 4966s (35% -> 55%, a charge nobody logged the middle of),
    // 7744s (58% -> 57%, on and idle) and 15131s -- all of them real
    // continuous use. Only past six hours does the pattern change
    // character entirely: 36597s, 38784s, 39671s, each one an overnight,
    // each ending one percent below where it started. A one-hour
    // threshold cut a normal day into five floating islands; six hours
    // cuts exactly the nights.
    readonly property int gapSeconds: 21600

    property bool loaded: false

    // Median draw over the last 15 minutes, and the whole reason the
    // estimate below is worth showing.
    //
    // UPower's own timeToEmpty is instantaneous and violently noisy: two
    // consecutive samples 74s apart on this machine read 25574s (7.1h) and
    // 56233s (15.6h), a factor of 2.2, because the rate they divide by
    // swings 2.3W -> 8.3W with whatever the CPU happens to be doing. Shown
    // raw it is not an estimate, it is a dice roll, and it would be
    // visibly unstable at the exact moment someone opens the drawer to
    // check it.
    //
    // Median rather than mean: a build kicking off is an outlier, not a
    // change in the trend, and the mean chases it while the median
    // ignores it.
    property real medianWatts: 0

    // Seconds until empty (discharging) or until full (charging), from
    // medianWatts. 0 means "no usable estimate" -- at rest on AC, or
    // before the first history arrives.
    readonly property real estimateSeconds: {
        // Below this the division explodes into days and means nothing.
        if (root.medianWatts <= 0.05) return 0;
        if (root.charging) {
            const remaining = root.energyFull - root.energy;
            return remaining > 0 ? remaining / root.medianWatts * 3600 : 0;
        }
        if (root.discharging) return root.energy / root.medianWatts * 3600;
        return 0;
    }

    // ---------------------------------------------------------------
    // fetch
    // ---------------------------------------------------------------

    function refresh() {
        // Re-entrancy guard: the 30s timer and a span change can land on
        // the same frame, and a second start would orphan the first
        // collector's output.
        if (!root.present || historyProc.running) return;
        historyProc.command = ["sh", "-c", root._script];
        historyProc.running = true;
    }

    // Both series in ONE process: the charge history the curve is drawn
    // from, and a fixed 15min window of `rate` for medianWatts. The
    // second must NOT follow the displayed span -- at a 3-day span there
    // is no such thing as "the last 15 minutes" in the display series.
    // Two gdbus calls, one sh, one fork.
    //
    // A span of 0 means "since this machine came up" and is resolved here
    // against /proc/uptime, in the shell that is forking anyway, rather
    // than by a FileView re-read on a timer in QML. Floored at 10 minutes
    // so opening the drawer right after a boot draws a short axis instead
    // of a degenerate one.
    //
    // The device path is discovered inline on every call rather than
    // cached in a property: it is one exec of upower against a fork this
    // shell is doing anyway, and it means a battery that re-enumerates
    // (a dock, a suspend/resume that re-probes) is picked up with no
    // invalidation logic here at all.
    //
    // LC_ALL=C is load-bearing, not hygiene: this session runs under
    // fr_FR and the parser below expects `6.585`, not `6,585`.
    readonly property string _script:
        "export LC_ALL=C; " +
        "dev=$(upower -e 2>/dev/null | grep -m1 -i bat); " +
        "[ -n \"$dev\" ] || exit 0; " +
        "span=" + root.spanSeconds + "; " +
        "[ \"$span\" -eq 0 ] && span=$(awk '{printf \"%d\", $1}' /proc/uptime); " +
        "[ \"$span\" -lt 600 ] && span=600; " +
        "g() { gdbus call --system --dest org.freedesktop.UPower " +
        "--object-path \"$dev\" " +
        "--method org.freedesktop.UPower.Device.GetHistory \"$1\" \"$2\" \"$3\" 2>/dev/null; }; " +
        "echo \"#SPAN $span\"; " +
        "g charge \"$span\" 200; " +
        "echo '#RATE'; " +
        "g rate 900 30"

    Process {
        id: historyProc
        stdout: StdioCollector {
            onStreamFinished: root._ingest(this.text)
        }
    }

    // Repeats only while the drawer is on screen, at upowerd's own
    // sampling interval -- polling faster would re-fetch points that
    // cannot have changed.
    Timer {
        id: refreshTimer
        interval: 30000
        repeat: true
        running: root.panelOpen && root.present
        onTriggered: root.refresh()
    }

    // ---------------------------------------------------------------
    // parsing
    // ---------------------------------------------------------------

    // gdbus prints the a(uus) as
    //   ([(uint32 1789800683, 6.585, uint32 2), (1789800652, 4.552, 2)],)
    // -- the `uint32` tag appears on the first tuple's fields only, hence
    // the optional group. The outer `([...],)` cannot match this shape
    // (no digit,float,digit triple), so it needs no special handling.
    // `v` is watts in the rate series and percent in the charge one.
    function _points(text) {
        const out = [];
        const re = /\((?:uint32\s+)?(\d+),\s*(-?[\d.]+(?:[eE][+-]?\d+)?),\s*(?:uint32\s+)?(\d+)\)/g;
        let m;
        while ((m = re.exec(text)) !== null) {
            out.push({ t: parseInt(m[1]), v: parseFloat(m[2]), s: parseInt(m[3]) });
        }
        return out;
    }

    function _median(values) {
        if (values.length === 0) return 0;
        const s = values.slice().sort((a, b) => a - b);
        const mid = Math.floor(s.length / 2);
        return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
    }

    function _ingest(text) {
        const parts = text.split("#RATE");
        const head = parts[0] || "";
        const rateText = parts[1] || "";

        const spanMatch = head.match(/#SPAN\s+(\d+)/);
        const span = spanMatch ? parseInt(spanMatch[1]) : root.spanSeconds;

        // The #SPAN line is `#SPAN 86400` -- one number, not a triple, so
        // _points cannot mistake it for a sample.
        const charge = root._points(head);

        // Keep charging (1) and discharging (2), drop the 0 markers --
        // see the note on `samples`. Reversed on the way in: upower hands
        // back newest first.
        const clean = [];
        for (let i = charge.length - 1; i >= 0; i--) {
            const p = charge[i];
            if (p.s === 1 || p.s === 2) clean.push({ t: p.t, pct: p.v, s: p.s });
        }

        // `up` -- was the level RISING into this point -- and it, not the
        // `s` UPower reports, is what colours the curve.
        //
        // Found by looking at a chart that drew an unmistakable 19% ->
        // 100% climb in blue. UPower's state belongs to the sample, and
        // at a bucket boundary the sample that closes a charge has
        // already been taken after the charger came out: the pair
        // (19:13, 19%, charging) -> (20:54, 100%, discharging) describes
        // a charge whose endpoint says "discharging", so keying the
        // segment off the arriving point's state paints the whole climb
        // wrong. The direction of the line cannot disagree with itself
        // that way -- if the level went up, the battery was charging,
        // whatever the bucket's label says.
        for (let i = 0; i < clean.length; i++) {
            clean[i].up = i > 0 && clean[i].pct > clean[i - 1].pct;
        }

        // Only rate samples taken in the SAME direction the battery is
        // going now: mixing a charge burst into a discharge estimate
        // would halve it.
        const wanted = root.charging ? 1 : 2;
        const rates = [];
        for (const p of root._points(rateText)) if (p.s === wanted) rates.push(p.v);

        const now = Date.now() / 1000;
        root.samples = clean;
        // axisStart BEFORE axisEnd, and the order is load-bearing.
        // Bindings re-evaluate between these two statements, so the
        // other order leaves one frame where axisEnd is `now` and
        // axisStart is still 0 -- a span of 57 years, which PowerCurve's
        // tick generator turned into ten thousand labels. It took the
        // shell to 104% CPU and 4.5GB RSS. Setting start first makes the
        // transient span negative instead, which every consumer already
        // clamps away.
        root.axisStart = now - span;
        root.axisEnd = now;
        root.medianWatts = root._median(rates);
        root.loaded = true;
    }
}
