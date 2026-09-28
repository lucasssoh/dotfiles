import QtQuick
import "../../theme"
import "../../services"

// The screen's three controls on one line, in Balise's SYSTEM group:
// the brightness gauge, then round Night mode and HDR buttons. Replaces
// the Night mode / HDR pair of ToggleRows (asked for, from the mockups:
// "fais 3 pour Balise", with HDR moved up beside the moon).
//
// The gauge is the mixer's thick-bar language: the fill IS the handle,
// never narrower than a disc, carrying the sun in the inverse ink, the
// percentage at the right. Drag or scroll to set; it writes through
// OsdState.setBrightness (brightnessctl, one call in flight) and reads
// OsdState.brightness, which the brightness keys keep current too.
//
// HDR locks it: with HDR on this panel ignores backlight changes, so the
// gauge greys out, reads "HDR" and takes no input -- the popup does the
// same (see Osd.qml).
Item {
    id: row

    property bool hdrActive: false
    property int revealIndex: 0

    implicitHeight: 38

    RevealPop { item: row; index: row.revealIndex }

    readonly property real level: OsdState.brightness
    readonly property int buttonSize: 38

    // Read the real level whenever the drawer opens: the keys move it
    // while Balise is closed, and nothing pushes backlight changes.
    Connections {
        target: BaliseState
        function onPanelOpenChanged() {
            if (BaliseState.panelOpen) OsdState.readBrightness();
        }
    }
    Component.onCompleted: OsdState.readBrightness()

    // ---- the gauge -----------------------------------------------------
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: moon.left
        anchors.rightMargin: 8
        height: parent.height
        radius: height / 2
        color: DrawerTheme.cardRaised

        Rectangle {
            id: fill
            height: parent.height
            radius: height / 2
            width: row.hdrActive ? height
                 : Math.max(height, parent.width * Math.max(0, Math.min(1, row.level)))
            color: row.hdrActive ? "#3a3a3e" : DrawerTheme.on
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.height - width) / 2
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: ""   // mgc sun
            color: row.hdrActive ? DrawerTheme.secondary : DrawerTheme.onInk
            font.family: Fonts.iconMingcute
            font.pixelSize: 17
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 13
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: row.hdrActive ? "HDR" : Math.round(row.level * 100)
            // On the dark track, or on the white fill once it reaches it.
            color: row.hdrActive ? DrawerTheme.secondary
                 : (fill.width > parent.width - 44 ? DrawerTheme.onInk : DrawerTheme.primary)
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            enabled: !row.hdrActive
            cursorShape: row.hdrActive ? Qt.ArrowCursor : Qt.PointingHandCursor
            function apply(mx) { OsdState.setBrightness(mx / width); }
            onPressed: (m) => apply(m.x)
            onPositionChanged: (m) => { if (pressed) apply(m.x); }
            onWheel: (w) => OsdState.setBrightness(row.level + (w.angleDelta.y > 0 ? 0.05 : -0.05))
        }
    }

    // ---- the two round buttons ----------------------------------------
    component RoundButton: Rectangle {
        id: btn
        property bool on: false
        property string glyph: ""
        property string label: ""
        signal clicked()

        width: row.buttonSize
        height: row.buttonSize
        radius: width / 2
        color: btn.on
            ? (hit.containsMouse ? Qt.rgba(DrawerTheme.on.r, DrawerTheme.on.g, DrawerTheme.on.b, 0.88) : DrawerTheme.on)
            : (hit.containsMouse ? DrawerTheme.accentStrongest : DrawerTheme.cardRaised)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: btn.glyph !== "" ? btn.glyph : btn.label
            color: btn.on ? DrawerTheme.onInk : DrawerTheme.primary
            font.family: btn.glyph !== "" ? Fonts.iconMingcute : Fonts.ui
            font.pixelSize: btn.glyph !== "" ? 17 : 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    RoundButton {
        id: moon
        anchors.right: hdr.left
        anchors.rightMargin: 8
        glyph: ""   // mgc moon
        on: BaliseState.nightModeEnabled
        onClicked: BaliseState.toggleNightMode()
    }

    RoundButton {
        id: hdr
        anchors.right: parent.right
        label: "HDR"
        on: row.hdrActive
        onClicked: HdrState.toggle()
    }
}
