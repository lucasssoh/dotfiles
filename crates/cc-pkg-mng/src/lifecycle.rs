//! A machine's life: init, installing, channels, upgrade, rollback.

use std::collections::{BTreeMap, BTreeSet};
use std::io::IsTerminal;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde::Deserialize;

use crate::manifest::{self, Layer, Units};
use crate::state::{self, State};
use crate::ui::Ui;
use crate::{git, ops, plan, resolve, sys};

/// unit → question id → answer
pub type Answers = BTreeMap<String, BTreeMap<String, String>>;

pub struct Flags {
    pub dry_run: bool,
    pub yes: bool,
}

impl Flags {
    pub fn interactive(&self, ui: &Ui) -> bool {
        !self.yes && ui.tty && std::io::stdin().is_terminal()
    }
}

// ───────────────────────────── installing ─────────────────────────────

/// Resolve, ask, plan, confirm, apply. Every command that changes the
/// machine ends here.
pub fn install_units(
    ui: &mut Ui,
    flags: &Flags,
    repo: &Path,
    units: &Units,
    state: &mut State,
    names: &[String],
    preset: &Answers,
) -> Result<()> {
    let order = resolve::closure(units, names)?;
    let answers = ask(ui, flags, units, state, &order, preset)?;
    let plan = plan::build(repo, units, state, &order, &answers)?;
    ops::show_plan(ui, &plan);
    if flags.dry_run {
        return Ok(());
    }
    if !plan.has_work() && order.iter().all(|n| state.installed(n)) {
        ui.line("\nNothing to do.");
        return Ok(());
    }
    if flags.interactive(ui) {
        println!();
        if !dialoguer::Confirm::new().with_prompt("Proceed?").default(true).interact()? {
            bail!("cancelled");
        }
    }
    ui.open_log(&state::state_dir().join("logs"), "install")?;
    ops::apply(ui, repo, units, state, &plan)?;
    ui.line(&format!("\n{} {} unit(s) in place.", ui.green("Done."), plan.units.len()));
    Ok(())
}

