import QtQuick
import "../../theme"
import "../../services"
import ".."

// The password card, centred on a veil over the whole screen: what asks,
// the command that asked for it, the field. Enter answers, Escape cancels,
// Tab unrolls the commands.
// Built while an ask is open and destroyed once it has faded (shell.qml).
Item {
    id: root

    readonly property var ask: SesameState.card
    readonly property bool open: SesameState.open
    readonly property bool confirm: root.ask ? root.ask.confirm : false
    readonly property var chain: root.ask ? (root.ask.chain || []) : []

    // Which steps of "Asked by" are unrolled, by index. A new ask starts
    // with the step that asks unrolled, without animating.
    property var openSteps: []
    // Steps whose whole command already shows on one line: nothing to
    // unfold, so they count as unfolded and Tab passes them by.
    property var fitSteps: []
    property bool animate: false
    readonly property bool canUnfold: root.chain.some((_, i) => root.fitSteps[i] !== true)
    readonly property bool allOpen: root.chain.every((_, i) => root.fitSteps[i] === true || root.openSteps[i] === true)
    function setFit(i, fits) {
        if ((root.fitSteps[i] === true) === fits) return;
        const a = root.fitSteps.slice();
        a[i] = fits;
        root.fitSteps = a;
    }
    function setStep(i, open) {
        const a = root.openSteps.slice();
        a[i] = open;
        root.openSteps = a;
    }
    // Tab: all unrolled or all folded, nearest step first, 40 ms apart.
    property var staggerQueue: []
    property bool staggerOpen: false
    function setAll(open) {
        const q = [];
        for (let i = root.chain.length - 1; i >= 0; i--)
            if (root.fitSteps[i] !== true && (root.openSteps[i] === true) !== open) q.push(i);
        if (q.length === 0) return;
        root.staggerOpen = open;
        root.setStep(q[0], open);
        root.staggerQueue = q.slice(1);
        if (root.staggerQueue.length > 0) staggerTimer.restart();
    }
    Timer {
        id: staggerTimer
        interval: 40
        repeat: true
        onTriggered: {
            if (root.staggerQueue.length === 0) { stop(); return; }
            root.setStep(root.staggerQueue[0], root.staggerOpen);
            root.staggerQueue = root.staggerQueue.slice(1);
        }
    }
    // One line of the mono text, the height of a folded step.
    Text {
        id: lineProbe
        visible: false
        text: "x"
        font.family: Fonts.mono
        font.pixelSize: 12
    }

    readonly property string glyph: {
        const k = root.ask ? root.ask.kind : "";
        return k === "polkit" ? "" : k === "gpg" ? "" : "";
    }
    readonly property string okLabel: {
        if (!root.ask) return "OK";
        if (root.confirm) return "Allow";
        if (root.ask.kind === "polkit") return "Authenticate";
        if (root.ask.echo) return "Send";
        return "Unlock";
    }

    function submit() {
        if (!root.open) return;
        const s = root.confirm ? "" : field.text;
        field.text = "";
        SesameState.answer(s);
    }
    function dismiss() {
        if (!root.open) return;
        field.text = "";
        SesameState.cancel();
    }

    // A new ask (a retry, the next in the queue): empty field, focus back.
    property var lastId: null
    onAskChanged: {
        if (root.ask && root.ask.id !== root.lastId) {
            root.lastId = root.ask.id;
            field.text = "";
            root.resetSteps();
            Qt.callLater(root.focusInput);
        }
    }
    Component.onCompleted: {
        root.lastId = root.ask ? root.ask.id : null;
        root.resetSteps();
        root.focusInput();
    }
    function resetSteps() {
        root.animate = false;
        staggerTimer.stop();
        const steps = [];
        if (root.chain.length > 0) steps[root.chain.length - 1] = true;
        root.openSteps = steps;
        Qt.callLater(() => root.animate = true);
    }
    function focusInput() {
        if (root.confirm) keyCatcher.forceActiveFocus();
        else field.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.38 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    // The veil takes the clicks: nothing behind is reachable while asked.
    MouseArea {
        anchors.fill: parent
        onClicked: root.focusInput()
    }

    Keys.onEscapePressed: root.dismiss()

    // Where the card shows, in the window's coordinates, for its blur
    // region (shell.qml): it scales about its centre as it opens.
    readonly property bool blurShown: root.open
    readonly property real blurX: card.x + card.width * (1 - card.scale) / 2
    readonly property real blurY: card.y + card.height * (1 - card.scale) / 2
    readonly property real blurWidth: card.width * card.scale
    readonly property real blurHeight: card.height * card.scale
    readonly property real blurRadius: 30 * card.scale

    Item {
        id: card
        anchors.centerIn: parent
        width: 440
        height: column.height + 24 * 2

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        GlassPane { anchors.fill: parent; radius: 30 }

        // Clicks on the card stay on the card.
        MouseArea { anchors.fill: parent; onClicked: root.focusInput() }

        Column {
            id: column
            x: 24
            y: 24
            width: card.width - 48
            spacing: 16

            Row {
                width: parent.width
                spacing: 12

                Rectangle {
                    width: 42
                    height: 42
                    radius: IslandStyle.round(14)
                    color: DrawerTheme.card
                    border.width: DrawerTheme.edgeWidth()
                    border.color: DrawerTheme.edgeColour()
                    Text {
                        anchors.centerIn: parent
                        text: root.glyph
                        color: DrawerTheme.primary
                        font.family: Fonts.iconLucide
                        font.pixelSize: 20
                    }
                }
                Column {
                    width: parent.width - 54
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: root.ask ? root.ask.title : ""
                        color: DrawerTheme.primary
                        font.family: Fonts.ui
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        renderType: Text.NativeRendering
                        text: root.ask ? root.ask.message : ""
                        color: DrawerTheme.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }
                }
            }

            // Asked by: outermost first, the step that asks last and
            // brightest. Each step shows one line; a click unrolls its whole
            // command, Tab unrolls or folds them all, nearest first. The
            // text is always wrapped: unrolling only grows its box, and a
            // fade stands where the ellipsis would, so nothing jumps.
            Column {
                visible: root.chain.length > 0
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: askedLabel.implicitHeight
                    Text {
                        id: askedLabel
                        renderType: Text.NativeRendering
                        text: "Asked by"
                        color: DrawerTheme.secondary
                        font.family: Fonts.ui
                        font.pixelSize: 11
                        font.letterSpacing: 0.4
                    }
                    Row {
                        visible: root.canUnfold
                        anchors.right: parent.right
                        anchors.verticalCenter: askedLabel.verticalCenter
                        spacing: 4
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: tabKey.implicitWidth + 10
                            height: tabKey.implicitHeight + 2
                            radius: 5
                            color: "transparent"
                            border.width: 1.5
                            border.color: DrawerTheme.muted
                            Text {
                                id: tabKey
                                anchors.centerIn: parent
                                renderType: Text.NativeRendering
                                text: "Tab"
                                color: DrawerTheme.muted
                                font.family: Fonts.mono
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            text: root.allOpen ? "fold" : "unfold"
                            color: DrawerTheme.muted
                            font.family: Fonts.ui
                            font.pixelSize: 11
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: steps.height + 10 * 2
                    radius: IslandStyle.round(14)
                    color: DrawerTheme.card
                    border.width: DrawerTheme.edgeWidth()
                    border.color: DrawerTheme.edgeColour()
                    Column {
                        id: steps
                        x: 8
                        y: 10
                        width: parent.width - 16
                        spacing: 2
                        Repeater {
                            model: root.chain
                            Item {
                                id: step
                                required property var modelData
                                required property int index
                                readonly property bool last: index === root.chain.length - 1
                                // A step is {cmd, cwd}; a bare string from an older daemon.
                                readonly property string cmd: typeof modelData === "string" ? modelData : (modelData.cmd || "")
                                readonly property string cwd: typeof modelData === "string" ? "" : (modelData.cwd || "")
                                readonly property bool open: root.openSteps[index] === true
                                readonly property bool showsCwd: last && cwd !== ""
                                readonly property bool fits: full.lineCount <= 1 && !showsCwd
                                onFitsChanged: root.setFit(index, fits)
                                Component.onCompleted: root.setFit(index, fits)
                                readonly property real indent: Math.min(index, 3) * 10
                                readonly property color ground: stepHover.containsMouse && !fits ? DrawerTheme.cardHover : DrawerTheme.card

                                width: steps.width
                                height: body.height + 4

                                Rectangle {
                                    anchors.fill: parent
                                    radius: IslandStyle.round(9)
                                    color: step.ground
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                Text {
                                    x: 6 + step.indent
                                    y: 2
                                    width: 14
                                    height: lineProbe.implicitHeight
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    renderType: Text.NativeRendering
                                    text: "›"
                                    color: DrawerTheme.muted
                                    font.family: Fonts.mono
                                    font.pixelSize: 12
                                    rotation: step.open && !step.fits ? 90 : 0
                                    Behavior on rotation {
                                        enabled: root.animate
                                        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                    }
                                }
                                Column {
                                    id: body
                                    x: 6 + step.indent + 18
                                    y: 2
                                    width: step.width - x - 6
                                    Item {
                                        width: parent.width
                                        height: step.open ? full.implicitHeight : lineProbe.implicitHeight
                                        clip: true
                                        Behavior on height {
                                            enabled: root.animate
                                            NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                        }
                                        Text {
                                            id: full
                                            width: parent.width
                                            renderType: Text.NativeRendering
                                            text: step.cmd
                                            color: step.last ? DrawerTheme.primary : DrawerTheme.secondary
                                            font.family: Fonts.mono
                                            font.pixelSize: 12
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                            maximumLineCount: 10
                                            elide: Text.ElideRight
                                        }
                                        // In the ellipsis's place, at the end of the first line.
                                        Rectangle {
                                            anchors.right: parent.right
                                            width: 48
                                            height: lineProbe.implicitHeight
                                            opacity: step.open || full.lineCount <= 1 ? 0 : 1
                                            Behavior on opacity {
                                                enabled: root.animate
                                                NumberAnimation { duration: 140 }
                                            }
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0; color: Qt.rgba(step.ground.r, step.ground.g, step.ground.b, 0) }
                                                GradientStop { position: 0.8; color: step.ground }
                                            }
                                        }
                                    }
                                    // Where the asking step runs, under it once unrolled.
                                    Item {
                                        width: parent.width
                                        height: step.open && step.showsCwd ? cwdText.implicitHeight + 2 : 0
                                        clip: true
                                        Behavior on height {
                                            enabled: root.animate
                                            NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                        }
                                        Text {
                                            id: cwdText
                                            y: step.open ? 2 : -4
                                            width: parent.width
                                            renderType: Text.NativeRendering
                                            text: "in " + step.cwd
                                            color: DrawerTheme.muted
                                            font.family: Fonts.mono
                                            font.pixelSize: 11
                                            elide: Text.ElideMiddle
                                            opacity: step.open ? 1 : 0
                                            Behavior on y {
                                                enabled: root.animate
                                                NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                            }
                                            Behavior on opacity {
                                                enabled: root.animate
                                                SequentialAnimation {
                                                    PauseAnimation { duration: step.open ? 60 : 0 }
                                                    NumberAnimation { duration: 180 }
                                                }
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    id: stepHover
                                    anchors.fill: parent
                                    enabled: !step.fits
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setStep(step.index, !step.open);
                                        root.focusInput();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.ask && root.ask.error !== ""
                width: parent.width
                renderType: Text.NativeRendering
                text: root.ask ? root.ask.error : ""
                color: DrawerTheme.danger
                font.family: Fonts.ui
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }

            // Outlined, not filled: the shell keeps away from white slabs.
            Rectangle {
                visible: !root.confirm
                width: parent.width
                height: 42
                radius: IslandStyle.round(13)
                color: "transparent"
                border.width: DrawerTheme.edgeWidth(field.activeFocus ? 1.5 : 1)
                border.color: DrawerTheme.edgeColour(field.activeFocus ? DrawerTheme.primary : DrawerTheme.faint)
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: root.ask && root.ask.echo ? TextInput.Normal : TextInput.Password
                    // A bigger dot than the UI font's bullet, which at 14 px
                    // was a speck.
                    passwordCharacter: "●"
                    color: DrawerTheme.primary
                    selectionColor: DrawerTheme.ink(0.25)
                    font.family: Fonts.ui
                    font.pixelSize: 14
                    font.letterSpacing: echoMode === TextInput.Password ? 3 : 0
                    clip: true
                    focus: true
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: root.dismiss()
                    Keys.onTabPressed: root.setAll(!root.allOpen)
                    Keys.onBacktabPressed: root.setAll(!root.allOpen)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text.length === 0
                        renderType: Text.NativeRendering
                        text: !root.ask ? "" : root.ask.echo ? "Answer" : root.ask.kind === "polkit" || root.ask.kind === "git" ? "Password" : "Passphrase"
                        color: DrawerTheme.muted
                        font.family: Fonts.ui
                        font.pixelSize: 14
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Repeater {
                    model: [
                        { label: root.confirm ? "Deny" : "Cancel", main: false },
                        { label: root.okLabel, main: true }
                    ]
                    Rectangle {
                        required property var modelData
                        width: label.implicitWidth + 36
                        height: 36
                        radius: IslandStyle.round(18)
                        color: modelData.main
                            ? (hover.containsMouse ? Qt.darker(DrawerTheme.on, DrawerTheme.dark ? 1.08 : 0.8) : DrawerTheme.on)
                            : (hover.containsMouse ? DrawerTheme.cardHover : DrawerTheme.card)
                        border.width: DrawerTheme.edgeWidth()
                        border.color: DrawerTheme.edgeColour()
                        Text {
                            id: label
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            text: modelData.label
                            color: modelData.main ? DrawerTheme.onInk : DrawerTheme.primary
                            font.family: Fonts.ui
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.main ? root.submit() : root.dismiss()
                        }
                    }
                }
            }
        }
    }

    // Allow/Deny cards have no field to hold the keys.
    Item {
        id: keyCatcher
        Keys.onTabPressed: root.setAll(!root.allOpen)
        Keys.onBacktabPressed: root.setAll(!root.allOpen)
        Keys.onReturnPressed: root.submit()
        Keys.onEnterPressed: root.submit()
        Keys.onEscapePressed: root.dismiss()
    }
}
