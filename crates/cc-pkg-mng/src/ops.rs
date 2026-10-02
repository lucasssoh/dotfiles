//! Showing a plan, applying it, and removing units.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Context, Result, bail};

use crate::manifest::{RunAs, Units};
use crate::plan::{HookPlan, LinkState, Plan};
use crate::state::{LinkRecord, State, UnitState, state_dir};
use crate::sys::{self, tilde};
use crate::ui::Ui;

pub fn show_plan(ui: &mut Ui, plan: &Plan) {
    ui.heading("Plan");
    if !plan.coprs.is_empty() {
        ui.line(&format!("  COPRs to enable   {}", plan.coprs.join(" ")));
    }
    for r in &plan.repos {
        ui.line(&format!("  repo to add       {r}"));
    }
    if plan.packages.is_empty() {
        ui.line(&format!("  {}", ui.dim("packages          all present")));
    } else {
        ui.line(&format!("  packages          {} to install: {}", plan.packages.len(), plan.packages.join(" ")));
    }
    if !plan.downgrades.is_empty() {
        ui.line(&format!("  downgrade         {}", plan.downgrades.join(" ")));
    }
    for u in &plan.units {
        let tag = if u.new {
            ui.green("new")
        } else if u.changed {
            ui.yellow("changed")
        } else if u.has_work() {
            ui.yellow("repair")
        } else {
            ui.dim("up to date")
        };
        ui.line(&format!("\n  {} {}", ui.bold(&u.name), tag));
        for p in &u.drop_local {
            ui.line(&format!("    {} {}  {}", ui.dim("·"), tilde(p), ui.dim("remove the local build (a link to the RPM's replaces it)")));
        }
        for l in &u.links {
            let what = match &l.state {
                LinkState::Ok => continue,
                LinkState::Create => "link".to_string(),
                LinkState::Replace(old) => format!("relink (was → {})", old.display()),
                LinkState::Backup => "back up the existing file, then link".to_string(),
                LinkState::Unmet(cond) => format!("skip (needs {cond})"),
            };
            ui.line(&format!("    {} {}  {}", ui.dim("·"), tilde(&l.dst), ui.dim(&what)));
        }
        for f in u.files.iter().filter(|f| f.copy) {
            ui.line(&format!("    {} {}  {}", ui.dim("·"), f.dst.display(), ui.dim("copy (root)")));
        }
        for (s, _) in u.user_services.iter().filter(|(_, on)| !on) {
            ui.line(&format!("    {} {s}  {}", ui.dim("·"), ui.dim("enable (user)")));
        }
        for (s, _) in u.system_services.iter().filter(|(_, on)| !on) {
            ui.line(&format!("    {} {s}  {}", ui.dim("·"), ui.dim("enable (system, next boot)")));
        }
        if let Some(b) = &u.build {
            ui.line(&format!("    {} build {}  {}", ui.dim("·"), b.bins.join(", "), ui.dim("(local cargo build)")));
        }
        for h in &u.hooks {
            match h {
                HookPlan::Run(h, _) => ui.line(&format!("    {} hook {}  {}", ui.dim("·"), h.name, ui.dim(&h.does))),
                HookPlan::Skip => {}
                HookPlan::Pending(h) => ui.line(&format!(
                    "    {} hook {}  {}",
                    ui.dim("○"),
                    h.name,
                    ui.dim("not extracted yet — still done by the current modules")
                )),
            }
        }
    }
    if plan.needs_root() {
        ui.line(&format!("\n  {}", ui.yellow("Needs root: you will be asked for your password once.")));
    }
}

/// Keeps the sudo timestamp fresh for the whole run.
struct SudoSession(Arc<AtomicBool>);

