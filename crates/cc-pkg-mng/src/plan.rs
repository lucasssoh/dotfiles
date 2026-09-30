//! What an install would do, computed without touching anything.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::git;
use crate::manifest::{Hook, RunAs, Unit, Units};
use crate::state::State;
use crate::sys;

/// Where the Rust apps' RPMs come from on the stable channel.
pub const RPM_REPO: &str = "https://lucasssoh.github.io/dotfiles/coucou-shell.repo";

#[derive(Debug, PartialEq)]
pub enum LinkState {
    /// Already the right link.
    Ok,
    /// Nothing there yet.
    Create,
    /// A symlink pointing elsewhere; replaced.
    Replace(PathBuf),
    /// A real file or directory; moved to the backups, then linked.
    Backup,
    /// Conditional link whose unit is absent; left alone.
    Unmet(String),
}

#[derive(Debug)]
pub struct LinkPlan {
    pub src: PathBuf,
    pub dst: PathBuf,
    pub state: LinkState,
}

#[derive(Debug)]
pub struct FilePlan {
    pub src: PathBuf,
    pub dst: PathBuf,
    pub copy: bool,
}

#[derive(Debug)]
pub enum HookPlan {
    Run(Hook, PathBuf),
    /// Unchanged since it last ran.
    Skip,
    /// No script yet (only described in the manifest).
    Pending(Hook),
}

#[derive(Debug)]
pub struct BinPlan {
    pub source: PathBuf,
    pub bins: Vec<String>,
}

#[derive(Debug)]
pub struct UnitPlan {
    pub name: String,
    pub new: bool,
    pub changed: bool,
    pub fingerprint: String,
    pub answers: BTreeMap<String, String>,
    pub links: Vec<LinkPlan>,
    pub files: Vec<FilePlan>,
    /// (service, already enabled)
    pub user_services: Vec<(String, bool)>,
    pub system_services: Vec<(String, bool)>,
    pub hooks: Vec<HookPlan>,
    pub build: Option<BinPlan>,
    /// Local builds left from edge, which would shadow the RPM's binaries.
    pub drop_local: Vec<PathBuf>,
}

impl UnitPlan {
    pub fn has_work(&self) -> bool {
        self.new
            || self.changed
            || self.links.iter().any(|l| !matches!(l.state, LinkState::Ok | LinkState::Unmet(_)))
            || self.files.iter().any(|f| f.copy)
            || self.user_services.iter().chain(&self.system_services).any(|(_, on)| !on)
            || self.hooks.iter().any(|h| matches!(h, HookPlan::Run(..)))
            || self.build.is_some()
            || !self.drop_local.is_empty()
    }
}

#[derive(Debug, Default)]
pub struct Plan {
    pub units: Vec<UnitPlan>,
    pub coprs: Vec<String>,
    pub repos: Vec<String>,
    pub packages: Vec<String>,
    /// Rust apps newer than the release checked out (after a rollback).
    pub downgrades: Vec<String>,
}

impl Plan {
    pub fn needs_root(&self) -> bool {
        !self.coprs.is_empty()
            || !self.repos.is_empty()
            || !self.packages.is_empty()
            || !self.downgrades.is_empty()
            || self.units.iter().any(|u| {
                u.files.iter().any(|f| f.copy)
                    || u.system_services.iter().any(|(_, on)| !on)
                    || u.hooks.iter().any(|h| matches!(h, HookPlan::Run(h, _) if h.run_as == RunAs::Root))
            })
    }

    pub fn has_work(&self) -> bool {
        self.needs_root() || self.units.iter().any(UnitPlan::has_work)
    }
}

/// Repo paths a unit's fingerprint covers: its manifest directory and every
/// source it links, copies, runs or builds.
pub fn fingerprint_paths(repo: &Path, unit: &Unit) -> Vec<PathBuf> {
    let mut paths = vec![unit.dir.clone()];
    paths.extend(unit.links.keys().chain(unit.files.keys()).map(|s| repo.join(s)));
    // A Rust app's sources: on edge, a change rebuilds it.
    paths.extend(unit.binaries.iter().map(|b| repo.join(&b.source)));
    for h in &unit.hooks {
        paths.extend(h.run.iter().chain(&h.watch).map(|s| repo.join(s)));
    }
    paths
}

