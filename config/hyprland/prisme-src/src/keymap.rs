use gtk4::gdk;
use std::collections::HashMap;

/// Actions déclenchables au clavier -- le fichier externe ne mappe QUE vers
/// ces noms (jamais directement vers une touche codée en dur), pour que le
/// reste du programme n'ait jamais à connaître un nom de touche brut.
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

/// Config par défaut, recopiée en dur plutôt qu'`include_str!` du fichier
/// externe (config/hyprland/prisme/keymap.conf) : ce dernier vit HORS de
/// prisme-src/, qu'install.sh copie seul dans ~/.cache/prisme-build/ avant
/// `cargo build` -- un chemin relatif s'y résout dans le vide (même
/// problème que le CSS de secours, cf. theme.rs). Le vrai fichier, éditable
/// sans recompiler, reste config/hyprland/prisme/keymap.conf (symlinké vers
/// ~/.config/prisme/ par install.sh, dans le même dossier que style.css) :
/// cette constante n'est qu'un filet de secours si ce fichier est absent ou
/// illisible.
const FALLBACK: &str = "\
close = Escape
move_left = Left, h, H
move_right = Right, l, L
activate = Return, KP_Enter, space
toggle_mode = Tab
select = Down, j, J
deselect = Up, k, K
";

pub struct Keymap(HashMap<gdk::Key, Action>);

impl Keymap {
    /// Charge ~/.config/prisme/keymap.conf s'il existe, sinon la config par
    /// défaut ci-dessus. Rechargé à chaque lancement (pas de daemon Prisme,
    /// éditer le fichier suffit).
    pub fn load() -> Self {
        let content = user_path()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .unwrap_or_else(|| FALLBACK.to_string());
        Self(parse(&content))
    }

    pub fn action(&self, key: gdk::Key) -> Option<Action> {
        self.0.get(&key).copied()
    }
}

fn user_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/prisme/keymap.conf"))
}

/// Format : une ligne par action, `nom = touche1, touche2, ...`. `#` en
/// début de ligne (après espaces) commente. Les noms de touches suivent la
/// convention X11/GDK (`gdk_keyval_from_name` -- Escape, Return, KP_Enter,
/// Left, Right, Up, Down, Tab, space, h, H, ...), pas de table de
/// correspondance maison à maintenir. Une ligne ou une touche invalide est
/// ignorée (avec un message sur stderr) plutôt que de faire échouer tout le
/// fichier -- une faute de frappe ne doit pas priver l'utilisateur de
/// toutes les autres touches.
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
            eprintln!("[prisme] keymap.conf: action inconnue '{}'", name.trim());
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
                None => eprintln!("[prisme] keymap.conf: touche inconnue '{key_name}'"),
            }
        }
    }
    map
}

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
