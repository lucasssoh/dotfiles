import QtQuick
import Quickshell

// Time -> escalation phase. Pure logic, no rendering (Veille.qml wires
// fontSize/opacity onto the actual Text) -- kept separate so the
// wrap-around-midnight arithmetic can be read (and eventually tested) on
// its own, without the rest of the overlay's plumbing around it.
//
// The five thresholds (dayStart/normal/late/midnight/veryLate) all cross
// midnight at different points relative to each other, so they can't be
// compared as plain "HH:mm" strings or minute-of-day ints -- 00:30 is
// NOT less than 23:00 in wall-clock terms, but it IS later in the
// evening. Fixed by remapping everything into minutes-SINCE-dayStart
// (`m()` below): dayStart itself always lands on 0, and every other
// threshold falls somewhere in [0, 1440) in the order the evening
// actually unfolds. The current phase is then just "the highest
// threshold whose m() is <= now's m()" -- a single linear scan, no
// special-cased midnight branch.
//
// Also owns the hourly PULSE (see `inPulse` below): the phase/tier
// (size, opacity, whether messages are allowed) is a function of time
// alone, same as before, but the overlay is only actually mapped to the
// screen for a brief window around each round hour -- not permanently
// for the whole evening.
Scope {
    id: root

    // Injected, not read directly from a live SystemClock here -- lets
    // Veille.qml's debug `setNow` hook (see its own header) drive this
    // exactly like a real clock tick, and keeps this file a pure function
    // of its inputs.
    property date now: new Date()
    property var config: null   // VeilleConfig instance

    readonly property var thresholds: root.config ? root.config.thresholds : ({})
    readonly property var phaseDefs: root.config ? root.config.phases : ({})

    // Ordered oldest -> latest in the evening's own timeline. "day" has
    // no configurable threshold of its own -- it IS dayStart, m() = 0 by
    // construction -- so it's always a valid fallback and the scan below
    // never comes up empty.
    readonly property var order: ["day", "evening", "late", "midnight", "veryLate"]
    readonly property var thresholdKey: ({
        day: "dayStart", evening: "normal", late: "late",
        midnight: "midnight", veryLate: "veryLate"
    })

    function parseMinutes(hhmm) {
        if (!hhmm || typeof hhmm !== "string") return 0;
        const parts = hhmm.split(":");
        const h = parseInt(parts[0], 10) || 0;
        const min = parseInt(parts[1], 10) || 0;
        return ((h * 60 + min) % 1440 + 1440) % 1440;
    }

    readonly property int dayStartMinutes: parseMinutes(root.thresholds.dayStart || "05:00")

    // Minutes elapsed since dayStart, wrapping through midnight.
    function m(minuteOfDay) {
        return ((minuteOfDay - root.dayStartMinutes) % 1440 + 1440) % 1440;
    }

    readonly property int nowMinutes: root.now.getHours() * 60 + root.now.getMinutes()
    readonly property int nowM: m(root.nowMinutes)

    readonly property string phaseName: {
        let best = "day";
        for (let i = 0; i < order.length; i++) {
            const name = order[i];
            const key = thresholdKey[name];
            const thresholdM = (name === "day") ? 0 : m(parseMinutes(root.thresholds[key]));
            if (thresholdM <= root.nowM) best = name;
        }
        return best;
    }

    readonly property var phase: root.phaseDefs[root.phaseName] || { visible: true, fontSize: 48, opacity: 0.5 }
    readonly property int fontSize: root.phase.fontSize !== undefined ? root.phase.fontSize : 48
    readonly property real targetOpacity: root.phase.opacity !== undefined ? root.phase.opacity : 0.5
    // Asked for: the clock has no business being on screen in broad
    // daylight -- "il est censé être là la nuit surtout". Per-phase, not
    // a single hardcoded cutoff, so a night-shift schedule (or just a
    // different taste) can flip which tiers show by editing veille.json
    // rather than this file. Defaults to visible when a phase entry
    // omits the key, so an old/partial config (or the "day" fallback
    // object two lines up) never goes invisible by accident.
    readonly property bool phaseVisible: root.phase.visible !== undefined ? root.phase.visible : true

    // How much a message's cooldown should shrink at this phase -- later
    // phases nag more often, asked for ("le cooldown se réduit"). Not
    // config-exposed: this is the shape of the escalation itself, not a
    // tunable like the thresholds/sizes are.
    readonly property real intervalFactor: {
        if (root.phaseName === "midnight") return 0.75;
        if (root.phaseName === "veryLate") return 0.5;
        return 1.0;
    }

    // Only late/midnight/veryLate ever show a message -- day/evening stay
    // silent, asked for ("horloge discrète" with no nagging before 22h).
    readonly property bool messagesEnabled:
        root.phaseName === "late" || root.phaseName === "midnight" || root.phaseName === "veryLate"

    // ---- hourly pulse ---------------------------------------------------
    // Asked for: not permanently on screen even during a visible phase --
    // "il ne faut pas qu'il soit constamment là", just a brief appearance
    // around each round hour ("les heures piles"), starting a little
    // early since second-precision is available to place it exactly:
    // "3 secondes avant". leadSeconds is how early the pulse starts
    // relative to the hour mark, pulseSeconds is its total length (so it
    // also runs pulseSeconds-leadSeconds PAST the hour) -- fires every
    // hour a visible phase is active, not just the 4 configured
    // thresholds, so e.g. 2am/3am during veryLate still pulses even
    // though neither has a threshold of its own.
    readonly property int leadSeconds:
        (root.config && root.config.pulse && root.config.pulse.leadSeconds !== undefined)
            ? root.config.pulse.leadSeconds : 3
    readonly property int pulseSeconds:
        (root.config && root.config.pulse && root.config.pulse.durationSeconds !== undefined)
            ? root.config.pulse.durationSeconds : 10

    readonly property int secIntoHour: root.now.getMinutes() * 60 + root.now.getSeconds()
    readonly property int trailingSeconds: Math.max(0, root.pulseSeconds - root.leadSeconds)
    readonly property bool inPulse:
        root.secIntoHour >= (3600 - root.leadSeconds) || root.secIntoHour < root.trailingSeconds

    // Minutes elapsed since a given named threshold (e.g. "late"),
    // wrapping through midnight the same way the phase computation does
    // -- used for the {hours} message slot ("how long since things got
    // late"), not a per-app session timer (nothing in this file tracks
    // how long any window has held focus).
    function minutesSince(thresholdName) {
        const raw = root.thresholds[thresholdName];
        if (raw === undefined) return 0;
        return root.nowM - root.m(root.parseMinutes(raw));
    }

    // Real calendar-day rollover (23:59:59 -> 00:00:00), independent of
    // where `midnight` the THRESHOLD happens to be configured -- the spec
    // calls this its own special event ("un événement particulier"), not
    // just another phase transition. Tracked as a plain day-string so it
    // fires exactly once per actual rollover, not once per phase
    // recompute.
    property string lastSeenDay: Qt.formatDateTime(root.now, "yyyy-MM-dd")
    signal midnightCrossed()

    onNowChanged: {
        const day = Qt.formatDateTime(root.now, "yyyy-MM-dd");
        if (day !== root.lastSeenDay) {
            root.lastSeenDay = day;
            root.midnightCrossed();
        }
    }
}
