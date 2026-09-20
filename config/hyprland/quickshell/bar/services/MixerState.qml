pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "."

// Fourth drawer on toolsIsland, beside NotificationState, BaliseState and
// PowerState, built to the same shape: panelOpen/activeScreen/
// togglePanel/close, with the other three closed pre-emptively so the
// four are mutually exclusive rather than stacking (see
// NotificationState.qml's own note on why that rule exists for this
// island and not for centerIsland's).
//
// What this one replaces is the ONE remaining place in the bar where a
// control shelled out to an external UI to do something the process
// already had live handles on. AudioOutput.qml's left click ran
// `audio.sh roue-gen && roue audio-output` -- a script that re-generated
// a wheel config from `pactl list sinks`, then launched a separate
// process to draw it -- purely to pick a sink. Per-application volume had
// no in-bar path at all: right click opened pavucontrol, a whole GTK app,
// for a row of sliders.
//
// Both are plain property writes here:
//
//   Pipewire.preferredDefaultAudioSink = node     picks the output
//   node.audio.volume = v                          moves any slider
//
// so nothing in the drawer's actions shells out. The single Process in
// this file is a READ, and it is there because pipewire does not expose
// the one fact that decides whether those actions can succeed at all --
// see `unavailable`.
//
// BINDING, and why the node lists are gated on panelOpen. Quickshell hands
// out every PwNode in the graph unbound: `name`, `nickname`, `isSink` and
// `isStream` are constant and readable straight away, but `audio.volume`,
// `audio.muted` and `properties` only track their real values while
// something holds the node in a PwObjectTracker. So the tracker below
// takes the whole displayed set, and takes it ONLY while the drawer is
// open -- binding twenty nodes permanently to render a pill that shows one
// icon would be paying for the panel at all times to avoid a frame of
// latency when it opens.
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
        PowerState.close();
        root.activeScreen = screen;
        root.panelOpen = true;
        // Availability can change while the drawer is shut (a cable goes
        // in, a headset comes out), so the answer is re-asked on the way
        // in rather than trusted from last time.
        root.refreshAvailability();
    }

    function close() {
        root.panelOpen = false;
    }

    // ---------------------------------------------------------------
    // the graph
    // ---------------------------------------------------------------

    readonly property var _all: Pipewire.nodes ? Pipewire.nodes.values : []

    // `audio` is the discriminator for "this is an audio node", not a
    // mask over `type`: it is a constant pointer (null on video nodes),
    // so it answers correctly on a node that has not been bound yet,
    // which every node in this list is until the tracker below takes it.
    //
    // Sorted by id throughout. The graph hands nodes back in whatever
    // order it enumerated them, which changes across a suspend/resume or
    // a card re-probe -- unsorted, that reshuffles the rows under the
    // pointer for no reason the user can see.
    function _pick(test) {
        const out = [];
        for (const n of root._all) if (n && n.audio && test(n)) out.push(n);
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    // Output devices. `!isStream` is what separates a sink DEVICE from an
    // application playing into one -- both report isSink true, because for
    // a playback stream the sink side is the side it feeds.
    //
    // `!_isEq` keeps the equalizer chains out, and that exclusion is not
    // cosmetic: each one is a real Audio/Sink and would otherwise sit in
    // the output picker looking like a device -- and worse,
    // `_followHardware` would treat it as newly connected hardware and make
    // it the default. A chain's own output follows the default, so the
    // default being a chain means the chain feeding itself.
    readonly property var sinks: root._pick(
        n => n.isSink && !n.isStream && !root._isEq(n))

    // Both halves of every chain: the sinks applications are routed INTO,
    // and the streams they play OUT of. Matched on the two prefixes
    // 50-equalizer.conf promises rather than on four literal names, so a
    // fifth slot needs no change here.
    //
    // The exclusion is load-bearing twice over, and both were found by
    // running into them. An equalizer sink is an Audio/Sink like any other,
    // so without this it sits in the output picker looking like a device --
    // and `_followHardware` treats it as newly connected hardware and makes
    // it the default, which means the chain feeding itself. Measured
    // exactly that way with a test chain: it appeared, and the bar made it
    // the default output within the second.
    function _isEq(n) {
        return n.name.indexOf("eq_slot_") === 0 || n.name.indexOf("eq_out_") === 0;
    }

    // Input devices. The `.monitor` guard is belt and braces and it is
    // worth saying why it never fires: `pactl list sources` shows four
    // monitor sources here, one per sink, and NONE of them reach this
    // list, because a monitor is not a node. It is a set of output ports
    // ON the sink node, and the standalone "Monitor of ..." source is a
    // shape the pulse protocol invents for clients that cannot see ports.
    // Quickshell reads the graph, so it never sees them.
    //
    // Kept anyway, for one line: if that ever stops being true the
    // symptom would be "Monitor of HDMI / DisplayPort 3 Output" offered
    // as a microphone, and worse, auto-selected as one by
    // `_followHardware` the first time a sink appears.
    //
    // On `name` rather than properties["device.class"] == "monitor",
    // which is the more explicit test and the wrong one here: `properties`
    // needs the node bound, and this list is what DECIDES what to bind.
    // The `.monitor` suffix is on the constant `name`.
    readonly property var sources: root._pick(
        n => !n.isSink && !n.isStream && !/\.monitor$/.test(n.name))

    // Applications playing audio. `_isEq` bars the equalizer's own output
    // stream, which is a Stream/Output/Audio like any player and showed up
    // in the list as an application called "Equalizer" -- the chain
    // offering itself a volume slider and an EQ button that would have
    // routed it into itself.
    readonly property var streams: root._pick(
        n => n.isStream && n.isSink && !root._isOurs(n) && !root._isEq(n))
    // ...and applications listening. Shown only when non-empty, under the
    // input section: "what has my microphone open" is the question that
    // list answers, and it has no other answer anywhere in this bar.
    readonly property var recordStreams: root._pick(
        n => n.isStream && !n.isSink && !root._isOurs(n))

    // The bar's own streams, out of both lists. Not hygiene -- a
    // correctness fix with a visible symptom: the two PwNodePeakMonitors
    // below are themselves capture streams, so the first build of this
    // drawer listed "Quickshell Peak Detect" twice under INPUT. The panel
    // was reporting, as applications holding the microphone open, the two
    // meters it had just opened to draw itself.
    //
    // Matched on `name`, which is pipewire's `node.name` and is
    // "quickshell" for anything this process opens (checked against
    // `pactl list source-outputs`, where application.name is the pretty
    // "Quickshell Peak Detect" and node.name is the bare one). Constant,
    // so it answers on an unbound node -- which matters, because this
    // test runs inside the very lists that decide what gets bound.
    function _isOurs(n) { return n.name === "quickshell"; }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // `preferredDefaultAudioSink`, not `defaultAudioSink` -- the latter is
    // read-only and reports what is CURRENTLY default, the former is the
    // configured preference and is what actually moves it. Writing it is
    // the whole of what the roue wheel's generated config plus
    // `pactl set-default-sink` used to do.
    function setSink(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }

    function setSource(node) {
        if (node) Pipewire.preferredDefaultAudioSource = node;
    }

    // TWO trackers, because the two halves are needed for different lengths
    // of time.
    //
    // DEVICES, only while the drawer is open. Nothing about a sink is
    // needed when nobody is looking at it: its name and nickname are
    // constant properties, readable unbound, and only `audio.volume` and
    // `audio.muted` -- the two things the master sliders draw -- require
    // binding. Holding twenty nodes open permanently to avoid one frame of
    // latency on a panel that is shut most of the time is the trade this
    // refuses.
    PwObjectTracker {
        objects: root.panelOpen ? root.sinks.concat(root.sources) : []
    }

    // STREAMS, always. This one is not a display concern and gating it on
    // the drawer was a bug, found by probing `_serial` with the panel shut
    // and getting `undefined`: `properties` is empty on an unbound node,
    // `object.serial` lives in `properties`, and `object.serial` is how a
    // stream is named to `pactl move-sink-input`.
    //
    // So with the drawer closed the equalizer could not route anything --
    // which is precisely when it most needs to, since the whole point of
    // remembering an application is that starting it tomorrow puts it back
    // through the chain without anyone opening a panel.
    //
    // The cost is bounded by how many things are playing at once, which is
    // one or two, not by how many devices exist.
    PwObjectTracker {
        objects: root.streams.concat(root.recordStreams)
    }

    // ---------------------------------------------------------------
    // what can actually be selected
    // ---------------------------------------------------------------
    //
    // A picker row that does nothing when clicked is worse than no row,
    // and without this every one of them is one. Measured on this machine
    // with nothing plugged in: of four sinks, THREE are dead (HDMI 1/2/3,
    // whose ports report "not available" with no display on them), and of
    // two sources one is (the analog headset mic). Selecting a dead one is
    // not merely ineffective -- wireplumber accepts the request, refuses
    // it, and writes the old device straight back, so the tick visibly
    // fails to move. Confirmed the same way through `pactl
    // set-default-sink`, which bounces identically: this is policy, not a
    // bug in the write above.
    //
    // Pipewire cannot answer it. Availability belongs to the DEVICE ROUTE,
    // one level below PwNode, whose `properties` map does not carry it --
    // the same floor AudioOutput.qml hits looking for the active port. So:
    // one `pactl` read, which is why this file has a Process in it.
    //
    // It runs at startup (so the first open has its answer and no row
    // appears then vanishes), on every open, whenever the node lists
    // change, and on every pactl event -- see portWatcher, and see
    // `autoSwitch` for why this had to stop being gated on the drawer
    // being open.
    //
    // Failure is safe by construction: no output, or no pactl at all,
    // leaves the map empty and every device selectable, which is precisely
    // the behaviour this replaces.
    property var unavailable: ({})

    function refreshAvailability() {
        if (availProc.running) return;
        availProc.running = true;
    }

    onSinksChanged: root.refreshAvailability()
    onSourcesChanged: root.refreshAvailability()
    Component.onCompleted: root.refreshAvailability()

    // Plugging a jack or an HDMI cable does NOT change the node list.
    // That was the surprise here, and it is what this watcher exists for:
    // under ALSA UCM all four sinks are present from boot whether or not
    // anything is connected to them, and connecting a display flips its
    // port from "not available" to available without adding, removing or
    // otherwise touching a single pipewire node. Nothing in
    // Quickshell.Services.Pipewire fires for it, because from pipewire's
    // side nothing happened.
    //
    // `pactl subscribe` does fire, so it is the event source. Same
    // watch/query split StreamModule.qml and AudioOutput.qml both use: a
    // long-running watcher that only ever triggers the one-shot query
    // above, never parses anything itself.
    //
    // Debounced, because one physical plug-in emits a burst -- card,
    // sink, source and server events arrive together as wireplumber
    // re-evaluates routes -- and each would otherwise fork its own pactl.
    //
    // AudioOutput.qml runs a second `pactl subscribe` of its own, per bar,
    // for the active-port glyph. The two should be one watcher; they are
    // not yet, and that is worth knowing before adding a third.
    Process {
        id: portWatcher
        running: true
        command: ["bash", "-c", "export LC_ALL=C; exec pactl subscribe"]
        stdout: SplitParser {
            onRead: (line) => {
                if (/ on (sink|source|card|server) #/.test(line)) watchDebounce.restart();
            }
        }
    }

    Timer {
        id: watchDebounce
        interval: 400
        onTriggered: root.refreshAvailability()
    }

    // Prints the name of every sink/source whose ACTIVE port is marked
    // unavailable, one per line.
    //
    // Keyed on the active port rather than on "any unavailable port in the
    // list": under ALSA UCM each of these carries exactly one port, but a
    // card in a classic profile has several on one sink, and there the
    // question is only ever about the one in use.
    //
    // LC_ALL=C is load-bearing, not hygiene -- this session runs under
    // fr_FR and pactl translates its own key names, so `Active Port:` and
    // `not available` are only these strings under C.
    Process {
        id: availProc
        command: ["bash", "-c",
            "export LC_ALL=C; for kind in sinks sources; do " +
            "pactl list $kind 2>/dev/null | awk '" +
            "/^(Sink|Source) #/ { name = \"\"; delete avail } " +
            "$1 == \"Name:\" { name = $2 } " +
            "/^\\t\\t\\[/ { split($0, a, \":\"); key = a[1]; gsub(/^[ \\t]+/, \"\", key); " +
            "avail[key] = ($0 ~ /not available/) ? 0 : 1 } " +
            "/^\\tActive Port: / { p = $0; sub(/^\\tActive Port: /, \"\", p); " +
            "if (name != \"\" && (p in avail) && avail[p] == 0) print name }'; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of this.text.split("\n")) {
                    const name = line.trim();
                    if (name !== "") map[name] = true;
                }
                root.unavailable = map;
            }
        }
    }

    // What the pickers actually list. The CURRENT device is never filtered
    // out of its own list, however it is marked: it is already in use, so
    // a reading of the hardware that says otherwise is the thing that is
    // wrong, and hiding it would leave a picker with no tick in it.
    readonly property var pickableSinks: root.sinks.filter(
        n => n === root.sink || !root.unavailable[n.name])
    readonly property var pickableSources: root.sources.filter(
        n => n === root.source || !root.unavailable[n.name])

    // ---------------------------------------------------------------
    // follow the hardware
    // ---------------------------------------------------------------
    //
    // Plug something in and the sound comes out of it -- and goes into it,
    // when it has an input worth using. Asked for, and not something the
    // session manager will do on its own HERE, for a reason worth writing
    // down because it is caused by this very drawer.
    //
    // WirePlumber 0.5 picks the default device by `priority.session` among
    // the available ones -- but only while nothing has been CONFIGURED.
    // The moment anything writes `default.configured.audio.sink` the
    // choice is pinned and priority stops mattering, which is exactly what
    // pinning is for. `pactl set-default-sink` writes it, and so does
    // setSink above. So the act of ever choosing an output by hand is what
    // switches the automatic behaviour off, permanently, and the fix has
    // to live on the side that did the pinning.
    //
    // (`wireplumber.policy.switch-on-connect`, set in
    // ~/.config/wireplumber/wireplumber.conf.d/10-bluetooth-policy.conf,
    // is a 0.4-era key. It is not in `wpctl settings` on 0.5.14 and does
    // nothing at all now.)
    //
    // The rule here is deliberately narrow: switch only to a device that
    // has just JOINED the selectable set. Not "the highest priority one",
    // which would undo a manual choice at the next unrelated event, and
    // not "any change", which would fight the user every time a stream
    // starts. Joining the set covers both shapes a connection takes --
    // a new node (USB, bluetooth) and a port going from unavailable to
    // available (jack, HDMI) -- because the set is built from both.
    //
    // A device leaving needs nothing: wireplumber already falls back on
    // its own when the pinned device disappears.

    // null until seeded. The seed is the first non-empty reading and it
    // switches nothing -- otherwise every boot would "connect" the
    // built-in speakers and yank the default away from whatever was
    // restored. Sinks and sources seed independently: a machine can
    // enumerate its outputs a beat before its inputs, and one empty list
    // must not hold the other's seed back.
    property var _knownSinks: null
    property var _knownSources: null

    // Newest wins when more than one arrives at once. The lists are
    // ordered by node id (see _pick), and a higher id means more recently
    // created -- so for genuinely new nodes this is "the one that just
    // appeared". For a port flipping available the id is old and the order
    // is arbitrary among equals, which is the one case where there is no
    // right answer and any of them is fine.
    function _joined(list, known) {
        let found = null;
        for (const n of list) if (known.indexOf(n.name) === -1) found = n;
        return found;
    }

    function _followHardware() {
        // Nothing may be written before the graph's metadata exists.
        // Found by restarting pipewire under a running bar: the nodes come
        // back before the metadata does, and the write lands on nothing --
        // "Cannot set default node as metadata is not ready", straight out
        // of quickshell.
        if (!Pipewire.ready) return;

        root._knownSinks = root._reseed(root.pickableSinks, root._knownSinks,
                                        root.sink, root.setSink);
        // "s'il le peut" -- a headset that arrives with a microphone takes
        // the input too; an HDMI display, which has none, simply never
        // joins this list and the input is left alone.
        root._knownSources = root._reseed(root.pickableSources, root._knownSources,
                                          root.source, root.setSource);
    }

    // Returns the new known set for one direction, switching on the way if
    // something joined. Both directions are the same three cases:
    //
    //   EMPTY   -> back to unseeded. This is the case a pipewire restart
    //             finds, and getting it wrong is loud: every device
    //             vanishes and comes back, so with `[]` remembered as the
    //             known set the whole machine reads as freshly connected
    //             and the default is yanked to an arbitrary one of them.
    //             Reproduced exactly that way, restarting the three user
    //             units under a running bar.
    //   UNSEEDED-> record and switch nothing, which is also what boot is.
    //   SEEDED  -> diff, and follow whatever joined.
    function _reseed(list, known, current, apply) {
        if (list.length === 0) return null;
        const names = list.map(n => n.name);
        if (known === null) return names;
        const joined = root._joined(list, known);
        // Already the default: nothing to do, and writing it anyway would
        // republish the metadata for no reason.
        if (joined && joined !== current) apply(joined);
        return names;
    }

    // One trigger for both shapes of connection. `pickableSinks` is
    // derived from the node list AND from `unavailable`, so it changes
    // whether a node appeared or a port merely woke up -- which is the
    // whole reason the selectable set, rather than the raw node list, is
    // what gets diffed.
    onPickableSinksChanged: root._followHardware()
    onPickableSourcesChanged: root._followHardware()

    // ---------------------------------------------------------------
    // level meters
    // ---------------------------------------------------------------
    //
    // Live peak on the two master rows only, never per application. A
    // PwNodePeakMonitor is not a property read: it opens a real capture
    // stream against the node, so the cost scales with how many are
    // running, and on a row of app sliders it would be paying for a dozen
    // streams to animate a dozen hairlines nobody is looking at.
    //
    // On the two masters it earns it -- on the input especially, where
    // "is this microphone actually picking me up" is a question no number
    // on screen answers and a moving bar answers instantly.
    //
    // `enabled` is gated on panelOpen, so both streams exist only while
    // the drawer is on screen.
    PwNodePeakMonitor {
        id: sinkMeter
        node: root.sink
        enabled: root.panelOpen
    }
    PwNodePeakMonitor {
        id: sourceMeter
        node: root.source
        enabled: root.panelOpen
    }

    readonly property real sinkPeak: sinkMeter.peak
    readonly property real sourcePeak: sourceMeter.peak

    // ---------------------------------------------------------------
    // the equalizer
    // ---------------------------------------------------------------
    //
    // The chains themselves are config/pipewire/50-equalizer.conf -- four
    // of them, pre-declared, see that file for why four and why not loaded
    // on demand. This half decides which application sits in which chain
    // and what curve it carries.
    //
    // PER APPLICATION, and that is the shape of everything below. A curve
    // belongs to an application name, not to the output: a film gets its
    // dialogue lifted while a browser in the next window is left exactly
    // alone. The name is the key rather than a node id because the whole
    // value of the setting is that it survives the application closing, and
    // a node id survives nothing.
    //
    // ONE RESIDENT pw-cli, and this is the part worth reading before
    // touching it. A filter-chain control port can only be moved by writing
    // the node's Props, and nothing in Quickshell.Services.Pipewire can
    // write Props -- PwNode exposes `audio` and `properties`, neither of
    // which reaches a filter's control ports. So it goes through pw-cli,
    // and the only question was how.
    //
    // Measured both ways on this machine:
    //
    //   a fresh `pw-cli` per write            8 ms
    //   one resident `pw-cli` fed by a pipe   83 us      (600 writes, 50 ms)
    //
    // Resident wins by two orders of magnitude, and it is what makes a band
    // audible WHILE its fader is dragged rather than only when it is let
    // go. At rest it costs nothing measurable: 0 ms of CPU over 3 s of
    // idling, 7.5 MB resident, flat across 600 writes.
    //
    // THE TRAP. If pw-cli's stdin reaches EOF it does not exit, it spins --
    // measured at 1 s of CPU in 10 s, which is how the first attempt at
    // this benchmark produced nonsense. `stdinEnabled` must therefore stay
    // true for the whole session; setting it false to "tidy up" would close
    // the pipe and leave a process burning a tenth of a core until the bar
    // is restarted. It is set once, declaratively, and never touched.
    //
    // LC_ALL=C for the same reason as every other exec in this bar: the
    // session is fr_FR, and the decimal separator of a gain written as
    // "3.5" is not negotiable.

    // Must match the slot count in 50-equalizer.conf. Not derived from
    // `eqSlots.length` below, which is what the graph happens to be
    // offering right now: this is what the bar was built against, and a
    // mismatch between the two is a misconfiguration worth seeing rather
    // than silently absorbing.
    readonly property int slotCount: 4

    // Sorted by slot number, not by node id. The four modules load in
    // whatever order the daemon gets to them, so node ids do not follow
    // the names, and "slot 0" has to mean eq_slot_0 every time or a curve
    // lands in someone else's chain.
    readonly property var eqSlots: {
        const out = [];
        for (const n of root._all) {
            if (!n || !n.name) continue;
            const m = /^eq_slot_(\d+)$/.exec(n.name);
            if (m) out.push({ index: parseInt(m[1]), node: n, name: n.name });
        }
        out.sort((a, b) => a.index - b.index);
        return out;
    }

    // The drawer's whole equalizer is gated on this. A machine that never
    // ran config/pipewire/install.sh has no chains, and a page of faders
    // wired to nothing is worse than no page.
    readonly property bool eqPresent: root.eqSlots.length > 0

    // Band centres, matching 50-equalizer.conf's own order. Labels only --
    // the frequencies live in the chains, and duplicating them as numbers
    // here would be two sources of truth for one curve.
    readonly property var bandLabels: ["60", "250", "1k", "4k", "12k"]
    // +/- 12 dB. Wide enough to fix a headphone, narrow enough that the
    // full travel of a short fader is still a fine adjustment.
    readonly property real bandRange: 12

    // ---- presets -----------------------------------------------------
    //
    // TEN. There were twenty-eight -- the whole familiar genre list plus
    // every tone-shaper -- and that was too many to choose from and too
    // many to draw: the page had to hide them behind a chevron to fit,
    // which is what made it move every time it was opened. Ten fit on the
    // page at once, so the list is simply there and the page never changes
    // height.
    //
    // What went: the near-duplicates (Electronic and Latin next to Dance,
    // R&B and Deep next to Hip-hop, Metal and Live next to Rock, Soft and
    // Piano next to Acoustic, Lounge, Reggae, Movie, Night) and the raw
    // tone-shapers, which a fader does better than a preset -- pulling the
    // 12k band down IS "treble cut", and it takes one gesture on a control
    // that is already on screen.
    //
    // What stayed is one entry per shape the curve can usefully take: flat,
    // a lift at both ends (Acoustic, Classical, Rock), bass alone (Bass
    // boost, Hip-hop), a scooped middle (Dance, Jazz), a raised middle
    // (Pop), and speech (Vocal) -- the one that matters for a series, where
    // the dialogue needs lifting out of the effects.
    //
    // Written for FIVE bands, not transposed from a ten-band table:
    // dropping every other entry of one lands the wrong gain on a shelf
    // covering an octave more than the peak it replaced.
    //
    // "flat" is first and is not a preset so much as the absence of one --
    // it is what an application starts with, and it is also the reset: with
    // the list always on screen there is no need for a separate "reset"
    // link, the first chip IS it.
    readonly property var presets: [
        { id: "flat",      name: "Flat",        gains: [  0,   0,   0,   0,   0] },
        { id: "acoustic",  name: "Acoustic",    gains: [  4,   1,   1,   2,   3] },
        { id: "bass",      name: "Bass boost",  gains: [  7,   4,   0,   0,   0] },
        { id: "classical", name: "Classical",   gains: [  4,   2,  -2,   2,   4] },
        { id: "dance",     name: "Dance",       gains: [  6,   1,   2,   4,   2] },
        { id: "hiphop",    name: "Hip-hop",     gains: [  6,   3,  -1,   2,   3] },
        { id: "jazz",      name: "Jazz",        gains: [  3,   1,  -2,   2,   3] },
        { id: "pop",       name: "Pop",         gains: [ -1,   2,   4,   2,  -1] },
        { id: "rock",      name: "Rock",        gains: [  6,   3,  -1,   3,   5] },
        { id: "vocal",     name: "Vocal",       gains: [ -3,  -1,   4,   3,  -1] }
    ]

    function presetName(id) {
        for (const p of root.presets) if (p.id === id) return p.name;
        return "Custom";
    }

    function presetGains(id) {
        for (const p of root.presets) if (p.id === id) return p.gains.slice();
        return [0, 0, 0, 0, 0];
    }

    // ---- per-application profiles ------------------------------------
    //
    // { "mpv": { enabled: true, preset: "rock", gains: [6,3,-1,3,5] }, ... }
    //
    // `gains` is carried alongside `preset` rather than derived from it, so
    // that nudging one band after picking Rock keeps the other four where
    // the preset put them. `preset` then becomes a label for where the
    // curve came from, and goes to "" -- shown as Custom -- as soon as a
    // fader moves.
    property var eqProfiles: ({})

    function profileFor(app) {
        const p = root.eqProfiles[app];
        if (p) return p;
        return { enabled: false, preset: "flat", gains: [0, 0, 0, 0, 0] };
    }

    function _setProfile(app, prof) {
        if (app === "") return;
        const next = {};
        for (const k in root.eqProfiles) next[k] = root.eqProfiles[k];
        next[app] = prof;
        root.eqProfiles = next;
        saveTimer.restart();
    }

    function appEq(node) { return root.profileFor(root.streamLabel(node)).enabled; }

    // The setters take a NAME, not a node, and the page that calls them
    // keeps the name rather than the node for exactly that reason: an
    // application can quit while its page is open, and the profile is still
    // worth editing then -- it is what will be applied when it comes back.
    // Everything keyed on a node would go null at that moment.

    function setAppEqNamed(app, on) {
        const p = root.profileFor(app);
        root._setProfile(app, { enabled: on, preset: p.preset, gains: p.gains });
    }

    function setAppPresetNamed(app, id) {
        const p = root.profileFor(app);
        root._setProfile(app, { enabled: p.enabled, preset: id, gains: root.presetGains(id) });
        root._pushFor(app);
    }

    function setAppBandNamed(app, i, db) {
        const p = root.profileFor(app);
        const g = p.gains.slice();
        // One decimal. A drag hands over a continuous number, and without
        // this the saved file fills up with values like -9.104872881355934
        // -- fourteen digits of precision on a control whose readout is a
        // whole dB and whose smallest audible step is bigger than that.
        g[i] = Math.round(Math.max(-root.bandRange, Math.min(root.bandRange, db)) * 10) / 10;
        // The preset label stops being true the moment a fader moves: the
        // curve is no longer Rock, it is Rock with one band pulled, and
        // calling it Rock would be the picker lying about what you hear.
        root._setProfile(app, { enabled: p.enabled, preset: "", gains: g });
        // The audio moves NOW; only the disk write waits (saveTimer).
        root._pushBand(app, i, g[i]);
    }

    // ---- the pipe ----------------------------------------------------

    Process {
        id: pwctl
        running: root.eqPresent
        command: ["bash", "-c", "export LC_ALL=C; exec pw-cli"]
        // Never set this false. See THE TRAP above.
        stdinEnabled: true
        onExited: pwctlRestart.restart()
        // A respawned pw-cli knows nothing about the curves, and the chains
        // it is now talking to still hold whatever was last written to
        // them -- which after a pipewire restart is flat. Re-push
        // everything rather than assume either side remembers.
        onRunningChanged: if (pwctl.running) root.pushAll()
    }

    // pw-cli dying is not expected, but a respawn loop on a binary that
    // fails instantly would be worse than the outage. Two seconds, and it
    // only ever re-arms from `onExited`.
    Timer {
        id: pwctlRestart
        interval: 2000
        onTriggered: if (root.eqPresent) pwctl.running = true
    }

    // One command carries both channels: they are two chains that always
    // hold the same value (see 50-equalizer.conf), so splitting them into
    // two writes would double the traffic to say the same thing twice, and
    // leave a window where the stereo image is lopsided.
    //
    // The parameter names are the same in every slot -- they are scoped to
    // their own graph -- so only the node id changes between them.
    function _writeBand(slotNode, i, db) {
        if (!slotNode || !pwctl.running) return;
        pwctl.write('s ' + slotNode.id + ' Props { params = [ '
                  + '"eq_l_' + i + ':Gain" ' + db + ' '
                  + '"eq_r_' + i + ':Gain" ' + db + ' ] }\n');
    }

    function _slotNodeFor(app) {
        const idx = root._slotOf[app];
        if (idx === undefined) return null;
        for (const s of root.eqSlots) if (s.index === idx) return s.node;
        return null;
    }

    function _pushBand(app, i, db) { root._writeBand(root._slotNodeFor(app), i, db); }

    // One application's whole curve into whichever slot it holds.
    function _pushFor(app) {
        const node = root._slotNodeFor(app);
        if (!node) return;
        const g = root.profileFor(app).gains;
        for (let i = 0; i < g.length; i++) root._writeBand(node, i, g[i]);
    }

    // Every held slot. Used on load, on a pw-cli respawn, and after any
    // reassignment -- a slot that just changed hands is still holding the
    // previous application's curve.
    function pushAll() {
        for (const app in root._slotOf) root._pushFor(app);
    }

    // ---- slot assignment and routing ---------------------------------
    //
    // { "mpv": 0, "vlc": 2 }. Sticky: an application keeps its slot for as
    // long as it is both playing and switched on, so a stream is never
    // moved between chains for bookkeeping reasons. A slot is released
    // only when its application stops being eligible, and the stream goes
    // back to the default output in the same pass.
    property var _slotOf: ({})

    // Node id -> did we last put it in a chain. Without this every
    // re-evaluation would re-issue a move for every stream, and a move is
    // a fork.
    property var _routed: ({})

    // pactl indexes sink-inputs by `object.serial`, not by node id -- they
    // happen to be equal for a node created early and diverge for anything
    // created later, which is every application stream. Getting this wrong
    // moves the wrong stream, silently.
    function _serial(n) {
        if (!n || !n.properties) return undefined;
        const s = n.properties["object.serial"];
        return s === undefined || s === null ? undefined : s;
    }

    // The one fork in the equalizer, and it is per CLICK or per application
    // start, never per frame: nothing here runs while a fader is dragged.
    //
    // `move-sink-input` takes a sink NAME, so the destination is spelled
    // rather than looked up -- one less id to keep in sync.
    function _move(node, sinkName) {
        const serial = root._serial(node);
        if (serial === undefined || sinkName === "") return false;
        Quickshell.execDetached(["bash", "-c",
            "export LC_ALL=C; pactl move-sink-input " + serial + " " + sinkName]);
        return true;
    }

    // How many applications want a chain but could not have one. The page
    // says so rather than leaving a switch that turns on and does nothing.
    property int eqOverflow: 0

    // Brings slots and routing in line with the profiles, moving only what
    // is not already where it belongs.
    //
    // Switching an application OFF moves its stream back out of the chain
    // rather than zeroing its bands. Zeroing would be one write instead of
    // a move, and it would leave ten biquads running on every sample to
    // multiply it by one -- half a percent of a core, indefinitely, for no
    // audible difference. Emptied, the chain suspends and is not scheduled
    // at all.
    function _reconcile() {
        if (!root.eqPresent) return;

        // Who is eligible right now: playing, and switched on.
        const want = [];
        for (const n of root.streams)
            if (root.profileFor(root.streamLabel(n)).enabled) want.push(root.streamLabel(n));

        // Release first, so a slot freed by one application is available to
        // another in the same pass rather than a frame later.
        const slots = {};
        for (const app in root._slotOf)
            if (want.indexOf(app) !== -1) slots[app] = root._slotOf[app];

        const taken = [];
        for (const app in slots) taken.push(slots[app]);

        let overflow = 0;
        for (const app of want) {
            if (slots[app] !== undefined) continue;
            let free = -1;
            for (const s of root.eqSlots)
                if (taken.indexOf(s.index) === -1) { free = s.index; break; }
            if (free === -1) { overflow++; continue; }
            slots[app] = free;
            taken.push(free);
        }

        const changed = JSON.stringify(slots) !== JSON.stringify(root._slotOf);
        root._slotOf = slots;
        root.eqOverflow = overflow;

        const routed = {};
        for (const n of root.streams) {
            const app = root.streamLabel(n);
            const idx = slots[app];
            const target = idx === undefined
                ? (root.sink ? root.sink.name : "")
                : "eq_slot_" + idx;
            const inChain = idx !== undefined;
            if (root._routed[n.id] === inChain) { routed[n.id] = inChain; continue; }
            // A stream whose serial is not readable yet (unbound, or gone
            // between one frame and the next) is left for the next pass
            // rather than recorded as done.
            routed[n.id] = root._move(n, target) ? inChain : root._routed[n.id];
        }
        root._routed = routed;

        // A slot that just changed hands is still holding the previous
        // application's curve.
        if (changed) root.pushAll();
    }

    onStreamsChanged: root._reconcile()
    onEqProfilesChanged: root._reconcile()

    // ---- persistence -------------------------------------------------
    //
    // ~/.local/state, NOT the ~/.cache that BandTint.qml uses. That file is
    // a cache in the real sense -- a daemon regenerates it from the
    // wallpaper on demand, and losing it costs a recomputation. A curve
    // someone dialled in by ear cannot be regenerated by anything, and a
    // cache cleaner is entitled to delete ~/.cache.
    //
    // Debounced: dragging a fader produces a write per frame to the audio
    // graph, which is the point, and one file write when the hand stops.
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: root._save()
    }

    function _save() {
        eqFile.setText(JSON.stringify({ profiles: root.eqProfiles }));
    }

    FileView {
        id: eqFile
        path: Quickshell.env("HOME") + "/.local/state/bar-equalizer.json"
        atomicWrites: true
        // Handled below, so the very first run -- where there is nothing to
        // restore yet -- does not print a failure for a file that is not
        // supposed to exist. Same call VeilleConfig.qml makes, for the same
        // reason.
        printErrors: false
        onLoaded: root._adopt(eqFile.text())
        onLoadFailed: (error) => {
            // No file yet is the normal first-run case and means exactly
            // what the defaults already say: no application switched on.
            if (error === FileViewError.FileNotFound) return;
            console.warn("[mixer] could not read " + eqFile.path + ": "
                         + FileViewError.toString(error));
        }
    }

    function _adopt(raw) {
        try {
            const d = JSON.parse(raw);
            if (d && d.profiles) root.eqProfiles = d.profiles;
        } catch (e) {
            // A truncated or hand-edited file is not worth an error state:
            // the default is no application switched on, which is exactly
            // what "no settings yet" should mean.
            return;
        }
        root._reconcile();
    }

    // ---------------------------------------------------------------
    // labels and glyphs
    // ---------------------------------------------------------------

    // nickname first: PipeWire's `node.nick` is the short human name
    // ("Speaker", "HDMI 1") while `description` is the full ALSA mouthful
    // ("Meteor Lake-P HD Audio Controller HDMI / DisplayPort 3 Output"),
    // which is 60 characters into a 320px column.
    function deviceLabel(n) {
        if (!n) return "—";
        return n.nickname || n.description || n.name || "—";
    }

    // Applications name themselves in `application.name` ("Firefox",
    // "mpv"); `media.name` is the TRACK, which belongs to the notification
    // centre's MPRIS block and not here -- this row is a volume control,
    // and labelling it with a song title makes two different things in two
    // drawers look like the same widget.
    function streamLabel(n) {
        if (!n) return "";
        const p = n.properties || {};
        return p["application.name"] || p["node.name"] || n.description || n.name || "";
    }

    // Lucide, the same set the whole bar draws from (Fonts.iconPhosphor is
    // the lucide file -- see theme/Fonts.qml for why that name stuck).
    // Deliberately glyphs rather than the real desktop icons
    // `application.icon-name` points at: a themed PNG dropped into this
    // column would be the only raster image in any drawer.
    function streamGlyph(n) {
        const s = root.streamLabel(n).toLowerCase();
        if (/firefox|chrom|brave|librewolf|epiphany|webkit/.test(s)) return "\uE0E8";   // globe
        if (/mpv|vlc|celluloid|totem|video/.test(s)) return "\uE0D0";                   // film
        if (/spotify|rhythmbox|audacious|music|lollypop/.test(s)) return "\uE122";      // music
        if (/discord|telegram|signal|element|slack/.test(s)) return "\uE116";           // message-circle
        if (/steam|lutris|heroic|wine|proton|game/.test(s)) return "\uE0DF";            // gamepad-2
        return "\uE55A";                                                                // audio-lines
    }

    // Off the device's own name, and on this machine that is enough --
    // worth writing down, because AudioOutput.qml spends thirty lines and
    // a permanent `pactl subscribe` watcher on what looks like the same
    // question and concludes pipewire cannot answer it.
    //
    // It cannot, for the case that module was written against: one analog
    // sink whose ACTIVE PORT moves between speaker and headphones while
    // its name stays "Speaker". But this laptop's card runs under ALSA
    // UCM, which splits every route into a sink of its own -- Speaker,
    // HDMI 1/2/3, and a Headphones sink that appears when something is in
    // the jack. There is no port to interrogate here, because the route
    // IS the device and `node.nick` already names it.
    //
    // So a picker row and the glyph beside it come from one constant
    // string, with no process and no subscription behind them.
    function deviceGlyph(n) {
        if (!n) return "\uE166";                                       // speaker
        const s = (n.nickname || n.name || "").toLowerCase();
        if (/headphones?|headset|earbuds/.test(s)) return "\uE0F1";    // headphones
        if (/hdmi|displayport/.test(s)) return "\uE11D";               // monitor
        if (/bluez|bluetooth/.test(s)) return "\uE05C";                // bluetooth
        if (/mic|capture|input/.test(s)) return "\uE118";              // mic
        return "\uE166";                                               // speaker
    }

    // Four steps, so the icon beside a slider is a readout and not just a
    // decoration that happens to sit there.
    function volumeGlyph(muted, v) {
        if (muted) return "\uE626";        // volume-off
        if (v <= 0.001) return "\uE1AC";   // volume-x
        if (v < 0.5) return "\uE1AA";      // volume-1
        return "\uE1AB";                   // volume-2
    }
}
