//! A machine's life: init, installing, channels, upgrade, rollback.

use std::collections::{BTreeMap, BTreeSet};
use std::io::IsTerminal;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde::Deserialize;

use crate::manifest::{self, Layer, Units};
use crate::state::State;
use crate::ui::{Shown, Stop, Ui};
use crate::{git, ops, pipeline, sys};

/// unit → question id → answer
pub type Answers = BTreeMap<String, BTreeMap<String, String>>;

pub struct Flags {
    pub dry_run: bool,
    pub yes: bool,
    /// Let dnf remove or replace packages in the way (--allowerasing).
    pub allow_erasing: bool,
    /// A second go after the user said yes: the plan is not shown again.
    pub again: bool,
}

impl Flags {
    pub fn interactive(&self, ui: &Ui) -> bool {
        !self.yes && ui.tty && std::io::stdin().is_terminal()
    }
}

// ───────────────────────────── installing ─────────────────────────────

/// Resolve, ask, plan, confirm, apply: `install`, and `init`'s last step.
pub fn install_units(
    ui: &mut Ui,
    flags: &Flags,
    repo: &Path,
    state: &mut State,
    names: &[String],
    preset: &Answers,
) -> Result<()> {
    let job = || pipeline::Job {
        title: "install".into(),
        mv: None,
        names: Some(names.to_vec()),
        preset: preset.clone(),
        confirm: "Install?".into(),
        done: None,
    };
    with_erasing_offer(ui, flags, |ui, flags| pipeline::run(ui, flags, repo, state, job()))
}

/// Run `f`; when packages block it and dnf could get past by replacing
/// some, say which and offer to (on a terminal), then run it again.
fn with_erasing_offer(ui: &mut Ui, flags: &Flags, mut f: impl FnMut(&mut Ui, &Flags) -> Result<()>) -> Result<()> {
    match f(ui, flags) {
        Err(e) if e.downcast_ref::<pipeline::Blocked>().is_some() && flags.interactive(ui) => {
            let blocked = e.downcast::<pipeline::Blocked>().unwrap();
            let gone = pipeline::would_remove(&blocked.transactions);
            let what = if gone.is_empty() { "the packages in the way".to_string() } else { gone.join(", ") };
            println!();
            let yes = dialoguer::Confirm::with_theme(&ui.theme())
                .with_prompt(format!("Let dnf remove {what}?"))
                .default(false)
                .interact()?;
            if !yes {
                return Err(Shown.into());
            }
            let again = Flags { dry_run: flags.dry_run, yes: true, allow_erasing: true, again: true };
            f(ui, &again)
        }
        Err(e) if e.downcast_ref::<pipeline::Blocked>().is_some() => Err(Shown.into()),
        other => other,
    }
}

/// Answers for every question of `order`: given, then remembered, then
/// asked (or the default without a terminal or with --yes).
pub fn ask(ui: &mut Ui, flags: &Flags, units: &Units, state: &State, order: &[String], preset: &Answers) -> Result<Answers> {
    let interactive = flags.interactive(ui);
    let mut all = Answers::new();
    for name in order {
        let mut answers = state.units.get(name).map(|u| u.answers.clone()).unwrap_or_default();
        if let Some(given) = preset.get(name) {
            answers.extend(given.clone());
        }
        for q in &units[name].questions {
            if answers.contains_key(&q.id) {
                continue;
            }
            let value = if interactive {
                let default = q.choices.iter().position(|c| *c == q.default).unwrap_or(0);
                let i = dialoguer::Select::with_theme(&ui.theme())
                    .with_prompt(format!("{name}: {}", q.ask))
                    .items(&q.choices)
                    .default(default)
                    .interact()?;
                q.choices[i].clone()
            } else {
                q.default.clone()
            };
            answers.insert(q.id.clone(), value);
        }
        all.insert(name.clone(), answers);
    }
    Ok(all)
}

// ──────────────────────────────── init ────────────────────────────────

