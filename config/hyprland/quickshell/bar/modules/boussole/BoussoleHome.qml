import QtQuick
import ".."          // DrawerHandle
import "../../theme"
import "../../services"

// Boussole's drawer, under its place in the bar: today first. The session
// under way or the next one, with what to do now, then the day as the
// timetable and the plan make it: courses filled, sessions outlined, free
// periods dotted, each with its hour.
//
// Same entry contract as the calendar's: `drawerOpen` from the caller, the
// island animates `height` to `implicitHeight`.
Item {
    id: root

    property bool drawerOpen: false

    implicitHeight: handle.implicitHeight + 12 + content.implicitHeight + 20
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    readonly property var b: BoussoleState
    readonly property var t: b.tracking
    readonly property var active: {
        if (!root.t) return null;
        for (const r of root.b.today) if (r.id === root.t.session) return r;
        return null;
    }
    readonly property var upcoming: {
        for (const r of root.b.today) if (r.type === "session" && !r.past && (r.state === "planned" || r.state === "postponed")) return r;
        return null;
    }
    readonly property var current: root.active || root.upcoming

    component Label: Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        font.family: Fonts.ui
        color: DrawerTheme.primary
        wrapMode: Text.WordWrap
    }

    component Pill: Rectangle {
        id: pill
        property string text: ""
        property bool primary: false
        signal clicked()
        height: 40
        width: pillText.implicitWidth + 30
        radius: height / 2
        color: pill.primary ? (pillHit.containsMouse ? DrawerTheme.secondary : DrawerTheme.on) : (pillHit.containsMouse ? DrawerTheme.cardHover : "transparent")
        border.width: pill.primary ? 0 : 1
        border.color: DrawerTheme.faint
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.text
            color: pill.primary ? DrawerTheme.onInk : DrawerTheme.primary
            font.family: Fonts.ui
            font.pixelSize: 14
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
        }
        MouseArea {
            id: pillHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: BoussoleState.close()
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 12
        spacing: 14

        // ---- header -----------------------------------------------------
        Row {
            width: parent.width
            spacing: 8
            Label {
                text: root.b.tr("Today", "Aujourd'hui")
                font.pixelSize: 20
                font.weight: Font.Bold
            }
            Label {
                anchors.baseline: parent.children[0].baseline
                text: new Date(root.b.nowMs).toLocaleDateString(Qt.locale(root.b.fr ? "fr_FR" : "en_US"), root.b.fr ? "dddd d MMMM" : "dddd, MMMM d")
                color: DrawerTheme.secondary
                font.pixelSize: 14
            }
        }

        Label {
            visible: !root.b.daemonConnected
            width: parent.width
            text: root.b.tr("The Boussole service is not running.", "Le service Boussole ne tourne pas.")
            color: DrawerTheme.secondary
            font.pixelSize: 14
        }

        // ---- now ----------------------------------------------------------
        Rectangle {
            visible: root.current !== null
            width: parent.width
            height: nowCol.implicitHeight + 28
            radius: 18
            color: DrawerTheme.card
            border.width: root.active ? 1 : 0
            border.color: DrawerTheme.faint

            Column {
                id: nowCol
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 6

                Label {
                    text: root.active
                        ? (root.t.counting ? root.b.tr("Under way · ", "En cours · ") : root.b.tr("Paused · ", "En pause · "))
                          + Math.floor(root.b.effectiveSecs / 60) + root.b.tr(" min effective", " min effectives")
                        : (root.current ? root.current.start + " – " + root.current.end : "")
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                }
                Label {
                    width: parent.width
                    text: root.current ? root.current.title : ""
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Repeater {
                    model: root.current ? root.current.parts : []
                    delegate: Label {
                        required property var modelData
                        width: nowCol.width
                        text: (modelData.domain ? modelData.domain + " · " : "") + modelData.what + " · " + modelData.minutes + " min"
                        color: DrawerTheme.secondary
                        font.pixelSize: 14
                    }
                }
                Item { width: 1; height: 4 }
                Flow {
                    width: parent.width
                    spacing: 8
                    Pill {
                        visible: !root.active
                        primary: true
                        text: root.b.tr("Start", "Commencer")
                        onClicked: root.b.start(root.current.id)
                    }
                    Pill {
                        visible: !root.active
                        text: root.b.tr("Not tonight", "Pas ce soir")
                        onClicked: root.b.skip(root.current.id)
                    }
                    Pill {
                        visible: root.active !== null
                        primary: true
                        text: root.b.tr("Close", "Clore")
                        onClicked: root.b.closeSession(root.active.id)
                    }
                }
            }
        }

        // ---- the day ------------------------------------------------------
        Label {
            visible: root.b.today.length > 0
            text: root.b.tr("The day", "La journée")
            color: DrawerTheme.secondary
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }

        Repeater {
            model: root.b.today
            delegate: Row {
                id: line
                required property var modelData
                readonly property var r: modelData
                width: content.width
                spacing: 12
                opacity: r.past && r.state !== "started" ? 0.55 : 1

                Label {
                    width: 46
                    horizontalAlignment: Text.AlignRight
                    topPadding: 9
                    text: line.r.start
                    color: DrawerTheme.secondary
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }

                Rectangle {
                    width: line.width - 58
                    height: block.implicitHeight + 16
                    radius: 12
                    color: line.r.type === "course" ? DrawerTheme.card : "transparent"
                    border.width: line.r.type === "course" ? 0 : 1
                    border.color: line.r.type === "session" ? DrawerTheme.primary : DrawerTheme.faint
                    // Free periods: a dotted outline, drawn as dashes.
                    Canvas {
                        anchors.fill: parent
                        visible: line.r.type === "offer"
                        onPaint: {
                            const c = getContext("2d");
                            c.reset();
                            c.setLineDash([4, 4]);
                            c.strokeStyle = DrawerTheme.muted;
                            c.lineWidth = 1;
                            c.beginPath();
                            c.roundedRect(0.5, 0.5, width - 1, height - 1, 12, 12);
                            c.stroke();
                        }
                    }
                    Column {
                        id: block
                        x: 12
                        y: 8
                        width: parent.width - 24
                        spacing: 2
                        Label {
                            width: parent.width
                            text: line.r.title + (line.r.state === "closed" ? "  ✓" : line.r.state === "skipped" || line.r.state === "missed" ? "  ✗" : "")
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.strikeout: line.r.state === "skipped"
                        }
                        Label {
                            width: parent.width
                            text: line.r.type === "course"
                                ? line.r.start + " – " + line.r.end
                                : line.r.start + " – " + line.r.end
                                  + (line.r.parts && line.r.parts.length ? " · " + line.r.parts.map(p => p.what).join(" + ") : "")
                                  + (line.r.type === "offer" ? root.b.tr(" · optional", " · facultatif") : "")
                            color: DrawerTheme.secondary
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }

        Label {
            visible: root.b.daemonConnected && root.b.today.length === 0
            width: parent.width
            text: root.b.paused ? root.b.tr("Paused: no sessions for now.", "En pause : pas de séance pour l'instant.")
                                : root.b.tr("Nothing planned today.", "Rien de prévu aujourd'hui.")
            color: DrawerTheme.secondary
            font.pixelSize: 14
        }
    }
}
