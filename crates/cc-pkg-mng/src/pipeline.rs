//! Carrying out a plan, in an order that never leaves the machine half on
//! one version and half on the other:
//!
//!   check     repositories ready, the release's packages published
//!   download  every transaction resolved and fetched (`--downloadonly`)
//!   packages  cc-pkg-mng first (then the new one carries on), the rest
//!   units     the checkout moves, then each unit is applied
//!
//! Up to the checkout nothing a session runs has changed: a failure there
//! leaves the version as it was. For a move between versions the plan is
//! made from the target version extracted beside the checkout (staging),
//! so its packages are known before the checkout moves. The version is
//! written once every unit is in place; until then `state.upgrading` says
//! how far a move got.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail};

use crate::dnf::{self, Problem};
use crate::lifecycle::{self, Answers, Flags};
use crate::manifest::{Layer, Units};
use crate::ops::{self, SudoSession, plural};
use crate::plan::{self, Plan};
use crate::state::{State, UnitState, Upgrading, state_dir};
use crate::ui::{CmdFailed, Mark, Shown, Stop, Ui};
use crate::{git, manifest, resolve, sys};

/// A move between versions.
pub struct Move {
    /// "upgrade" or "rollback".
    pub kind: &'static str,
    /// How the versions read (a tag, or `git describe` on edge).
    pub from: String,
    pub to: String,
    pub how: How,
}

pub enum How {
    /// Stable: check out this tag, detached.
    Detach(String),
    /// Edge: fast-forward the branch to this commit of its upstream.
    FastForward(String),
}

impl How {
    fn rev(&self) -> &str {
        match self {
            How::Detach(r) | How::FastForward(r) => r,
        }
    }
}

pub struct Job {
    /// The rail's title: `upgrade v2.5.0 → v2.6.0`, `install`.
    pub title: String,
    pub mv: Option<Move>,
    /// Units asked for; None: everything installed, plus core units the
    /// version adds.
    pub names: Option<Vec<String>>,
    pub preset: Answers,
    /// The question before anything happens.
    pub confirm: String,
    /// The closing line when all went well, if not the default.
    pub done: Option<String>,
}

/// The transactions failed and dnf said `--allowerasing` would get past
/// them: the caller may offer it. Already on screen.
#[derive(Debug)]
pub struct Blocked {
    /// dnf arguments of each transaction, for a dry run with --allowerasing.
    pub transactions: Vec<Vec<String>>,
}

impl std::fmt::Display for Blocked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("packages blocked")
    }
}

impl std::error::Error for Blocked {}

/// The target version's units and packaging, extracted from git beside the
/// checkout: what an upgrade plans from before it moves anything.
struct Staging {
    dir: PathBuf,
}

impl Staging {
    fn extract(repo: &Path, rev: &str) -> Result<(Staging, Units)> {
        let dir = state_dir().join("staging");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
        let staging = Staging { dir };
        archive(repo, rev, &["units".into(), "packaging".into()], &staging.dir)?;
        let units = manifest::load_all(&staging.dir)?;
        // Then whatever the units' fingerprints cover, so that "changed"
        // means the same here as after the checkout moves.
        let wanted: BTreeSet<String> = units
            .values()
            .flat_map(|u| plan::fingerprint_paths(&staging.dir, u))
            .filter_map(|p| p.strip_prefix(&staging.dir).ok().map(|r| r.to_string_lossy().into_owned()))
            .filter(|p| !p.is_empty() && !p.starts_with("units") && !p.starts_with("packaging"))
            .collect();
        if !wanted.is_empty() {
            let mut args = vec!["ls-tree", "--name-only", rev, "--"];
            args.extend(wanted.iter().map(String::as_str));
            let present: Vec<String> = git::git(repo, &args)?.lines().map(str::to_string).collect();
            if !present.is_empty() {
                archive(repo, rev, &present, &staging.dir)?;
            }
        }
        Ok((staging, units))
    }
}

