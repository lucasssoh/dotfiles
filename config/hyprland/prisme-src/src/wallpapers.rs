//! Découverte des fichiers wallpapers sur disque : résolution des dossiers
//! source et listing filtré/trié, sans dépendance à l'état de l'UI.

use std::path::{Path, PathBuf};

/// Extensions reconnues -- mêmes que scripts/set_wallpaper.sh (jpg/jpeg/png/webp,
/// insensible à la casse).
const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp"];

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

/// Fichier de config utilisateur listant le dossier des wallpapers
/// originaux -- symlinké par install.sh depuis
/// config/hyprland/prisme/wallpapers.conf, comme keymap.conf/style.css.
fn config_path() -> PathBuf {
    home().join(".config/prisme/wallpapers.conf")
}

/// Lit la première ligne non vide et non commentée (#) de wallpapers.conf
/// -- un chemin absolu, ou préfixé par `~/`. Fichier absent/illisible/vide
/// -> None, originals_dir() retombe alors sur le défaut ci-dessous. Même
/// fichier lu par les scripts bash historiques (wallpaper-cache-
/// watcher.sh, restore_wallpaper.sh, wallpaper-slideshow.sh,
/// set_wallpaper.sh) pour rester agnostiques du même dossier configuré.
fn configured_dir() -> Option<PathBuf> {
    let content = std::fs::read_to_string(config_path()).ok()?;
    let line = content
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty() && !l.starts_with('#'))?;
    Some(match line.strip_prefix("~/") {
        Some(rest) => home().join(rest),
        None => PathBuf::from(line),
    })
}

/// Dossier "Original" -- configurable via wallpapers.conf (cf.
/// configured_dir()), sinon même chemin par défaut que WALL_DIR dans
/// set_wallpaper.sh (symlinké vers le dépôt par set_wallpapers.sh).
pub fn originals_dir() -> PathBuf {
    configured_dir().unwrap_or_else(|| home().join("Images/Wallpapers"))
}

/// Une image wallpaper trouvée sur disque : chemin complet et nom de
/// fichier (affiché dans l'UI, écrit tel quel dans la playlist JSON).
#[derive(Clone, Debug)]
pub struct Wallpaper {
    pub path: PathBuf,
    pub name: String,
}

fn has_known_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// Liste les wallpapers d'un dossier, triés par nom -- même tri que
/// `for img in "$SRC_DIR"/*` dans set_wallpaper.sh (ordre alphabétique du
/// glob shell).
pub fn scan(dir: &Path) -> Vec<Wallpaper> {
    let mut entries: Vec<Wallpaper> = match std::fs::read_dir(dir) {
        Ok(read_dir) => read_dir
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_file() && has_known_extension(p))
            .map(|path| {
                let name = path
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_default();
                Wallpaper { path, name }
            })
            .collect(),
        Err(_) => Vec::new(),
    };
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    entries
}
