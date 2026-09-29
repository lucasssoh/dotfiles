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
    #[serde(default)]
    pub units: BTreeMap<String, UnitState>,
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
