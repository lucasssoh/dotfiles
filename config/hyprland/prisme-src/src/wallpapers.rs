use std::path::{Path, PathBuf};

/// Extensions reconnues -- mêmes que scripts/set_wallpaper.sh (jpg/jpeg/png/webp,
/// insensible à la casse).
const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp"];

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME non défini"))
}

/// Dossier "Original" -- même chemin que WALL_DIR dans set_wallpaper.sh
/// (symlinké vers le dépôt par set_wallpapers.sh).
pub fn originals_dir() -> PathBuf {
    home().join("Images/Wallpapers")
}

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
