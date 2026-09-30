//! cc-pkg-mng 2 — the coucou-shell package manager.
//! Design: docs/design/cc-pkg-mng-2.md.

mod manifest;
mod ops;
mod plan;
mod resolve;
mod state;
mod sys;
mod ui;

use std::collections::{BTreeMap, BTreeSet};
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};

use manifest::{Layer, Units};
use state::State;
use ui::Ui;

#[derive(Parser)]
#[command(name = "cc-pkg-mng", version, about = "The coucou-shell package manager")]
struct Cli {
    /// The coucou-shell checkout to use (remembered for next time).
    #[arg(long, global = true, value_name = "PATH")]
    dir: Option<PathBuf>,
    /// Show what would happen; change nothing.
    #[arg(short = 'n', long = "dry-run", global = true)]
    dry_run: bool,
    /// Take every default: no questions, no confirmation.
    #[arg(short = 'y', long, global = true)]
    yes: bool,
    /// Warnings and errors only.
    #[arg(short, long, global = true)]
    quiet: bool,
    /// Stream every command's output.
    #[arg(long, global = true)]
    verbose: bool,
    #[arg(long, global = true)]
    no_color: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// List units.
    List {
        /// Only installed units.
        #[arg(long)]
        installed: bool,
        #[arg(long, value_name = "core|apps|configs")]
        layer: Option<String>,
    },
    /// Show what a unit contains.
    Info { unit: String },
    /// Install units (and what they require).
    Install {
        #[arg(required = true)]
        units: Vec<String>,
    },
    /// Remove units: unlink, restore what they replaced.
    Remove {
        #[arg(required = true)]
        units: Vec<String>,
    },
    /// Installed units and their health.
    Status,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let mut ui = Ui::new(cli.no_color, cli.quiet, cli.verbose);
    match run(&cli, &mut ui) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{} {e:#}", ui.red("error:"));
            ExitCode::FAILURE
        }
    }
}

fn run(cli: &Cli, ui: &mut Ui) -> Result<()> {
    let mut state = State::load()?;
    let repo = resolve_repo(cli.dir.as_deref(), &state)?;
    let units = manifest::load_all(&repo)?;
    if state.repo.as_deref() != Some(repo.as_path()) && !cli.dry_run {
        state.repo = Some(repo.clone());
        state.save()?;
    }

    match &cli.cmd {
        Cmd::List { installed, layer } => list(ui, &units, &state, *installed, layer.as_deref()),
        Cmd::Info { unit } => info(ui, &repo, &units, &state, unit),
        Cmd::Status => status(ui, &repo, &units, &state),
        Cmd::Install { units: names } => {
            let order = resolve::closure(&units, names)?;
            let answers = ask(ui, cli, &units, &state, &order)?;
            let plan = plan::build(&repo, &units, &state, &order, &answers)?;
            ops::show_plan(ui, &plan);
            if cli.dry_run {
                return Ok(());
            }
            if !plan.has_work() && order.iter().all(|n| state.installed(n)) {
                ui.line("\nNothing to do.");
                return Ok(());
            }
            if !cli.yes && ui.tty && std::io::stdin().is_terminal() {
                println!();
                let go = dialoguer::Confirm::new().with_prompt("Proceed?").default(true).interact()?;
                if !go {
                    bail!("cancelled");
                }
            }
            ui.open_log(&state::state_dir().join("logs"), "install")?;
            ops::apply(ui, &repo, &units, &mut state, &plan)?;
            ui.line(&format!("\n{} {} unit(s) in place.", ui.green("Done."), plan.units.len()));
            Ok(())
        }
        Cmd::Remove { units: names } => {
            if !cli.dry_run {
                ui.open_log(&state::state_dir().join("logs"), "remove")?;
            }
            ops::remove(ui, &units, &mut state, names, cli.dry_run)
        }
    }
}

/// --dir, then $COUCOU_SHELL_DIR, then the remembered checkout, then the
/// current directory if it is one.
fn resolve_repo(flag: Option<&Path>, state: &State) -> Result<PathBuf> {
    let candidate = flag
        .map(Path::to_path_buf)
        .or_else(|| std::env::var_os("COUCOU_SHELL_DIR").map(PathBuf::from))
        .or_else(|| state.repo.clone())
        .or_else(|| std::env::current_dir().ok().filter(|d| d.join("units").is_dir()));
    let Some(dir) = candidate else {
        bail!("no coucou-shell checkout known — pass --dir PATH");
    };
    std::fs::canonicalize(&dir).with_context(|| format!("{} does not exist", dir.display()))
}

