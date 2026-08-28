import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import "../theme"

// Single consolidated "open Balise" button -- replaces the three separate
// Network/Bluetooth/Ethernet icons that used to sit in this pill, asked
// for: "sur la barre un seul bouton pour ouvrir balise sans la notion de
// header en onglet" (Balise itself drops its tab header for a Control
// Center layout -- see the project plan; this is the bar-side half of
// that same change).
//
// Elastic width, animated -- back to tracking content (was pinned to
// Hdr.qml's fixed 40px footprint for a pass, then asked to widen/narrow
// with whatever icons are actually showing, animated rather than
// snapping). Background stays fully transparent: unlike Hdr there's no
// single on/off boolean this badge could carry in a fill color, so it
// stays quiet and lets the icons (and the GlassRim edge, which now
// tracks the animated width live too) do all the talking.
//
// Icon-selection logic and glyph codepoints for the wifi/bluetooth slots
// are copied verbatim from Network.qml/Bluetooth.qml (same three-state
// Bluetooth shape, same wifi-or-ethernet priority) rather than shared by
// reference -- those two files (plus Ethernet.qml) are left in place,
// unreferenced from the bar for now, as the manual fallback tools (nmtui,
// blueman-manager) live behind their right-clicks and might still be
// worth a home later.
//
// A permanent GEAR icon (same codepoint as Balise's own per-row
// "configure" gear, ui/icon.rs::GEAR) sits first, always visible --
// added after live-testing showed the badge going completely BLANK with
// WiFi/Bluetooth/Ethernet all off, leaving nothing to even indicate a
// button was there. The two status slots are conditional and sit next to
// it, each collapsing to nothing (not a placeholder glyph, and not just
// an instant visible:false snap -- see IconSlot below) when there's
// nothing to report:
//   - internet: WiFi (with signal tier) OR Ethernet, whichever is
//     actually carrying traffic (Network.qml's own activeDevice
//     priority: wired beats wifi if both are somehow connected). Neither
//     connected -> empty.
//   - bluetooth: shown whenever the radio is powered on, connected or
//     not ("activé, utilisé ou non") -- hidden only when fully off.

