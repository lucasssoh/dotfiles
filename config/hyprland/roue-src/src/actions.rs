//! Runs the shell action associated with a confirmed sector.

use std::process::{Command, Stdio};

/// Launches `action` through a shell, detached (never awaited): the wheel
/// closes immediately after confirming a sector, so it must never block on
/// `hyprlock`, `systemctl suspend`, etc. Same pattern as
/// `apply::ensure_awww_daemon` in Prisme (`Command::spawn` + null stdio).
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