impl Drop for Staging {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// `git archive <rev> -- <paths> | tar -x -C <dir>`.
fn archive(repo: &Path, rev: &str, paths: &[String], dir: &Path) -> Result<()> {
    let mut git = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["archive", "--format=tar", rev, "--"])
        .args(paths)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("running git archive")?;
    let out = git.stdout.take().unwrap();
    let tar = Command::new("tar").arg("-x").arg("-C").arg(dir).stdin(out).stderr(Stdio::piped()).output().context("running tar")?;
    let status = git.wait()?;
    if !status.success() || !tar.status.success() {
        let mut err = String::new();
        if let Some(mut e) = git.stderr.take() {
            use std::io::Read;
            let _ = e.read_to_string(&mut err);
        }
        bail!("extracting {rev}: {}{}", err.trim(), String::from_utf8_lossy(&tar.stderr).trim());
    }
    Ok(())
}

/// Everything installed that the version still has, plus the core units it
/// adds; units it dropped are named and forgotten.
fn reapply_names(ui: &mut Ui, state: &mut State, units: &Units, to: &str) -> Vec<String> {
    let gone: Vec<String> = state.units.keys().filter(|n| !units.contains_key(*n)).cloned().collect();
    for n in &gone {
        ui.warn(&format!("{n}: gone from {to}, links left in place"));
        state.units.remove(n);
    }
    let mut names: Vec<String> = state.units.keys().cloned().collect();
    for u in units.values().filter(|u| u.layer == Layer::Core && !u.optional) {
        if !names.contains(&u.name) {
            names.push(u.name.clone());
        }
    }
    names
}

