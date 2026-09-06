pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
    // {notifId, notification, expiresAt} rows, newest FIRST (that is also
    // the on-screen order, so nothing has to reverse this to render it).
    // expiresAt: 0 means "never auto-hide" (critical urgency). Capped
    // purely as a render/height concern -- the cap never drops anything
    // from trackedNotifications, only from this presentation list.
    //
    // A ListModel, not the plain JS array this used to be. A JS array is
    // not a diffable model: any change to it resets the view wholesale, so
    // every delegate was destroyed and rebuilt on every arrival and every
    // expiry. That silently rules out ANY enter/exit animation (a
    // destroyed delegate cannot animate its own departure) and made the
    // arrival slide fire on the whole stack rather than the new card. With
    // a ListModel the view sees real insert/remove operations and can run
    // NotificationToast.qml's own add/remove Transitions on exactly the
    // row that changed.
    //
    // `dynamicRoles` because one of the roles is the Notification QObject
    // itself; static roles infer their type from the first row inserted
    // and do not hold object references.
    ListModel { id: toastModel; dynamicRoles: true }
    readonly property alias toasts: toastModel
    readonly property int maxToasts: 4

    // Which monitor the current stack of toasts belongs on, by Hyprland
    // output NAME (not a screen object): the toast surface is a
    // per-screen `Variants` in shell.qml, so without this ONE
    // notification popped a card on EVERY monitor at once -- two
    // identical "Connected to <ssid>" cards side by side on a
    // laptop-plus-external setup, which reads as the backend having sent
    // the notification twice. It hadn't: dbus-monitor sees exactly one
    // Notify per connect.
    //
    // Latched when the stack goes from empty to non-empty, NOT bound
    // live to `Hyprland.focusedMonitor` -- a live binding would teleport
    // a card that is already on screen the moment focus moves, and a
    // notification arriving while others are still up joins the stack
    // where the user is already looking.
    //
    // A name rather than the ShellScreen itself so an unplugged monitor
    // leaves a string that simply resolves to nothing instead of a
    // dangling object reference; shell.qml maps it back and falls back to
    // showing on every screen when it cannot (see `toastScreen` there),
    // so a display change can never swallow a notification entirely.
    // Same reason it starts empty.
    property string toastScreenName: ""

    // swaync/config.json's own timeout / timeout-low / timeout-critical,
    // ported verbatim (6s / 4s / never). Critical always overrides
    // whatever expireTimeout the sending app itself requested -- swaync's
    // own hard override, not a guess about what the sender meant.
    function _timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;
        // MILLISECONDS, straight through -- this used to be
        // `expireTimeout * 1000`, which silently made any sender that
        // asks for its own timeout immortal: `notify-send -t 2000` was
        // landing 2000 SECONDS out (measured: expiresAt - now = 1999455ms
        // for a 2s request). It went unnoticed because notify-send's
        // default is -1, which takes the urgency branch below instead, so
        // ordinary notifications expired correctly the whole time. 0 is
        // still "never expire" here, which is also what the spec means by
        // it, so `>= 0` stays.
        if (n.expireTimeout >= 0) return n.expireTimeout;
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
        // Opening a fresh stack picks the monitor -- see toastScreenName.
        if (toastModel.count === 0)
            root.toastScreenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        // Inserted at the front, and the cap trims from the BACK -- newest
        // first in the model is also newest on top on screen.
        toastModel.insert(0, {
            notifId: n.id,
            notification: n,
            expiresAt: timeout > 0 ? Date.now() + timeout : 0
        });
        while (toastModel.count > root.maxToasts) toastModel.remove(toastModel.count - 1);
    }

    function _toastIndex(id) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).notifId === id) return i;
        }
        return -1;
    }

    function _removeToast(id) {
        const i = root._toastIndex(id);
        if (i >= 0) toastModel.remove(i);
    }

    // One shared re-checking Timer rather than one Timer per notification
    // -- simplest way to expire rows for the handful of concurrent toasts
    // this ever sees. Backwards so removing a row cannot shift one that
    // has not been examined yet out from under the loop.
    Timer {
        interval: 250
        repeat: true
        running: toastModel.count > 0
        onTriggered: {
            const now = Date.now();
            for (let i = toastModel.count - 1; i >= 0; i--) {
                const e = toastModel.get(i).expiresAt;
                if (e !== 0 && e <= now) toastModel.remove(i);
            }
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

    // Clear-all as a CASCADE rather than one bulk wipe -- asked for: "en
    // clear all il faut un petit effet escalier pour qu'il se degage une à
    // une même ultra rapidement, je veux garder le système reactif".
    //
    // The staircase is not animated here at all: dismissing one
    // notification per tick is enough, because each removal independently
    // fires NotificationCenter.qml's own `remove` transition, so the cards
    // peel off to the right one after another on their own. Doing it this
    // way rather than staggering delays inside the view is also what keeps
    // it interruptible -- see below.
    //
    // 45ms is deliberately shorter than the 180ms exit itself, so the
    // cards overlap in flight (a cascade, not a queue of separate
    // departures): ten notifications are fully gone in under half a
    // second. Nothing blocks meanwhile -- this is a Timer, not a loop, so
    // the drawer stays live and a notification arriving mid-cascade is
    // simply not part of the batch.
    property int clearStagger: 45
    property var _clearBatch: []

    function clearAll() {
        if (server.trackedNotifications.values.length === 0) return;
        // Snapshotted, and in `values` order -- oldest first, which is
        // also top-to-bottom on screen, so the cascade runs down the list
        // the way it is read.
        root._clearBatch = server.trackedNotifications.values.slice();
        root._clearStep();       // first card leaves immediately, no lead-in delay
        clearTimer.restart();
    }

    function _clearStep() {
        while (root._clearBatch.length > 0) {
            const n = root._clearBatch.shift();
            // Skip anything that went away on its own since the snapshot
            // (the sending app closed it, or the user beat the cascade to
            // it) -- dismiss() on an already-destroyed Notification would
            // throw and strand the rest of the batch.
            if (server.trackedNotifications.values.indexOf(n) >= 0) {
                root.dismissForever(n);
                return;
            }
        }
        clearTimer.stop();
    }

    Timer {
        id: clearTimer
        interval: root.clearStagger
        repeat: true
        onTriggered: root._clearStep()
    }

    // hide-on-action: true (swaync's own default, ported) -- an invoked
    // action closes the notification everywhere, not just the toast.
    function invokeAction(notification, action) {
        action.invoke();
        root.dismissForever(notification);
    }
}
