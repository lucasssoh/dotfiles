//! Unix-socket daemon/client, adapted from orbit-vendor/src/app/daemon.rs.
//! Balise needs to persist across opens like Orbit (unlike Prisme/Roue's
//! one-shot-and-exit model), so it needs the same daemon shape -- with its
//! own socket (see crate::paths) so the two coexist during the parallel
//! build-out.
//!
//! Wire format: JSON-lines, both directions, replacing the original
//! colon-delimited text protocol (see the project plan's QML-frontend
//! step). `balise` (CLI) and the daemon are the same binary, so there is
//! no external format to stay compatible with -- one schema, not two.
//! Every accepted connection is treated identically now, whether it's a
//! short-lived CLI invocation (`balise toggle`, still connect-send-read-
//! disconnect) or a long-lived one (the QML frontend's own
//! `Quickshell.Io.Socket`, staying open to receive a live `ServerPush`
//! stream) -- see `DaemonServer::run`'s per-connection task.

use std::os::unix::net::UnixStream as StdUnixStream;
use std::path::PathBuf;
use std::io::Write;

use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;
use tokio::sync::broadcast;

/// Client -> daemon. `#[serde(tag = "cmd")]` gives each variant a flat
/// `{"cmd": "wifi_toggle"}`-shaped JSON object (no nested "content" key),
/// the simplest shape for a QML `SplitParser` line to build by hand.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum ClientCommand {
    Show,
    Hide,
    Toggle {
        #[serde(default)]
        position: Option<String>,
        /// One of "wifi"/"bluetooth"/"ethernet" (see app/mod.rs's
        /// activate_tab).
        #[serde(default)]
        tab: Option<String>,
    },
    ReloadTheme,
    ReloadConfig,
    Quit,
    // ---- home page (QML frontend, first slice -- see the project plan) ----
    WifiToggle,
    BtToggle,
    NightModeToggle,
    Screenshot,
    /// Re-reads the current state from NetworkManager/BlueZ and
    /// re-broadcasts it -- fixes the QML frontend's cached state going
    /// stale. The GTK app never had this problem: its own
    /// `ClientCommand::Show` already calls `trigger_refresh` on every
    /// open. QML has no equivalent "just became visible" moment it tells
    /// the daemon about, and reusing `Show` outright would pop the real
    /// GTK window on screen as a side effect -- so this is `Show`'s own
    /// refresh half, on its own, safe to call as often as needed
    /// (BaliseState.qml polls it on an interval while its drawer is
    /// open, see that file's own header).
    ///
    /// Covers BOTH halves of that state: the radio power flags (stale
    /// when a radio is toggled from outside Balise -- a hardware rfkill
    /// key, GNOME quick settings, another app) AND the access-point /
    /// wired-profile / bluetooth-device lists the QML home page reads its
    /// hero card and tile subtitles from. It shipped as the power flags
    /// alone, which left that home page showing whatever a previous visit
    /// to a section list had cached, or nothing at all -- see the handler
    /// in app/mod.rs for the full story. Still no scanning: every read
    /// here is a cached one.
    RefreshState,
    // ---- section lists (QML frontend, second slice) -- scan/connect/
    // disconnect. Bluetooth pairing is still out (it needs the BlueZ
    // agent bridged to QML, a separate pass); WiFi credentials are in,
    // see `WifiConnect`.
    WifiScan,
    /// `credentials` absent (or all-empty) keeps the original meaning:
    /// join an open network, or reactivate a saved profile with the
    /// secret NM already holds. Present, it is what the user just typed
    /// into the detail page's form -- a passphrase, or a username +
    /// password + EAP method for an enterprise network like eduroam --
    /// and it is written into the profile before activation (see
    /// `NetworkManager::connect`).
    ///
    /// `security` rides along rather than being re-read daemon-side
    /// because the frontend already has it (it renders the form off the
    /// same value) and because a saved-but-out-of-range network has no
    /// scanned AP left to read the flags from. Absent/unrecognised falls
    /// back to WPA2-PSK, which is what the old code assumed for
    /// everything.
    WifiConnect {
        ssid: String,
        #[serde(default)]
        security: Option<String>,
        #[serde(default)]
        credentials: Option<crate::dbus::WifiCredentials>,
    },
    WifiDisconnect {
        ssid: String,
    },
    BtScan,
    BtConnect {
        path: String,
    },
    BtDisconnect {
        path: String,
    },
    EthConnect {
        connection_path: String,
        device_path: String,
    },
    EthDisconnect {
        device_path: String,
    },
    /// Ethernet has no scan (wired_profiles() is a plain, instant
    /// enumeration, not a slow radio scan) but still needs an explicit
    /// read to populate the QML section list on first open -- unlike
    /// WifiScan/BtScan there's no NM/BlueZ-side action to kick off first,
    /// just the same wired_profiles() call EthConnect/EthDisconnect
    /// already re-run after they change something.
    EthList,
    // ---- detail page (QML frontend, third slice) -- reachable by
    // tapping a row (outside its Connect/Disconnect pill), matching the
    // GTK app's own gear-button destination (ui/detail.rs). Read/toggle/
    // forget for an ALREADY paired/saved endpoint only -- no pairing
    // here (needs the BlueZ agent bridged to QML, a separate pass, see
    // the project plan).
    /// Only WiFi needs an explicit fetch: `AccessPoint` (already in the
    /// QML frontend's own list) plus this gives the full `WifiDetails`
    /// half detail.rs's build_wifi wants. Bluetooth/Ethernet's detail
    /// pages read entirely off their own list row -- no extra round trip.
    WifiDetail {
        ssid: String,
    },
    WifiForget {
        settings_path: String,
    },
    /// `ssid` alongside `settings_path` (NM's `set_autoconnect` itself
    /// only needs the latter) purely so the daemon can refetch and
    /// re-push `WifiDetail` afterward without QML having to ask twice.
    WifiAutoconnect {
        ssid: String,
        settings_path: String,
        autoconnect: bool,
    },
    BtForget {
        path: String,
    },
    BtTrust {
        path: String,
        trusted: bool,
    },
    /// Reuses the same `set_autoconnect` NM call WifiAutoconnect does --
    /// it operates on a generic connection settings path, not a
    /// WiFi-specific one, so it works for a wired profile just as well.
    EthAutoconnect {
        connection_path: String,
        autoconnect: bool,
    },
}

