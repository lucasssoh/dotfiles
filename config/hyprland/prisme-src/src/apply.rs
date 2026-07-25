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
        eprintln!("[prisme] échec d'écriture de {path:?}: {e}");
    }
}

/// Nom du dernier fond appliqué en mode Statique -- lu par main.rs pour
/// démarrer le carrousel focus dessus plutôt que sur la première carte.
/// Un champ `last_static` supplémentaire dans la playlist (ignoré par
/// restore_wallpaper.sh/wallpaper-slideshow.sh, qui ne lisent que les
/// champs qu'ils connaissent) -- pas un fichier séparé, pour n'avoir qu'un
/// seul état à tenir à jour. Repli sur `walls[0]` si `last_static` est
/// absent mais que la playlist est déjà en mode Statique -- cas des
/// playlists écrites avant l'ajout de ce champ (y compris par l'ancien
/// script bash).
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

/// Mode "Statique" -- équivalent de l'étape 21 de set_wallpaper.sh : stoppe
/// le diaporama, écrit la playlist, applique via awww avec la même
/// transition. `source_dir` est écrit dans la playlist (absent du format
/// historique du script bash -- cf. le patch correspondant dans
/// restore_wallpaper.sh) pour que la restauration au boot sache d'où
/// rejouer le wallpaper.
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
/// Préserve `last_static` de la playlist précédente (cf. `last_static()`) :
/// passer en Diaporama ne doit pas faire oublier le dernier choix Statique.
pub fn apply_dynamic(source_dir: &Path, duration: u32, walls: &[String]) {
    ensure_awww_daemon();

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