/// `--answers FILE`: everything `init` would ask, for unattended installs.
#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnswersFile {
    pub dir: Option<String>,
    pub channel: Option<String>,
    /// Optional core units, apps and configs to take (the rest of core is
    /// always installed).
    pub units: Option<Vec<String>>,
    #[serde(default)]
    pub answers: Answers,
}

pub fn init(
    ui: &mut Ui,
    flags: &Flags,
    dir_flag: Option<&Path>,
    channel_flag: Option<&str>,
    answers_file: Option<&Path>,
) -> Result<()> {
    let mut state = State::load()?;
    if state.channel.is_some() && !state.units.is_empty() {
        bail!(Stop::new(format!(
            "This machine is already set up, in {}.",
            state.repo.as_deref().map(sys::tilde).unwrap_or_default()
        ))
        .hint("move to the latest release", "cc-pkg-mng upgrade")
        .hint("add or remove units", "cc-pkg-mng install | remove"));
    }
    let file: AnswersFile = match answers_file {
        Some(p) => toml::from_str(&std::fs::read_to_string(p).with_context(|| format!("reading {}", p.display()))?)
            .with_context(|| format!("parsing {}", p.display()))?,
        None => AnswersFile::default(),
    };
    let interactive = flags.interactive(ui) && answers_file.is_none();
    if interactive {
        ui.welcome();
        ui.rail = true;
        ui.step(1, 3, "Where");
    }

    // 1. Where.
    let default_dir = sys::home().join("coucou-shell");
    let dir = match (dir_flag, &file.dir, &state.repo) {
        (Some(d), _, _) => d.to_path_buf(),
        (None, Some(d), _) => sys::expand(d),
        (None, None, Some(d)) => d.clone(),
        (None, None, None) if interactive => {
            let answer: String = dialoguer::Input::with_theme(&ui.theme())
                .with_prompt("Install coucou-shell in")
                .default(sys::tilde(&default_dir))
                .interact_text()?;
            sys::expand(&answer)
        }
        _ => default_dir,
    };

    let adopted = dir.join("units").is_dir();
    if adopted {
        ui.ok(&format!("checkout in {}", sys::tilde(&dir)));
    } else if dir.exists() && std::fs::read_dir(&dir).map(|mut d| d.next().is_some()).unwrap_or(false) {
        bail!(Stop::new(format!("{} is not empty and not a coucou-shell checkout.", sys::tilde(&dir))).hint("pick another", "cc-pkg-mng init --dir PATH"));
    } else if flags.dry_run {
        ui.line(&format!("  would clone {} into {}", git::url(), sys::tilde(&dir)));
        return Ok(());
    } else {
        ui.run(&format!("clone into {}", sys::tilde(&dir)), std::process::Command::new("git").args(["clone", &git::url()]).arg(&dir))?;
    }
    let repo = std::fs::canonicalize(&dir)?;

    // 2. Which channel.
    if interactive {
        ui.step(2, 3, "Channel");
    }
    let tags = git::release_tags(&repo)?;
    let channel = match (channel_flag, file.channel.as_deref()) {
        (Some(c), _) | (None, Some(c)) => c.to_string(),
        _ if interactive && !tags.is_empty() => {
            let items = [
                format!("stable · releases, latest {}", tags[0]),
                "edge · every commit on the default branch".to_string(),
            ];
            let i = dialoguer::Select::with_theme(&ui.theme()).with_prompt("Channel").items(&items).default(0).interact()?;
            if i == 0 { "stable".into() } else { "edge".into() }
        }
        _ if tags.is_empty() => "edge".into(),
        _ => "stable".into(),
    };
    match channel.as_str() {
        "stable" if tags.is_empty() => bail!(Stop::new("No release published yet.").hint("follow every commit", "cc-pkg-mng init --channel edge")),
        "stable" => {
            if git::exact_tag(&repo).as_deref() != Some(tags[0].as_str()) {
                require_clean(&repo)?;
                if flags.dry_run {
                    ui.line(&format!("  would check out {}", tags[0]));
                } else {
                    git::checkout_detached(&repo, &tags[0])?;
                    ui.ok(&format!("checked out {}", tags[0]));
                }
            }
        }
        "edge" => {
            if git::branch(&repo).is_none() && !flags.dry_run {
                git::checkout(&repo, &git::default_branch(&repo))?;
            }
            ui.ok(&format!("following {}", git::branch(&repo).unwrap_or_else(|| git::default_branch(&repo))));
        }
        other => bail!(Stop::new(format!("No channel named {other}.")).detail("stable or edge")),
    }
    if !flags.dry_run {
        state.repo = Some(repo.clone());
        state.channel = Some(channel.clone());
        state.version = Some(git::describe(&repo));
        state.save()?;
    }

    // 3. What.
    if interactive {
        ui.step(3, 3, "Applications");
    }
    let units = manifest::load_all(&repo)?;
    let (migrated, mut preset) = match migrate(&repo)? {
        Some((u, a)) if state.units.is_empty() => {
            ui.ok(&format!("{} carried over from the previous manager", ops::plural(u.len(), "unit", "units")));
            (u, a)
        }
        _ => (BTreeSet::new(), Answers::new()),
    };
    for (unit, a) in file.answers {
        preset.entry(unit).or_default().extend(a);
    }
    let chosen = match &file.units {
        Some(list) => {
            for n in list {
                if !units.contains_key(n) {
                    bail!(Stop::new(format!("Answers file: no unit named {n}.")).hint("every unit", "cc-pkg-mng list"));
                }
            }
            list.iter().cloned().collect()
        }
        None => choose(ui, interactive, &units, &state, &migrated)?,
    };
    let mut names: Vec<String> = units
        .values()
        .filter(|u| u.layer == Layer::Core && !u.optional)
        .map(|u| u.name.clone())
        .collect();
    for n in chosen {
        if !names.contains(&n) {
            names.push(n);
        }
    }

    // 4. The summary: install_units shows the plan and asks before anything.
    if interactive {
        ui.rail = false;
    }
    let _ = &units;
    install_units(ui, flags, &repo, &mut state, &names, &preset)?;
    if !flags.dry_run {
        ui.line(&format!("    Log in to a Hyprland session to start coucou-shell {}.", git::describe(&repo)));
    }
    Ok(())
}

