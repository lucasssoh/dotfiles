import QtQuick
import Quickshell.Services.Mpris
import "../theme"

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
        font.family: Fonts.ui
        font.pixelSize: 14
        visible: false
    }

    Text {
        id: placeholderMeasure
        text: root.placeholderText
        font.family: Fonts.ui
        font.pixelSize: 13
        visible: false
    }

    // +24 over the old figure: room for the static play/pause icon and
    // its gap to the viewport, on top of the viewport's own padding.
    readonly property real openWidth: Math.max(viewportWidth + 34 + 24, 84)

    // Placeholder text/width when no player is active -- asked for: this
    // side of the bar collapsing to 0 while ActiveWindow (the module
    // symmetric to this one across the fixed centerRow -- see shell.qml's
    // ONE BAR) still had real content made the bar visibly lopsided, and
    // vice versa. Not meant to look "full", just enough to keep both
    // sides roughly balanced when only one of the two is actually active.
    readonly property string placeholderText: "No media"
    readonly property real placeholderWidth: Math.max(placeholderMeasure.implicitWidth + 24, 84)

    // root's own size just tracks the pill's (below) -- previously root
    // animated its width while clipping a pill drawn at a FIXED
    // openWidth, so growth was really "reveal a wider slice of an
    // already-full-size pill". Since a pill's straight middle has no
    // rounding at all, that only showed rounded corners right at the
    // very start/end of the animation. Now the pill animates its OWN
    // width, so a large bottom radius keeps producing a proper rounded
    // shape (both bottom ends) at every size along the way, not just the
    // final one.
    implicitWidth: pill.width
    implicitHeight: 24

    // Always visible now -- was `root.active ? 1 : 0` (fully hidden with
    // nothing playing). The pill itself still draws a real placeholder
    // (below) when inactive, so hiding the whole Item on top of that
    // would just make the placeholder invisible too.
    opacity: 1

    Rectangle {
        id: pill
        width: root.active ? root.openWidth : root.placeholderWidth
        height: 24
        anchors.centerIn: parent
        // Top-square/bottom-rounded, same treatment as Block.qml -- the
        // bar sits flush against the screen's own top edge now (see
        // shell.qml's PanelWindow margins.top: 0), so this pill's top
        // stays flush too instead of showing a rounded notch under the
        // screen edge. 999 still clamps to the max valid radius (height/2
        // = 12) at any width, same "large enough" trick as the old
        // uniform radius:999.
        topLeftRadius: 999
        topRightRadius: 999
        bottomLeftRadius: 999
        bottomRightRadius: 999
        // Was #000000, its own separate black box -- asked for: removed
        // in favor of blending straight into the ONE BAR block's own
        // #0c0c0e fill behind it (shell.qml), same treatment every other
        // module in that block already gets (none of them draw their own
        // background any more, see Block.qml's header comment).
        color: "transparent"
        clip: true
        // No border (see the no-border pass in shell.qml's header
        // comment) -- playing state now shows only through the disc's
        // fill and this opacity dip, not an extra ring around the pill.
        //
        // waybar/style.css: #mpris.paused { opacity: 0.6 } fades the
        // WHOLE element (background/text together), not just the text
        // color. Third tier (0.35) for the placeholder state -- dimmer
        // still, reads as "nothing here" rather than "paused".
        opacity: root.playing ? 1.0 : (root.active ? 0.6 : 0.35)
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Behavior on width {
            NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
        }

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            visible: !root.active
            anchors.centerIn: parent
            text: root.placeholderText
            color: "#636366"   // colors.lua "muted" -- same token Hdr.qml/ActiveWindow.qml's own placeholder use
            font.family: Fonts.ui
            font.pixelSize: 13
        }

        Row {
            visible: root.active
            // Left-anchored instead of centered -- centerIn was adding
            // an equal gap on both sides (openWidth is wider than the
            // Row's natural content), leaving the disc floating away
            // from the pill's left edge instead of sitting snug in it.
            anchors.left: parent.left
            anchors.leftMargin: 6   // bumped up now the disc is smaller -- more breathing room around it
            anchors.verticalCenter: parent.verticalCenter
            // 4 -> 8: more breathing room specifically between the wave
            // and the scrolling title now that the wave itself is
            // narrower (asked for) -- previously 4 read fine against a
            // wider 5-bar/3px-spacing wave, tighter now that it's
            // shrunk.
            spacing: 8

            // Animated equalizer bars instead of a static play/pause glyph
            // (asked for). Paused: all bars pinned to the same minimum
            // height, no motion at all. Playing: each bar drifts to a new
            // random height on its own timer, independently of the
            // others (different index -> different interval, see
            // bar.index below), so the wave never looks lockstep/
            // mechanical. Each bar grows from its own vertical CENTER
            // symmetrically up and down (asked for -- was bottom-
            // anchored, all growth upward only), via
            // `anchors.verticalCenter` instead of `anchors.bottom`: a
            // Rectangle's height change with a centered anchor expands
            // equally on both sides for free, no extra math needed.
            //
            // Cheap by construction, not just by accident: the actual
            // rise/fall is a `Behavior`-driven NumberAnimation (scene-
            // graph interpolated, GPU-only, exactly how the marquee's
            // own scroll and every colour fade in this bar already
            // work) -- the JS only runs once every ~300-500ms per bar to
            // pick the next random target, not per frame. And like the
            // marquee's own `paused: !root.playing`, each bar's Timer is
            // gated on `root.playing` -- zero timers firing, zero
            // animation running, while paused or inactive.
            Item {
                id: waveIcon
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: waveRow.implicitWidth
                implicitHeight: 14

                readonly property real minBar: 3
                readonly property real maxBar: 14
                // Exact match to the scrolling title's own color below
                // (#237823/#ffffff), not just a similar accent pair --
                // asked for, so the icon reads as part of the same text
                // rather than its own separate color choice.
                readonly property color barColor: root.playing ? "#237823" : "#ffffff"

                Row {
                    id: waveRow
                    anchors.verticalCenter: parent.verticalCenter
                    // 3 -> 2 (both bar width and this spacing), asked
                    // for -- 5 bars at the old 3px/3px was noticeably
                    // wider than the old 3-bar version, this compacts it
                    // back down horizontally.
                    spacing: 2

                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            id: bar
                            required property int index
                            width: 2
                            radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: waveIcon.barColor
                            Behavior on color { ColorAnimation { duration: 200 } }

                            // Randomised while playing, pinned to
                            // `minBar` otherwise -- the height binding
                            // itself is what snaps every bar back to the
                            // SAME size the instant playback stops, no
                            // separate paused-state code path needed.
                            property real target: waveIcon.minBar
                            height: root.playing ? target : waveIcon.minBar
                            Behavior on height {
                                NumberAnimation { duration: 260; easing.type: Easing.InOutQuad }
                            }

                            Timer {
                                running: root.playing
                                repeat: true
                                triggeredOnStart: true
                                // Distinct fixed interval per bar (index-
                                // based, not itself randomised) is what
                                // keeps the five out of sync with each
                                // other -- the actual unpredictability
                                // comes from randomising the TARGET below
                                // instead.
                                interval: 320 + bar.index * 90
                                onTriggered: bar.target = waveIcon.minBar
                                    + Math.random() * (waveIcon.maxBar - waveIcon.minBar)
                            }
                        }
                    }
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
                // Retracted a few px in from viewport's own left/right
                // edges (asked for) -- the fade rectangles' OUTER corners
                // are rounded, which cuts a small notch out of their
                // coverage right at top/bottom near each edge, and text
                // was reaching far enough out to poke through that
                // notch. A second, slightly narrower clip just for the
                // text keeps it inside the flat (non-notched) part of the
                // fade instead of shrinking the fade or its radius.
                Item {
                    id: textClip
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    clip: true

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
                                font.family: Fonts.ui
                                font.pixelSize: 14
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

                // Fade the marquee out at both edges instead of the hard
                // clip cut (asked for) -- two thin gradient strips,
                // declared after `scroller` so they paint on top of it,
                // going from opaque black at the outer edge to fully
                // transparent at the inner edge. Cheap fake: not an
                // actual mask/shader sampling what's really behind (that
                // would need layer.effect + OpacityMask), just a flat
                // black fade -- good enough here because the island's
                // own background is already solid black by this point in
                // its vertical gradient (see shell.qml's centerIsland),
                // so "fade to black" and "fade to what's actually behind"
                // are the same thing at this particular spot in the bar.
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 26
                    // Only the OUTER corners rounded (asked for) -- the
                    // inner ones face the text and already fade to fully
                    // transparent there, so rounding them would be
                    // invisible anyway.
                    topLeftRadius: 8
                    bottomLeftRadius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#000000" }
                        GradientStop { position: 1.0; color: "#00000000" }
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 26
                    topRightRadius: 8
                    bottomRightRadius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 1.0; color: "#000000" }
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
