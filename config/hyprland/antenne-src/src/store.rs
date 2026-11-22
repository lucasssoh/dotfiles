//! Where Antenne keeps things, and the two small JSON files it owns.
//!
//! settings.json (~/.config/antenne): what the user chooses -- countries,
//! their own playlists, how often channels are checked, logos on or off.
//! state.json (~/.local/state/antenne): what Antenne remembers on its own --
//! the last channel and the favourites.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| "/tmp".into())
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var)
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| home().join(fallback))
}

pub fn config_dir() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config").join("antenne")
}
pub fn cache_dir() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("antenne")
}
pub fn state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("antenne")
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default)]
pub struct Settings {
    /// iptv-org country codes, lowercase ("fr", "be"...).
    pub countries: Vec<String>,
    /// The user's own M3U playlists: URLs or absolute paths.
    pub playlists: Vec<String>,
    pub check_every_hours: u64,
    /// Channel logos in the guide (otherwise initials).
    #[serde(alias = "previews")]
    pub logos: bool,
    /// Drop to the lowest quality when the connection keeps stalling.
    pub lower_on_weak: bool,
    /// Start on the channel watched last (else the first).
    pub open_last: bool,
    /// At the end of an episode, the next one after 5 s.
    pub autonext: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { countries: vec!["fr".into()], playlists: vec![], check_every_hours: 6, logos: true, lower_on_weak: true, open_last: true, autonext: true }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct State {
    /// Where each episode was left, by its link.
    pub progress: std::collections::HashMap<String, Progress>,
    /// Shows taken out of Continue watching (by their link), until one of
    /// their episodes plays again.
    pub hidden_continue: Vec<String>,
    pub last: Option<String>,
    pub favourites: Vec<String>,
    pub reminders: Vec<Reminder>,
}

/// Where an episode was left.
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct Progress {
    /// Seconds in, and the whole length.
    pub pos: f64,
    pub dur: f64,
    pub done: bool,
    /// When it was last watched.
    pub at: u64,
}

/// A programme to be told about when it starts.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Reminder {
    pub key: String,
    pub start: i64,
    pub stop: i64,
    pub title: String,
}

pub fn load<T: for<'de> Deserialize<'de> + Default>(path: &PathBuf) -> T {
    std::fs::read(path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

/// Written to a temporary file then renamed, so a crash mid-write never
/// leaves half a JSON file behind.
pub fn save<T: Serialize>(path: &PathBuf, v: &T) {
    if let Some(d) = path.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    let tmp = path.with_extension("tmp");
    if let Ok(b) = serde_json::to_vec_pretty(v) {
        if std::fs::write(&tmp, b).is_ok() {
            let _ = std::fs::rename(&tmp, path);
        }
    }
}

pub fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}
pub fn state_path() -> PathBuf {
    state_dir().join("state.json")
}
pub fn health_path() -> PathBuf {
    state_dir().join("health.json")
}

pub fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}