pub fn run(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State, job: Job) -> Result<()> {
    let reexec = std::env::var_os("CCPKG_REEXEC").is_some();

    // The tree to plan from: the target version for a move, the checkout
    // otherwise.
    let (staging, units) = match &job.mv {
        Some(mv) => {
            let (s, u) = Staging::extract(repo, mv.how.rev()).map_err(|e| {
                Stop::new(format!("{} can't be read by this cc-pkg-mng.", mv.to))
                    .detail(format!("{e:#}"))
                    .detail(format!("Still on {}.", mv.from))
                    .hint("update it", "sudo dnf upgrade cc-pkg-mng")
            })?;
            (Some(s), u)
        }
        None => (None, manifest::load_all(repo)?),
    };
    let tree = staging.as_ref().map(|s| s.dir.clone()).unwrap_or_else(|| repo.to_path_buf());
    let release = match &job.mv {
        Some(Move { how: How::Detach(tag), .. }) => tag.strip_prefix('v').map(str::to_string),
        Some(_) => None,
        None => plan::release_of(repo, state),
    };
    let to_label = job.mv.as_ref().map(|m| m.to.clone()).unwrap_or_else(|| git::describe(repo));
    let names = match &job.names {
        Some(n) => n.clone(),
        None => reapply_names(ui, state, &units, &to_label),
    };
    let order = resolve::closure(&units, &names)?;
    let answers = lifecycle::ask(ui, flags, &units, state, &order, &job.preset)?;
    let mut plan = plan::build(&tree, repo, &units, state, &order, &answers, release.as_deref())?;
    if reexec {
        // The new cc-pkg-mng is the one running: never again.
        plan.manager = None;
        plan.changes.retain(|c| c.name != "cc-pkg-mng");
    }

    if job.mv.is_none() && !plan.has_work() && order.iter().all(|n| state.installed(n)) {
        ui.line(&format!("\n {} {}", ui.green("✓"), ui.bold("Nothing to do.")));
        return Ok(());
    }

    let quiet_plan = reexec || flags.again;
    if !quiet_plan {
        ops::show_plan(ui, &plan, &job.title, state.channel.as_deref().unwrap_or(""));
    }
    if flags.dry_run {
        ui.rail_bottom();
        return Ok(());
    }
    if flags.interactive(ui) && !reexec {
        ui.rail_gap();
        let yes = dialoguer::Confirm::with_theme(&ui.theme()).with_prompt(&job.confirm).default(true).interact()?;
        if !yes {
            return Err(Stop { warn: true, title: "Cancelled.".into(), ..Default::default() }.into());
        }
    } else if !quiet_plan {
        ui.rail_bottom();
    }

    ui.open_log(&state_dir().join("logs"), job.mv.as_ref().map(|m| m.kind).unwrap_or("install"))?;
    let _sudo = if plan.needs_root() { Some(SudoSession::start()?) } else { None };
    if let Some(mv) = &job.mv {
        state.upgrading = Some(Upgrading {
            kind: mv.kind.to_string(),
            from: mv.from.clone(),
            to: mv.to.clone(),
            phase: "packages".into(),
            started: sys::now(),
        });
        state.save()?;
    }

    let changing = plan.units.iter().filter(|u| u.has_work() || !state.installed(&u.name)).count();
    let mut phases = Vec::new();
    if plan.has_packages() {
        let n = plan.changes.len();
        phases.push(("check".to_string(), String::new()));
        phases.push(("download".to_string(), String::new()));
        phases.push(("packages".to_string(), plural(n, "package", "packages")));
    }
    let units_note = match &job.mv {
        Some(mv) => format!("{}, then {}", mv.to, plural(changing, "unit", "units")),
        None => plural(changing, "unit", "units"),
    };
    phases.push(("units".to_string(), units_note));
    ui.board_begin(&job.title, phases);

    // ── packages ──
    let mut partial = false;
    if plan.has_packages() {
        match packages(ui, &plan, flags.allow_erasing, &mut partial) {
            Ok(true) => return reexec_manager(ui, &plan),
            Ok(false) => {}
            Err(e) => return Err(blocked(ui, state, &job, &plan, e, partial, flags.allow_erasing, flags.interactive(ui))),
        }
    }

    // ── units ──
    ui.heading("units");
    let mut repo_units = units;
    drop(staging);
    if let Some(mv) = &job.mv {
        if let Some(u) = state.upgrading.as_mut() {
            u.phase = "units".into();
        }
        state.save()?;
        let moved = match &mv.how {
            How::Detach(tag) => git::checkout_detached(repo, tag),
            How::FastForward(_) => git::fast_forward(repo),
        };
        if let Err(e) = moved {
            ui.fail(&format!("check out {}: {e:#}", mv.to));
            let log = ui.log_path().map(sys::tilde).unwrap_or_default();
            ui.board_end(Mark::Fail, &format!("Still on {}.", mv.from), &ui.hints(&[("details".into(), log)]));
            return Err(Shown.into());
        }
        ui.ok(&format!("checked out {}", mv.to));
        // From here the checkout is the target: plan again from it, now
        // that its packages are in.
        repo_units = manifest::load_all(repo)?;
        plan = plan::build(repo, repo, &repo_units, state, &order, &answers, release.as_deref())?;
        if !plan.packages.is_empty() || !plan.upgrades.is_empty() {
            let mut args = vec!["dnf", "install", "-y"];
            args.extend(plan.packages.iter().chain(&plan.upgrades).map(String::as_str));
            ui.run(&format!("dnf install {}", plural(plan.packages.len() + plan.upgrades.len(), "package", "packages")), &mut ops::sudo(&args))?;
        }
    }
    let changed_rpms: BTreeSet<String> = plan.changes.iter().map(|c| c.name.clone()).collect();
    let (applied, failed) = apply_units(ui, repo, &repo_units, state, &plan, &changed_rpms)?;
    ui.note(&match (applied, failed.len()) {
        (0, 0) => "up to date".to_string(),
        (a, 0) => format!("{a} applied"),
        (a, f) => format!("{a} of {} applied", a + f),
    });
    if plan.changes.iter().any(|c| c.name == "quickshell") {
        restart_bar(ui);
    }
    crate::dev::prune();

    // ── the closing line ──
    let log = ui.log_path().map(sys::tilde).unwrap_or_default();
    if !failed.is_empty() {
        let mut hints: Vec<(String, String)> = Vec::new();
        let title = match &job.mv {
            Some(mv) => {
                state.previous = Some(mv.from.clone());
                state.version = Some(mv.to.clone());
                state.save()?;
                hints.push(("retry".into(), format!("cc-pkg-mng {}", if mv.kind == "upgrade" { "upgrade" } else { "rollback" })));
                if mv.kind == "upgrade" && matches!(mv.how, How::Detach(_)) {
                    hints.push((format!("back to {}", mv.from), "cc-pkg-mng rollback".into()));
                }
                format!("{} installed, {} unfinished.", mv.to, failed.join(", "))
            }
            None => {
                hints.push(("retry".into(), format!("cc-pkg-mng install {}", failed.join(" "))));
                format!("{} unfinished.", failed.join(", "))
            }
        };
        hints.push(("details".into(), log));
        ui.board_end(Mark::Warn, &title, &ui.hints(&hints));
        return Err(Shown.into());
    }

    let close = match &job.mv {
        Some(mv) => {
            state.previous = Some(mv.from.clone());
            state.version = Some(mv.to.clone());
            state.upgrading = None;
            state.save()?;
            format!("coucou-shell {}", mv.to)
        }
        None => job.done.clone().unwrap_or_else(|| format!("{} in place", plural(changing.max(1), "unit", "units"))),
    };
    let mut after = Vec::new();
    if let Some(running) = sys::hyprland_running()
        && let Some(installed) = sys::rpm_version("hyprland")
            && installed != running {
                after.push(format!("{} Hyprland {installed} runs after the next login.", ui.yellow("!")));
            }
    ui.board_end(Mark::Done, &close, &after);
    Ok(())
}

