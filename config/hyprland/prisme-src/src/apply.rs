//! Applies the chosen wallpaper: writes state to `wallpaper-playlist.json`
//! and drives awww/systemd, staying compatible with the format read by the
//! historical bash scripts (restore_wallpaper.sh, wallpaper-slideshow.sh).
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

/// Cache of "filtered" variants (cropped/extended to the active screen's
/// aspect ratio) produced by scripts/wallpaper-filter-one.sh, continuously
/// fed by wallpaper-cache-watcher.sh. Same filenames as the originals
/// (resolved by plain basename). Never used for browsing/display
/// (main.rs/thumbs.rs keep reading the originals -- the user needs to
/// recognize their own photos in the carousel), only when actually
/// applying a wallpaper to the desktop (see apply_static/apply_dynamic).
fn filtered_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(".cache/filtered_wallpapers")
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

/// "Static" mode -- equivalent of step 21 in set_wallpaper.sh: stops the
/// slideshow, writes the playlist, applies via awww with the same
/// transition. `source` is written into the playlist (absent from the
/// historical bash script's format -- see the corresponding patch in
/// restore_wallpaper.sh) so boot-time restoration knows where to replay
/// the wallpaper from -- the directory actually applied (filtered cache
/// if available, originals otherwise, see filtered_dir()), not always
/// `source_dir` as received.
pub fn apply_static(source_dir: &Path, wallpaper_path: &Path, wallpaper_name: &str) {
    ensure_awww_daemon();

    let _ = Command::new("systemctl")
        .args(["--user", "stop", "wallpaper-slideshow.service"])
        .status();

    // Filtered variant if the cache has already produced it (normal case:
    // the watcher runs continuously), otherwise the original as-is -- an
    // image added two seconds ago, or whose extension slips past the
    // filter (case-sensitive regex), must not end up with no wallpaper at
    // all.
    let filtered = filtered_dir();
    let cached = filtered.join(wallpaper_name);
    let (applied_dir, applied_path) = if cached.is_file() {
        (filtered, cached)
    } else {
        (source_dir.to_path_buf(), wallpaper_path.to_path_buf())
    };

    write_playlist(&json!({
        "mode": "static",
        "source": applied_dir.to_string_lossy(),
        "walls": [wallpaper_name],
        "last_static": wallpaper_name,
    }));

    let _ = Command::new("awww")
        .arg("img")
        .arg(&applied_path)
        .args([
            "--transition-type",
            "wipe",
            "--transition-angle",
            "30",
            "--transition-fps",
            "45",
            "--transition-duration",
            "1",
        ])
        .status();
}

/// "Dynamic" (slideshow) mode -- equivalent of step 5: writes the
/// playlist then (re)starts wallpaper-slideshow.service, which re-reads it
/// every cycle. Preserves `last_static` from the previous playlist (see
/// `last_static()`): switching to Dynamic must not forget the last Static
/// choice.
pub fn apply_dynamic(source_dir: &Path, duration: u32, walls: &[String]) {
    ensure_awww_daemon();

    // Only one `source` for the whole playlist: wallpaper-slideshow.sh
    // applies "$SOURCE/$img" for each name, it can't mix two directories.
    // Only switches to the cache if ALL images in the selection are
    // already there; a single one missing and the whole batch stays on
    // the originals, rather than a slideshow that skips an image.
    let filtered = filtered_dir();
    let all_filtered = !walls.is_empty() && walls.iter().all(|name| filtered.join(name).is_file());
    let playlist_source = if all_filtered {
        filtered
    } else {
        source_dir.to_path_buf()
    };

    let mut value = json!({
        "mode": "dynamic",
        "duration": duration,
        "source": playlist_source.to_string_lossy(),
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