impl SudoSession {
    fn start() -> Result<SudoSession> {
        // `sudo -n true` first: it succeeds when no password is needed
        // (NOPASSWD, or credentials already cached), where `sudo -v` would
        // still ask for one as soon as any of the user's rules requires it —
        // and with no terminal (unattended installs) cannot.
        let ready = Command::new("sudo").args(["-n", "true"]).stderr(Stdio::null()).status();
        if !matches!(ready, Ok(s) if s.success()) {
            let status = Command::new("sudo").arg("-v").status().context("running sudo")?;
            if !status.success() {
                bail!("sudo authentication failed");
            }
        }
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        std::thread::spawn(move || {
            while !flag.load(Ordering::Relaxed) {
                std::thread::sleep(std::time::Duration::from_secs(50));
                let _ = Command::new("sudo").args(["-n", "-v"]).stderr(Stdio::null()).status();
            }
        });
        Ok(SudoSession(stop))
    }
}

impl Drop for SudoSession {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Relaxed);
    }
}

fn sudo(args: &[&str]) -> Command {
    let mut c = Command::new("sudo");
    c.arg("-n").args(args);
    c
}

pub fn apply(ui: &mut Ui, repo: &Path, units: &Units, state: &mut State, plan: &Plan) -> Result<()> {
    let _sudo = if plan.needs_root() { Some(SudoSession::start()?) } else { None };

    if !plan.coprs.is_empty() || !plan.repos.is_empty() || !plan.packages.is_empty() || !plan.downgrades.is_empty() {
        ui.heading("Packages");
        for copr in &plan.coprs {
            ui.run(&format!("enable COPR {copr}"), &mut sudo(&["dnf", "copr", "enable", "-y", copr]))?;
        }
        for r in &plan.repos {
            let from = format!("--from-repofile={r}");
            ui.run(&format!("add repo {r}"), &mut sudo(&["dnf", "config-manager", "addrepo", &from]))?;
        }
        if !plan.packages.is_empty() {
            let mut args = vec!["dnf", "install", "-y"];
            args.extend(plan.packages.iter().map(String::as_str));
            ui.run(&format!("dnf install ({} packages)", plan.packages.len()), &mut sudo(&args))?;
        }
        if !plan.downgrades.is_empty() {
            let mut args = vec!["dnf", "downgrade", "-y"];
            args.extend(plan.downgrades.iter().map(String::as_str));
            ui.run(&format!("dnf downgrade ({} packages)", plan.downgrades.len()), &mut sudo(&args))?;
        }
    }

    let backup_root = state_dir().join("backups");
    let stamp = sys::now().replace(':', "");
    let mut failed = Vec::new();

    for u in &plan.units {
        if !u.has_work() && state.installed(&u.name) {
            continue;
        }
        let blocked: Vec<&String> = units[&u.name].requires.iter().filter(|d| failed.contains(*d)).collect();
        if !blocked.is_empty() {
            ui.heading(&u.name);
            ui.fail(&format!("skipped: {} failed", blocked.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", ")));
            failed.push(u.name.clone());
            continue;
        }
        ui.heading(&u.name);
        match apply_unit(ui, repo, units, u, &backup_root.join(&u.name).join(&stamp)) {
            Ok((links, files)) => {
                state.units.insert(
                    u.name.clone(),
                    UnitState {
                        installed_at: sys::now(),
                        fingerprint: u.fingerprint.clone(),
                        answers: u.answers.clone(),
                        links,
                        files,
                    },
                );
                state.save()?;
            }
            Err(e) => {
                ui.fail(&format!("{}: {e:#}", u.name));
                failed.push(u.name.clone());
            }
        }
    }
    if !failed.is_empty() {
        bail!("{} unit(s) failed: {} — re-run to retry", failed.len(), failed.join(", "));
    }
    Ok(())
}