/// Optional core units, apps and configs, asked one group at a time.
fn choose(ui: &mut Ui, interactive: bool, units: &Units, state: &State, migrated: &BTreeSet<String>) -> Result<BTreeSet<String>> {
    let had = |n: &str| migrated.contains(n) || state.installed(n);
    let mut chosen = BTreeSet::new();

    for u in units.values().filter(|u| u.layer == Layer::Core && u.optional) {
        let default = had(&u.name);
        let yes = if interactive {
            dialoguer::Confirm::with_theme(&ui.theme())
                .with_prompt(u.ask.clone().unwrap_or_else(|| format!("Install {}?", u.name)))
                .default(default)
                .interact()?
        } else {
            default
        };
        if yes {
            chosen.insert(u.name.clone());
        }
    }

    let apps: Vec<_> = units.values().filter(|u| u.layer == Layer::Apps).collect();
    let defaults: Vec<bool> = apps.iter().map(|u| had(&u.name) || u.default.unwrap_or(true)).collect();
    let picked: Vec<usize> = if interactive {
        let items: Vec<String> = apps.iter().map(|u| format!("{:<10} {}", u.name, u.summary)).collect();
        dialoguer::MultiSelect::with_theme(&ui.theme())
            .with_prompt("Applications (space toggles, enter confirms)")
            .items(&items)
            .defaults(&defaults)
            .interact()?
    } else {
        (0..apps.len()).filter(|&i| defaults[i]).collect()
    };
    chosen.extend(picked.into_iter().map(|i| apps[i].name.clone()));

    for u in units.values().filter(|u| u.layer == Layer::Configs) {
        let existing: Vec<String> = u
            .links
            .values()
            .map(|d| sys::expand(d))
            .filter(|p| std::fs::symlink_metadata(p).is_ok())
            .map(|p| sys::tilde(&p))
            .collect();
        let default = had(&u.name);
        let adopt = if interactive {
            let hint = if existing.is_empty() {
                String::new()
            } else {
                format!(" (found {})", existing.iter().take(2).cloned().collect::<Vec<_>>().join(", "))
            };
            let items = ["keep mine", "use this one, mine backed up"];
            dialoguer::Select::with_theme(&ui.theme())
                .with_prompt(format!("{}: {}{hint}", u.name, u.summary))
                .items(items)
                .default(if default { 1 } else { 0 })
                .interact()?
                == 1
        } else {
            default
        };
        if adopt {
            chosen.insert(u.name.clone());
        }
    }
    if !interactive {
        ui.line(&format!(" {}  {}", ui.dim("│"), ui.dim(&format!("taking {}", chosen.iter().cloned().collect::<Vec<_>>().join(", ")))));
    }
    Ok(chosen)
}