/// A changed answer (wezterm: stable → smear) must re-run the unit's hooks,
/// so the answers are part of the fingerprint.
pub fn with_answers(files: String, answers: &BTreeMap<String, String>) -> String {
    if answers.is_empty() {
        return files;
    }
    let joined: Vec<String> = answers.iter().map(|(k, v)| format!("{k}={v}")).collect();
    format!("{files}+{}", joined.join(","))
}

/// `order`: the units to install, dependencies first (resolve::closure).
/// `answers`: every question of those units, already answered.
pub fn build(
    repo: &Path,
    units: &Units,
    state: &State,
    order: &[String],
    answers: &BTreeMap<String, BTreeMap<String, String>>,
) -> Result<Plan> {
    let mut plan = Plan::default();
    // On stable, the release checked out: its Rust apps come as RPMs of the
    // same version.
    let release = (state.channel.as_deref() == Some("stable"))
        .then(|| git::exact_tag(repo))
        .flatten()
        .and_then(|t| t.strip_prefix('v').map(str::to_string));
    let mut needs_repo = false;
    let installing: BTreeSet<&str> = order.iter().map(String::as_str).collect();

    // Packages: one rpm query for everything, including what conditional
    // links depend on.
    let mut all_pkgs: BTreeSet<String> = BTreeSet::new();
    for name in order {
        let u = &units[name];
        all_pkgs.extend(u.packages.dnf.iter().cloned());
        for cond in u.links_if.keys() {
            if let Some(c) = units.get(cond) {
                all_pkgs.extend(c.packages.dnf.iter().cloned());
            }
        }
    }
    let all_pkgs: Vec<String> = all_pkgs.into_iter().collect();
    let missing = sys::rpm_missing(&all_pkgs)?;

    let present = |cond: &str| -> bool {
        installing.contains(cond)
            || state.installed(cond)
            || units.get(cond).is_some_and(|c| {
                !c.packages.dnf.is_empty() && c.packages.dnf.iter().all(|p| !missing.contains(p))
            })
    };

    let mut coprs = BTreeSet::new();
    let mut repos = BTreeSet::new();
    let mut packages: Vec<String> = Vec::new();
    let add_pkg = |p: &String, packages: &mut Vec<String>| {
        if missing.contains(p) && !packages.contains(p) {
            packages.push(p.clone());
        }
    };

    for name in order {
        let u = &units[name];
        let prior = state.units.get(name);
        let unit_answers = answers.get(name).cloned().unwrap_or_default();
        let fingerprint = with_answers(sys::fingerprint(repo, &fingerprint_paths(repo, u)), &unit_answers);
        let new = prior.is_none();
        let changed = prior.is_some_and(|p| p.fingerprint != fingerprint);

        for p in &u.packages.dnf {
            add_pkg(p, &mut packages);
        }
        if u.packages.dnf.iter().any(|p| missing.contains(p)) {
            coprs.extend(u.packages.copr.iter().filter(|c| !sys::copr_enabled(c)).cloned());
            repos.extend(u.packages.repos.iter().filter(|r| !sys::repo_added(r)).cloned());
        }

        // Rust apps: on stable, the release's RPMs; on edge, built locally
        // from the checkout, since master is ahead of any published RPM.
        let local_bin = |bin: &String| sys::home().join(".local/bin").join(bin);
        let mut build = None;
        let mut drop_local = Vec::new();
        if let Some(b) = &u.binaries {
            if let Some(v) = &release {
                let wanted = format!("{}-{v}", b.rpm);
                match sys::rpm_version(&b.rpm) {
                    Some(have) if have == *v => {}
                    Some(have) if sys::newer(&have, v) => {
                        plan.downgrades.push(wanted);
                        needs_repo = true;
                    }
                    _ => {
                        packages.push(wanted);
                        needs_repo = true;
                    }
                }
                drop_local = b.bins.iter().map(local_bin).filter(|p| p.exists()).collect();
            } else if new || changed || b.bins.iter().any(|bin| !local_bin(bin).exists()) {
                build = Some(BinPlan { source: repo.join(&b.source), bins: b.bins.clone() });
                let build_deps = sys::rpm_missing(&u.packages.build)?;
                for p in &u.packages.build {
                    if build_deps.contains(p) && !packages.contains(p) {
                        packages.push(p.clone());
                    }
                }
            }
        }

        let links = u
            .links
            .iter()
            .map(|(src, dst)| {
                let src = repo.join(src);
                let dst = sys::expand(dst);
                let rel = src.strip_prefix(repo).unwrap().to_string_lossy().into_owned();
                let state = match u.link_condition(&rel) {
                    Some(cond) if !present(cond) => LinkState::Unmet(cond.to_string()),
                    _ => link_state(&src, &dst),
                };
                LinkPlan { src, dst, state }
            })
            .collect();

        let files = u
            .files
            .iter()
            .map(|(src, dst)| {
                let src = repo.join(src);
                let dst = PathBuf::from(dst);
                let copy = !sys::same_content(&src, &dst);
                FilePlan { src, dst, copy }
            })
            .collect();

        let user_services = u.services.user.iter().map(|s| (s.clone(), sys::service_enabled(s, true))).collect();
        let system_services = u.services.system.iter().map(|s| (s.clone(), sys::service_enabled(s, false))).collect();

        let hooks = u
            .hooks
            .iter()
            .map(|h| match &h.run {
                None => HookPlan::Pending(h.clone()),
                Some(_) if !(new || changed) => HookPlan::Skip,
                Some(script) => HookPlan::Run(h.clone(), repo.join(script)),
            })
            .collect();

        plan.units.push(UnitPlan {
            name: name.clone(),
            new,
            changed,
            fingerprint,
            answers: unit_answers,
            links,
            files,
            user_services,
            system_services,
            hooks,
            build,
            drop_local,
        });
    }
    if needs_repo && !sys::repo_added(RPM_REPO) {
        repos.insert(RPM_REPO.to_string());
    }
    plan.coprs = coprs.into_iter().collect();
    plan.repos = repos.into_iter().collect();
    plan.packages = packages;
    Ok(plan)
}