/// Daemon -> every connected client (broadcast, not a per-request reply --
/// see `DaemonServer::run`). Only the home page's own slice of state for
/// now; more fields land here as later steps (wifi/bluetooth/ethernet
/// lists, bt-agent prompts) are built, additively.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerPush {
    State {
        wifi: RadioState,
        bluetooth: RadioState,
        night_mode: NightModeState,
    },
    // Separate pushes, not folded into State -- a list shouldn't get
    // re-serialized and re-broadcast every time an UNRELATED radio
    // toggles. Pushed only when that specific list actually changes
    // (same granularity AppEvent::ScanResult/BtScanResult/WiredResult
    // already have -- see app/mod.rs).
    WifiList {
        access_points: Vec<crate::dbus::AccessPoint>,
    },
    BluetoothList {
        devices: Vec<crate::dbus::BluetoothDevice>,
    },
    WiredList {
        profiles: Vec<crate::dbus::WiredProfile>,
    },
    /// The WiFi detail page's own extra fetch (see `ClientCommand::
    /// WifiDetail`'s doc comment) -- Bluetooth/Ethernet need no
    /// equivalent, their detail pages read straight off their own list
    /// row.
    WifiDetail {
        details: crate::dbus::WifiDetails,
    },
    /// How a `WifiConnect` ended. Only meaningful once credentials could
    /// be typed: before that, a failed connect had nowhere to be reported
    /// (the GTK app has its own error label, the QML frontend just watched
    /// the list and eventually noticed nothing had changed). A password
    /// form has to say "that password was rejected" and say it in the
    /// place the password was typed, so the outcome is pushed explicitly
    /// rather than inferred.
    ///
    /// `error` is empty when `ok` -- it carries the daemon's own message
    /// otherwise ("Authentication failed -- check the credentials",
    /// "Connection timeout", ...), rendered verbatim under the form.
    WifiConnectResult {
        ssid: String,
        ok: bool,
        error: String,
    },
}

