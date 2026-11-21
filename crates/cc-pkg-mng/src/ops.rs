//! Showing a plan, applying it, and removing units.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Context, Result, bail};

use crate::manifest::{RunAs, Units};
use crate::plan::{HookPlan, LinkState, Plan};
use crate::state::{LinkRecord, State, state_dir};
use crate::sys::{self, tilde};
use crate::ui::{Stop, Ui};

/// What a unit's plan does, in a few words: `2 links · hook island look`.
pub fn unit_work(u: &crate::plan::UnitPlan) -> String {
    let mut parts = Vec::new();
    let links = u.links.iter().filter(|l| !matches!(l.state, LinkState::Ok | LinkState::Unmet(_))).count();
    let backups = u.links.iter().filter(|l| l.state == LinkState::Backup).count();
    let back_from_dev = u.links.iter().any(|l| matches!(&l.state, LinkState::Replace(old) if old.starts_with(crate::dev::dir())));
    if back_from_dev {
        parts.push("ends the dev build".to_string());
    }
    if links > 0 {
        parts.push(plural(links, "link", "links"));
    }
    if backups > 0 {
        parts.push(format!("{backups} backed up"));
    }
    let copies = u.files.iter().filter(|f| f.copy).count();
    if copies > 0 {
        parts.push(plural(copies, "system file", "system files"));
    }
    let services = u.user_services.iter().chain(&u.system_services).filter(|(_, on)| !on).count();
    if services > 0 {
        parts.push(plural(services, "service", "services"));
    }
    if let Some(b) = &u.build {
        parts.push(format!("build {}", b.bins.join(", ")));
    }
    if !u.drop_local.is_empty() {
        parts.push("local build replaced by the release's".to_string());
    }
    for h in &u.hooks {
        if let HookPlan::Run(h, _) = h {
            parts.push(format!("hook: {}", h.does));
        }
    }
    if parts.is_empty() {
        parts.push(if u.new { "recorded".into() } else { "files changed".into() });
    }
    parts.join(" · ")
}

