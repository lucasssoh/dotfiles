import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// ============================================================
// Generic port of waybar's `custom/*` module contract: waybar's own
// custom modules are already a declarative "run this, expect JSON,
// re-run every N seconds, run this other thing on click" contract —
// Quickshell has no built-in equivalent (everything is QML/JS), so
// this recreates that one contract as a reusable component. Every
// custom/* entry from waybar/config.jsonc becomes one instantiation of
// this component with different `command`/`interval`/click values,
// instead of 10 hand-rolled Process+Timer blocks.
//
// JSON mode expects the same {"text":...,"class":...,"tooltip":...}
// shape the existing waybar/scripts/*.sh scripts already print — those
// scripts are reused unchanged (see shell.qml).
// ============================================================

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

    property var command: []            // e.g. ["bash", "-c", "...status"]
    property int interval: 5000         // ms, 0 = run once, no polling
    property bool json: true            // parse stdout as {text,class,tooltip} vs raw text
    property var clickCommand: []       // left-click, fire-and-forget
    property var rightClickCommand: []  // right-click, fire-and-forget
    property var classColors: ({})      // {"hdr-on": "#a8b4c4", ...} -- mirrors
                                         // the #custom-hdr.hdr-on {color: ...}
                                         // class selectors in waybar/style.css
    property var classIcons: ({})       // {"notification": "", ...} -- for
                                         // modules whose JSON "text" is data
                                         // (e.g. swaync's unread count) rather
                                         // than the glyph itself; mirrors
                                         // waybar's "format-icons" keyed by
                                         // class/alt. Empty = show obj.text
                                         // as-is (the common case).

    // Icon font override. Default stays Fonts.icon (the Nerd Font) --
    // it's what every waybar script's own glyphs are written against,
    // so a plain instantiation keeps rendering the script's text as-is.
    // The display-layout instance in shell.qml opts into Phosphor
    // instead (asked for: the rest of TOOLS is Phosphor, so its one
    // Nerd Font glyph read as a different icon set sitting in the same
    // row) and supplies its own Phosphor codepoints via `classIcons`,
    // leaving the script's Nerd Font output for waybar/config.jsonc,
    // which still runs the same `status` command.
    //
    // Size travels with the family: the two ink very differently within
    // their em-box (see the pixelSize note further down), so a per-
    // instance family override that couldn't also move the size would
    // just trade one mismatch for another.
    property string iconFont: Fonts.icon
    property real iconPixelSize: 10

    // Per-class override of `iconPixelSize`, keyed exactly like
    // `classIcons` / `classColors` above. Unset classes fall back to
    // `iconPixelSize`, so an instance that does not need this never
    // mentions it.
    //
    // This exists because a single size for a module whose glyph CHANGES
    // is only ever tuned against one of its states. Optical size is not
    // nominal size: two glyphs at the same pixelSize read as the same
    // size only if they fill a similar share of their box. Measured on
    // the three display-layout glyphs (silhouette area, outline plus the
    // whitespace it encloses, which is what the eye reads as mass):
    // lu-monitor 64%, lu-laptop 54%, lu-monitor-smartphone 33%. That is a
    // 2:1 spread inside one module.
    property var classIconSizes: ({})

    property string text: ""
    property string tooltip: ""
    property string moduleClass: ""

    property real textOpacity: 1.0      // waybar/style.css per-module opacity (e.g. #custom-apps: 0.8)
    property real letterSpacing: 0      // waybar/style.css per-module letter-spacing (e.g. #custom-apps: 4px)
    property real minWidth: 0           // floor in px -- mirrors waybar's "min-length"/CSS
                                         // min-width, reserves space so a module's own text
                                         // changing length (or briefly being empty before the
                                         // first poll) doesn't shift every module after it
    property real padding: 20           // total horizontal padding (both sides combined,
                                         // since the label is centered) -- per-instance so one
                                         // glued pair (e.g. display+hdr) can sit tighter without
                                         // affecting other ScriptModule instances (apps, etc.)

    // 5px margin around badge, same as Balise's own implicitWidth --
    // badge itself (not this Item directly) is what root.padding/
    // root.minWidth now size, see badge below.
    implicitWidth: badge.width + 5
    implicitHeight: 24

    function poll() {
        if (!proc.running) proc.running = true;
    }

    Process {
        id: proc
        command: root.command
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                if (!root.json) {
                    root.text = out;
                    return;
                }
                try {
                    const obj = JSON.parse(out);
                    root.text = obj.text || "";
                    root.tooltip = obj.tooltip || "";
                    root.moduleClass = obj.class || "";
                } catch (e) {
                    // Non-JSON output on a json:true module -- show it raw
                    // rather than going blank, easier to spot while wiring
                    // up a new module.
                    root.text = out;
                }
            }
        }
    }

    Timer {
        interval: root.interval
        running: root.interval > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    Component.onCompleted: if (root.interval === 0) root.poll();

    // Small badge, same recipe as Hdr.qml/BaliseButton.qml's own (asked
    // for explicitly -- "comme hdr ou balise ou l'icone est plus petite
    // et encadré dans un sous bouton avec border glass"): a transparent
    // Rectangle sized to content (root.padding/root.minWidth still drive
    // that, same as before -- just sizing THIS instead of the whole
    // Item directly now), radius 6 to match Hdr's own and BaliseButton's
    // (all three sit in the same `tools` pill and now share the one
    // rounded-but-not-capsule corner), plus GlassRim's edge below.
    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: Math.max(label.implicitWidth + root.padding, root.minWidth)
        // 18 -> 22: the chip stopped being the thing that fits and went
        // back to being the thing that frames. Every bar icon is one size
        // now (15px, see Fonts.qml), and a Lucide glyph at 15 inks up to
        // 16px tall -- inside an 18px chip that left ONE pixel of padding,
        // so the only way to keep 18 was to shrink the glyph, which is the
        // wrong end to give (asked for: "plutot agrandir le bouton que de
        // retrecir l'icon qui s'y trouve"). 22 restores ~3px a side, the
        // same breathing room the 12px glyphs used to have at 18.
        // Still fits: modules are 24 tall inside the island's 31px row, so
        // this grows into slack that was already there -- no module
        // implicitHeight moved, no row got taller.
        // Radius stays 6, NOT half the height: a 22px chip capsules at 11,
        // and "coin arrondi mais pas totalement arrondi comme un pill" is
        // still the rule these three share.
        height: 22
        radius: 6
        color: "transparent"

        // One GlassChip in place of the bottom+top GlassRim pair, same
        // swap and same 0.40/0.18 balance as Hdr.qml's own -- and a
        // layer.effect for the same reason, see there.
        layer.enabled: true
        layer.effect: GlassChip {
            radius: 6
            lightBottom: 1.0
            lightTop: 0.45
        }
    }

    // Fonts.icon: the one current instantiation (display-layout status,
    // see shell.qml) only ever shows an icon glyph here, never mixed with
    // prose -- a future instance that needs real text alongside would
    // need its own Text/Row split, same as e.g. Bluetooth.qml.
    //
    // Size history, and why it now lives per class (`classIconSizes`
    // above) instead of in one number: 15 -> 12 -> 10 -> 15 -> per-state.
    //
    // The 12 and the 10 were both "still too big, surtout en mode both",
    // and both shrank ALL THREE states to fix the one that was worst --
    // under the Nerd Font, "both" (nf-md-monitor_multiple, two
    // overlapping monitors) was far the bulkiest of the three. That left
    // internal/external smaller than they needed to be, which is exactly
    // what the later 10 -> 14 -> 15 passes were undoing.
    //
    // Lucide inverts the premise: lu-monitor-smartphone is the LIGHTEST
    // of the three now (33% silhouette against lu-monitor's 64%), so a
    // single number tuned on "both" would make "external" the heavy one
    // instead -- which is what it did, and what "l'icon de display est un
    // peu grand par rapport aux autres" was about. Each state carries its
    // own size now, so no state is tuned against another one's shape.
    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: badge
        text: root.classIcons[root.moduleClass] !== undefined
            ? root.classIcons[root.moduleClass] : root.text
        color: root.classColors[root.moduleClass] || root.ink.primary
        opacity: root.textOpacity
        font.family: root.iconFont
        // Bold, same "thicken every icon in METRICS/TOOLS" pass that
        // moved those two blocks' Phosphor glyphs onto the Phosphor-Bold
        // family. JetBrainsMono Nerd Font ships Bold under the SAME
        // family name (verified via `fc-list`, style=Bold), so unlike
        // Phosphor this one IS a font.weight and not a second family --
        // harmless on a Phosphor-Bold `iconFont`, which is already the
        // bold cut and has no weight axis to move.
        font.weight: Font.Bold
        font.pixelSize: root.classIconSizes[root.moduleClass] !== undefined
            ? root.classIconSizes[root.moduleClass] : root.iconPixelSize
        font.letterSpacing: root.letterSpacing
    }

    // Same two-source "verre métal" edge as Hdr's badge and Balise's own
    // -- traces badge's live x/y/width/height.
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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton && root.clickCommand.length > 0)
                Quickshell.execDetached(root.clickCommand);
            else if (mouse.button === Qt.RightButton && root.rightClickCommand.length > 0)
                Quickshell.execDetached(root.rightClickCommand);
        }
    }
}
