//! Single source of truth for every path Balise touches on disk: the
//! runtime config directory and the daemon's IPC socket. Orbit duplicates
//! this logic three times over (config.rs, theme.rs, app/daemon.rs); one
//! module here instead.

use std::path::PathBuf;

/// Runtime config directory, normally `~/.config/balise` (symlinked by
/// install.sh from config/hyprland/balise/, same convention as
/// prisme/roue) -- overridable via `BALISE_CONFIG_DIR` so the crate
/// is developable straight out of the repo without touching install.sh's
/// `modules=(...)` symlink array before the Phase 5 cutover (see the
/// project plan). Only intended for development; the real machine setup
/// should rely on the symlink, not the env var.
pub fn config_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("BALISE_CONFIG_DIR") {
        return PathBuf::from(dir);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".config").join("balise")
}

pub fn config_file() -> PathBuf {
    config_dir().join("config.toml")
}

pub fn style_file() -> PathBuf {
    config_dir().join("style.css")
}

/// The daemon's Unix domain socket. The name was deliberately kept
/// distinct from Orbit's `orbit.sock` while the two ran side by side
/// during Balise's build-out; Orbit has since been removed, but the name
/// stays as-is -- renaming it now would only break any running daemon
/// mid-upgrade for no gain.
const SOCKET_NAME: &str = "balise.sock";

pub fn socket_path() -> PathBuf {
    let path = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let user = std::env::var("USER").unwrap_or_else(|_| "user".to_string());
            PathBuf::from(format!("/tmp/balise-{}", user))
        })
        .join(SOCKET_NAME);

    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    path
}