#[derive(Debug, Clone, Copy, Serialize)]
pub struct RadioState {
    pub enabled: bool,
}

#[derive(Debug, Clone, Copy, Serialize)]
pub struct NightModeState {
    pub active: bool,
}

impl ServerPush {
    pub fn to_line(&self) -> String {
        // Only fails on a type that can't be represented in JSON at all
        // (NaN floats, non-string map keys) -- none of which appear
        // anywhere in this enum, so unwrap_or_default (an empty line the
        // reader on the other end will just fail to parse and skip) is
        // safe rather than a real error path to plumb through.
        serde_json::to_string(self).unwrap_or_default()
    }
}

pub struct DaemonServer {
    listener: Option<UnixListener>,
    path: PathBuf,
    tx: broadcast::Sender<String>,
}

impl DaemonServer {
    pub async fn new() -> Result<Self, std::io::Error> {
        let socket_path = crate::paths::socket_path();

        if socket_path.exists() {
            if StdUnixStream::connect(&socket_path).is_ok() {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::AddrInUse,
                    "Daemon is already running",
                ));
            }
            let _ = std::fs::remove_file(&socket_path);
        }

        let listener = UnixListener::bind(&socket_path)?;
        // 32 is generous for how few state changes happen per second
        // (radio toggles, scan results) -- a slow/stalled subscriber just
        // drops the oldest queued pushes (broadcast::error::RecvError::
        // Lagged) rather than blocking every other connection; the next
        // push still carries the FULL state, so a dropped one is never
        // load-bearing.
        let (tx, _rx) = broadcast::channel(32);

        Ok(Self {
            listener: Some(listener),
            path: socket_path,
            tx,
        })
    }

    /// A clone of the broadcast sender, to be handed to whatever owns the
    /// app's actual state (app/mod.rs's AppEvent loop) so it can push a
    /// fresh `ServerPush` after every state-changing event -- taken
    /// BEFORE `run()` consumes `self`.
    pub fn broadcaster(&self) -> broadcast::Sender<String> {
        self.tx.clone()
    }

    /// Spawns a dedicated OS thread with its own single-threaded tokio
    /// runtime for the accept loop, so it can never be starved by the GTK
    /// main loop sharing the process. `_server_guard` keeps `self` (and
    /// therefore its `Drop` unlinking the socket) alive for as long as
    /// this thread runs.
    ///
    /// Each accepted connection gets its own task looping on
    /// `tokio::select!` between two independent, unordered event sources
    /// on the same socket: the next line the client sends (a command),
    /// and the next broadcast push (state changed elsewhere). Both read
    /// and write happen in that one task, so there's no cross-task
    /// synchronization needed on the write half -- the loop ending (on
    /// EOF/error) drops both stream halves and this connection's
    /// broadcast subscription together, no separate cleanup signal
    /// needed.
    pub fn run<F>(mut self, callback: F)
    where
        F: Fn(ClientCommand) + Send + Sync + 'static,
    {
        if let Some(listener) = self.listener.take() {
            let tx = self.tx.clone();
            let callback = std::sync::Arc::new(callback);
            std::thread::spawn(move || {
                let rt = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .unwrap();

                let _server_guard = self;

                rt.block_on(async move {
                    loop {
                        match listener.accept().await {
                            Ok((stream, _)) => {
                                let callback = callback.clone();
                                let mut push_rx = tx.subscribe();
                                tokio::spawn(async move {
                                    let (read_half, mut write_half) = stream.into_split();
                                    let mut lines = BufReader::new(read_half).lines();

                                    loop {
                                        tokio::select! {
                                            line = lines.next_line() => {
                                                match line {
                                                    Ok(Some(text)) => {
                                                        let reply = match serde_json::from_str::<ClientCommand>(&text) {
                                                            Ok(cmd) => {
                                                                callback(cmd);
                                                                "{\"ok\":true}\n"
                                                            }
                                                            Err(_) => "{\"ok\":false}\n",
                                                        };
                                                        if write_half.write_all(reply.as_bytes()).await.is_err() {
                                                            break;
                                                        }
                                                    }
                                                    // EOF (client disconnected) or a read error --
                                                    // either way this connection is done.
                                                    Ok(None) | Err(_) => break,
                                                }
                                            }
                                            push = push_rx.recv() => {
                                                match push {
                                                    Ok(line) => {
                                                        if write_half.write_all(line.as_bytes()).await.is_err()
                                                            || write_half.write_all(b"\n").await.is_err()
                                                        {
                                                            break;
                                                        }
                                                    }
                                                    // Lagged: this connection missed some pushes
                                                    // under load -- not fatal, the next successful
                                                    // one still carries full state. Closed: the
                                                    // whole DaemonServer is gone (process exiting).
                                                    Err(broadcast::error::RecvError::Lagged(_)) => {}
                                                    Err(broadcast::error::RecvError::Closed) => break,
                                                }
                                            }
                                        }
                                    }
                                });
                            }
                            Err(e) => {
                                eprintln!("balise: socket accept error: {}", e);
                            }
                        }
                    }
                });
            });
        }
    }
}

