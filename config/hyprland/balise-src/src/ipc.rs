//! Unix-socket daemon/client, adapted from orbit-vendor/src/app/daemon.rs.
//! Balise needs to persist across opens like Orbit (unlike Prisme/Roue's
//! one-shot-and-exit model), so it needs the same daemon shape -- with its
//! own socket (see crate::paths) so the two coexist during the parallel
//! build-out.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream as StdUnixStream;
use std::path::PathBuf;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;

#[derive(Debug, Clone)]
pub enum DaemonCommand {
    Show,
    Hide,
    /// (position override, tab). Tab is one of "wifi"/"bluetooth"/
    /// "ethernet" (see app/mod.rs's activate_tab).
    Toggle(Option<String>, Option<String>),
    ReloadTheme,
    ReloadConfig,
    Quit,
}

impl DaemonCommand {
    fn from_bytes(bytes: &[u8]) -> Option<Self> {
        let s = String::from_utf8_lossy(bytes);
        if s.starts_with("show") {
            Some(Self::Show)
        } else if s.starts_with("hide") {
            Some(Self::Hide)
        } else if s.starts_with("reload-theme") {
            Some(Self::ReloadTheme)
        } else if s.starts_with("reload-config") {
            Some(Self::ReloadConfig)
        } else if s.starts_with("toggle") {
            let parts: Vec<&str> = s.split(':').collect();
            let pos = if parts.len() > 1 && !parts[1].is_empty() {
                Some(parts[1].to_string())
            } else {
                None
            };
            let tab = if parts.len() > 2 && !parts[2].is_empty() {
                Some(parts[2].to_string())
            } else {
                None
            };
            Some(Self::Toggle(pos, tab))
        } else if s.starts_with("quit") {
            Some(Self::Quit)
        } else {
            None
        }
    }

    fn to_wire(&self) -> String {
        match self {
            Self::Show => "show".to_string(),
            Self::Hide => "hide".to_string(),
            Self::ReloadTheme => "reload-theme".to_string(),
            Self::ReloadConfig => "reload-config".to_string(),
            Self::Toggle(pos, tab) => {
                let p = pos.as_deref().unwrap_or("");
                let t = tab.as_deref().unwrap_or("");
                format!("toggle:{}:{}", p, t)
            }
            Self::Quit => "quit".to_string(),
        }
    }
}

pub struct DaemonServer {
    listener: Option<UnixListener>,
    path: PathBuf,
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

        Ok(Self {
            listener: Some(listener),
            path: socket_path,
        })
    }

    /// Spawns a dedicated OS thread with its own single-threaded tokio
    /// runtime for the accept loop, so it can never be starved by the GTK
    /// main loop sharing the process. `_server_guard` keeps `self` (and
    /// therefore its `Drop` unlinking the socket) alive for as long as
    /// this thread runs.
    pub fn run<F>(mut self, callback: F)
    where
        F: Fn(DaemonCommand) + Send + 'static,
    {
        if let Some(listener) = self.listener.take() {
            std::thread::spawn(move || {
                let rt = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .unwrap();

                let _server_guard = self;

                rt.block_on(async {
                    loop {
                        match listener.accept().await {
                            Ok((mut stream, _)) => {
                                let mut buf = [0u8; 64];
                                if let Ok(n) = stream.read(&mut buf).await {
                                    if n > 0 {
                                        if let Some(cmd) = DaemonCommand::from_bytes(&buf[..n]) {
                                            callback(cmd);
                                            let _ = stream.write_all(b"ok").await;
                                            let _ = stream.flush().await;
                                        } else {
                                            let _ = stream.write_all(b"unknown").await;
                                        }
                                    }
                                }
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
    pub fn send_command(cmd: DaemonCommand) -> Result<String, std::io::Error> {
        let socket_path = crate::paths::socket_path();

        let mut stream = StdUnixStream::connect(&socket_path)?;
        stream.set_read_timeout(Some(std::time::Duration::from_secs(2)))?;
        stream.set_write_timeout(Some(std::time::Duration::from_secs(2)))?;

        stream.write_all(cmd.to_wire().as_bytes())?;
        stream.flush()?;

        let mut buf = [0u8; 32];
        let n = stream.read(&mut buf)?;
        Ok(String::from_utf8_lossy(&buf[..n]).to_string())
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
