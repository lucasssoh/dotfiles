use serde_json::json;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Même fichier, même chemin que WALL_DIR/CACHE_DIR + PLAYLIST_FILE dans
/// scripts/set_wallpaper.sh -- Prisme est une UI de remplacement pour ce
/// script, pas un nouveau backend : restore_wallpaper.sh, wallpaper-
/// slideshow.service et slideshow-fullscreen-guard.sh continuent de lire ce
/// même fichier sans modification (à part le champ `source`, cf. plus bas).
fn playlist_path() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME non défini");
    PathBuf::from(home).join(".config/hypr/wallpaper-playlist.json")
}

/// Reproduit `if ! pidof awww-daemon; then awww-daemon & sleep 0.5; fi` de
/// set_wallpaper.sh -- appelé en synchrone juste avant d'appliquer, ce n'est
/// jamais le chemin emprunté une fois le daemon déjà démarré (cas courant).
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

fn write_playlist(value: &serde_json::Value) {
    let path = playlist_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Err(e) = std::fs::write(&path, value.to_string()) {
        eprintln!("[prisme] échec d'écriture de {path:?}: {e}");
    }
}

/// Mode "Statique" -- équivalent de l'étape 21 de set_wallpaper.sh : stoppe
/// le diaporama, écrit la playlist, applique via awww avec la même
/// transition. `source_dir` est écrit dans la playlist (absent du format
/// historique du script bash -- cf. le patch correspondant dans
/// restore_wallpaper.sh) pour que la restauration au boot sache si le
/// wallpaper venait de la source "Original" ou "Filtré".
pub fn apply_static(source_dir: &Path, wallpaper_path: &Path, wallpaper_name: &str) {
    ensure_awww_daemon();

    let _ = Command::new("systemctl")
        .args(["--user", "stop", "wallpaper-slideshow.service"])
        .status();

    write_playlist(&json!({
        "mode": "static",
        "source": source_dir.to_string_lossy(),
        "walls": [wallpaper_name],
    }));

    let _ = Command::new("awww")
        .arg("img")
        .arg(wallpaper_path)
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

/// Mode "Diaporama" -- équivalent de l'étape 5 : écrit la playlist puis
/// (re)démarre wallpaper-slideshow.service, qui la relit à chaque cycle.
pub fn apply_dynamic(source_dir: &Path, duration: u32, walls: &[String]) {
    ensure_awww_daemon();

    write_playlist(&json!({
        "mode": "dynamic",
        "duration": duration,
        "source": source_dir.to_string_lossy(),
        "walls": walls,
    }));

    let _ = Command::new("systemctl")
        .args(["--user", "restart", "wallpaper-slideshow.service"])
        .status();
}