/// Units and answers carried over from cc-pkg-mng 1 (state.v1): every module
/// it applied successfully, through units/legacy-map.toml.
pub fn migrate(repo: &Path) -> Result<Option<(BTreeSet<String>, Answers)>> {
    let path = std::env::var_os("CCPKG_OLD_STATE").map(PathBuf::from).unwrap_or_else(|| {
        std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| sys::home().join(".local/state"))
            .join("dotfiles/state.v1")
    });
    let Ok(text) = std::fs::read_to_string(&path) else { return Ok(None) };

    #[derive(Deserialize)]
    struct LegacyMap {
        modules: BTreeMap<String, Vec<String>>,
    }
    let map_path = repo.join("units/legacy-map.toml");
    let map: LegacyMap = toml::from_str(&std::fs::read_to_string(&map_path).with_context(|| format!("reading {}", map_path.display()))?)?;

    let mut units = BTreeSet::new();
    let mut answers = Answers::new();
    for line in text.lines() {
        let Some((key, value)) = line.split_once('\t') else { continue };
        if let Some(module) = key.strip_prefix("mod.").and_then(|k| k.strip_suffix(".rc")) {
            if value == "0" {
                units.extend(map.modules.get(module).into_iter().flatten().cloned());
            }
        } else if key == "wezterm.variant" {
            answers.entry("wezterm".into()).or_default().insert("variant".into(), value.to_string());
        }
    }
    Ok(Some((units, answers)))
}

// ───────────────────────── channels and versions ───────────────────────

/// A version as it reads: the tag on stable, `git describe` otherwise.
pub fn label(repo: &Path, rev: &str) -> String {
    git::git(repo, &["describe", "--tags", "--exact-match", rev])
        .or_else(|_| git::git(repo, &["describe", "--tags", "--always", rev]))
        .unwrap_or_else(|_| rev.chars().take(12).collect())
}

pub fn require_clean(repo: &Path) -> Result<()> {
    let dirty = git::dirty(repo)?;
    if !dirty.is_empty() {
        let mut stop = Stop::new(format!("Uncommitted changes in {}.", sys::tilde(repo)));
        for d in dirty.iter().take(6) {
            stop = stop.detail(d.trim().to_string());
        }
        if dirty.len() > 6 {
            stop = stop.detail(format!("and {} more", dirty.len() - 6));
        }
        return Err(stop
            .hint("put them aside", format!("git -C {} stash", sys::tilde(repo)))
            .into());
    }
    Ok(())
}