pub fn link_state(src: &Path, dst: &Path) -> LinkState {
    match std::fs::symlink_metadata(dst) {
        Err(_) => LinkState::Create,
        Ok(meta) if meta.file_type().is_symlink() => {
            let resolved = std::fs::canonicalize(dst).ok();
            if resolved.is_some() && resolved == std::fs::canonicalize(src).ok() {
                LinkState::Ok
            } else {
                LinkState::Replace(std::fs::read_link(dst).unwrap_or_default())
            }
        }
        Ok(_) => LinkState::Backup,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn link_states() {
        let tmp = std::env::temp_dir().join(format!("ccpkg-link-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();
        let src = tmp.join("src");
        let other = tmp.join("other");
        std::fs::write(&src, "a").unwrap();
        std::fs::write(&other, "b").unwrap();

        assert_eq!(link_state(&src, &tmp.join("absent")), LinkState::Create);

        let good = tmp.join("good");
        std::os::unix::fs::symlink(&src, &good).unwrap();
        assert_eq!(link_state(&src, &good), LinkState::Ok);

        // A relative link that resolves to the same file is fine too.
        let rel = tmp.join("rel");
        std::os::unix::fs::symlink("src", &rel).unwrap();
        assert_eq!(link_state(&src, &rel), LinkState::Ok);

        let wrong = tmp.join("wrong");
        std::os::unix::fs::symlink(&other, &wrong).unwrap();
        assert_eq!(link_state(&src, &wrong), LinkState::Replace(other.clone()));

        let dangling = tmp.join("dangling");
        std::os::unix::fs::symlink(tmp.join("gone"), &dangling).unwrap();
        assert!(matches!(link_state(&src, &dangling), LinkState::Replace(_)));

        assert_eq!(link_state(&src, &other), LinkState::Backup);
        std::fs::remove_dir_all(&tmp).unwrap();
    }
}
