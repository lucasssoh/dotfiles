//! Exécution de l'action shell associée à un secteur validé.

use std::process::{Command, Stdio};

/// Lance `action` via un shell, détaché (jamais attendu) : la roue se ferme
/// immédiatement après avoir validé un secteur, elle ne doit jamais bloquer
/// sur `hyprlock`, `systemctl suspend`, etc. Même schéma que
/// `apply::ensure_awww_daemon` dans Prisme (`Command::spawn` + stdio nulle).
pub fn run(action: &str) {
    if let Err(e) = Command::new("sh")
        .arg("-c")
        .arg(action)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        eprintln!("[roue] failed to launch {action:?}: {e}");
    }
}
