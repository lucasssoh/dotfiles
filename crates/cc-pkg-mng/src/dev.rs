//! Dev builds: on stable, a Rust app built from the checkout you are working
//! in runs in place of the release's, until `dev --off`.
//!
//! Nothing here is in state.toml: the release a machine follows never records
//! a dev build. What runs is decided by the entry point alone
//! (`~/.local/bin/<bin>`, see sys::entry_point): a link into `dev/` while a
//! dev build is on, a link to the RPM's binary otherwise. `dev/<unit>.toml`
//! only says where a build came from, and how to undo it.

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::lifecycle::Flags;
use crate::manifest::Units;
use crate::ops::{self, SudoSession};
use crate::state::{State, state_dir};
use crate::sys::{self, tilde};
use crate::ui::Ui;
use crate::{git, manifest};

#[derive(Debug, Serialize, Deserialize)]
pub struct Record {
    /// The checkout it was built from.
    pub checkout: PathBuf,
    /// `git describe --dirty` of that checkout at build time.
    pub revision: String,
    pub built_at: String,
    pub bins: Vec<String>,
    /// User services restarted on and off (balise).
    #[serde(default)]
    pub services: Vec<String>,
}

pub fn dir() -> PathBuf {
    state_dir().join("dev")
}

fn record_path(unit: &str) -> PathBuf {
    dir().join(format!("{unit}.toml"))
}

/// Does this entry point run a dev build?
pub fn is_dev_link(entry: &Path) -> bool {
    std::fs::read_link(entry).is_ok_and(|t| t.starts_with(dir()))
}

/// The dev builds running now, by unit.
pub fn active() -> Vec<(String, Record)> {
    let (on, _) = records();
    on
}

/// Drops the records an install or upgrade has ended, by pointing their
/// entry points back at the RPM.
pub fn prune() {
    for (unit, rec) in records().1 {
        forget(&unit, &rec);
    }
}

/// (running, ended)
fn records() -> (Vec<(String, Record)>, Vec<(String, Record)>) {
    let (mut on, mut ended) = (Vec::new(), Vec::new());
    let Ok(entries) = std::fs::read_dir(dir()) else {
        return (on, ended);
    };
    for e in entries.flatten() {
        let path = e.path();
        let Some(unit) = path.file_stem().and_then(|s| s.to_str()).map(str::to_string) else { continue };
        if path.extension().is_none_or(|x| x != "toml") {
            continue;
        }
        let Some(rec) = std::fs::read_to_string(&path).ok().and_then(|s| toml::from_str::<Record>(&s).ok()) else {
            continue;
        };
        if rec.bins.iter().any(|b| is_dev_link(&sys::entry_point(b))) {
            on.push((unit, rec));
        } else {
            ended.push((unit, rec));
        }
    }
    on.sort_by(|a, b| a.0.cmp(&b.0));
    (on, ended)
}

fn forget(unit: &str, rec: &Record) {
    for b in &rec.bins {
        let _ = std::fs::remove_file(dir().join(b));
    }
    let _ = std::fs::remove_file(record_path(unit));
}

/// Point `entry` at `target` in one rename: a keypress at that instant
/// finds either the old binary or the new one, never nothing.
fn point(entry: &Path, target: &Path) -> Result<()> {
    let name = entry.file_name().context("entry point without a name")?.to_string_lossy();
    let tmp = entry.with_file_name(format!(".{name}.link"));
    let _ = std::fs::remove_file(&tmp);
    std::fs::create_dir_all(entry.parent().unwrap())?;
    std::os::unix::fs::symlink(target, &tmp).with_context(|| format!("linking {}", tmp.display()))?;
    std::fs::rename(&tmp, entry).with_context(|| format!("replacing {}", entry.display()))
}

fn restart(ui: &mut Ui, services: &[String]) -> Result<()> {
    for s in services {
        // try-restart: a service that isn't running stays stopped.
        ui.run(&format!("restart {s} (user)"), Command::new("systemctl").args(["--user", "try-restart", s]))?;
    }
    Ok(())
}

/// The checkout to build from: --from, else the one the shell is in, else
/// the one this machine follows.
fn checkout(from: Option<&Path>, managed: &Path) -> Result<PathBuf> {
    let top = |d: &Path| git::git(d, &["rev-parse", "--show-toplevel"]).ok().map(PathBuf::from);
    let dir = match from {
        Some(p) => top(p)
            .filter(|t| t.join("units").is_dir())
            .with_context(|| format!("{} is not a coucou-shell checkout", p.display()))?,
        None => std::env::current_dir()
            .ok()
            .and_then(|d| top(&d))
            .filter(|t| t.join("units").is_dir())
            .unwrap_or_else(|| managed.to_path_buf()),
    };
    std::fs::canonicalize(&dir).with_context(|| format!("{} does not exist", dir.display()))
}

