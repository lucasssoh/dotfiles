import QtQuick
import "../../theme"
import ".."          // GlassCard
import "../balise"   // RevealPop

// One card: a glyph that mutes, a name, a percentage, and a slider. The
// output master, the input master and every application row are all this
// component with different properties -- the only structural switch is
// `compact`, which shrinks the badge and the type for the application
// rows so a list of four of them does not stand as tall as the two
// masters it sits under.
//
// Card colours come from the same three-state set BaliseDeviceRow uses
// (card / cardHover / accentSoft + accent border), so a row here and a
// row in Balise's network list are recognisably the same object. What is
// NOT shared is what "active" means: a Balise row lights up when the
// device is connected, this one lights up when the stream is MUTED,
// because mute is the only state a volume row has that is worth
// interrupting a glance for.
Rectangle {
    id: row

    property int revealIndex: 0
    RevealPop { item: row; index: row.revealIndex }

    property string glyph: ""
    property string title: ""
    property bool compact: false

    property real value: 0
    property real maximum: 1.0
    property bool muted: false
    property real peak: -1

    // Application rows carry a chevron that opens their own page. It used
    // to be the masters that had one, unfolding a device picker beneath
    // them -- that picker is a plain list now, so the only chevron left in
    // this drawer means "there is a page behind this", and it points the
    // way a page is.
    property bool expandable: false

    // Application rows additionally carry an EQ badge, left of the chevron.
    // It is a READOUT, not a control: the switch that sets it lives on the
    // application's own page, which the chevron opens. Two places to toggle
    // one setting is how a row and a page start disagreeing about it.
    property bool eqable: false
    property bool eqOn: false

    signal moved(real v)
    signal muteToggled()
    signal expandToggled()

    readonly property real pad: row.compact ? 10 : 12
    readonly property real badgeSize: row.compact ? 26 : 32

    width: parent ? parent.width : 0
    implicitHeight: row.pad * 2 + body.implicitHeight
    height: row.implicitHeight
    radius: 14

    // Only lit rows and hovered rows pay for the blur -- same gate
    // DrawerTile and BaliseDeviceRow both use.
    layer.enabled: row.muted || hover.containsMouse
    layer.effect: GlassCard { radius: 14 }

    color: row.muted
        ? (hover.containsMouse ? Surfaces.accentStrong : Surfaces.accentSoft)
        : (hover.containsMouse ? Surfaces.cardHover : Surfaces.card)
    border.width: 1
    border.color: row.muted ? Qt.rgba(0xa8 / 255, 0xb4 / 255, 0xc4 / 255, 0.55) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    // Hover only. The card itself is not clickable: every pixel that does
    // something in this row already belongs to one of the three hit areas
    // below (badge, chevron, slider), and a fourth "clicking anywhere
    // does the default thing" would put a mute toggle under a
    // mis-aimed drag.
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: row.pad
        anchors.verticalCenter: parent.verticalCenter
        width: row.badgeSize
        height: row.badgeSize
        radius: row.compact ? 8 : 10
        color: row.muted
            ? Surfaces.accentStrong
            : (badgeHit.containsMouse ? Surfaces.accentSoft : Surfaces.cardHover)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: row.glyph
            color: row.muted ? Ink.accent : Ink.primary
            font.family: Fonts.iconPhosphor
            font.pixelSize: row.compact ? 14 : 16
        }

        // The badge IS the mute button. Asked of this shape by the rest
        // of the bar: AudioOutput.qml's own glyph already changes to
        // volume-off on mute, so the icon is where a user looks to learn
        // the state, and making the thing you look at also the thing you
        // press saves a fourth control on a 320px row.
        MouseArea {
            id: badgeHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.muteToggled()
        }
    }

    Column {
        id: body
        anchors.left: badge.right
        anchors.leftMargin: row.pad
        anchors.right: parent.right
        anchors.rightMargin: row.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.compact ? 6 : 8

        Item {
            width: parent.width
            height: nameCol.implicitHeight

            // A Column around one Text, kept rather than collapsed into a
            // bare anchored Text: `height: nameCol.implicitHeight` above
            // is what gives the header row its height, and a positioner
            // is the thing that reports that without hard-coding a line
            // box measurement that changes with `compact`.
            Column {
                id: nameCol
                anchors.left: parent.left
                anchors.right: readout.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: row.title
                    color: Ink.primary
                    font.family: Fonts.ui
                    font.pixelSize: row.compact ? 12 : 13
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            // Fixed width, right-aligned. The obvious spelling (a Text
            // that sizes to its content) re-lays-out the whole header on
            // every percent, which during a drag means the chevron beside
            // it twitching left and right the entire time the knob moves.
            Text {
                id: readout
                // Rightmost of whatever is present: badge, then chevron,
                // then the card edge.
                anchors.right: eqBtn.visible ? eqBtn.left
                             : (chevron.visible ? chevron.left : parent.right)
                anchors.rightMargin: (chevron.visible || eqBtn.visible) ? 6 : 0
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: Math.round(row.value * 100) + "%"
                color: row.muted ? Ink.faint : Ink.secondary
                font.family: Fonts.ui
                font.pixelSize: 11
            }

            Item {
                id: chevron
                visible: row.expandable
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "\uE06F"   // lu-chevron-right
                    color: chevronHit.containsMouse ? Ink.primary : Ink.secondary
                    font.family: Fonts.iconPhosphor
                    font.pixelSize: 14
                }

                MouseArea {
                    id: chevronHit
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.expandToggled()
                }
            }

            // Says whether this application is going through an equalizer
            // chain right now. Drawn only when it IS -- an unlit "EQ" on
            // every row would be five words of chrome saying nothing, and
            // the chevron beside it already advertises that there is a page
            // to open.
            Rectangle {
                id: eqBtn
                visible: row.eqable && row.eqOn
                anchors.right: chevron.visible ? chevron.left : parent.right
                anchors.rightMargin: chevron.visible ? 6 : 0
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 18
                radius: 9
                color: Surfaces.accentStrong
                border.width: 1
                border.color: Ink.accent

                Text {
                    anchors.centerIn: parent
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferNoHinting
                    text: "EQ"
                    color: Ink.accent
                    font.family: Fonts.ui
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 0.5
                }
            }
        }

        MixerSlider {
            width: parent.width
            value: row.value
            maximum: row.maximum
            muted: row.muted
            peak: row.peak
            onMoved: (v) => row.moved(v)
        }
    }
}