impl Drop for DaemonServer {
    fn drop(&mut self) {
        if self.path.exists() {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}

pub struct DaemonClient;

impl DaemonClient {
    /// Sends one command and reads back the daemon's one-line ack --
    /// unchanged connect-send-read-disconnect shape for the short-lived
    /// CLI callers (`balise toggle`/`show`/`hide`/...). Any `ServerPush`
    /// lines the daemon might also send on this same connection before
    /// the ack (a race is possible now that pushes and acks share one
    /// socket) are skipped: this reads lines until it sees one that
    /// parses as an ack object, since a CLI caller only ever cares about
    /// its own command's result, never about state pushes.
    pub fn send_command(cmd: ClientCommand) -> Result<String, std::io::Error> {
        let socket_path = crate::paths::socket_path();

        let mut stream = StdUnixStream::connect(&socket_path)?;
        stream.set_read_timeout(Some(std::time::Duration::from_secs(2)))?;
        stream.set_write_timeout(Some(std::time::Duration::from_secs(2)))?;

        let mut line = serde_json::to_string(&cmd).unwrap_or_default();
        line.push('\n');
        stream.write_all(line.as_bytes())?;
        stream.flush()?;

        // Small bounded read loop rather than a single read() -- a
        // ServerPush broadcast landing between our write and the
        // daemon's own ack reply is now possible (both share the same
        // connection), and this is the CLI's one place to shrug it off.
        let mut reader = std::io::BufReader::new(&stream);
        for _ in 0..8 {
            let mut buf = String::new();
            use std::io::BufRead;
            if reader.read_line(&mut buf)? == 0 {
                break;
            }
            if buf.contains("\"ok\"") {
                return Ok(buf.trim().to_string());
            }
        }
        Ok(String::new())
    }

    pub fn is_daemon_running() -> bool {
        let socket_path = crate::paths::socket_path();

        if !socket_path.exists() {
            return false;
        }

        match StdUnixStream::connect(&socket_path) {
            Ok(_) => true,
            Err(_) => {
                let _ = std::fs::remove_file(&socket_path);
                false
            }
        }
    }
}