pub fn run(
    ui: &mut Ui,
    flags: &Flags,
    state: &State,
    managed: &Path,
    from: Option<&Path>,
    names: &[String],
    off: bool,
) -> Result<()> {
    if off {
        return stop(ui, flags, names);
    }
    if names.is_empty() {
        return list(ui);
    }
    match state.channel.as_deref() {
        Some("stable") => {}
        Some("edge") => bail!(
            "on edge, the checkout already is what runs: `cc-pkg-mng install {}` rebuilds what changed",
            names.join(" ")
        ),
        _ => bail!("no channel chosen yet — run `cc-pkg-mng init`"),
    }
    let src = checkout(from, managed)?;
    let units: Units = manifest::load_all(&src)?;
    let mut builds = Vec::new();
    let mut deps = std::collections::BTreeSet::new();
    for n in names {
        let u = units.get(n).with_context(|| format!("no unit named \"{n}\" in {}", tilde(&src)))?;
        let b = u.binaries.as_ref().with_context(|| format!("{n} has no Rust app to build"))?;
        deps.extend(u.packages.build.iter().cloned());
        builds.push((u, b));
    }
    let deps: Vec<String> = deps.into_iter().collect();
    let missing: Vec<String> = sys::rpm_missing(&deps)?.into_iter().collect();
    let revision = git::describe(&src);

    ui.heading("Dev build");
    ui.line(&format!("  from              {} {}", tilde(&src), ui.dim(&revision)));
    if !missing.is_empty() {
        ui.line(&format!("  build deps        {}", missing.join(" ")));
    }
    for (u, b) in &builds {
        ui.line(&format!("  {:<17} {} replace the release's", u.name, b.bins.join(", ")));
    }
    if flags.dry_run {
        return Ok(());
    }

    ui.open_log(&state_dir().join("logs"), "dev")?;
    prune();
    if !missing.is_empty() {
        let _sudo = SudoSession::start()?;
        let mut args = vec!["dnf", "install", "-y"];
        args.extend(missing.iter().map(String::as_str));
        ui.run(&format!("dnf install ({} build deps)", missing.len()), &mut ops::sudo(&args))?;
    }
    for (u, b) in &builds {
        ui.heading(&u.name);
        ops::build_bins(ui, &src.join(&b.source), &b.bins, &dir(), true)?;
        let rec = Record {
            checkout: src.clone(),
            revision: revision.clone(),
            built_at: sys::now(),
            bins: b.bins.clone(),
            services: u.services.user.clone(),
        };
        std::fs::write(record_path(&u.name), toml::to_string(&rec)?)?;
        for bin in &b.bins {
            point(&sys::entry_point(bin), &dir().join(bin))?;
        }
        restart(ui, &rec.services)?;
        ui.ok(&format!("{} now run{} this build", b.bins.join(", "), if b.bins.len() == 1 { "s" } else { "" }));
    }
    ui.line(&format!("\n  {}", ui.dim("Back to the release: cc-pkg-mng dev --off")));
    Ok(())
}

fn list(ui: &mut Ui) -> Result<()> {
    let running = active();
    if running.is_empty() {
        ui.line("No dev build running: Roue, Prisme and Balise are the release's.");
        return Ok(());
    }
    ui.heading("Dev builds");
    for (unit, rec) in &running {
        ui.line(&format!(
            "  {:<16} from {} {}  {}",
            unit,
            tilde(&rec.checkout),
            rec.revision,
            ui.dim(&format!("built {}", rec.built_at))
        ));
    }
    ui.line(&format!("\n  {}", ui.dim("Back to the release: cc-pkg-mng dev --off")));
    Ok(())
}

/// Every dev build (or those of `names`) off: the entry points back on the
/// RPM's binaries.
fn stop(ui: &mut Ui, flags: &Flags, names: &[String]) -> Result<()> {
    let running = active();
    for n in names {
        if !running.iter().any(|(u, _)| u == n) {
            bail!("no dev build of \"{n}\" is running");
        }
    }
    let chosen: Vec<&(String, Record)> =
        running.iter().filter(|(u, _)| names.is_empty() || names.contains(u)).collect();
    if chosen.is_empty() {
        ui.line("No dev build running: nothing to undo.");
        return Ok(());
    }
    if flags.dry_run {
        for (unit, rec) in &chosen {
            ui.line(&format!("  would put {} back on the release's {}", unit, rec.bins.join(", ")));
        }
        return Ok(());
    }
    ui.open_log(&state_dir().join("logs"), "dev")?;
    for (unit, rec) in chosen {
        ui.heading(unit);
        for bin in &rec.bins {
            let entry = sys::entry_point(bin);
            if !is_dev_link(&entry) {
                continue;
            }
            let rpm = PathBuf::from("/usr/bin").join(bin);
            if rpm.exists() {
                point(&entry, &rpm)?;
            } else {
                std::fs::remove_file(&entry)?;
                ui.warn(&format!("{bin}: no RPM binary in /usr/bin — `cc-pkg-mng install {unit}` puts it back"));
            }
        }
        forget(unit, rec);
        restart(ui, &rec.services)?;
        ui.ok(&format!("{} back on the release", rec.bins.join(", ")));
    }
    Ok(())
}
