import QtQuick
import Quickshell.Services.Mpris

// Native port of waybar's `mpris` module -- no exec, no poll:
// Mpris.players is a live DBus-backed model. Same colors/shape as
// waybar/style.css's #mpris rule (background, 2px overlay2 border,
// 9999px = full pill, @play/@muted text).
//
// Two departures from "match waybar exactly", both leaning on things
// GTK-CSS couldn't do cheaply:
//  - open/close is a "stretch from the center" (see the pill Rectangle's
//    width animation below) instead of an instant pop.
//  - the title marquee-scrolls regardless of length while playing (see
//    viewportWidth/copyCount below for how a short title still scrolls
//    smoothly instead of leaving the viewport half-blank); paused
//    titles sit parked at x:0 with zero animation running. This is a
//    QML property animation (scene-graph
//    driven, ticks only while actually animating), not a redraw-on-a-
//    poll-loop like a waybar marquee would have needed -- which is
//    exactly why config.jsonc's own comment rejected one ("a marquee
//    needs a fast poll loop even while idle, not worth the battery
//    cost"). That constraint doesn't apply here.

Item {
    id: root

    property var player: {
        const ps = Mpris.players.values;
        // playerctld itself shows up as an MPRIS player (it's a proxy
        // for "whichever real player is active") but has no metadata of
        // its own -- same blacklist swaync/config.json already applies
        // to its mpris widget.
        const real = ps.filter(p => p.dbusName.indexOf("playerctld") === -1);
        for (let i = 0; i < real.length; i++) if (real[i].isPlaying) return real[i];
        return real.length > 0 ? real[0] : null;
    }
    readonly property bool active: root.player !== null
    readonly property bool playing: root.player !== null && root.player.isPlaying
    readonly property string titleText: root.player
        ? (root.player.trackTitle || root.player.identity || "") : ""

    // Scrolls regardless of length again, but this time with a proper
    // fix for the problem that caused a "fixed 200px, always" to look
    // sparse on short titles: the viewport has a MINIMUM width (not a
    // fixed one) so short titles still get a decently-sized ticker, and
    // the number of repeated copies in the loop (see viewport.copyCount
    // below) is computed from how many actually fit, instead of being
    // hardcoded at 2 -- so however wide the viewport ends up (floor,
    // ceiling, or content-sized in between), it's always fully covered
    // by scrolling content, never mostly blank.
    readonly property int minViewport: 120
    readonly property int maxViewport: 200
    readonly property int naturalWidth: titleMeasure.implicitWidth
    readonly property int viewportWidth: Math.max(Math.min(naturalWidth, maxViewport), minViewport)

    // Invisible, root-level so both viewportWidth (above) and the
    // scroller's per-copy math (below) can size off the same measurement
    // without depending on any one particular Repeater-generated copy.
    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: titleMeasure
        text: root.titleText
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        visible: false
    }

    // +24 over the old figure: room for the static play/pause icon and
    // its gap to the viewport, on top of the viewport's own padding.
    readonly property real openWidth: Math.max(viewportWidth + 34 + 24, 84)

    // root's own size just tracks the pill's (below) -- previously root
    // animated its width while clipping a pill drawn at a FIXED
    // openWidth, so growth was really "reveal a wider slice of an
    // already-full-size pill". Since a pill's straight middle has no
    // rounding at all, that only showed rounded corners right at the
    // very start/end of the animation. Now the pill animates its OWN
    // width, so radius:999 keeps producing a proper full-pill shape
    // (rounded both ends) at every size along the way, not just the
    // final one.
    implicitWidth: pill.width
    implicitHeight: 24

    opacity: root.active ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 260 }
    }

    Rectangle {
        id: pill
        width: root.active ? root.openWidth : 0
        height: 24
        anchors.centerIn: parent
        radius: 999
        color: "#000000"
        border.width: 1
        border.color: root.playing ? "#237823" : "#ffffff"
        clip: true
        // waybar/style.css: #mpris.paused { opacity: 0.6 } fades the
        // WHOLE element (background/border/text together), not just the
        // text color -- root's own opacity above is already spoken for
        // (open/close fade), so this lives on the pill itself instead.
        opacity: root.playing ? 1.0 : 0.6
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Behavior on width {
            NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
        }

        Row {
            // Left-anchored instead of centered -- centerIn was adding
            // an equal gap on both sides (openWidth is wider than the
            // Row's natural content), leaving the disc floating away
            // from the pill's left edge instead of sitting snug in it.
            anchors.left: parent.left
            anchors.leftMargin: 6   // bumped up now the disc is smaller -- more breathing room around it
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Static, deliberately OUTSIDE viewport's clip/scroller --
            // reflects current state (play glyph while playing, pause
            // glyph while paused), never moves. Filled disc: the state
            // color becomes the disc's fill instead of the glyph's,
            // glyph itself flips to the pill's own background color.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: root.playing ? "#237823" : "#8e8e93"

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    anchors.centerIn: parent
                    // Music note instead of a play triangle -- same glyph
                    // config.jsonc's own player-icons already use as the
                    // generic/default player icon, so it's a known-good
                    // codepoint in this environment.
                    text: root.playing ? "󰎈" : "󰏤"
                    color: "#000000"
                    font.pixelSize: 8
                }
            }

            Item {
                id: viewport
                anchors.verticalCenter: parent.verticalCenter
                width: root.viewportWidth
                height: 18
                clip: true

                readonly property int gap: 40     // trailing space after each copy
                readonly property real speed: 40  // px/s
                readonly property real unitWidth: Math.max(root.naturalWidth + gap, 1)
                // Enough repeated copies to keep the viewport fully
                // covered by content at every point in the loop, however
                // wide the viewport ends up being (min/max/content-sized)
                // -- this is what "always scrolls" actually needs beyond
                // just removing the overflow check: 2 fixed copies of a
                // short title in a wide-ish viewport left most of it
                // blank.
                readonly property int copyCount: Math.max(2, Math.ceil(width / unitWidth) + 1)

                // Real one-directional loop, not a bounce: once the row
                // has scrolled left by exactly one unitWidth, copy N+1 is
                // sitting exactly where copy N started -- snapping x back
                // to 0 at that instant is visually seamless, reads as an
                // infinite ticker rather than a jump.
                Row {
                    id: scroller
                    x: 0
                    spacing: 0

                    Repeater {
                        model: viewport.copyCount
                        delegate: Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: root.titleText
                            // Paused-state fade lives on the whole `pill`
                            // above (matches waybar's #mpris.paused rule,
                            // which faded the element, not just this
                            // color) -- an opacity here too would double
                            // it up.
                            color: root.playing ? "#237823" : "#ffffff"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 13
                            rightPadding: viewport.gap  // each copy carries its own trailing gap
                        }
                    }

                    NumberAnimation {
                        target: scroller
                        property: "x"
                        // `running` (bound to "is there text") is
                        // start/stop -- toggling it back to true always
                        // restarts from `from`. `paused` (bound to
                        // playing) is real pause/resume: freezes x and
                        // continues from that exact spot instead of
                        // snapping back to the start every time play
                        // resumes. Both guarded on titleText !== "" --
                        // calling setPaused() while the animation isn't
                        // running is a Qt warning, not just a no-op.
                        running: root.titleText !== ""
                        paused: root.titleText !== "" ? !root.playing : false
                        loops: Animation.Infinite
                        from: 0
                        to: -viewport.unitWidth
                        duration: viewport.unitWidth / viewport.speed * 1000
                        easing.type: Easing.Linear
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: if (root.player) root.player.togglePlaying()
    }
}