pub fn plural(n: usize, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

/// The plan, on the rail: packages with their versions, then the units
/// that change. The question comes after it, from the caller.
pub fn show_plan(ui: &mut Ui, plan: &Plan, title: &str, aside: &str) {
    ui.rail_top(title, aside);
    if plan.has_packages() {
        ui.rail_gap();
        let n = plan.changes.len();
        ui.rail_section(&plural(n, "package", "packages"), "");
        let w = plan.changes.iter().map(|c| c.name.chars().count()).max().unwrap_or(0).max(10);
        for c in &plan.changes {
            let what = match (&c.from, &c.to) {
                (Some(a), Some(b)) => format!("{a} → {b}"),
                (None, Some(b)) => format!("{b} {}", ui.dim("new")),
                (Some(a), None) => a.clone(),
                (None, None) => ui.dim("new"),
            };
            let first = if plan.manager.is_some() && c.name == "cc-pkg-mng" { format!("   {}", ui.dim("updated first")) } else { String::new() };
            ui.rail_row(&format!("{:<w$}   {what}{first}", c.name));
        }
        for copr in &plan.coprs {
            ui.rail_row(&ui.dim(&format!("+ COPR {copr}")));
        }
        for r in &plan.repos {
            ui.rail_row(&ui.dim(&format!("+ repository {}", r.rsplit('/').next().unwrap_or(r))));
        }
    }
    let changing: Vec<_> = plan.units.iter().filter(|u| u.has_work()).collect();
    let unchanged = plan.units.len() - changing.len();
    ui.rail_gap();
    if changing.is_empty() {
        ui.rail_section("units", &format!("{unchanged} up to date"));
    } else {
        let note = if unchanged > 0 { format!("{unchanged} unchanged") } else { String::new() };
        let what = if changing.iter().all(|u| u.new) { "new" } else { "changed" };
        ui.rail_section(&format!("{} {what}", plural(changing.len(), "unit", "units")), &note);
        let w = changing.iter().map(|u| u.name.chars().count()).max().unwrap_or(0).max(10);
        for u in &changing {
            let tag = if u.new && what != "new" { format!("{} ", ui.green("new")) } else { String::new() };
            ui.rail_row(&format!("{:<w$}   {tag}{}", u.name, ui.dim(&unit_work(u))));
        }
        let pending: Vec<&str> = plan
            .units
            .iter()
            .flat_map(|u| u.hooks.iter())
            .filter_map(|h| if let HookPlan::Pending(h) = h { Some(h.name.as_str()) } else { None })
            .collect();
        if !pending.is_empty() {
            ui.rail_row(&ui.dim(&format!("not automated yet: {}", pending.join(", "))));
        }
    }
    if plan.needs_root() {
        ui.rail_gap();
        ui.line(&format!(" {}  {}", ui.dim("│"), ui.dim("sudo password asked once")));
    }
}

/// Keeps the sudo timestamp fresh for the whole run.
pub struct SudoSession(Arc<AtomicBool>);

impl SudoSession {
    pub fn start() -> Result<SudoSession> {
        // `sudo -n true` first: it succeeds when no password is needed
        // (NOPASSWD, or credentials already cached), where `sudo -v` would
        // still ask for one as soon as any of the user's rules requires it —
        // and with no terminal (unattended installs) cannot.
        let ready = Command::new("sudo").args(["-n", "true"]).stderr(Stdio::null()).status();
        if !matches!(ready, Ok(s) if s.success()) {
            let status = Command::new("sudo").arg("-v").status().context("running sudo")?;
            if !status.success() {
                bail!(Stop::new("sudo refused the password."));
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

pub fn sudo(args: &[&str]) -> Command {
    let mut c = Command::new("sudo");
    c.arg("-n").args(args);
    c
}

pub fn apply_unit(
    ui: &mut Ui,
    repo: &Path,
    units: &Units,
    u: &crate::plan::UnitPlan,
    backup_dir: &Path,
) -> Result<(Vec<LinkRecord>, Vec<String>)> {
    if let Some(b) = &u.build {
        build_bins(ui, &b.source, &b.bins, &sys::home().join(".local/bin"), false)?;
        ui.ok(&format!("{} built", b.bins.join(", ")));
    }
    for p in &u.drop_local {
        std::fs::remove_file(p).with_context(|| format!("removing {}", p.display()))?;
        ui.ok(&format!("{} now the release's", tilde(p)));
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
                ui.ok(&format!("linked {}, previous one in {}", tilde(&l.dst), tilde(&to)));
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
    // Started as well as enabled when run from the session: the services
    // hang off graphical-session.target, which this Hyprland session never
    // activates (hyprland.lua starts them at login instead), so a service
    // enabled by an upgrade would otherwise sit stopped until the next
    // login. Only the ones enabled here and now: nothing already running is
    // restarted. From a TTY or over SSH there is no session to start them in.
    let in_session = std::env::var_os("WAYLAND_DISPLAY").is_some();
    for s in to_enable {
        let mut cmd = Command::new("systemctl");
        cmd.args(["--user", "enable"]);
        if in_session {
            cmd.arg("--now");
        }
        cmd.arg(s);
        let what = if in_session { "enable and start" } else { "enable" };
        ui.run(&format!("{what} {s} (user)"), &mut cmd)?;
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
            ui.run(&format!("hook {}", hook.does), &mut cmd)?;
        }
    }
    let acted = u.build.is_some()
        || !u.drop_local.is_empty()
        || u.files.iter().any(|f| f.copy)
        || u.system_services.iter().chain(&u.user_services).any(|(_, on)| !on)
        || u.links.iter().any(|l| !matches!(l.state, LinkState::Ok))
        || u.hooks.iter().any(|h| matches!(h, HookPlan::Run(..)));
    if !acted {
        ui.ok("in place");
    }
    Ok((links, files))
}

/// `cargo build --release` in `source`, then each binary moved into `dest`
/// whole (copy beside it, rename over): a running one keeps its old file.
/// `quick`: a dev build, same optimisation but no LTO and incremental, in
/// its own target dir so it never invalidates the release artifacts.
pub fn build_bins(ui: &mut Ui, source: &Path, bins: &[String], dest: &Path, quick: bool) -> Result<()> {
    let mut target = std::env::var_os("CARGO_TARGET_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| sys::home().join(".cache/dotfiles/cargo-target"));
    let mut cargo = Command::new("cargo");
    if quick {
        target.push("dev");
        cargo.env("CARGO_PROFILE_RELEASE_LTO", "off").env("CARGO_PROFILE_RELEASE_INCREMENTAL", "true");
    }
    cargo.args(["build", "--release"]).current_dir(source).env("CARGO_TARGET_DIR", &target);
    ui.run(&format!("build {}", bins.join(", ")), &mut cargo)?;
    std::fs::create_dir_all(dest)?;
    for bin in bins {
        let tmp = dest.join(format!(".{bin}.new"));
        let built = target.join("release").join(bin);
        std::fs::copy(&built, &tmp).with_context(|| format!("copying {}", built.display()))?;
        std::fs::rename(&tmp, dest.join(bin))?;
    }
    Ok(())
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
            bail!(Stop::new(format!("{n} is not installed.")));
        }
        let blockers: Vec<String> = crate::resolve::dependents(units, &installed, n)
            .into_iter()
            .filter(|d| !names.contains(d))
            .collect();
        if !blockers.is_empty() {
            bail!(Stop::new(format!("{n} is needed by {}.", blockers.join(", "))).hint("remove them too", format!("cc-pkg-mng remove {n} {}", blockers.join(" "))));
        }
    }
    for n in names {
        let rec = state.units[n].clone();
        ui.heading(n);
        for l in &rec.links {
            let ours = std::fs::read_link(&l.dst).is_ok_and(|t| t == l.src);
            if !ours {
                ui.skip(&format!("{} left alone: no longer our link", tilde(&l.dst)));
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
                ui.line(&format!("  {}", ui.dim(&format!("packages kept: {}", kept.join(" ")))));
            }
            if !rec.files.is_empty() || !u.services.system.is_empty() {
                ui.line(&format!("  {}", ui.dim("system files and services kept")));
            }
        }
        if !dry {
            state.units.remove(n);
            state.save()?;
        }
    }
    Ok(())
}
