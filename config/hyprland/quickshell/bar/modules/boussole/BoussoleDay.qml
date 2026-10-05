import QtQuick
import "../../theme"
import "../../services"

// A day's rows, as the service sends them: courses filled, sessions
// outlined, optional slots dashed, each under its hour.
Column {
    id: root

    property var rows: []
    spacing: 8

    Repeater {
        model: root.rows
        delegate: Row {
            id: line
            required property var modelData
            readonly property var r: modelData
            width: root.width
            spacing: 12
            opacity: r.past && r.state !== "started" ? 0.55 : 1

            BoussoleText {
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
                border.width: line.r.type === "session" ? 1 : 0
                border.color: DrawerTheme.primary

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
                    BoussoleText {
                        width: parent.width
                        text: line.r.title + (line.r.state === "closed" ? "  ✓" : (line.r.state === "skipped" || line.r.state === "missed") ? "  ✗" : "")
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        font.strikeout: line.r.state === "skipped"
                    }
                    BoussoleText {
                        width: parent.width
                        text: line.r.start + " – " + line.r.end
                              + (line.r.parts && line.r.parts.length ? " · " + line.r.parts.map(p => (p.domain ? p.domain + " " : "") + p.what).join(" + ") : "")
                              + (line.r.type === "offer" ? BoussoleState.tr(" · optional", " · facultatif") : "")
                        color: DrawerTheme.secondary
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
