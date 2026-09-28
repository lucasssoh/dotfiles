import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../theme"
import "../services"

// Native port of waybar's `pulseaudio#output`. Zero exec, zero poll for
// volume/mute: Pipewire.defaultAudioSink is a live DBus/pipewire-backed
// reference, PwObjectTracker keeps its `audio` sub-properties bound and
// reactive. wpctl/pactl are gone entirely for *that* display; left click
// opens the mixer drawer (see the click handler below), and whatever it
// changes, Pipewire.defaultAudioSink above picks up live.
//
// The headphone-vs-speaker icon is the one thing PwNode genuinely can't
// answer: Quickshell.Services.Pipewire exposes no port/route data at all
// (checked the qmltypes -- name/description/nickname only), and on this
// machine's combo jack the SINK's own description never changes between
// "speaker" and "headphone" -- only its active PORT does (analog-output-
// speaker vs analog-output-headphones), which lives one level down, in
// libpulse's port list, not in anything PwNode surfaces. `pactl` is the
// only thing that can see it. Kept event-driven per the "avoid polling"
// rule anyway: `pactl subscribe` is a long-running watcher (same
// watch/query split as StreamModule.qml), a one-shot re-query only runs
// when it actually prints a sink/card/server change line, never on a
// clock. Both halves of that split must be forced to LC_ALL=C -- pactl
// translates both its event stream and its `list sinks` keys, and the
// watcher missing that export is what kept this icon stale. That
// watcher and its query now live in services/OsdState.qml, shared with
// the volume popup; this module only reads OsdState.outputGlyph.
Item {
    id: root

    // The ink ramp this module draws with. Points at the dark-material
    // singleton by default, which is what every call site below used
    // directly before this property existed -- so this changes nothing on
    // its own. It exists so the band's islands can hand a LIGHT ramp to
    // the modules sitting on them, per island, without touching any of
    // those call sites again. See theme/Ink.qml's MATERIAL note for why
    // the material flips rather than the ink alone.
    property QtObject ink: Ink

    readonly property var node: Pipewire.defaultAudioSink
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property bool muted: node && node.audio ? node.audio.muted : false

    // The active port (headphones, HDMI...) and the glyph it maps to
    // live in OsdState now, shared with the volume popup -- see there.


    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    // Outer breathing room, set per-instance from shell.qml -- these two
    // are the only "bare" modules in TOOLS (no border, no badge, no
    // padding of their own), so at the row's uniform `rowSpacing: 2` the
    // glyphs sat 2px from the bordered blocks on either side while every
    // bordered neighbour keeps ~6px between its own glyph and its edge.
    // The gap was structurally regular and still read as unequal.
    //
    // Padding on BOTH sides now, but never equal on both: headphones+mic
    // are one group, so the gap BETWEEN them has to stay the smaller one.
    // Fully symmetric padding was tried first and inverts exactly that --
    // it grows the inner gap to twice the outer ones and the pair stops
    // reading as a pair.
    //
    // The outer side stays the bigger number (5 against the inner 2, set
    // in shell.qml). The inner one used to be 0, which put headphones and
    // mic 4px apart -- the tightest gap in the whole row, half of any
    // other, on the one pair with no borders to do the separating. It is
    // 8px now, still comfortably under the ~14px that shell.qml's
    // `groupGap` puts on either side of the pair.
    //
    // Asked for as "espacer un peu plus [display] [audio] [balise]", and
    // done here rather than by raising `rowSpacing`: that number is
    // deliberately one value for the whole row (see shell.qml) and
    // raising it would also push apart perf/battery/clock/bell, undoing
    // the "compact" pass that brought it 4 -> 2.
    property real leadingPad: 0
    property real trailingPad: 0

    // Which bar instance this module belongs to, handed down by shell.qml
    // exactly as Battery/BaliseButton/NotificationBell take theirs -- the
    // mixer opens on the monitor whose bar was clicked. Null on any caller
    // that doesn't set it, which means the drawer opens on no particular
    // screen rather than crashing.
    property var screen: null

    implicitWidth: label.implicitWidth + 2 + root.leadingPad + root.trailingPad   // tight fit, no floor -- same fix Battery.qml got, TOOLS' icon-only modules don't need METRICS' square-pill padding
    implicitHeight: 24
    visible: root.node !== null

    // One glyph for the output, shared with the volume popup so the two
    // can never disagree about what is playing where (OsdState.outputGlyph).
    readonly property string iconGlyph: OsdState.outputGlyph
    // Icon ONLY -- the numeric level that used to sit before it is gone,
    // asked for: "puisqu'on a deja ce retour, enleve les valeurs devant
    // les icones audio output et input". That retour is the OSD (Osd.qml,
    // bottom-center), which pops up on exactly the gestures that change
    // this value -- the scroll handler below, and the media keys in
    // keybinds.lua -- so the permanent readout was spelling out a number
    // that is only ever looked at in the moment it is already being shown,
    // larger, somewhere else. The icon still carries what stays true
    // between those moments: the output route (speaker/headphones/HDMI)
    // and mute.
    //
    // The Row is kept around its single remaining child rather than
    // anchoring that Text directly, so `label.implicitWidth` above still
    // measures the same thing and this file stays structurally identical
    // to AudioInput.qml next to it.
    //
    // No color rule for #pulseaudio.output in waybar/style.css -- only
    // the glyph changes on mute, color stays plain text.
    Row {
        id: label
        // Not centerIn: the pads are one-sided. With both at 0 this is
        // x: 1 on a width of implicitWidth+2, i.e. exactly what
        // centerIn resolved to before.
        anchors.verticalCenter: parent.verticalCenter
        x: root.leadingPad + 1

        // Phosphor vs Inter: box-centering (anchors.verticalCenter) is
        // what measured aligned for Phosphor -- see Temperature.qml's
        // comment for the full reasoning/history.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconGlyph
            color: root.ink.primary
            font.family: Fonts.iconMingcute
            font.pixelSize: 17
        }
    }

    MouseArea {
        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Left click used to regenerate a wheel config from `pactl list
        // sinks` and launch the external `roue` process to draw it, purely
        // to pick an output. It opens the mixer drawer instead now
        // (modules/mixer/), which does the same job as a property write
        // on Pipewire.preferredDefaultAudioSink and carries the per-app
        // sliders that had no in-bar path at all. The roue audio wheels
        // and audio.sh's roue-gen have since been removed from the repo;
        // the roue "Actions" hub opens this same mixer instead.
        //
        // Right click still opens pavucontrol. Kept deliberately: this
        // drawer does levels and routing, not per-stream device moves or
        // card profile switching, and the escape hatch to the full app is
        // one click either way.
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                MixerState.togglePanel(root.screen);
            else
                Quickshell.execDetached(["pavucontrol"]);
        }
        onWheel: (wheel) => {
            if (!root.node || !root.node.audio) return;
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            // Capped at 1.0 (100%), not 1.5 -- the boost headroom went
            // unused and asked to come out, same cap as the media-key
            // bind in keybinds.lua now uses.
            root.node.audio.volume = Math.max(0, Math.min(1.0, root.node.audio.volume + step));
        }
    }
}