/// Answers for every question of `order`: given, then remembered, then
/// asked (or the default without a terminal or with --yes).
fn ask(ui: &mut Ui, flags: &Flags, units: &Units, state: &State, order: &[String], preset: &Answers) -> Result<Answers> {
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
                let i = dialoguer::Select::new()
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
        bail!(
            "this machine is already set up ({}) — use `upgrade`, `install` or `remove`",
            state.repo.as_deref().map(sys::tilde).unwrap_or_default()
        );
    }
    let file: AnswersFile = match answers_file {
        Some(p) => toml::from_str(&std::fs::read_to_string(p).with_context(|| format!("reading {}", p.display()))?)
            .with_context(|| format!("parsing {}", p.display()))?,
        None => AnswersFile::default(),
    };
    let interactive = flags.interactive(ui) && answers_file.is_none();

    // 1. Where.
    let default_dir = sys::home().join("coucou-shell");
    let dir = match (dir_flag, &file.dir, &state.repo) {
        (Some(d), _, _) => d.to_path_buf(),
        (None, Some(d), _) => sys::expand(d),
        (None, None, Some(d)) => d.clone(),
        (None, None, None) if interactive => {
            let answer: String = dialoguer::Input::new()
                .with_prompt("Install coucou-shell in")
                .default(sys::tilde(&default_dir))
                .interact_text()?;
            sys::expand(&answer)
        }
        _ => default_dir,
    };

    ui.heading("Checkout");
    let adopted = dir.join("units").is_dir();
    if adopted {
        ui.ok(&format!("using the existing checkout in {}", sys::tilde(&dir)));
    } else if dir.exists() && std::fs::read_dir(&dir).map(|mut d| d.next().is_some()).unwrap_or(false) {
        bail!("{} exists and is not a coucou-shell checkout — pick another directory", dir.display());
    } else if flags.dry_run {
        ui.line(&format!("  would clone {} into {}", git::url(), sys::tilde(&dir)));
        return Ok(());
    } else {
        ui.run(&format!("clone into {}", sys::tilde(&dir)), std::process::Command::new("git").args(["clone", &git::url()]).arg(&dir))?;
    }
    let repo = std::fs::canonicalize(&dir)?;

    // 2. Which channel.
    let tags = git::release_tags(&repo)?;
    let channel = match (channel_flag, file.channel.as_deref()) {
        (Some(c), _) | (None, Some(c)) => c.to_string(),
        _ if interactive && !tags.is_empty() => {
            let items = [
                format!("stable — releases (latest {})", tags[0]),
                "edge — every commit on the default branch".to_string(),
            ];
            let i = dialoguer::Select::new().with_prompt("Channel").items(&items).default(0).interact()?;
            if i == 0 { "stable".into() } else { "edge".into() }
        }
        _ if tags.is_empty() => "edge".into(),
        _ => "stable".into(),
    };
    match channel.as_str() {
        "stable" if tags.is_empty() => bail!("no release has been published yet — use --channel edge"),
        "stable" => {
            if git::exact_tag(&repo).as_deref() != Some(tags[0].as_str()) {
                let dirty = git::dirty(&repo)?;
                if !dirty.is_empty() {
                    bail!("uncommitted changes in {}:\n  {}\ncommit or stash them first", repo.display(), dirty.join("\n  "));
                }
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
        other => bail!("unknown channel \"{other}\" (stable or edge)"),
    }
    if !flags.dry_run {
        state.repo = Some(repo.clone());
        state.channel = Some(channel.clone());
        state.version = Some(git::describe(&repo));
        state.save()?;
    }

    // 3. What.
    let units = manifest::load_all(&repo)?;
    let (migrated, mut preset) = match migrate(&repo)? {
        Some((u, a)) if state.units.is_empty() => {
            ui.ok(&format!("found the previous manager's state: {} unit(s) carried over", u.len()));
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
                    bail!("answers file: no unit named \"{n}\"");
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

    install_units(ui, flags, &repo, &units, &mut state, &names, &preset)?;
    if !flags.dry_run {
        ui.line(&format!(
            "\ncoucou-shell {} ({channel}) in {}. Log out and back in to start the session.",
            git::describe(&repo),
            sys::tilde(&repo)
        ));
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
            dialoguer::Confirm::new()
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
        dialoguer::MultiSelect::new()
            .with_prompt("Applications (space to toggle, enter to confirm)")
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
                format!(" (you have {})", existing.iter().take(2).cloned().collect::<Vec<_>>().join(", "))
            };
            let items = ["keep mine", "use this one — replaced files are backed up"];
            dialoguer::Select::new()
                .with_prompt(format!("{}: {}{hint}", u.name, u.summary))
                .items(&items)
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
        ui.line(&format!("  {}", ui.dim(&format!("taking: {}", chosen.iter().cloned().collect::<Vec<_>>().join(", ")))));
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

fn short(repo: &Path) -> Result<String> {
    Ok(git::exact_tag(repo).unwrap_or(git::head(repo)?[..12].to_string()))
}

fn require_clean(repo: &Path) -> Result<()> {
    let dirty = git::dirty(repo)?;
    if !dirty.is_empty() {
        bail!(
            "uncommitted changes in {}:\n  {}\ncommit or stash them first",
            repo.display(),
            dirty.join("\n  ")
        );
    }
    Ok(())
}

pub fn channel(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State, new: Option<&str>) -> Result<()> {
    let Some(new) = new else {
        ui.line(&format!("channel  {}", state.channel.as_deref().unwrap_or("none (run init)")));
        ui.line(&format!("version  {}", git::describe(repo)));
        let tags = git::release_tags(repo)?;
        ui.line(&format!("latest   {}", tags.first().map(String::as_str).unwrap_or("no release yet")));
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
            ui.ok("channel: edge — `upgrade` follows the default branch");
        }
        "stable" => ui.ok("channel: stable — `upgrade` moves to the latest release"),
        other => bail!("unknown channel \"{other}\" (stable or edge)"),
    }
    if !flags.dry_run {
        state.channel = Some(new.to_string());
        state.save()?;
    }
    Ok(())
}

pub fn upgrade(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State, to: Option<&str>) -> Result<()> {
    let Some(channel) = state.channel.clone() else {
        bail!("no channel chosen yet — run `cc-pkg-mng init`");
    };
    require_clean(repo)?;
    ui.run("fetch", std::process::Command::new("git").arg("-C").arg(repo).args(["fetch", "--quiet", "--tags", "--force"]))?;
    let before = short(repo)?;

    match channel.as_str() {
        "stable" => {
            let tags = git::release_tags(repo)?;
            let target = match to {
                Some(t) if tags.iter().any(|x| x == t) => t.to_string(),
                Some(t) => bail!("no release named {t} (known: {})", tags.join(", ")),
                None => tags.first().cloned().context("no release has been published yet")?,
            };
            if git::exact_tag(repo).as_deref() == Some(target.as_str()) {
                ui.ok(&format!("already on {target}"));
                return Ok(());
            }
            if flags.dry_run {
                ui.line(&format!("  would move {before} → {target}"));
                return Ok(());
            }
            git::checkout_detached(repo, &target)?;
        }
        "edge" => {
            if to.is_some() {
                bail!("--to picks a release: it only applies to the stable channel");
            }
            if flags.dry_run {
                ui.line("  would fast-forward the default branch");
                return Ok(());
            }
            if git::branch(repo).is_none() {
                git::checkout(repo, &git::default_branch(repo))?;
            }
            git::fast_forward(repo)?;
            if short(repo)? == before {
                ui.ok("already up to date");
                return Ok(());
            }
        }
        other => bail!("unknown channel \"{other}\" in the state"),
    }
    let after = short(repo)?;
    ui.ok(&format!("{before} → {after}"));
    state.previous = Some(before);
    state.version = Some(after);
    state.save()?;
    reapply(ui, flags, repo, state)
}

pub fn rollback(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State) -> Result<()> {
    if state.channel.as_deref() != Some("stable") {
        bail!("rollback moves between releases (stable channel); on edge, check out a commit with git");
    }
    let Some(previous) = state.previous.clone() else {
        bail!("no previous release recorded on this machine");
    };
    require_clean(repo)?;
    let current = short(repo)?;
    if flags.dry_run {
        ui.line(&format!("  would move {current} → {previous}"));
        return Ok(());
    }
    git::checkout_detached(repo, &previous)?;
    ui.ok(&format!("{current} → {previous}"));
    state.previous = Some(current);
    state.version = Some(previous);
    state.save()?;
    reapply(ui, flags, repo, state)
}

/// After the checkout moved: everything installed, plus core units the new
/// version introduced.
fn reapply(ui: &mut Ui, flags: &Flags, repo: &Path, state: &mut State) -> Result<()> {
    let units = manifest::load_all(repo)?;
    let gone: Vec<String> = state.units.keys().filter(|n| !units.contains_key(*n)).cloned().collect();
    for n in &gone {
        ui.warn(&format!("{n} no longer exists in this version; its links are left as they are"));
        state.units.remove(n);
    }
    let mut names: Vec<String> = state.units.keys().cloned().collect();
    for u in units.values().filter(|u| u.layer == Layer::Core && !u.optional) {
        if !names.contains(&u.name) {
            ui.line(&format!("  new in this version: {}", u.name));
            names.push(u.name.clone());
        }
    }
    install_units(ui, flags, repo, &units, state, &names, &Answers::new())
}

/// Change a remembered answer; `install <unit>` then applies it.
pub fn set(ui: &mut Ui, units: &Units, state: &mut State, unit: &str, question: &str, value: &str) -> Result<()> {
    let u = units.get(unit).with_context(|| format!("no unit named \"{unit}\""))?;
    let q = u.questions.iter().find(|q| q.id == question).with_context(|| {
        let ids: Vec<&str> = u.questions.iter().map(|q| q.id.as_str()).collect();
        format!("{unit} has no question \"{question}\" (it has: {})", if ids.is_empty() { "none".into() } else { ids.join(", ") })
    })?;
    if !q.choices.iter().any(|c| c == value) {
        bail!("{unit}.{question} must be one of: {}", q.choices.join(", "));
    }
    let Some(rec) = state.units.get_mut(unit) else {
        bail!("{unit} is not installed — `cc-pkg-mng install {unit}` asks this question");
    };
    rec.answers.insert(question.to_string(), value.to_string());
    state.save()?;
    ui.ok(&format!("{unit}: {} = {value}", q.ask));
    ui.line(&format!("  apply it with: cc-pkg-mng install {unit}"));
    Ok(())
}
