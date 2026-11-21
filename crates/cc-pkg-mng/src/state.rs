//! Persistent state: `${XDG_STATE_HOME:-~/.local/state}/coucou-shell/state.toml`.
//!
//! Plain data, rewritten atomically (temp file + rename) after every unit, so
//! an interrupted run keeps what it completed.

use std::collections::BTreeMap;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

pub const SCHEMA: u32 = 1;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct State {
    #[serde(default)]
    pub schema: u32,
    /// The checkout this machine follows.
    #[serde(default)]
    pub repo: Option<PathBuf>,
    /// "stable" (release tags) or "edge" (the default branch).
    #[serde(default)]
    pub channel: Option<String>,
    /// What is checked out: a tag on stable, a commit on edge.
    #[serde(default)]
    pub version: Option<String>,
    /// The version before the last upgrade, for `rollback`.
    #[serde(default)]
    pub previous: Option<String>,
    /// A move between versions under way: set before its packages, cleared
    /// once every unit is in place. Still there at the next run means the
    /// last one stopped half-way, and where.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upgrading: Option<Upgrading>,
    #[serde(default)]
    pub units: BTreeMap<String, UnitState>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Upgrading {
    /// "upgrade" or "rollback".
    pub kind: String,
    pub from: String,
    pub to: String,
    /// "packages" until the checkout moves, then "units".
    pub phase: String,
    pub started: String,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct UnitState {
    pub installed_at: String,
    pub fingerprint: String,
    #[serde(default)]
    pub answers: BTreeMap<String, String>,
    #[serde(default)]
    pub links: Vec<LinkRecord>,
    #[serde(default)]
    pub files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinkRecord {
    pub src: PathBuf,
    pub dst: PathBuf,
    /// Where a file that stood at `dst` was moved before linking.
    #[serde(default)]
    pub backup: Option<PathBuf>,
}

pub fn state_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("CCPKG_STATE_DIR") {
        return PathBuf::from(dir);
    }
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::sys::home().join(".local/state"));
    base.join("coucou-shell")
}

impl State {
    pub fn load() -> Result<State> {
        let path = state_dir().join("state.toml");
        if !path.exists() {
            return Ok(State { schema: SCHEMA, ..Default::default() });
        }
        let text = std::fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
        toml::from_str(&text).with_context(|| format!("parsing {}", path.display()))
    }

    pub fn save(&self) -> Result<()> {
        let dir = state_dir();
        std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
        let path = dir.join("state.toml");
        let tmp = dir.join("state.toml.tmp");
        let text = toml::to_string_pretty(self)?;
        std::fs::write(&tmp, text).with_context(|| format!("writing {}", tmp.display()))?;
        std::fs::rename(&tmp, &path).with_context(|| format!("replacing {}", path.display()))?;
        Ok(())
    }

    pub fn installed(&self, name: &str) -> bool {
        self.units.contains_key(name)
    }
}

/// One cc-pkg-mng changing the machine at a time: an exclusive lock on
/// `<state>/lock`, held until the process ends (or execs: the file is
/// close-on-exec). The file says who holds it.
pub struct Lock(std::fs::File);

impl Drop for Lock {
    fn drop(&mut self) {
        // Who held it no longer matters.
        let _ = self.0.set_len(0);
    }
}

impl Lock {
    pub fn take(what: &str) -> Result<Lock> {
        use std::io::{Read, Seek, Write};
        use std::os::fd::AsRawFd;
        let dir = state_dir();
        std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
        let path = dir.join("lock");
        let mut file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&path)
            .with_context(|| format!("opening {}", path.display()))?;
        // SAFETY: flock on a descriptor this File owns.
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            let mut holder = String::new();
            let _ = file.read_to_string(&mut holder);
            let holder = holder.trim();
            let mut stop = crate::ui::Stop::new("cc-pkg-mng is already running.");
            if !holder.is_empty() {
                stop = stop.detail(holder.to_string());
            }
            return Err(stop.into());
        }
        file.set_len(0)?;
        file.rewind()?;
        let _ = write!(file, "{what}, pid {}, since {}", std::process::id(), crate::sys::local_hm());
        Ok(Lock(file))
    }
}
