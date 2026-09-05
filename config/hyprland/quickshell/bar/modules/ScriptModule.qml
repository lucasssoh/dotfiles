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
    // Item directly now), radius 8 to match Hdr's own (this module sits
    // right next to it in the `tools` pill), plus GlassRim's edge below.
    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: Math.max(label.implicitWidth + root.padding, root.minWidth)
        height: 18
        radius: 8
        color: "transparent"
    }

    // Fonts.icon: the one current instantiation (display-layout status,
    // see shell.qml) only ever shows an icon glyph here, never mixed with
    // prose -- a future instance that needs real text alongside would
    // need its own Text/Row split, same as e.g. Bluetooth.qml.
    //
    // 15 -> 12 -> 10: still read as too big (asked for again, "surtout
    // en mode both") -- display-layout.sh's "both" state uses nf-md-
    // monitor_multiple specifically (two overlapping monitor shapes),
    // a visually bulkier glyph at any given pixelSize than the single-
    // monitor/laptop ones the internal/external states use, on top of
    // Fonts.icon (a Nerd Font) generally inking wider within its own
    // em-box than Fonts.iconPhosphor's glyphs do. 10 shrinks all three
    // states, "both" included, rather than leaving them at a size only
    // tuned against the two narrower glyphs.
    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        id: label
        anchors.centerIn: badge
        text: root.classIcons[root.moduleClass] !== undefined
            ? root.classIcons[root.moduleClass] : root.text
        color: root.classColors[root.moduleClass] || "#f2f2f7"
        opacity: root.textOpacity
        font.family: Fonts.icon
        font.pixelSize: 10
        font.letterSpacing: root.letterSpacing
    }

    // Same two-source "verre métal" edge as Hdr's badge and Balise's own
    // (topLeft full strength, a fainter bottomRight source) -- traces
    // badge's live x/y/width/height.
    GlassRim { target: badge; cornerRadius: badge.radius }
    GlassRim { target: badge; cornerRadius: badge.radius; lightOrigin: "bottomRight"; strength: 0.45 }

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
