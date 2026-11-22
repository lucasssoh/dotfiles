//! The little Antenne asks of Hyprland and of the bar.
//!
//! This Hyprland is configured in Lua, so `hyprctl dispatch` takes Lua:
//! hl.dsp.window.move / hl.dsp.focus, as Liseuse does (see its comment on
//! why the classic `focuswindow address:` form fails to parse).

use serde_json::Value;
use std::process::{Command, Stdio};

fn json(args: &[&str]) -> Option<Value> {
    let out = Command::new("hyprctl").arg("-j").args(args).stderr(Stdio::null()).output().ok()?;
    serde_json::from_slice(&out.stdout).ok()
}

fn dispatch(lua: &str) {
    let _ = Command::new("hyprctl").args(["dispatch", lua]).stdout(Stdio::null()).stderr(Stdio::null()).status();
}

pub struct Ours {
    pub address: String,
    pub workspace: i64,
}

/// Our own window, found by PID: there is only ever one.
pub fn our_window() -> Option<Ours> {
    let pid = std::process::id() as i64;
    let clients = json(&["clients"])?;
    clients.as_array()?.iter().find(|c| c["pid"].as_i64() == Some(pid)).map(|c| Ours {
        address: c["address"].as_str().unwrap_or_default().to_string(),
        workspace: c["workspace"]["id"].as_i64().unwrap_or(0),
    })
}

pub fn active_workspace() -> Option<i64> {
    json(&["activeworkspace"])?["id"].as_i64()
}

pub fn active_address() -> Option<String> {
    json(&["activewindow"])?["address"].as_str().map(str::to_string)
}

pub fn move_to(address: &str, workspace: i64) {
    dispatch(&format!("hl.dsp.window.move({{ window = 'address:{address}', workspace = '{workspace}' }})"));
}

pub fn focus(address: &str) {
    dispatch(&format!("hl.dsp.focus({{ window = 'address:{address}' }})"));
}

/// Do Not Disturb as the bar reports it ("zen=0 dnd=1"). None when the bar
/// cannot be asked, in which case nothing is changed or restored.
pub fn dnd() -> Option<bool> {
    let out = Command::new("qs").args(["-c", "bar", "ipc", "call", "bar", "focusState"]).stderr(Stdio::null()).output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    if s.contains("dnd=1") {
        Some(true)
    } else if s.contains("dnd=0") {
        Some(false)
    } else {
        None
    }
}

pub fn set_dnd(on: bool) {
    let _ = Command::new("qs")
        .args(["-c", "bar", "ipc", "call", "bar", "setDnd", if on { "true" } else { "false" }])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// On battery, ask HLS for a stream around 720p rather than the best one:
/// half the network, a lighter decode, on a laptop screen it barely shows.
pub fn on_battery() -> bool {
    let Ok(dir) = std::fs::read_dir("/sys/class/power_supply") else { return false };
    let mut has_battery = false;
    for e in dir.flatten() {
        let p = e.path();
        let kind = std::fs::read_to_string(p.join("type")).unwrap_or_default();
        match kind.trim() {
            "Mains" if std::fs::read_to_string(p.join("online")).unwrap_or_default().trim() == "1" => return false,
            "Battery" => has_battery = true,
            _ => {}
        }
    }
    has_battery
}
