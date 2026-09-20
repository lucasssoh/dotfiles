import QtQuick
import ".."          // DrawerHandle / DrawerGroupLabel
import "../balise"   // RevealPop
import "../../theme"
import "../../services"

// Fourth drawer entry on toolsIsland, after NotificationCenter,
// BaliseHome and PowerHome -- opened by clicking either audio module in
// the TOOLS pill (shell.qml), the same "click the thing you want the
// detail of" affordance the other three are, and like PowerHome it needs
// no new pixel in the row: the two modules were already there and were
// already clickable, they just used to launch something else.
//
// Satisfies the DrawerIsland contract the others do: `drawerOpen` bound
// from outside, `implicitHeight` computed here, and a `Behavior on height`
// equal to the island's `revealDuration` (220). Width is not set here --
// DrawerIsland forces every entry to `fixedDrawerWidth` (360), so
// everything below sizes off `parent.width`.
//
// The layout is three bands, and the order is the order they are wanted
// in rather than the order pipewire lists them:
//
//   OUTPUT   master level for the default sink, and under it -- on
//            demand -- the sinks to choose between. This is what replaced
//            the `roue audio-output` wheel.
//   INPUT    the same for the default source, plus the applications
//            currently HOLDING it open, which is a question nothing else
//            in this bar answers.
//   PLAYING  one row per application feeding the sink. This has never had
//            an in-bar equivalent at all; it was pavucontrol or nothing.
//
// The two masters and an application row are all the same component
// (MixerRow) -- see there for why the badge is the mute button and why
// the percentage is drawn at a fixed width.
//
// TWO PAGES, on the navigation Balise already uses (see BaliseHome.qml):
// `currentPage` switches a Loader between the three bands above and one
// application's equalizer, and `implicitHeight` follows whichever page is
// actually loaded, so DrawerIsland's own height Binding animates the
// transition exactly the way it animates open and close.
//
// The equalizer used to sit on this page, between INPUT and PLAYING, and
// it was about 260px of faders and preset chips for something adjusted
// once per application and then left for weeks -- it pushed the list of
// what is actually playing off the bottom of the drawer. It is a page of
// its own now, reached by the chevron on an application's row.
Item {
    id: root

    property bool drawerOpen: false

    // "home" | "app"
    property string currentPage: "home"
    // Which application's page. A NAME, not a node: it has to survive the
    // application quitting while its page is open -- see MixerAppPage.
    property string appLabel: ""

    // Looked up live rather than snapshotted, so an application that stops
    // and restarts under an open page keeps working. Null is a legitimate
    // value and the page handles it.
    readonly property var appNode: {
        for (const n of MixerState.streams)
            if (MixerState.streamLabel(n) === root.appLabel) return n;
        return null;
    }

    function openApp(label) {
        if (label === "") return;
        root.appLabel = label;
        root.currentPage = "app";
    }
    function goHome() { root.currentPage = "home"; }

    implicitHeight: handle.implicitHeight + 20
                    + (pageLoader.item ? pageLoader.item.implicitHeight : 0) + 20
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    // Every open starts at the top level, the same rule Balise was given
    // explicitly ("si je me trouve dans un contexte ou sous-contexte [...]
    // et que je quitte, je reviens à l'interface principale, toujours").
    // Nothing else resets it: closing the drawer only touches `panelOpen`.
    //
    // Done on OPEN rather than on close, and for the same reason Balise
    // does: the drawer still takes this file's own height Behavior to
    // retract, and swapping the Loader mid-collapse is a visible content
    // jump. Here the height is still 0 when it happens.
    onDrawerOpenChanged: {
        if (root.drawerOpen) {
            root.currentPage = "home";
            root.appLabel = "";
            BaliseReveal.replay();
        }
    }

    // The cascade replays on every navigation. Unlike Balise, whose pages
    // are rebuilt wholesale, only one of these two is a fresh build -- so
    // the kick is explicit rather than left to RevealPop's own
    // Component.onCompleted.
    onCurrentPageChanged: BaliseReveal.replay()

    // ---- node access -------------------------------------------------
    //
    // Every read goes through these four rather than touching
    // `node.audio` inline. A PwNode can be handed over before it is bound
    // and can vanish between one frame and the next (an application
    // quitting is exactly that), so `audio` is null often enough that the
    // inline spelling would be four null guards per row.

    function vol(n) { return n && n.audio ? n.audio.volume : 0; }
    function isMuted(n) { return n && n.audio ? n.audio.muted : false; }
    function setVol(n, v) { if (n && n.audio) n.audio.volume = v; }
    function toggleMute(n) { if (n && n.audio) n.audio.muted = !n.audio.muted; }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: MixerState.close()
    }

    // The page area. A single Loader, not the pair BaliseHome uses -- that
    // one cross-fades two live pages, which is worth its bookkeeping when
    // you can be four levels deep in a network list. There are two pages
    // here and the drawer's own height animation already carries the
    // change.
    Loader {
        id: pageLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        sourceComponent: root.currentPage === "app" ? appPage : homePage
    }

    Component {
        id: appPage

        MixerAppPage {
            node: root.appNode
            appLabel: root.appLabel
            glyph: root.appNode ? MixerState.streamGlyph(root.appNode) : "\uE55A"
            onBackRequested: root.goHome()
        }
    }

    Component {
        id: homePage

        Column {
        id: content
        spacing: 16

        // ---- OUTPUT --------------------------------------------------
        Column {
            width: parent.width
            spacing: 8

            DrawerGroupLabel {
                text: "OUTPUT"
                revealIndex: 0
            }

            MixerRow {
                revealIndex: 1
                glyph: MixerState.volumeGlyph(root.isMuted(MixerState.sink),
                                              root.vol(MixerState.sink))
                title: MixerState.deviceLabel(MixerState.sink)
                value: root.vol(MixerState.sink)
                muted: root.isMuted(MixerState.sink)
                peak: MixerState.sinkPeak
                onMoved: (v) => root.setVol(MixerState.sink, v)
                onMuteToggled: root.toggleMute(MixerState.sink)
            }

            // The outputs, listed. This was a picker behind a chevron and
            // is not any more, for the reason the preset list stopped
            // being one: unfolding it changed the drawer's height and the
            // drawer animated every pixel of it, so the panel moved every
            // time anyone looked for a device. The list is short -- the
            // unselectable entries are already filtered out, see
            // MixerState.unavailable -- so it simply sits here.
            //
            // Still hidden when there is exactly ONE, which is not a
            // choice: the master row above already names it, and a
            // one-entry list under it would say the same word twice.
            Column {
                width: parent.width
                spacing: 2
                visible: MixerState.pickableSinks.length > 1

                Repeater {
                    model: MixerState.pickableSinks
                    delegate: MixerDeviceRow {
                        required property var modelData
                        required property int index
                        revealIndex: 2 + index
                        glyph: MixerState.deviceGlyph(modelData)
                        title: MixerState.deviceLabel(modelData)
                        current: modelData === MixerState.sink
                        onPicked: MixerState.setSink(modelData)
                    }
                }
            }
        }

        // ---- INPUT ---------------------------------------------------
        Column {
            width: parent.width
            spacing: 8

            DrawerGroupLabel {
                text: "INPUT"
                revealIndex: 2
            }

            MixerRow {
                revealIndex: 3
                glyph: root.isMuted(MixerState.source) ? "\uE119" : "\uE118"   // lu-mic-off / lu-mic
                title: MixerState.deviceLabel(MixerState.source)
                // 1.5, matching AudioInput.qml's own scroll cap -- see
                // MixerSlider.maximum for why the output does not get the
                // same headroom.
                maximum: 1.5
                value: root.vol(MixerState.source)
                muted: root.isMuted(MixerState.source)
                peak: MixerState.sourcePeak
                onMoved: (v) => root.setVol(MixerState.source, v)
                onMuteToggled: root.toggleMute(MixerState.source)
            }

            // The inputs, listed -- same as the outputs above.
            Column {
                width: parent.width
                spacing: 2
                visible: MixerState.pickableSources.length > 1

                Repeater {
                    model: MixerState.pickableSources
                    delegate: MixerDeviceRow {
                        required property var modelData
                        required property int index
                        revealIndex: 4 + index
                        glyph: MixerState.deviceGlyph(modelData)
                        title: MixerState.deviceLabel(modelData)
                        current: modelData === MixerState.source
                        onPicked: MixerState.setSource(modelData)
                    }
                }
            }

            // What currently has the microphone open. Drawn only when
            // something does -- an always-present "nothing is recording"
            // line would be a permanent reassurance nobody asked for,
            // whereas the list appearing IS the signal.
            Column {
                width: parent.width
                spacing: 6
                visible: MixerState.recordStreams.length > 0

                Repeater {
                    model: MixerState.recordStreams
                    delegate: MixerRow {
                        required property var modelData
                        required property int index
                        revealIndex: 4 + index
                        compact: true
                        glyph: "\uE118"   // lu-mic
                        title: MixerState.streamLabel(modelData)
                        maximum: 1.5
                        value: root.vol(modelData)
                        muted: root.isMuted(modelData)
                        onMoved: (v) => root.setVol(modelData, v)
                        onMuteToggled: root.toggleMute(modelData)
                    }
                }
            }
        }

        // ---- PLAYING -------------------------------------------------
        Column {
            width: parent.width
            spacing: 8

            DrawerGroupLabel {
                text: "PLAYING"
                revealIndex: 8
            }

            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: MixerState.streams
                    delegate: MixerRow {
                        required property var modelData
                        required property int index
                        revealIndex: 9 + index
                        compact: true
                        glyph: MixerState.streamGlyph(modelData)
                        title: MixerState.streamLabel(modelData)
                        value: root.vol(modelData)
                        muted: root.isMuted(modelData)
                        // The row keeps the two things you reach for without
                        // thinking -- level and mute -- and hands everything
                        // else to a page of its own. The chevron is the same
                        // affordance the two masters use for their device
                        // pickers, so "there is more under this" reads the
                        // same way everywhere in the drawer.
                        expandable: MixerState.eqPresent
                        // Lit while this application is going through a
                        // chain, so the list says at a glance which ones are
                        // equalized without opening anything.
                        eqable: MixerState.eqPresent
                        eqOn: MixerState.appEq(modelData)
                        onMoved: (v) => root.setVol(modelData, v)
                        onMuteToggled: root.toggleMute(modelData)
                        onExpandToggled: root.openApp(MixerState.streamLabel(modelData))
                    }
                }
            }

            // Empty state, and it is a real one: the section header is
            // still drawn above it, so the drawer keeps the same three
            // bands whether or not anything is playing. A section that
            // disappeared entirely would make the panel a different
            // height and a different shape every time it opens.
            Item {
                width: parent.width
                height: 34
                visible: MixerState.streams.length === 0

                Text {
                    id: emptyLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "Nothing playing"
                    color: Ink.muted
                    font.family: Fonts.ui
                    font.pixelSize: 12

                    RevealPop { item: emptyLabel; index: 9; fromScale: 1.0 }
                }
            }
        }
    }
    }
}
