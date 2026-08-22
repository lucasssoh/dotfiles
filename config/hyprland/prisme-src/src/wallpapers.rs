//! Discovery of wallpaper files on disk: resolving the source directory
//! and a filtered/sorted listing, with no dependency on UI state.

use std::path::{Path, PathBuf};

/// Recognized extensions -- same as scripts/set_wallpaper.sh
/// (jpg/jpeg/png/webp, case-insensitive), plus jxl (JPEG XL -- GNOME's
/// default wallpapers ship in that format; decoded by thumbs.rs/
/// wallpaper-filter.rs via jxl-oxide, the `image` crate has no native
/// support for it).
const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "jxl"];

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

/// User config file listing the original wallpapers directory --
/// symlinked by install.sh from config/hyprland/prisme/wallpapers.conf,
/// like keymap.conf/style.css.
fn config_path() -> PathBuf {
    home().join(".config/prisme/wallpapers.conf")
}

/// Reads the first non-empty, non-commented (#) line of wallpapers.conf --
/// an absolute path, or one prefixed with `~/`. File absent/unreadable/
/// empty -> None, originals_dir() then falls back to the default below.
/// Same file read by the historical bash scripts (wallpaper-cache-
/// watcher.sh, restore_wallpaper.sh, wallpaper-slideshow.sh,
/// set_wallpaper.sh) to stay agnostic of the same configured directory.
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

/// "Original" directory -- configurable via wallpapers.conf (see
/// configured_dir()), otherwise the same default path as WALL_DIR in
/// set_wallpaper.sh (symlinked to the repo by set_wallpapers.sh).
pub fn originals_dir() -> PathBuf {
    configured_dir().unwrap_or_else(|| home().join("Images/Wallpapers"))
}

/// A wallpaper image found on disk: full path and filename (shown in the
/// UI, written as-is into the JSON playlist).
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

/// Lists a directory's wallpapers, sorted by name -- same sort as
/// `for img in "$SRC_DIR"/*` in set_wallpaper.sh (alphabetical shell glob
/// order).
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
