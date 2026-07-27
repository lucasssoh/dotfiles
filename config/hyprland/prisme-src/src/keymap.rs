//! Prisme's configurable keyboard shortcuts: optional text file
//! (`~/.config/prisme/keymap.conf`) mapping action names to GDK keys, with
//! a built-in fallback if the file is absent.

use gtk4::gdk;
use std::collections::HashMap;

/// Actions triggerable from the keyboard -- the external file ONLY maps
/// onto these names (never directly onto a hardcoded key), so the rest of
/// the program never has to know a raw key name.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    Close,
    MoveLeft,
    MoveRight,
    Activate,
    ToggleMode,
    Select,
    Deselect,
}

/// Default config, hardcoded here rather than `include_str!`-ed from the
/// external file (config/hyprland/prisme/keymap.conf): the latter lives
/// OUTSIDE prisme-src/, which install.sh copies alone into
/// ~/.cache/prisme-build/ before `cargo build` -- a relative path there
/// resolves to nothing (same problem as the fallback CSS, see theme.rs).
/// The real file, editable without recompiling, stays
/// config/hyprland/prisme/keymap.conf (symlinked to ~/.config/prisme/ by
/// install.sh, in the same folder as style.css): this constant is only a
/// safety net for when that file is absent or unreadable.
const FALLBACK: &str = "\
close = Escape
move_left = Left, h, H
move_right = Right, l, L
activate = Return, KP_Enter, space
toggle_mode = Tab
select = Down, j, J
deselect = Up, k, K
";

/// Resolved GDK key -> action table, ready to query from the keyboard
/// event handler.
pub struct Keymap(HashMap<gdk::Key, Action>);

impl Keymap {
    /// Loads ~/.config/prisme/keymap.conf if it exists, otherwise the
    /// default config above. Reloaded on every launch (no Prisme daemon,
    /// editing the file is enough).
    pub fn load() -> Self {
        let content = user_path()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .unwrap_or_else(|| FALLBACK.to_string());
        Self(parse(&content))
    }

    /// Action associated with a key, if any.
    pub fn action(&self, key: gdk::Key) -> Option<Action> {
        self.0.get(&key).copied()
    }
}

/// Location of the user config file, symlinked by install.sh.
fn user_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/prisme/keymap.conf"))
}

/// Format: one line per action, `name = key1, key2, ...`. A `#` at the
/// start of a line (after whitespace) comments it out. Key names follow
/// the X11/GDK convention (`gdk_keyval_from_name` -- Escape, Return,
/// KP_Enter, Left, Right, Up, Down, Tab, space, h, H, ...), no homemade
/// lookup table to maintain. An invalid line or key is ignored (with a
/// message on stderr) rather than failing the whole file -- a typo
/// shouldn't cost the user every other key.
fn parse(content: &str) -> HashMap<gdk::Key, Action> {
    let mut map = HashMap::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((name, keys)) = line.split_once('=') else {
            continue;
        };
        let Some(action) = parse_action(name.trim()) else {
            eprintln!("[prisme] keymap.conf: unknown action '{}'", name.trim());
            continue;
        };
        for key_name in keys.split(',') {
            let key_name = key_name.trim();
            if key_name.is_empty() {
                continue;
            }
            match gdk::Key::from_name(key_name) {
                Some(key) => {
                    map.insert(key, action);
                }
                None => eprintln!("[prisme] keymap.conf: unknown key '{key_name}'"),
            }
        }
    }
    map
}

/// Converts a textual action name (left side of `=` in keymap.conf) into
/// an `Action` variant.
fn parse_action(name: &str) -> Option<Action> {
    Some(match name {
        "close" => Action::Close,
        "move_left" => Action::MoveLeft,
        "move_right" => Action::MoveRight,
        "activate" => Action::Activate,
        "toggle_mode" => Action::ToggleMode,
        "select" => Action::Select,
        "deselect" => Action::Deselect,
        _ => return None,
    })
}
