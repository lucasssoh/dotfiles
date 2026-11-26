pragma Singleton
import QtQuick
import Quickshell

// Where each bar's side groups end, per screen, for the side sheets
// (Programme on the left, the notification centre on the right) that
// continue them down to the bottom of the screen. Each bar reports its
// own; a sheet reads the screen it opens on.
Singleton {
    id: root

    // The width a sheet takes at least, whatever the bar's group.
    readonly property int minWidth: 440

    // { screen name: { left: width of the left group, right: width of the
    //   right group } }, in pixels from each screen edge.
    property var groups: ({})

    function report(name: string, left: real, right: real): void {
        const g = root.groups[name];
        if (g && g.left === left && g.right === right)
            return;
        const next = Object.assign({}, root.groups);
        next[name] = { left: left, right: right };
        root.groups = next;
    }

    // The width of the bar's group on `screen`'s `edge` ("left" or
    // "right"), or minWidth when that group is narrower: what an attached
    // sheet is as wide as, and what a floating one lines up under.
    function width(screen, edge: string): real {
        const g = screen ? root.groups[screen.name] : null;
        return Math.max(root.minWidth, g ? g[edge] : 0);
    }
}
