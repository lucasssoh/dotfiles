import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import "../theme"
import "../services"

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

    property var screen: null

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
    // WifiNetwork.signalStrength is a 0..1 double (verified live against
    // Quickshell.Networking: nmcli's 100% link reads back as 0.9), NOT a
    // 0-100 percentage -- so the *100 is what makes the tier thresholds
    // below mean anything. Without it every connected link rounded to 0
    // or 1 and the badge was permanently pinned to the wifi-low glyph,
    // whatever the actual signal.
    readonly property int wifiSignal: {
        if (root.netKind !== "wifi" || !root.activeDevice) return 0;
        const nets = root.activeDevice.networks.values;
        for (let i = 0; i < nets.length; i++) {
            if (nets[i].connected) return Math.round(nets[i].signalStrength * 100);
        }
        return 0;
    }
    // ph-network / ph-wifi-low/medium/high, same codepoints as
    // Network.qml's own icon() (kept in step with balise-src/src/ui/
    // icon.rs's table). "" (no glyph) for "none" -- deliberately not the
    // wifi-slash Network.qml itself falls back to.
    //
    // Ethernet was ph-plugs (U+EB5A) until Battery.qml took a plug for
    // "battery at rest on AC": two plug shapes inches apart in the same
    // pill read as the same state. It was wrong twice over anyway --
    // EB5A draws plugs coming APART, so the CONNECTED state showed an
    // unplugging gesture, and at this size its diagonals never resolved
    // into anything. ph-network's strokes are axis-aligned and stay
    // legible at 15px. Codepoint as a \u escape, not a literal glyph:
    // the old one came from the font's GSUB ligature table, which
    // misattributes names -- render and look before trusting it.
    function netIcon() {
        if (root.netKind === "ethernet") return "\uEDDE";
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
            font.family: Fonts.iconPhosphorBold
            font.pixelSize: 12
        }
    }

    // Same "verre métal" edge as Hdr's badge, Balise's own panel, Roue's
    // hub -- see GlassRim.qml's header for the shared five-stop ramp.
    // Traces `badge`'s live x/y/width/height (GlassRim.qml binds to
    // `target`'s geometry every frame), so it grows/shrinks in step with
    // the animated resize above instead of needing its own Behavior.
    // Symmetric light from BELOW, not the topLeft/bottomRight diagonal the
    // bar's bigger panes use -- asked for, for the island badges
    // specifically ("un light source bas symétrique, pas haut gauche bas
    // droite"). Two sources still, same idiom as before: the lit one from
    // the bottom plus a fainter one from the top, so the upper arête
    // still reads instead of dissolving into the pill behind it.
    //
    // vSpan 1.0 (not the 0.65/0.5 diagonal default) spends the whole
    // five-stop ramp across the badge's 18px height, which is what makes
    // the bottom edge read as the lit one on a chip this small.
    //
    // 0.40/0.18 and not the full-strength 1.0/0.45 the panes use: a
    // corner hot spot only ever lights a short arc, while a symmetric
    // source lights the ENTIRE bottom run at the ramp's brightest stop,
    // so the same numbers that read as a highlight on a pane read as a
    // white underline here -- measured, 157 luminance against the old
    // diagonal's 92 peak, and "la puissance du blanc est trop forte".
    // 0.40 puts it at 66, below the look it replaces, with the direction
    // still legible; 0.28 was tried too and loses the bottom edge into
    // the other three.
    GlassRim {
        target: badge
        cornerRadius: badge.radius
        lightOrigin: "bottom"
        vSpan: 1.0
        strength: 0.40
    }
    GlassRim {
        target: badge
        cornerRadius: badge.radius
        lightOrigin: "top"
        vSpan: 1.0
        strength: 0.18
    }

    // Opens Balise's own drawer on toolsIsland now (BaliseHome.qml, see
    // the project plan) instead of launching the separate GTK app --
    // BaliseState owns the toggle/mutual-exclusion-with-notifications
    // logic, same shape as NotificationBell.qml's own click handler.
    MouseArea {
        anchors.fill: parent
        onClicked: BaliseState.togglePanel(root.screen)
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

        // The glyph can also change WITHOUT `shown` changing -- a wifi
        // tier switch (low -> medium -> high as the signal moves, or on
        // roaming to a stronger AP) and bluetooth's own
        // ph-bluetooth -> ph-bluetooth-connected are both glyph-only
        // changes on an already-visible slot. `displayGlyph` used to be
        // written ONLY from onShownChanged/Component.onCompleted, so
        // those never reached the Text: the slot kept rendering whatever
        // tier it happened to have when it first appeared (observed
        // live: still the half-signal glyph on a 100% link). Guarded on
        // a non-empty glyph so the hide path keeps showing the icon that
        // was actually there while it fades out -- that's the whole
        // reason displayGlyph exists as a separate property.
        onGlyphChanged: {
            if (slot.glyph === "") return;
            slot.displayGlyph = slot.glyph;
            // Tiers aren't guaranteed to ink the same width; resync the
            // box, but only when no in/out animation is currently
            // driving implicitWidth itself.
            if (slot.shown && !showSeq.running && !hideSeq.running)
                slot.implicitWidth = label.implicitWidth;
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
            font.family: Fonts.iconPhosphorBold
            font.pixelSize: 12
            opacity: 0
        }
    }
}