/// check, download, packages. Ok(true): cc-pkg-mng itself was just
/// replaced, and the new one should carry on.
fn packages(ui: &mut Ui, plan: &Plan, allow_erasing: bool, partial: &mut bool) -> Result<bool> {
    ui.heading("check");
    for copr in &plan.coprs {
        ui.run(&format!("enable COPR {copr}"), &mut ops::sudo(&["dnf", "copr", "enable", "-y", copr]))?;
    }
    for r in &plan.repos {
        let from = format!("--from-repofile={r}");
        ui.run(&format!("add repository {}", r.rsplit('/').next().unwrap_or(r)), &mut ops::sudo(&["dnf", "config-manager", "addrepo", "--overwrite", &from]))?;
    }
    if plan.refresh_repo {
        ui.run("refresh coucou-shell's repository", &mut ops::sudo(&["dnf", "makecache", "--refresh", "--repo=coucou-shell"]))?;
        ui.note("published");
    } else {
        ui.note("repositories ready");
    }

    let transactions = transactions(plan, allow_erasing);
    ui.heading("download");
    let mut size = Vec::new();
    for (label, args) in &transactions {
        let mut a: Vec<&str> = args.iter().map(String::as_str).collect();
        a.push("--downloadonly");
        let out = ui.run_output(&format!("{label}, download"), &mut ops::sudo(&a))?;
        size.extend(dnf::download_size(&out));
    }
    let note = if size.is_empty() { "no conflicts".to_string() } else { format!("{} · no conflicts", size.join(" + ")) };
    ui.note(&note);

    ui.heading("packages");
    for (label, args) in &transactions {
        let a: Vec<&str> = args.iter().map(String::as_str).collect();
        ui.run(label, &mut ops::sudo(&a))?;
        *partial = true;
        if plan.manager.is_some() && args.iter().any(|x| x.starts_with("cc-pkg-mng-")) && sys::running_from_rpm() {
            ui.note(&format!("cc-pkg-mng {}", plan.manager.as_deref().unwrap_or("").trim_start_matches("cc-pkg-mng-")));
            return Ok(true);
        }
    }
    let installed = plan.changes.iter().filter(|c| c.from.is_none()).count();
    let moved = plan.changes.len() - installed;
    let mut note = Vec::new();
    if moved > 0 {
        note.push(format!("{moved} upgraded"));
    }
    if installed > 0 {
        note.push(format!("{installed} installed"));
    }
    ui.note(&note.join(" · "));
    Ok(false)
}

/// dnf transactions, cc-pkg-mng's own first: (label, arguments).
fn transactions(plan: &Plan, allow_erasing: bool) -> Vec<(String, Vec<String>)> {
    let mut out = Vec::new();
    let mut push = |label: String, verb: &str, pkgs: &[String]| {
        if pkgs.is_empty() {
            return;
        }
        let mut args: Vec<String> = vec!["dnf".into(), verb.into(), "-y".into()];
        if allow_erasing {
            args.push("--allowerasing".into());
        }
        args.extend(pkgs.iter().cloned());
        out.push((label, args));
    };
    if let Some(m) = &plan.manager {
        push(m.replacen("cc-pkg-mng-", "cc-pkg-mng ", 1).to_string(), "install", std::slice::from_ref(m));
    }
    push(format!("dnf install, {}", plural(plan.packages.len(), "package", "packages")), "install", &plan.packages);
    push(format!("dnf upgrade, {}", plural(plan.upgrades.len(), "package", "packages")), "upgrade", &plan.upgrades);
    push(format!("dnf downgrade, {}", plural(plan.downgrades.len(), "package", "packages")), "downgrade", &plan.downgrades);
    out
}

