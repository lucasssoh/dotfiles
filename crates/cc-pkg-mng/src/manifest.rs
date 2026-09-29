//! Unit manifests: `units/<layer>/<name>/unit.toml` (docs/design/cc-pkg-mng-2.md).

use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde::Deserialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Layer {
    Core,
    Apps,
    Configs,
}

impl fmt::Display for Layer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Layer::Core => "core",
            Layer::Apps => "apps",
            Layer::Configs => "configs",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RunAs {
    User,
    Root,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Packages {
    #[serde(default)]
    pub dnf: Vec<String>,
    #[serde(default)]
    pub copr: Vec<String>,
    /// Build dependencies of [binaries], needed only for a local build.
    #[serde(default)]
    pub build: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Binaries {
    pub rpm: String,
    pub source: String,
    pub bins: Vec<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Services {
    #[serde(default)]
    pub user: Vec<String>,
    #[serde(default)]
    pub system: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Question {
    pub id: String,
    pub ask: String,
    pub choices: Vec<String>,
    pub default: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Hook {
    pub name: String,
    pub run_as: RunAs,
    pub does: String,
    /// The script that does it today (M1 bookkeeping).
    #[serde(default)]
    pub from: Option<String>,
    /// The hook script, relative to the repo. Absent: not extracted yet.
    #[serde(default)]
    pub run: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Verify {
    #[serde(default)]
    pub commands: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Unit {
    pub name: String,
    pub layer: Layer,
    pub summary: String,
    #[serde(default)]
    pub requires: Vec<String>,
    #[serde(default)]
    pub optional: bool,
    #[serde(default)]
    pub ask: Option<String>,
    #[serde(default)]
    pub default: Option<bool>,
    #[serde(default)]
    pub packages: Packages,
    #[serde(default)]
    pub binaries: Option<Binaries>,
    /// repo path → destination (user scope).
    #[serde(default)]
    pub links: BTreeMap<String, String>,
    /// unit → links made only when that unit is present.
    #[serde(default)]
    pub links_if: BTreeMap<String, Vec<String>>,
    /// repo path → system path, copied as root.
    #[serde(default)]
    pub files: BTreeMap<String, String>,
    #[serde(default)]
    pub services: Services,
    #[serde(default)]
    pub questions: Vec<Question>,
    #[serde(default)]
    pub hooks: Vec<Hook>,
    #[serde(default)]
    pub verify: Verify,
    /// Directory holding unit.toml (filled in by the loader).
    #[serde(skip)]
    pub dir: PathBuf,
}

impl Unit {
    /// The unit a conditional link depends on, if any.
    pub fn link_condition(&self, src: &str) -> Option<&str> {
        self.links_if
            .iter()
            .find(|(_, paths)| paths.iter().any(|p| p == src))
            .map(|(unit, _)| unit.as_str())
    }
}

pub type Units = BTreeMap<String, Unit>;

pub fn load_all(repo: &Path) -> Result<Units> {
    let root = repo.join("units");
    if !root.is_dir() {
        bail!("{} has no units/ directory — is it a coucou-shell checkout?", repo.display());
    }
    let mut units = Units::new();
    for layer_dir in sorted_dirs(&root)? {
        for unit_dir in sorted_dirs(&layer_dir)? {
            let path = unit_dir.join("unit.toml");
            if !path.is_file() {
                continue;
            }
            let text = std::fs::read_to_string(&path)
                .with_context(|| format!("reading {}", path.display()))?;
            let mut unit: Unit =
                toml::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
            let dir_name = file_name(&unit_dir);
            if unit.name != dir_name {
                bail!("{}: name is \"{}\", directory is \"{}\"", path.display(), unit.name, dir_name);
            }
            if unit.layer.to_string() != file_name(&layer_dir) {
                bail!("{}: layer is \"{}\", directory is \"{}\"", path.display(), unit.layer, file_name(&layer_dir));
            }
            unit.dir = unit_dir;
            units.insert(unit.name.clone(), unit);
        }
    }
    Ok(units)
}

fn sorted_dirs(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut out: Vec<PathBuf> = std::fs::read_dir(dir)
        .with_context(|| format!("reading {}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_dir())
        .collect();
    out.sort();
    Ok(out)
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}
