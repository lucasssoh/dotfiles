//! Applies the chosen wallpaper: writes state to `wallpaper-playlist.json`
//! and hands the wallpaper to hypr/scripts/wallpaper-set (static) or
//! wallpaper-slideshow.service (dynamic), in the format restore_wallpaper.sh
//! and wallpaper-slideshow.sh read.
//! Prisme is a replacement UI, not a new backend.

use serde_json::json;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Same file, same path as WALL_DIR/CACHE_DIR + PLAYLIST_FILE in
/// scripts/set_wallpaper.sh -- Prisme is a replacement UI for that script,
/// not a new backend: restore_wallpaper.sh, wallpaper-slideshow.service
/// and slideshow-fullscreen-guard.sh keep reading this same file
/// unmodified (except for the `source` field, see below).
fn playlist_path() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(".config/hypr/wallpaper-playlist.json")
}

/// hypr/scripts/wallpaper-set: puts a wallpaper on every screen, each one
/// getting the version fitted to its own resolution from the cache
/// (~/.cache/filtered_wallpapers/<W>x<H>/), or the original while that is
/// not ready. The one place that talks to awww for a wallpaper -- this
/// module, the slideshow and the login restore all call it -- and it also
/// refreshes the bar's tint.
fn wallpaper_set() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(".config/hypr/scripts/wallpaper-set")
}

/// Reproduces `if ! pidof awww-daemon; then awww-daemon & sleep 0.5; fi`
/// from set_wallpaper.sh -- called synchronously right before applying,
/// never the path taken once the daemon is already running (the common
/// case).
fn ensure_awww_daemon() {
    let running = Command::new("pidof")
        .arg("awww-daemon")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !running {
        let _ = Command::new("awww-daemon")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        std::thread::sleep(std::time::Duration::from_millis(500));
    }
}

fn read_playlist() -> Option<serde_json::Value> {
    let content = std::fs::read_to_string(playlist_path()).ok()?;
    serde_json::from_str(&content).ok()
}

fn write_playlist(value: &serde_json::Value) {
    let path = playlist_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Err(e) = std::fs::write(&path, value.to_string()) {
        eprintln!("[prisme] failed to write {path:?}: {e}");
    }
}

/// Name of the last wallpaper applied in Static mode -- read by main.rs to
/// start the carousel focused on it instead of the first card. An extra
/// `last_static` field in the playlist (ignored by
/// restore_wallpaper.sh/wallpaper-slideshow.sh, which only read the fields
/// they know about) -- not a separate file, to keep just one piece of
/// state to maintain. Falls back to `walls[0]` if `last_static` is absent
/// but the playlist is already in Static mode -- the case for playlists
/// written before this field was added (including by the old bash
/// script).
pub fn last_static() -> Option<String> {
    let playlist = read_playlist()?;
    if let Some(name) = playlist.get("last_static").and_then(|v| v.as_str()) {
        return Some(name.to_string());
    }
    if playlist.get("mode").and_then(|v| v.as_str()) == Some("static") {
        if let Some(name) = playlist
            .get("walls")
            .and_then(|v| v.as_array())
            .and_then(|a| a.first())
            .and_then(|v| v.as_str())
        {
            return Some(name.to_string());
        }
    }
    None
}

/// "Static" mode: stops the slideshow, writes the playlist, puts the
/// wallpaper on every screen. `source` in the playlist is the folder of the
/// originals: which fitted version each screen gets is wallpaper-set's
/// business, so the playlist stays valid whatever screens come and go.
pub fn apply_static(source_dir: &Path, wallpaper_path: &Path, wallpaper_name: &str) {
    ensure_awww_daemon();

    let _ = Command::new("systemctl")
        .args(["--user", "stop", "wallpaper-slideshow.service"])
        .status();

    write_playlist(&json!({
        "mode": "static",
        "source": source_dir.to_string_lossy(),
        "walls": [wallpaper_name],
        "last_static": wallpaper_name,
    }));

    let _ = Command::new(wallpaper_set()).arg(wallpaper_path).status();
}

/// "Dynamic" (slideshow) mode -- equivalent of step 5: writes the
/// playlist then (re)starts wallpaper-slideshow.service, which re-reads it
/// every cycle. Preserves `last_static` from the previous playlist (see
/// `last_static()`): switching to Dynamic must not forget the last Static
/// choice.
pub fn apply_dynamic(source_dir: &Path, duration: u32, walls: &[String]) {
    ensure_awww_daemon();

    // The originals' folder, as for Static: wallpaper-slideshow.sh hands
    // each "$SOURCE/$img" to wallpaper-set, which picks each screen's
    // fitted version.
    let mut value = json!({
        "mode": "dynamic",
        "duration": duration,
        "source": source_dir.to_string_lossy(),
        "walls": walls,
    });
    if let Some(last_static) = last_static() {
        value["last_static"] = json!(last_static);
    }
    write_playlist(&value);

    let _ = Command::new("systemctl")
        .args(["--user", "restart", "wallpaper-slideshow.service"])
        .status();
}