/// A package step failed: what it means, on the rail's closing line, and
/// the state put back where it was.
#[allow(clippy::too_many_arguments)]
fn blocked(ui: &mut Ui, state: &mut State, job: &Job, plan: &Plan, err: anyhow::Error, partial: bool, allow_erasing: bool, interactive: bool) -> anyhow::Error {
    let output = err.downcast_ref::<CmdFailed>().map(|c| c.output.clone()).unwrap_or_default();
    let problem = dnf::classify(&output);
    let target = job.mv.as_ref().map(|m| m.to.as_str()).unwrap_or("the install");
    let mut detail: Vec<String> = Vec::new();
    let mut hints: Vec<(String, String)> = Vec::new();
    let mut erasing = false;
    let title = match &problem {
        Problem::NotFound(p) => {
            detail.extend(p.iter().map(|x| ui.dim(x)));
            if p.iter().any(|x| x.contains(release_suffix(job).as_str()) && !release_suffix(job).is_empty()) {
                hints.push(("retry later".into(), retry(job)));
                format!("{target} is tagged but not published yet.")
            } else {
                format!("{} not found in the repositories.", plural(p.len(), "package", "packages"))
            }
        }
        Problem::Conflict { lines, erasing: e } => {
            erasing = *e;
            detail.extend(lines.iter().map(|x| ui.dim(x)));
            if *e && !interactive {
                hints.push(("let dnf replace them".into(), format!("{} --allow-erasing", retry(job))));
            }
            format!("Packages block {target}.")
        }
        Problem::Network(l) => {
            detail.extend(l.iter().map(|x| ui.dim(x)));
            hints.push(("retry".into(), retry(job)));
            "The repositories can't be reached.".to_string()
        }
        Problem::Key(l) => {
            detail.extend(l.iter().map(|x| ui.dim(x)));
            "A package signature can't be checked.".to_string()
        }
        Problem::Other(l) => {
            detail.extend(l.iter().map(|x| ui.dim(x)));
            if output.is_empty() { format!("{err:#}") } else { "dnf stopped.".to_string() }
        }
    };
    ui.fail_phase(&[]);
    let width = crate::ui::terminal_width().saturating_sub(8).max(40);
    let mut after: Vec<String> = detail.iter().flat_map(|l| wrap(&crate::ui::plain(l), width)).map(|l| ui.dim(&l)).collect();
    let still = match (&job.mv, partial) {
        (Some(mv), false) => format!("Still on {}. Nothing changed.", mv.from),
        (Some(mv), true) => format!("Still on {}. Some packages moved: run it again.", mv.from),
        (None, false) => "Nothing installed.".to_string(),
        (None, true) => "Some packages installed.".to_string(),
    };
    after.push(String::new());
    after.push(still);
    hints.push(("details".into(), ui.log_path().map(sys::tilde).unwrap_or_default()));
    after.extend(ui.hints(&hints));
    ui.board_end(Mark::Fail, &title, &after);
    if !partial {
        state.upgrading = None;
        let _ = state.save();
    }
    if erasing && !allow_erasing {
        let transactions = transactions(plan, false).into_iter().map(|(_, a)| a).collect();
        return Blocked { transactions }.into();
    }
    Shown.into()
}

fn release_suffix(job: &Job) -> String {
    match &job.mv {
        Some(Move { how: How::Detach(tag), .. }) => format!("-{}", tag.trim_start_matches('v')),
        _ => String::new(),
    }
}

fn retry(job: &Job) -> String {
    match &job.mv {
        Some(mv) if mv.kind == "rollback" => "cc-pkg-mng rollback".into(),
        Some(_) => "cc-pkg-mng upgrade".into(),
        None => "cc-pkg-mng install".into(),
    }
}

