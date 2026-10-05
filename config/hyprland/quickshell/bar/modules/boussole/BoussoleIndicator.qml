import QtQuick
import "../../theme"
import "../../services"

// Boussole's place in the bar, right of the clock, always there once
// Boussole is installed. Text only while nothing presses; an outline under
// fifteen minutes; during a session a ring that empties over the
// Pomodoro's 25 minutes. With nothing going on, the compass alone (dimmed
// when the service is stopped), or "Set up" / "Paused".
// A click, or Super + D, opens the drawer.
Item {
    id: root

    property QtObject ink: Ink
    property var screen: null

    readonly property var b: BoussoleState
    readonly property var t: b.tracking

    function domainOf(s) {
        return s && s.parts && s.parts.length > 0 ? (s.parts[0].domain || "") : "";
    }
    readonly property int minutesToNext: {
        const n = root.b.next;
        if (!n) return -1;
        const p = n.date.split("-");
        const hm = n.start.split(":");
        const at = new Date(+p[0], +p[1] - 1, +p[2], +hm[0], +hm[1]);
        return Math.round((at.getTime() - root.b.nowMs) / 60000);
    }
    readonly property bool nextToday: root.b.next !== null && root.b.next.date === Qt.formatDate(new Date(root.b.nowMs), "yyyy-MM-dd")

    // What to say, most pressing first.
    readonly property string mode: {
        if (root.t) {
            if (root.t.flags.game) return "game";
            if (root.t.flags.paused) return "paused";
            return root.b.onBreak ? "break" : "session";
        }
        if (root.b.declare.length > 0) return "declare";
        if (root.b.gap) return "gap";
        if (root.b.next && root.minutesToNext >= 0 && root.minutesToNext < 15) return "soon";
        if (root.b.next && !root.b.paused) return "next";
        // Nothing going on: the place stays, with a quiet placeholder.
        if (!root.b.daemonConnected) return root.b.installed ? "off" : "";
        if (root.b.setupNeeded) return "setup";
        if (root.b.paused) return "pause";
        return "idle";
    }

    readonly property string label: {
        const b = root.b;
        const mm = (s) => Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
        switch (root.mode) {
        case "game": return b.tr("Session paused · game open", "Séance en pause · jeu ouvert");
        case "paused": return b.tr("Session paused", "Séance en pause");
        case "break": return b.tr("Break · ", "Pause · ") + mm(b.phaseLeft);
        case "session": {
            const doc = root.t.doc;
            return Math.ceil(b.phaseLeft / 60) + " min" + (doc ? "" : b.tr(" · on paper", " · sur papier"));
        }
        case "declare": return b.declare.length + b.tr(" to declare", " à déclarer");
        case "gap": return b.tr("Free ", "Creux ") + b.gap.start + "-" + b.gap.end + (b.gap.parts.length ? " · " + root.domainOf(b.gap) + " ?" : "");
        case "soon": return root.domainOf(b.next) + b.tr(" in ", " dans ") + root.minutesToNext + " min";
        case "setup": return b.tr("Set up", "À régler");
        case "pause": return b.tr("Paused", "En pause");
        case "off":
        case "idle": return "";
        case "next": {
            const day = root.nextToday ? "" : (new Date(b.next.date + "T12:00").toLocaleDateString(Qt.locale(b.fr ? "fr_FR" : "en_US"), "ddd") + " ");
            return root.domainOf(b.next) + " · " + day + b.next.start;
        }
        }
        return "";
    }

    visible: root.mode !== ""
    implicitWidth: root.visible ? row.implicitWidth + 16 : 0
    implicitHeight: 24

    // An outline when the session is close, to catch the eye.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.ink.primary
        visible: root.mode === "soon"
        opacity: 0.8
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        // The Pomodoro: a ring that empties.
        Canvas {
            id: ring
            visible: root.mode === "session" || root.mode === "break"
            width: 13
            height: 13
            anchors.verticalCenter: parent.verticalCenter
            readonly property real pomodoroLeft: 1 - BoussoleState.phaseProgress
            readonly property color ringColor: root.ink.primary
            onPomodoroLeftChanged: requestPaint()
            onRingColorChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.lineWidth = 2;
                c.strokeStyle = Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.25);
                c.beginPath();
                c.arc(6.5, 6.5, 5.2, 0, 2 * Math.PI);
                c.stroke();
                c.strokeStyle = ringColor;
                c.beginPath();
                c.arc(6.5, 6.5, 5.2, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * pomodoroLeft);
                c.stroke();
            }
        }

        Text {
            visible: !ring.visible
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "game" ? "" : root.mode === "paused" ? "" : ""
            color: root.ink.primary
            // The service stopped: still there, dimmed.
            opacity: root.mode === "off" ? 0.45 : 1
            font.family: Fonts.iconLucide
            font.pixelSize: 14
        }

        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.label
            color: root.ink.primary
            font.family: Fonts.ui
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        // Waiting to be declared: a red dot.
        Rectangle {
            visible: root.mode === "declare"
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            color: DrawerTheme.danger
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: BoussoleState.togglePanel(root.screen)
    }
}
