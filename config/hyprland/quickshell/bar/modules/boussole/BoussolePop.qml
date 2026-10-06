import QtQuick

// A card that comes and goes in the session panel, the way Balise's pop
// in: a fade with a slight zoom and a little overshoot, on `scale` (a
// render transform, so the column around it does not jitter). Going, it
// fades out and only then gives its room back.
Rectangle {
    id: pop

    property bool shown: false

    visible: pop.shown || pop.opacity > 0.01
    opacity: pop.shown ? 1 : 0
    scale: pop.shown ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
}