Item {
    id: root

    // ---- internet slot (WiFi OR Ethernet, whichever is active) --------
    readonly property var activeDevice: {
        const devices = Networking.devices.values;
        let wifi = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d.connected) continue;
            if (d.type === DeviceType.Wired) return d;
            if (d.type === DeviceType.Wifi) wifi = d;
        }
        return wifi;
    }
    readonly property string netKind: !root.activeDevice ? "none" : (root.activeDevice.type === DeviceType.Wired ? "ethernet" : "wifi")
    readonly property int wifiSignal: {
        if (root.netKind !== "wifi" || !root.activeDevice) return 0;
        const nets = root.activeDevice.networks.values;
        for (let i = 0; i < nets.length; i++) {
            if (nets[i].connected) return Math.round(nets[i].signalStrength);
        }
        return 0;
    }
    // ph-plugs-connected / ph-wifi-low/medium/high, same codepoints as
    // Network.qml's own icon() (verified against balise-src/src/ui/
    // icon.rs's table). "" (no glyph) for "none" -- deliberately not the
    // wifi-slash Network.qml itself falls back to.
    function netIcon() {
        if (root.netKind === "ethernet") return "";
        if (root.netKind === "wifi") {
            const s = root.wifiSignal;
            if (s < 33) return "";
            if (s < 66) return "";
            return "";
        }
        return "";
    }

    // ---- bluetooth slot (shown whenever the radio is on) ---------------
    readonly property bool btEnabled: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property bool btConnected: {
        if (!Bluetooth.defaultAdapter) return false;
        const devices = Bluetooth.defaultAdapter.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected) return true;
        }
        return false;
    }
    // ph-bluetooth / ph-bluetooth-connected, same codepoints as
    // Bluetooth.qml's own icon(). "" for fully off.
    function btIcon() {
        if (!root.btEnabled) return "";
        return root.btConnected ? "" : "";
    }

    // Width tracks `content`'s own live width (badge padding: 7px each
    // side) instead of a fixed 40. NOT animated here, or on `badge`
    // below, despite both changing size as icons appear/disappear --
    // `content.implicitWidth` is ALREADY a smoothly-animated value at
    // this point (each IconSlot's own ParallelAnimation drives it frame
    // by frame, see below), so a plain direct binding is what makes
    // root/badge track it exactly, in lockstep, every frame.
    //
    // Putting ANOTHER Behavior on top of that (tried first) meant this
    // width was chasing a constantly-moving target with its own 220ms
    // lag instead of just mirroring it -- it visibly settled into place
    // a beat AFTER the icon's own animation had already finished, which
    // read as two separate movements back to back ("en deux parties"),
    // not the single continuous resize that was actually wanted. One
    // real animated source (the icon), everything downstream of it a
    // plain binding, not a second smoothing pass.
    implicitWidth: badge.width + 5
    implicitHeight: 24

    // Same 18px height/6px radius as Hdr's badge, fully transparent (see
    // header comment above for why no fill color). Width now follows
    // `content` instead of a fixed 35 -- see the no-Behavior explanation
    // on `implicitWidth` above, same reasoning applies here.
    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: Math.max(content.implicitWidth + 14, 24)
        height: 18
        radius: 6
        color: "transparent"
    }

    // Up to 3 icons (gear always, net/bt conditional).
    Row {
        id: content
        anchors.centerIn: parent
        spacing: 4

        // Order asked for explicitly: Bluetooth all the way to the left,
        // internet in the middle, the permanent gear all the way to the
        // right. Row lays children out in declaration order.
        IconSlot { glyph: root.btIcon() }
        IconSlot { glyph: root.netIcon() }

        // Permanent anchor icon -- see header comment: without this the
        // badge went fully blank whenever WiFi/Bluetooth/Ethernet were
        // all off, with nothing left to click on visually. Never
        // animated in/out itself, only ever present.
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""
            color: "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 12
        }
    }

    // Same "verre métal" edge as Hdr's badge, Balise's own panel, Roue's
    // hub -- see GlassRim.qml's header for the shared five-stop ramp.
    // Traces `badge`'s live x/y/width/height (GlassRim.qml binds to
    // `target`'s geometry every frame), so it grows/shrinks in step with
    // the animated resize above instead of needing its own Behavior.
    // Two sources, matching Hdr's own badge (and metrics/launchers/tools
    // in shell.qml): full-strength topLeft (default) plus a fainter
    // bottomRight one, asked for explicitly ("le bouton hdr a un light
    // source en bas à droite, ajoute aussi ça pour le bouton balise").
    GlassRim { target: badge; cornerRadius: badge.radius }
    GlassRim { target: badge; cornerRadius: badge.radius; lightOrigin: "bottomRight"; strength: 0.45 }

    // No --tab any more: Balise itself is dropping the tab-header concept
    // (see the project plan), and this button no longer distinguishes
    // "which icon was clicked" the way the three separate ones used to --
    // it just opens/closes Balise on whatever it last showed.
    Process {
        id: openBalise
        command: ["bash", "-c", "$HOME/.config/waybar/scripts/balise-toggle.sh"]
    }

    MouseArea {
        anchors.fill: parent
        onClicked: openBalise.running = true
    }

    // One conditional icon slot: collapses its own width to 0 (not a
    // visible:false snap) and fades out when `glyph` goes empty, and the
    // reverse on the way back in -- asked for: "les icones qui
    // s'affichent de manière plus animé lorsqu'on part de rien vers
    // icone ou icon vers rien". `visible:false` was the obvious way to
    // hide a Row child, and it was already used for the SAME reason
    // fixed-tier icons switch shape elsewhere in this bar (Row skips
    // invisible children when laying out) -- but a plain visible toggle
    // has no animation of its own, it's just gone one frame and there
    // the next.
    //
    // Width and opacity overlap, on a STAGGERED start rather than either
    // running together or running as two fully back-to-back steps: the
    // first pass ran them together, which looked wrong live -- a glyph
    // fading in while its own box was still mid-grow reads as the icon
    // being squeezed out of a slit. A strict two-step SequentialAnimation
    // (widen fully, THEN fade) was tried next and asked for by name, but
    // looked "saccadé" live -- width motion hard-stops the instant
    // opacity motion starts, which reads as two separate little jerks
    // instead of one continuous gesture. This is the middle ground:
    // opacity starts partway through the width animation (a PauseAnimation
    // delay inside a ParallelAnimation) and the two tails overlap, so
    // there's always SOMETHING moving and no dead handoff point, while
    // the box is still clearly widening before the icon becomes
    // noticeable (delay is a majority of the width animation's own
    // duration). Same idea mirrored for hiding: fade starts first, width
    // starts shrinking a little later and keeps moving after the icon's
    // already invisible. `displayGlyph` -- not `slot.glyph` directly --
    // is what the Text actually shows: it's set to the new glyph right
    // when growing STARTS (so there's something correct to fade in once
    // opacity starts moving), but deliberately NOT cleared when hiding
    // starts, so the fade-out shows the icon that was actually there
    // instead of blank space. `clip: true` hides the glyph's own
    // un-clipped tails while its box is mid-collapse.
    component IconSlot: Item {
        id: slot
        required property string glyph
        readonly property bool shown: slot.glyph !== ""
        property string displayGlyph: ""

        implicitWidth: 0
        implicitHeight: label.implicitHeight
        clip: true

        // onShownChanged below never fires for the state a binding
        // already starts at (QML only fires *Changed on an actual
        // change, not the initial evaluation) -- without this, an icon
        // that's already meant to be visible the moment the bar first
        // loads (e.g. WiFi already connected on startup) would stay
        // collapsed forever, since nothing ever triggers showSeq. Snaps
        // straight to the settled "shown" state instead of animating it
        // -- there's nothing to animate FROM on a cold start.
        Component.onCompleted: {
            if (slot.shown) {
                slot.displayGlyph = slot.glyph;
                slot.implicitWidth = label.implicitWidth;
                label.opacity = 1;
            }
        }

        onShownChanged: {
            if (slot.shown) {
                slot.displayGlyph = slot.glyph;
                hideSeq.stop();
                showSeq.start();
            } else {
                showSeq.stop();
                hideSeq.start();
            }
        }

        ParallelAnimation {
            id: showSeq
            NumberAnimation { target: slot; property: "implicitWidth"; to: label.implicitWidth; duration: 200; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 110 }
                NumberAnimation { target: label; property: "opacity"; to: 1; duration: 140 }
            }
        }

        ParallelAnimation {
            id: hideSeq
            NumberAnimation { target: label; property: "opacity"; to: 0; duration: 130 }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                NumberAnimation { target: slot; property: "implicitWidth"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: label
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: slot.displayGlyph
            color: "#f2f2f7"
            font.family: Fonts.iconPhosphor
            font.pixelSize: 12
            opacity: 0
        }
    }
}