pub fn channel(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State, new: Option<&str>) -> Result<()> {
    let Some(new) = new else {
        let tags = git::release_tags(repo)?;
        ui.line(&format!("{}  {}", ui.dim("channel"), state.channel.as_deref().unwrap_or("not set up")));
        ui.line(&format!("{}  {}", ui.dim("version"), git::describe(repo)));
        ui.line(&format!("{}  {}", ui.dim("latest "), tags.first().map(String::as_str).unwrap_or("no release yet")));
        return Ok(());
    };
    match new {
        "edge" => {
            if git::branch(repo).is_none() {
                // Leaving a release checkout for the branch: a checkout.
                require_clean(repo)?;
                if !flags.dry_run {
                    git::checkout(repo, &git::default_branch(repo))?;
                }
            }
            ui.ok("edge: upgrade follows every commit");
        }
        "stable" => ui.ok("stable: upgrade moves to the latest release"),
        other => bail!(Stop::new(format!("No channel named {other}.")).detail("stable or edge")),
    }
    if !flags.dry_run {
        state.channel = Some(new.to_string());
        state.save()?;
    }
    Ok(())
}

fn fetch(repo: &Path) -> Result<()> {
    git::git(repo, &["fetch", "--quiet", "--tags", "--force"]).map(|_| ()).map_err(|e| {
        Stop::new("The coucou-shell repository can't be reached.")
            .detail(format!("{e:#}"))
            .hint("retry", "cc-pkg-mng upgrade")
            .into()
    })
}

/// A run that stopped half-way: said before going on.
fn interrupted(ui: &mut Ui, state: &State) {
    if let Some(u) = &state.upgrading {
        ui.warn(&format!("{} {} → {} unfinished: carrying on", u.kind, u.from, u.to));
    }
}

pub fn upgrade(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State, to: Option<&str>) -> Result<()> {
    let Some(channel) = state.channel.clone() else {
        bail!(Stop::new("This machine isn't set up yet.").hint("set it up", "cc-pkg-mng init"));
    };
    require_clean(repo)?;
    fetch(repo)?;
    interrupted(ui, state);
    let head = git::head(repo)?;
    let from = label(repo, &head);

    let how = match channel.as_str() {
        "stable" => {
            let tags = git::release_tags(repo)?;
            let target = match to {
                Some(t) if tags.iter().any(|x| x == t) => t.to_string(),
                Some(t) => bail!(Stop::new(format!("No release named {t}.")).detail(format!("known: {}", tags.iter().take(6).cloned().collect::<Vec<_>>().join(", ")))),
                None => tags.first().cloned().context("no release published yet")?,
            };
            pipeline::How::Detach(target)
        }
        "edge" => {
            if to.is_some() {
                bail!(Stop::new("--to picks a release, on the stable channel."));
            }
            if git::branch(repo).is_none() && !flags.dry_run {
                git::checkout(repo, &git::default_branch(repo))?;
            }
            let upstream = git::git(repo, &["rev-parse", "@{u}"]).map_err(|_| Stop::new("The checkout's branch follows no upstream."))?;
            let head = git::head(repo)?;
            if git::git(repo, &["merge-base", "--is-ancestor", &head, &upstream]).is_err() {
                bail!(Stop::new("The checkout's branch has diverged from its upstream.")
                    .hint("bring it back in line", format!("git -C {} pull --rebase", sys::tilde(repo))));
            }
            pipeline::How::FastForward(upstream)
        }
        other => bail!(Stop::new(format!("Unknown channel {other} in the state.")).hint("pick one", "cc-pkg-mng channel stable")),
    };
    let target_rev = git::git(repo, &["rev-parse", &format!("{}^{{commit}}", match &how {
        pipeline::How::Detach(t) => t.as_str(),
        pipeline::How::FastForward(r) => r.as_str(),
    })])?;
    let to_label = label(repo, &target_rev);

    if target_rev == head {
        // Already there: still re-applied, for what a stopped run left
        // undone, or a package rebuilt for this release.
        let title = match &state.upgrading {
            Some(u) if u.to == to_label => format!("finish {} → {}", u.from, u.to),
            _ => format!("repair {to_label}"),
        };
        let resuming = state.upgrading.clone();
        let job = || pipeline::Job {
            title: title.clone(),
            mv: None,
            names: None,
            preset: Answers::new(),
            confirm: format!("Finish {to_label}?"),
            done: Some(format!("coucou-shell {to_label}")),
        };
        let result = with_erasing_offer(ui, flags, |ui, flags| pipeline::run(ui, flags, repo, state, job()));
        if result.is_ok() {
            if let Some(u) = resuming {
                state.previous = Some(u.from);
            }
            state.version = Some(to_label.clone());
            state.upgrading = None;
            state.save()?;
        }
        return result;
    }

    let kind = "upgrade";
    let title = format!("{kind} {from} → {to_label}");
    let confirm = format!("Upgrade to {to_label}?");
    let make = |how: &pipeline::How| pipeline::Job {
        title: title.clone(),
        mv: Some(pipeline::Move { kind, from: from.clone(), to: to_label.clone(), how: clone_how(how) }),
        names: None,
        preset: Answers::new(),
        confirm: confirm.clone(),
        done: None,
    };
    with_erasing_offer(ui, flags, |ui, flags| pipeline::run(ui, flags, repo, state, make(&how)))
}

