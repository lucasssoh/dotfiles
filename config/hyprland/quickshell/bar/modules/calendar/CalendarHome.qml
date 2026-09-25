import QtQuick
import ".."          // DrawerHandle
import "../balise"   // RevealPop
import "../../theme"
import "../../services"

// Month calendar -- TOOLS' fifth drawer entry, opened by the clock (see
// Clock.qml). Same entry contract as PowerHome/MixerHome: `drawerOpen`,
// an implicitHeight the island reveals to, and a height Behavior that
// matches the island's revealDuration (220).
//
// The grid is always 6 weeks (42 cells), Monday first, so the drawer is
// the same height whatever the month -- paging never makes it jump.
// Holidays come from CalendarState, which computes them rather than
// fetching them; personal events come from khal through it too (added
// with Super+A -- see hypr/scripts/agenda.py). A day with events gets a
// dot; hovering it lists them in the footer.

Item {
    id: root

    property bool drawerOpen: false

    implicitHeight: handle.implicitHeight + 20 + content.implicitHeight + 20
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

    onDrawerOpenChanged: {
        if (root.drawerOpen) BaliseReveal.replay();
        else root.hoveredText = "";
    }

    readonly property var enUS: Qt.locale("en_US")

    // 42 cells: { y, m, d, inMonth, today, weekend, holiday, events }.
    readonly property var cells: {
        const y = CalendarState.viewYear;
        const m = CalendarState.viewMonth;
        // getDay() is 0 = Sunday; shift so Monday is column 0.
        const lead = (new Date(y, m, 1).getDay() + 6) % 7;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const dt = new Date(y, m, 1 - lead + i);
            const cy = dt.getFullYear(), cm = dt.getMonth(), cd = dt.getDate();
            out.push({
                y: cy, m: cm, d: cd,
                inMonth: cm === m,
                today: cy === CalendarState.todayYear
                    && cm === CalendarState.todayMonth
                    && cd === CalendarState.todayDay,
                weekend: i % 7 >= 5,
                holiday: CalendarState.holiday(cy, cm, cd),
                events: CalendarState.eventsOn(cy, cm, cd)
            });
        }
        return out;
    }

    // What the day under the pointer holds (holiday, then its events),
    // shown in the footer line in place of the default hint -- no tooltip
    // window for it. "" when the hovered day has nothing.
    property string hoveredText: ""
    property bool hoveredHoliday: false

    function eventLabel(e) {
        if (e.allDay) return e.title;
        return new Date(e.start).toLocaleTimeString(root.enUS, "HH:mm") + " " + e.title;
    }

    function describeDay(c) {
        const parts = [];
        if (c.holiday !== "") parts.push(c.holiday);
        for (const e of c.events) parts.push(root.eventLabel(e));
        return parts.join("  ·  ");
    }

    // Default footer: the next personal event if there is one, else the
    // next public holiday.
    readonly property string footerText: {
        if (root.hoveredText !== "") return root.hoveredText;
        const e = CalendarState.nextEvent;
        if (e !== null) {
            const s = new Date(e.start);
            const now = new Date();
            let day;
            if (s <= now) day = "Now";
            else if (s.toDateString() === now.toDateString()) day = "Today";
            else day = s.toLocaleDateString(root.enUS, "ddd MMM d");
            return "Next: " + day + "  ·  " + root.eventLabel(e);
        }
        const n = CalendarState.nextHoliday;
        if (n.days === 0) return "Today  ·  " + n.name;
        const when = n.days === 1 ? "tomorrow" : "in " + n.days + " days";
        return "Next: " + n.date.toLocaleDateString(root.enUS, "MMM d")
            + "  ·  " + n.name + "  (" + when + ")";
    }

    DrawerHandle {
        id: handle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        onCloseRequested: CalendarState.close()
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: handle.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 12
        spacing: 12

        // ---- header: ‹ Month Year › -----------------------------------
        Item {
            id: header
            width: parent.width
            height: 28

            RevealPop { item: header; index: 0 }

            Text {
                id: prev
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "‹"
                color: prevHit.containsMouse ? Ink.primary : Ink.secondary
                font.family: Fonts.ui
                font.pixelSize: 20
                MouseArea {
                    id: prevHit
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: CalendarState.shiftMonth(-1)
                }
            }

            Text {
                anchors.centerIn: parent
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: root.enUS.standaloneMonthName(CalendarState.viewMonth)
                    + " " + CalendarState.viewYear
                // Accent while away from the current month: it is also
                // the button that brings you back.
                color: CalendarState.monthOffset !== 0 && titleHit.containsMouse
                    ? Ink.accent : Ink.primary
                font.family: Fonts.ui
                font.pixelSize: 15
                MouseArea {
                    id: titleHit
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: CalendarState.monthOffset !== 0
                        ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: CalendarState.resetMonth()
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferNoHinting
                text: "›"
                color: nextHit.containsMouse ? Ink.primary : Ink.secondary
                font.family: Fonts.ui
                font.pixelSize: 20
                MouseArea {
                    id: nextHit
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: CalendarState.shiftMonth(1)
                }
            }
        }

        // ---- weekday labels + day grid --------------------------------
        Column {
            id: grid
            width: parent.width
            spacing: 4

            RevealPop { item: grid; index: 1 }

            readonly property real cellW: width / 7

            Row {
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Text {
                        width: grid.cellW
                        horizontalAlignment: Text.AlignHCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferNoHinting
                        text: modelData
                        color: index >= 5 ? Ink.muted : Ink.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 11
                    }
                }
            }

            Grid {
                id: days
                columns: 7

                // Wheel pages months. Accumulated so a touchpad's stream
                // of small deltas pages once per notch-equivalent rather
                // than once per event.
                property real wheelAcc: 0
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        days.wheelAcc += event.angleDelta.y;
                        while (days.wheelAcc >= 120) { days.wheelAcc -= 120; CalendarState.shiftMonth(-1); }
                        while (days.wheelAcc <= -120) { days.wheelAcc += 120; CalendarState.shiftMonth(1); }
                    }
                }

                Repeater {
                    model: root.cells
                    Item {
                        id: cell
                        width: grid.cellW
                        height: 32

                        Rectangle {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: width / 2
                            color: modelData.today ? Surfaces.accent
                                : cellHit.containsMouse ? Surfaces.cardHover
                                : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferNoHinting
                            text: modelData.d
                            color: modelData.today ? Ink.onLight
                                : modelData.holiday !== "" ? Ink.danger
                                : modelData.weekend ? Ink.secondary
                                : Ink.primary
                            opacity: modelData.inMonth ? 1 : 0.3
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            font.weight: modelData.today ? Font.DemiBold : Font.Normal
                        }

                        // Event dot, tucked under the number (inside the
                        // today pastille too, in its own ink).
                        Rectangle {
                            visible: modelData.events.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            width: 4
                            height: 4
                            radius: 2
                            color: modelData.today ? Ink.onLight : Ink.accent
                            opacity: modelData.inMonth ? 1 : 0.3
                        }

                        MouseArea {
                            id: cellHit
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            onContainsMouseChanged: {
                                const t = root.describeDay(modelData);
                                if (containsMouse) {
                                    root.hoveredText = t;
                                    root.hoveredHoliday = modelData.holiday !== "" && modelData.events.length === 0;
                                } else if (root.hoveredText === t) {
                                    root.hoveredText = "";
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- footer: next holiday / hovered holiday -------------------
        Text {
            id: footer
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: root.footerText
            color: root.hoveredText === "" ? Ink.secondary
                : root.hoveredHoliday ? Ink.danger : Ink.primary
            font.family: Fonts.ui
            font.pixelSize: 12

            RevealPop { item: footer; index: 2 }
        }
    }
}
