import QtQuick
import "../../theme"

// The bar's one and only text field -- built here rather than pulled from
// QtQuick.Controls for the same reason every other control in this shell
// is hand-drawn (see NotificationCard.qml's own close button,
// DrawerIsland's reveal): Controls brings a whole style stack whose look
// would then have to be fought back into this palette, for a rounded box
// with a caret in it.
//
// Plain `TextInput`, not `TextField`: TextInput is QtQuick proper, so it
// costs no new import and no style plumbing, and everything Controls'
// TextField would have added on top (placeholder, echo toggle, focus
// ring, the box itself) is exactly what this file draws.
//
// IMPORTANT, and the whole reason this file could not exist before: the
// bar is a layer-shell surface declared `focusable: false`, so the
// compositor sends it no key events at all and a field inside it is
// simply dead. Whoever shows one of these has to raise
// BaliseState.textInputActive first (see BaliseDetailPage.qml's own
// Binding, and shell.qml's `focusable`) -- this component deliberately
// does NOT do that itself, since the flag is per-window and one field
// turning it off on unload would cut the field next to it off mid-typing.
Rectangle {
    id: field

    property string placeholder: ""
    property alias text: input.text
    // Password fields start masked; the eye toggle below flips this one
    // field only, and it re-masks whenever the text is cleared.
    property bool secret: false
    property bool showSecret: false
    // Ignored unless `secret` -- an identity field has nothing to hide.
    readonly property bool masked: field.secret && !field.showSecret

    signal accepted()
    signal escaped()

    function forceFieldFocus() { input.forceActiveFocus(); }

    width: parent ? parent.width : 0
    height: 40
    radius: 11
    color: input.activeFocus ? Surfaces.cardRaised : Surfaces.card
    border.width: 1
    // The focus ring is the only cue that keystrokes are landing here --
    // there is no window title bar or system focus indicator on a layer
    // surface to fall back on.
    border.color: input.activeFocus ? Surfaces.accent : Qt.rgba(1, 1, 1, 0.10)
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    // Declared BEFORE the TextInput on purpose, so it sits under it: the
    // TextInput keeps its own clicks (caret placement, drag-selection)
    // and this only catches the padding around it. A 40px-tall pill that
    // only takes focus on its text baseline reads as broken.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: {
            input.forceActiveFocus();
            input.cursorPosition = input.text.length;
        }
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.right: revealBtn.visible ? revealBtn.left : parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        selectByMouse: true

        color: "#f2f2f7"
        selectionColor: Surfaces.accentStrongest
        selectedTextColor: "#f2f2f7"
        font.family: Fonts.ui
        font.pixelSize: 13
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting

        echoMode: field.masked ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        // 0 rather than the default second-long peek: a shoulder-surfable
        // reveal of the last character is not something to ship by
        // default when the eye toggle right next to it makes the whole
        // value visible on purpose.
        passwordMaskDelay: 0
        // A passphrase is exactly the kind of string a helpful IME or
        // autocapitalise would corrupt.
        inputMethodHints: field.secret
            ? Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            : Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

        onAccepted: field.accepted()
        Keys.onEscapePressed: field.escaped()

        Text {
            anchors.fill: parent
            // Empty is enough -- NOT `&& !activeFocus`. The form focuses
            // its first field on open (see BaliseDetailPage's focusTimer),
            // and hiding the placeholder on focus left the top field of
            // the enterprise form showing nothing but a caret, with no
            // label anywhere saying it wanted a username.
            visible: input.text === ""
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferNoHinting
            text: field.placeholder
            color: "#8e8e93"
            font.family: Fonts.ui
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }

    // Reveal toggle -- "eye"/"eye-slash" have no VERIFIED Phosphor
    // codepoint anywhere in this bar yet, and guessing one is the exact
    // mistake this codebase's history warns against (see
    // BaliseNetworkRow.qml's own note), so it is a word.
    Text {
        id: revealBtn
        visible: field.secret && input.text !== ""
        anchors.right: parent.right
        anchors.rightMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferNoHinting
        text: field.showSecret ? "Hide" : "Show"
        color: revealArea.containsMouse ? "#f2f2f7" : Surfaces.accent
        font.family: Fonts.ui
        font.pixelSize: 11
        font.bold: true

        MouseArea {
            id: revealArea
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: field.showSecret = !field.showSecret
        }
    }

    // Emptying the field re-arms the mask, so clearing a rejected password
    // and typing the next one doesn't leave it in the open.
    Connections {
        target: input
        function onTextChanged() {
            if (input.text === "") field.showSecret = false;
        }
    }
}