/// The units, one item each; a unit whose requirement failed is skipped.
/// Services of the apps whose package or build changed are restarted.
fn apply_units(
    ui: &mut Ui,
    repo: &Path,
    units: &Units,
    state: &mut State,
    plan: &Plan,
    changed_rpms: &BTreeSet<String>,
) -> Result<(usize, Vec<String>)> {
    let backup_root = state_dir().join("backups");
    let stamp = sys::now().replace(':', "");
    let dev: Vec<String> = crate::dev::active().into_iter().map(|(n, _)| n).collect();
    let mut failed: Vec<String> = Vec::new();
    let mut applied = 0;
    for u in &plan.units {
        if !u.has_work() && state.installed(&u.name) {
            continue;
        }
        ui.item(&u.name);
        let blocked: Vec<&String> = units[&u.name].requires.iter().filter(|d| failed.contains(*d)).collect();
        if !blocked.is_empty() {
            ui.fail(&format!("skipped: needs {}", blocked.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", ")));
            failed.push(u.name.clone());
            continue;
        }
        match ops::apply_unit(ui, repo, units, u, &backup_root.join(&u.name).join(&stamp)) {
            Ok((links, files)) => {
                state.units.insert(
                    u.name.clone(),
                    UnitState { installed_at: sys::now(), fingerprint: u.fingerprint.clone(), answers: u.answers.clone(), links, files },
                );
                state.save()?;
                applied += 1;
                let unit = &units[&u.name];
                let rebuilt = u.build.is_some() || unit.binaries.as_ref().is_some_and(|b| changed_rpms.contains(&b.rpm));
                if rebuilt && !u.new && !dev.contains(&u.name) {
                    for s in &unit.services.user {
                        // try-restart: a service that isn't running stays stopped.
                        let _ = ui.run(&format!("restart {s}"), Command::new("systemctl").args(["--user", "try-restart", s]));
                    }
                }
            }
            Err(e) => {
                ui.fail(&format!("{e:#}"));
                failed.push(u.name.clone());
            }
        }
    }
    Ok((applied, failed))
}

/// A new quickshell: the bar restarted on it, inside a Hyprland session.
fn restart_bar(ui: &mut Ui) {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return;
    }
    let script = sys::home().join(".config/hypr/scripts/restart-quickshell-bar.sh");
    if script.is_file() {
        ui.item("bar");
        let _ = ui.run_detached("restart the bar", Command::new("bash").arg(&script));
    }
}

/// cc-pkg-mng's RPM was just replaced: the new binary carries on, with the
/// same arguments and no second confirmation.
fn reexec_manager(ui: &mut Ui, plan: &Plan) -> Result<()> {
    use std::os::unix::process::CommandExt;
    let v = plan.manager.as_deref().unwrap_or("").trim_start_matches("cc-pkg-mng-").to_string();
    ui.board_end(Mark::Done, &format!("cc-pkg-mng {v}, carrying on"), &[]);
    let err = Command::new("/usr/bin/cc-pkg-mng").args(std::env::args_os().skip(1)).env("CCPKG_REEXEC", "1").exec();
    Err(anyhow::Error::new(err).context("starting the new cc-pkg-mng"))
}

/// What `dnf --allowerasing` would remove for these transactions, without
/// doing it.
pub fn would_remove(transactions: &[Vec<String>]) -> Vec<String> {
    let mut out = Vec::new();
    for t in transactions {
        let mut args: Vec<&str> = t.iter().map(String::as_str).filter(|a| *a != "-y").collect();
        args.insert(2, "--assumeno");
        args.insert(3, "--allowerasing");
        if let Ok(o) = ops::sudo(&args).env("LC_ALL", "C").stdin(Stdio::null()).output() {
            let lines: Vec<String> = String::from_utf8_lossy(&o.stdout).lines().map(str::to_string).collect();
            for p in dnf::removals(&lines) {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
    }
    out
}


/// Word-wrap `text` to `width` columns, continuation lines indented two
/// more than the first.
fn wrap(text: &str, width: usize) -> Vec<String> {
    let indent: String = text.chars().take_while(|c| *c == ' ').collect();
    let mut out = Vec::new();
    let mut line = indent.clone();
    for word in text.split_whitespace() {
        if line.trim().is_empty() {
            line.push_str(word);
        } else if line.chars().count() + 1 + word.chars().count() > width {
            out.push(std::mem::take(&mut line));
            line = format!("{indent}  {word}");
        } else {
            line.push(' ');
            line.push_str(word);
        }
    }
    if !line.trim().is_empty() {
        out.push(line);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wraps_long_problems() {
        let w = wrap("Problem: package fakeapp conflicts with fakepkg-old from terra", 30);
        assert_eq!(w, vec!["Problem: package fakeapp", "  conflicts with fakepkg-old", "  from terra"]);
    }
}