fn apply_unit(
    ui: &mut Ui,
    repo: &Path,
    units: &Units,
    u: &crate::plan::UnitPlan,
    backup_dir: &Path,
) -> Result<(Vec<LinkRecord>, Vec<String>)> {
    if let Some(b) = &u.build {
        let target = std::env::var_os("CARGO_TARGET_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|| sys::home().join(".cache/dotfiles/cargo-target"));
        let mut cargo = Command::new("cargo");
        cargo.args(["build", "--release"]).current_dir(&b.source).env("CARGO_TARGET_DIR", &target);
        ui.run(&format!("build {}", b.bins.join(", ")), &mut cargo)?;
        let bin_dir = sys::home().join(".local/bin");
        std::fs::create_dir_all(&bin_dir)?;
        for bin in &b.bins {
            let tmp = bin_dir.join(format!(".{bin}.new"));
            let built = target.join("release").join(bin);
            std::fs::copy(&built, &tmp).with_context(|| format!("copying {}", built.display()))?;
            std::fs::rename(&tmp, bin_dir.join(bin))?;
        }
        ui.ok(&format!("installed {} in ~/.local/bin", b.bins.join(", ")));
    }
    for p in &u.drop_local {
        std::fs::remove_file(p).with_context(|| format!("removing {}", p.display()))?;
        ui.ok(&format!("removed the local build {}", tilde(p)));
    }

    let mut files = Vec::new();
    for f in &u.files {
        files.push(f.dst.display().to_string());
        if !f.copy {
            continue;
        }
        for src in sys::walk(&f.src) {
            let rel = src.strip_prefix(&f.src).unwrap();
            let dst = if rel.as_os_str().is_empty() { f.dst.clone() } else { f.dst.join(rel) };
            let mode = if sys::is_executable(&src) { "755" } else { "644" };
            ui.run(
                &format!("copy {}", dst.display()),
                &mut sudo(&["install", "-D", "-m", mode, &src.to_string_lossy(), &dst.to_string_lossy()]),
            )?;
        }
    }
    for (s, on) in &u.system_services {
        if !on {
            ui.run(&format!("enable {s} (system)"), &mut sudo(&["systemctl", "enable", s]))?;
        }
    }

    let mut links = Vec::new();
    let mut unit_files_linked = false;
    for l in &u.links {
        let mut backup = None;
        match &l.state {
            LinkState::Unmet(cond) => {
                ui.skip(&format!("{} (needs {cond})", tilde(&l.dst)));
                continue;
            }
            LinkState::Ok => {}
            LinkState::Create | LinkState::Replace(_) => {
                if matches!(l.state, LinkState::Replace(_)) {
                    std::fs::remove_file(&l.dst)?;
                }
                make_link(&l.src, &l.dst)?;
                ui.ok(&format!("linked {}", tilde(&l.dst)));
            }
            LinkState::Backup => {
                let rel = l.dst.strip_prefix(sys::home()).unwrap_or(&l.dst);
                let to = backup_dir.join(rel.strip_prefix("/").unwrap_or(rel));
                std::fs::create_dir_all(to.parent().unwrap())?;
                std::fs::rename(&l.dst, &to)
                    .with_context(|| format!("moving {} to the backups", l.dst.display()))?;
                make_link(&l.src, &l.dst)?;
                ui.ok(&format!("linked {} (previous one kept in {})", tilde(&l.dst), tilde(&to)));
                backup = Some(to);
            }
        }
        if l.state != LinkState::Ok && l.dst.to_string_lossy().contains("/systemd/user/") {
            unit_files_linked = true;
        }
        links.push(LinkRecord { src: l.src.clone(), dst: l.dst.clone(), backup });
    }

    let to_enable: Vec<&String> = u.user_services.iter().filter(|(_, on)| !on).map(|(s, _)| s).collect();
    if unit_files_linked || !to_enable.is_empty() {
        ui.run("systemctl --user daemon-reload", Command::new("systemctl").args(["--user", "daemon-reload"]))?;
    }
    for s in to_enable {
        ui.run(&format!("enable {s} (user)"), Command::new("systemctl").args(["--user", "enable", s]))?;
    }

    let unit = &units[&u.name];
    for h in &u.hooks {
        if let HookPlan::Run(hook, script) = h {
            // A root hook runs as the user too and calls `sudo -n` for its
            // system steps: this run holds the sudo session (SudoSession),
            // and building or cloning as root would land in /root.
            let hook_state = state_dir().join("hooks").join(&unit.name);
            std::fs::create_dir_all(&hook_state)?;
            let mut cmd = Command::new(script);
            cmd.current_dir(repo)
                .env("CCPKG_UNIT", &unit.name)
                .env("COUCOU_DIR", repo)
                .env("CCPKG_HOOK_STATE", &hook_state)
                .env("CCPKG_ROOT", if hook.run_as == RunAs::Root { "1" } else { "0" });
            for (k, v) in &u.answers {
                cmd.env(format!("CCPKG_ANSWER_{}", k.to_uppercase()), v);
            }
            ui.run(&format!("hook {}", hook.name), &mut cmd)?;
        }
    }
    let acted = u.build.is_some()
        || !u.drop_local.is_empty()
        || u.files.iter().any(|f| f.copy)
        || u.system_services.iter().chain(&u.user_services).any(|(_, on)| !on)
        || u.links.iter().any(|l| !matches!(l.state, LinkState::Ok))
        || u.hooks.iter().any(|h| matches!(h, HookPlan::Run(..)));
    if !acted {
        ui.ok("already in place — recorded");
    }
    Ok((links, files))
}

fn make_link(src: &Path, dst: &Path) -> Result<()> {
    if let Some(parent) = dst.parent() {
        std::fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
    }
    std::os::unix::fs::symlink(src, dst).with_context(|| format!("linking {}", dst.display()))
}

pub fn remove(ui: &mut Ui, units: &Units, state: &mut State, names: &[String], dry: bool) -> Result<()> {
    let installed: BTreeSet<String> = state.units.keys().cloned().collect();
    for n in names {
        if !installed.contains(n) {
            bail!("\"{n}\" is not installed");
        }
        let blockers: Vec<String> = crate::resolve::dependents(units, &installed, n)
            .into_iter()
            .filter(|d| !names.contains(d))
            .collect();
        if !blockers.is_empty() {
            bail!("{n} is required by {} — remove them too, or keep {n}", blockers.join(", "));
        }
    }
    for n in names {
        let rec = state.units[n].clone();
        ui.heading(&format!("remove {n}"));
        for l in &rec.links {
            let ours = std::fs::read_link(&l.dst).is_ok_and(|t| t == l.src);
            if !ours {
                ui.skip(&format!("{} (not our link any more, left alone)", tilde(&l.dst)));
                continue;
            }
            if dry {
                ui.line(&format!("    would unlink {}", tilde(&l.dst)));
                continue;
            }
            std::fs::remove_file(&l.dst)?;
            match &l.backup {
                Some(b) if b.exists() => {
                    std::fs::rename(b, &l.dst)?;
                    ui.ok(&format!("restored {}", tilde(&l.dst)));
                }
                _ => ui.ok(&format!("unlinked {}", tilde(&l.dst))),
            }
        }
        if let Some(u) = units.get(n) {
            for s in &u.services.user {
                if dry {
                    ui.line(&format!("    would disable {s} (user)"));
                } else if sys::service_enabled(s, true) {
                    let _ = ui.run(&format!("disable {s} (user)"), Command::new("systemctl").args(["--user", "disable", s]));
                }
            }
            let kept: Vec<String> = u.packages.dnf.clone();
            if !kept.is_empty() {
                ui.line(&format!("    {}", ui.dim(&format!("packages kept (other software may use them): {}", kept.join(" ")))));
            }
            if !rec.files.is_empty() || !u.services.system.is_empty() {
                ui.line(&format!("    {}", ui.dim("system files and services kept")));
            }
        }
        if !dry {
            state.units.remove(n);
            state.save()?;
        }
    }
    Ok(())
}