fn clone_how(h: &pipeline::How) -> pipeline::How {
    match h {
        pipeline::How::Detach(t) => pipeline::How::Detach(t.clone()),
        pipeline::How::FastForward(r) => pipeline::How::FastForward(r.clone()),
    }
}

pub fn rollback(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State) -> Result<()> {
    if state.channel.as_deref() != Some("stable") {
        bail!(Stop::new("rollback moves between releases, on the stable channel.").detail("On edge, check out a commit with git."));
    }
    let Some(previous) = state.previous.clone() else {
        bail!(Stop::new("No previous release recorded on this machine."));
    };
    require_clean(repo)?;
    let from = label(repo, &git::head(repo)?);
    let title = format!("rollback {from} → {previous}");
    let confirm = format!("Go back to {previous}?");
    let make = || pipeline::Job {
        title: title.clone(),
        mv: Some(pipeline::Move { kind: "rollback", from: from.clone(), to: previous.clone(), how: pipeline::How::Detach(previous.clone()) }),
        names: None,
        preset: Answers::new(),
        confirm: confirm.clone(),
        done: None,
    };
    with_erasing_offer(ui, flags, |ui, flags| pipeline::run(ui, flags, repo, state, make()))
}

/// Change a remembered answer; `install <unit>` then applies it.
pub fn set(ui: &mut Ui, units: &Units, state: &mut State, unit: &str, question: &str, value: &str) -> Result<()> {
    let u = units.get(unit).ok_or_else(|| Stop::new(format!("No unit named {unit}.")).hint("every unit", "cc-pkg-mng list"))?;
    let ids: Vec<&str> = u.questions.iter().map(|q| q.id.as_str()).collect();
    let q = u.questions.iter().find(|q| q.id == question).ok_or_else(|| {
        Stop::new(format!("{unit} has no question {question}.")).detail(if ids.is_empty() { "It asks none.".to_string() } else { format!("Its questions: {}", ids.join(", ")) })
    })?;
    if !q.choices.iter().any(|c| c == value) {
        bail!(Stop::new(format!("{unit} {question} takes {}.", q.choices.join(", "))));
    }
    let Some(rec) = state.units.get_mut(unit) else {
        bail!(Stop::new(format!("{unit} is not installed.")).hint("install it", format!("cc-pkg-mng install {unit}")));
    };
    rec.answers.insert(question.to_string(), value.to_string());
    state.save()?;
    ui.ok(&format!("{unit}: {} {value}", q.ask));
    ui.line(&format!("  {}  {}", ui.dim("apply it"), ui.bold(&format!("cc-pkg-mng install {unit}"))));
    Ok(())
}