/// Answers for every question of `order`: remembered ones, then asked
/// (or defaults with --yes / without a terminal).
fn ask(
    ui: &mut Ui,
    cli: &Cli,
    units: &Units,
    state: &State,
    order: &[String],
) -> Result<BTreeMap<String, BTreeMap<String, String>>> {
    let interactive = !cli.yes && ui.tty && std::io::stdin().is_terminal();
    let mut all = BTreeMap::new();
    for name in order {
        let mut answers = state.units.get(name).map(|u| u.answers.clone()).unwrap_or_default();
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

fn list(ui: &mut Ui, units: &Units, state: &State, installed_only: bool, layer: Option<&str>) -> Result<()> {
    let width = ui::terminal_width();
    for l in [Layer::Core, Layer::Apps, Layer::Configs] {
        if layer.is_some_and(|x| x != l.to_string()) {
            continue;
        }
        let rows: Vec<_> = units
            .values()
            .filter(|u| u.layer == l && (!installed_only || state.installed(&u.name)))
            .collect();
        if rows.is_empty() {
            continue;
        }
        ui.heading(&l.to_string());
        for u in rows {
            let mark = if state.installed(&u.name) { ui.green("●") } else { ui.dim("○") };
            let mut extra = String::new();
            if u.optional {
                extra.push_str(" (optional)");
            }
            if u.layer == Layer::Apps && u.default == Some(false) {
                extra.push_str(" (not default)");
            }
            let summary = ui::truncate(&format!("{}{extra}", u.summary), width.saturating_sub(22).max(20));
            ui.line(&format!("  {mark} {:<16} {}", u.name, ui.dim(&summary)));
        }
    }
    Ok(())
}

fn info(ui: &mut Ui, repo: &Path, units: &Units, state: &State, name: &str) -> Result<()> {
    let u = units.get(name).with_context(|| format!("no unit named \"{name}\""))?;
    ui.heading(&format!("{} ({})", u.name, u.layer));
    ui.line(&format!("  {}", u.summary));
    ui.line(&format!("  installed: {}", if state.installed(name) { "yes" } else { "no" }));
    if !u.requires.is_empty() {
        ui.line(&format!("  requires:  {}", u.requires.join(", ")));
    }
    if !u.packages.dnf.is_empty() {
        ui.line(&format!("  packages:  {}", u.packages.dnf.join(" ")));
    }
    if !u.packages.copr.is_empty() {
        ui.line(&format!("  coprs:     {}", u.packages.copr.join(" ")));
    }
    if let Some(b) = &u.binaries {
        ui.line(&format!("  binaries:  {} — RPM {} on stable, built from {} on edge", b.bins.join(", "), b.rpm, b.source));
    }
    if let Some(ask) = &u.ask {
        ui.line(&format!("  optional:  asked at init: \"{ask}\""));
    }
    for (src, dst) in &u.links {
        let cond = u.link_condition(src).map(|c| format!("  (if {c})")).unwrap_or_default();
        ui.line(&format!("  link       {dst} → {src}{cond}"));
    }
    for (src, dst) in &u.files {
        ui.line(&format!("  file       {dst} ← {src}"));
    }
    for s in &u.services.user {
        ui.line(&format!("  service    {s} (user)"));
    }
    for s in &u.services.system {
        ui.line(&format!("  service    {s} (system)"));
    }
    for q in &u.questions {
        ui.line(&format!("  question   {} [{}], default {}", q.ask, q.choices.join("|"), q.default));
    }
    for h in &u.hooks {
        let how = match (&h.run, &h.from) {
            (Some(_), _) => String::new(),
            (None, Some(from)) => format!("  — not extracted yet, done by {from}"),
            (None, None) => "  — not extracted yet".to_string(),
        };
        let who = match h.run_as {
            manifest::RunAs::User => "user",
            manifest::RunAs::Root => "root",
        };
        ui.line(&format!("  hook       {} ({who}): {}{how}", h.name, h.does));
    }
    for c in &u.verify.commands {
        ui.line(&format!("  verify     {c}"));
    }
    let _ = repo;
    Ok(())
}

fn status(ui: &mut Ui, repo: &Path, units: &Units, state: &State) -> Result<()> {
    let rev = std::process::Command::new("git")
        .args(["-C", &repo.to_string_lossy(), "describe", "--tags", "--always", "--dirty"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    ui.line(&format!("{}  {} {}", ui.bold("repo"), repo.display(), ui.dim(&rev)));
    ui.line(&format!("{} {}", ui.bold("state"), sys::tilde(&state::state_dir())));

    if state.units.is_empty() {
        ui.line("\nNo unit installed through cc-pkg-mng 2 yet.");
        return Ok(());
    }
    ui.heading("Installed");
    let mut unknown = BTreeSet::new();
    for (name, rec) in &state.units {
        let Some(u) = units.get(name) else {
            unknown.insert(name.clone());
            continue;
        };
        let fp = plan::with_answers(sys::fingerprint(repo, &plan::fingerprint_paths(repo, u)), &rec.answers);
        let broken = rec
            .links
            .iter()
            .filter(|l| plan::link_state(&l.src, &l.dst) != plan::LinkState::Ok)
            .count();
        let health = if broken > 0 {
            ui.red(&format!("{broken} link(s) broken"))
        } else if fp != rec.fingerprint {
            ui.yellow("changed since installed")
        } else {
            ui.green("up to date")
        };
        ui.line(&format!("  {:<16} {health}", name));
    }
    for n in unknown {
        ui.warn(&format!("{n}: installed, but no such unit in this checkout any more"));
    }
    Ok(())
}
