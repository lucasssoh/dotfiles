//! Discovery of wallpaper files on disk: resolving the source directory
//! and a filtered/sorted listing, with no dependency on UI state.

use std::collections::HashMap;
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

/// A wallpaper as Prisme shows it: one card. `path`/`name` are the file the
/// playlist records; `dark` is the other half of a light/dark pair, if the
/// folder has one (see `scan`). wallpaper-set puts up whichever half the
/// colour scheme asks for, so the playlist only ever names the light file.
#[derive(Clone, Debug)]
pub struct Wallpaper {
    pub path: PathBuf,
    pub name: String,
    pub dark: Option<PathBuf>,
}

impl Wallpaper {
    /// Filename of the dark half, if this is a pair.
    pub fn dark_name(&self) -> Option<String> {
        self.dark.as_ref().and_then(|p| p.file_name()).map(|n| n.to_string_lossy().into_owned())
    }

    /// True if `name` is either file of this wallpaper -- a playlist written
    /// before pairs existed may name the dark one.
    pub fn answers_to(&self, name: &str) -> bool {
        self.name == name || self.dark_name().as_deref() == Some(name)
    }
}

fn has_known_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

fn stem(name: &str) -> &str {
    Path::new(name).file_stem().and_then(|s| s.to_str()).unwrap_or(name)
}

/// Lists a directory's wallpapers, sorted by name -- same sort as
/// `for img in "$SRC_DIR"/*` in set_wallpaper.sh (alphabetical shell glob
/// order). NAME.ext and NAME-dark.ext (any of the known extensions) make one
/// entry, the light file carrying the dark one; a NAME-dark.ext alone stays
/// an entry of its own. Same rule as wallpaper-set.
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
                Wallpaper { path, name, dark: None }
            })
            .collect(),
        Err(_) => Vec::new(),
    };
    entries.sort_by(|a, b| a.name.cmp(&b.name));

    // First file per stem, the one a pair attaches to.
    let mut by_stem: HashMap<String, usize> = HashMap::new();
    for (i, w) in entries.iter().enumerate() {
        by_stem.entry(stem(&w.name).to_string()).or_insert(i);
    }
    let mut paired = vec![false; entries.len()];
    for i in 0..entries.len() {
        let Some(base) = stem(&entries[i].name).strip_suffix("-dark") else {
            continue;
        };
        if let Some(&light) = by_stem.get(base) {
            if entries[light].dark.is_none() {
                entries[light].dark = Some(entries[i].path.clone());
                paired[i] = true;
            }
        }
    }
    let mut paired = paired.into_iter();
    entries.retain(|_| !paired.next().unwrap_or(false));
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(files: &[&str]) -> Vec<(String, Option<String>)> {
        let dir = std::env::temp_dir().join(format!("prisme-scan-{}-{}", std::process::id(), files.len()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        for f in files {
            std::fs::write(dir.join(f), b"").unwrap();
        }
        let out = scan(&dir).iter().map(|w| (w.name.clone(), w.dark_name())).collect();
        let _ = std::fs::remove_dir_all(&dir);
        out
    }

    #[test]
    fn pairs_by_name() {
        let got = names(&["fold.jxl", "fold-dark.jxl", "road.jpg", "nuit-dark.jpg", "morph.jpg", "morph-dark.png", "notes.txt"]);
        assert_eq!(
            got,
            vec![
                ("fold.jxl".into(), Some("fold-dark.jxl".into())),
                ("morph.jpg".into(), Some("morph-dark.png".into())),
                ("nuit-dark.jpg".into(), None),
                ("road.jpg".into(), None),
            ]
        );
    }
}
