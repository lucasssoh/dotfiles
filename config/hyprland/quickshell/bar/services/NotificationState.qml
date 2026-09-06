pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "."

// State + trigger logic for the native notification daemon -- replaces
// swaync (GTK) entirely. NotificationBell.qml/NotificationToast.qml/
// NotificationCenter.qml (modules/) render whatever this holds, same
// service+render split as OsdState.qml/BatteryAlertState.qml.
//
// NotificationServer.trackedNotifications IS the notification-center's
// history -- a Notification only exists while `tracked === true`
// (dismiss()/expire()/tracked=false destroys the object and drops it
// from that list, notifying the sending app over D-Bus). Toasts are a
// SEPARATE, purely presentational list layered on top (toastQueue
// below): a toast timing out just stops floating on screen, it never
// touches trackedNotifications, so the notification still shows up in
// the center until the user actually clears it -- same toast-vs-history
// split swaync had, just built on Quickshell's one real list instead of
// two buffers kept in sync by hand.
Singleton {
    id: root

    // Registers org.freedesktop.Notifications on the session bus itself
    // (resilient via an internal QDBusServiceWatcher -- takes over
    // automatically from swaync/dunst if either is still running when
    // this starts, no coexistence code needed on this end). Capabilities
    // below drive what GetCapabilities() advertises to senders.
    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => root._handleNotification(n)
    }
    readonly property alias trackedNotifications: server.trackedNotifications

    // ---- do-not-disturb ----
    // Notifications still land in trackedNotifications/the bell badge
    // while dnd is on -- only the toast popup is suppressed. Same
    // "quieted, not blocked" behavior swaync's own dnd toggle had
    // (config.json's "dnd" widget).
    property bool dnd: false
    function toggleDnd() {
        root.dnd = !root.dnd;
    }

    // ---- bell badge ----
    property bool hasUnseen: false

    // ---- center open/close ----
    property bool centerOpen: false
    property var activeScreen: null

    // Closes Balise's own drawer first -- both now live as entries on the
    // same toolsIsland (see shell.qml), and were asked to be mutually
    // exclusive rather than stacking like Veille/Keybindings do:
    // "les deux ne peuvent pas s'empiler et soit l'un soit l'autre
    // s'ouvre". A direct call now (`import "."` makes BaliseState
    // resolvable here) -- this used to shell out to the external GTK
    // app's own `balise hide` CLI, back when Balise wasn't a QML drawer
    // in this same process yet.
    function toggleNotificationCenter(screen) {
        if (root.centerOpen && root.activeScreen === screen) {
            root.close();
            return;
        }
        BaliseState.close();
        root.activeScreen = screen;
        root.centerOpen = true;
        root.hasUnseen = false;
    }

    function close() {
        root.centerOpen = false;
    }

    // ---- toasts ----
    // {id, notification, expiresAt} entries, newest last. expiresAt: 0
    // means "never auto-hide" (critical urgency). Capped purely as a
    // render/height concern -- the cap never drops anything from
    // trackedNotifications, only from this presentation list.
    property var toastQueue: []
    readonly property int maxToasts: 4

    // swaync/config.json's own timeout / timeout-low / timeout-critical,
    // ported verbatim (6s / 4s / never). Critical always overrides
    // whatever expireTimeout the sending app itself requested -- swaync's
    // own hard override, not a guess about what the sender meant.
    function _timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;
        if (n.expireTimeout >= 0) return n.expireTimeout * 1000;
        return n.urgency === NotificationUrgency.Low ? 4000 : 6000;
    }

    function _handleNotification(n) {
        n.tracked = true;   // mandatory + synchronous, else n is destroyed
        root.hasUnseen = true;
        n.closed.connect(() => root._removeToast(n.id));

        if (root.dnd) return;   // still tracked/in history, just no popup

        // Battery-aware suppression (deliberately NOT implemented yet --
        // a product decision on threshold/scope, not a technical one):
        // BatteryAlertState.qml already exposes battDischarging/
        // battPercent, zero new UPower plumbing needed. Once decided,
        // this is a one-line addition here, e.g.:
        //   if (n.urgency === NotificationUrgency.Low
        //       && BatteryAlertState.battDischarging
        //       && BatteryAlertState.battPercent <= BatteryAlertState.tiers[0]) return;

        const timeout = root._timeoutFor(n);
        root.toastQueue = root.toastQueue
            .concat([{ id: n.id, notification: n, expiresAt: timeout > 0 ? Date.now() + timeout : 0 }])
            .slice(-root.maxToasts);
    }

    function _removeToast(id) {
        root.toastQueue = root.toastQueue.filter((e) => e.id !== id);
    }

    // One shared re-checking Timer rather than one Timer per notification
    // -- simplest way to expire entries out of a plain JS array for the
    // handful of concurrent toasts this ever sees.
    Timer {
        interval: 250
        repeat: true
        running: root.toastQueue.length > 0
        onTriggered: {
            const now = Date.now();
            root.toastQueue = root.toastQueue.filter((e) => e.expiresAt === 0 || e.expiresAt > now);
        }
    }

    // From the toast only -- hides the card, keeps the notification in
    // the center's history.
    function dismissToast(id) {
        root._removeToast(id);
    }

    // Forever -- from the center's own per-item close button (or
    // clearAll below). Removes from trackedNotifications too, which
    // notifies the sending app over D-Bus.
    function dismissForever(notification) {
        root._removeToast(notification.id);
        notification.dismiss();
    }

    function clearAll() {
        const all = server.trackedNotifications.values.slice();
        for (const n of all) root.dismissForever(n);
    }

    // hide-on-action: true (swaync's own default, ported) -- an invoked
    // action closes the notification everywhere, not just the toast.
    function invokeAction(notification, action) {
        action.invoke();
        root.dismissForever(notification);
    }
}
