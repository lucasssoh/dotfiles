//! cc-pkg-mng 2 — the coucou-shell package manager.
//! Design: docs/design/cc-pkg-mng-2.md.

mod dev;
mod git;
mod lifecycle;
mod manifest;
mod ops;
mod plan;
mod resolve;
mod state;
mod sys;
mod ui;

use std::collections::BTreeSet;
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
    /// Set up this machine: checkout, channel, units — or adopt an existing
    /// checkout and the previous manager's state.
    Init {
        #[arg(long, value_name = "stable|edge")]
        channel: Option<String>,
        /// Unattended: every answer from a TOML file.
        #[arg(long, value_name = "FILE")]
        answers: Option<PathBuf>,
    },
    /// Show or switch the channel: stable (releases) or edge (every commit).
    Channel { name: Option<String> },
    /// Move to the latest release (stable) or commit (edge), then re-apply.
    Upgrade {
        /// A specific release (stable only).
        #[arg(long, value_name = "vX.Y.Z")]
        to: Option<String>,
    },
    /// Back to the release before the last upgrade (stable only).
    Rollback,
    /// Run Roue, Prisme or Balise built from your working checkout instead of
    /// the release's, until `dev --off` (stable only). No unit: what runs now.
    Dev {
        units: Vec<String>,
        /// Back to the release's binaries: every dev build, or the units named.
        #[arg(long)]
        off: bool,
        /// The checkout to build from (default: the one you are in).
        #[arg(long, value_name = "PATH")]
        from: Option<PathBuf>,
    },
    /// Change an answer (e.g. `set wezterm variant smear`); `install` applies it.
    Set { unit: String, question: String, value: String },
}

fn main() -> ExitCode {
    // `cc-pkg-mng list | head`: stop quietly when the reader goes away,
    // like any Unix tool, instead of panicking on the broken pipe.
    // SAFETY: restoring a signal's default action, before any thread exists.
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
    // The front page and the long version are ours; `-V`, `<command>
    // --help` and `help <command>` stay clap's.
    let args: Vec<String> = std::env::args().skip(1).collect();
    let no_color = args.iter().any(|a| a == "--no-color");
    let bare: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--no-color").collect();
    match bare.as_slice() {
        [] | ["-h"] | ["--help"] | ["help"] => {
            front_page(&Ui::new(no_color, false, false));
            return ExitCode::SUCCESS;
        }
        ["--version"] | ["version"] => {
            long_version(&Ui::new(no_color, false, false));
            return ExitCode::SUCCESS;
        }
        _ => {}
    }
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
    let flags = lifecycle::Flags { dry_run: cli.dry_run, yes: cli.yes };
    if let Cmd::Init { channel, answers } = &cli.cmd {
        return lifecycle::init(ui, &flags, cli.dir.as_deref(), channel.as_deref(), answers.as_deref());
    }

    let mut state = State::load()?;
    let repo = resolve_repo(cli.dir.as_deref(), &state)?;
    let units = manifest::load_all(&repo)?;
    if state.repo.as_deref() != Some(repo.as_path()) && !cli.dry_run {
        state.repo = Some(repo.clone());
        state.save()?;
    }

    match &cli.cmd {
        Cmd::Init { .. } => unreachable!(),
        Cmd::List { installed, layer } => list(ui, &units, &state, *installed, layer.as_deref()),
        Cmd::Info { unit } => info(ui, &units, &state, unit),
        Cmd::Status => status(ui, &repo, &units, &state),
        Cmd::Install { units: names } => {
            lifecycle::install_units(ui, &flags, &repo, &units, &mut state, names, &lifecycle::Answers::new())
        }
        Cmd::Remove { units: names } => {
            if !cli.dry_run {
                ui.open_log(&state::state_dir().join("logs"), "remove")?;
            }
            ops::remove(ui, &units, &mut state, names, cli.dry_run)
        }
        Cmd::Channel { name } => lifecycle::channel(ui, &flags, &repo, &mut state, name.as_deref()),
        Cmd::Upgrade { to } => lifecycle::upgrade(ui, &flags, &repo, &mut state, to.as_deref()),
        Cmd::Rollback => lifecycle::rollback(ui, &flags, &repo, &mut state),
        Cmd::Dev { units: names, off, from } => dev::run(ui, &flags, &state, &repo, from.as_deref(), names, *off),
        Cmd::Set { unit, question, value } => lifecycle::set(ui, &units, &mut state, unit, question, value),
    }
}

/// `cc-pkg-mng`, `--help`: the logo, then the commands by what they are
/// for. Each command's own options are in `cc-pkg-mng <command> --help`.
fn front_page(ui: &Ui) {
    let groups: [(&str, &[(&str, &str)]); 5] = [
        ("everyday", &[
            ("upgrade", "move to the latest release, then re-apply"),
            ("status", "what is installed, and whether it is healthy"),
            ("install <unit>…", "add units, and what they need"),
            ("remove <unit>…", "unlink, and put back what they replaced"),
        ]),
        ("releases", &[
            ("channel [stable|edge]", "which updates this machine follows"),
            ("rollback", "back to the release before the last upgrade"),
        ]),
        ("explore", &[
            ("list", "every unit"),
            ("info <unit>", "what a unit contains"),
        ]),
        ("working on the shell", &[
            ("dev <unit>…", "run an app built from your checkout (stable)"),
            ("set <unit> <q> <value>", "change an answer; install applies it"),
        ]),
        ("first time", &[("init", "set up this machine")]),
    ];
    println!();
    println!(" {}   cc-pkg-mng {}", ui.bold(ui::LOGO[0]), env!("CARGO_PKG_VERSION"));
    println!(" {}   {}", ui.bold(ui::LOGO[1]), ui.dim("installs and updates coucou-shell"));
    for (group, cmds) in groups {
        println!("\n  {}", ui.dim(group));
        for (cmd, what) in cmds {
            println!("    {}{}", ui.bold(&format!("{cmd:<24}")), what);
        }
    }
    println!(
        "\n  {} {}   {} {}   {} {}   {} {}",
        ui.bold("-n"),
        ui.dim("dry run"),
        ui.bold("-y"),
        ui.dim("take defaults"),
        ui.bold("-q"),
        ui.dim("quiet"),
        ui.bold("--verbose"),
        ui.dim("every line")
    );
    println!("  cc-pkg-mng <command> --help {}", ui.dim("for one command's options"));
    println!();
}

/// `--version`: the manager's version, and what this machine follows.
/// `-V` keeps the bare line, for scripts.
fn long_version(ui: &Ui) {
    let state = State::load().unwrap_or_default();
    let repo = state.repo.clone().filter(|r| r.join("units").is_dir());
    let channel = state.channel.clone().unwrap_or_else(|| "not set up".into());
    let shell = repo.as_deref().map(git::describe).unwrap_or_else(|| "—".into());
    println!();
    println!(" {}   cc-pkg-mng {}", ui.bold(ui::LOGO[0]), ui.bold(env!("CARGO_PKG_VERSION")));
    println!(" {}   coucou-shell {} · {}", ui.bold(ui::LOGO[1]), ui.bold(&shell), ui.green(&channel));
    println!();
    if let Some(repo) = &repo {
        println!("  {}  {}", ui.dim("checkout "), sys::tilde(repo));
        if channel == "stable" {
            let tags = git::release_tags(repo).unwrap_or_default();
            match tags.first() {
                Some(latest) if git::exact_tag(repo).as_deref() == Some(latest.as_str()) => {
                    println!("  {}  {}  {}", ui.dim("latest   "), latest, ui.green("up to date"));
                }
                Some(latest) => {
                    println!("  {}  {}  {}", ui.dim("latest   "), latest, ui.yellow("cc-pkg-mng upgrade gets it"));
                }
                None => {}
            }
        } else if let Some(b) = git::branch(repo) {
            println!("  {}  {}", ui.dim("follows  "), b);
        }
        println!("  {}  {} installed", ui.dim("units    "), state.units.len());
    }
    for (unit, rec) in dev::active() {
        println!("  {}  {} {}", ui.dim("dev      "), ui.yellow(&unit), ui.dim(&format!("from {}", sys::tilde(&rec.checkout))));
    }
    println!();
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

fn info(ui: &mut Ui, units: &Units, state: &State, name: &str) -> Result<()> {
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
    ui.line(&format!(
        "{} {}",
        ui.bold("chan"),
        state.channel.as_deref().unwrap_or("none — run `cc-pkg-mng init`")
    ));
    ui.line(&format!("{} {}", ui.bold("state"), sys::tilde(&state::state_dir())));

    let dev_builds = dev::active();
    if !dev_builds.is_empty() {
        ui.heading("Dev builds");
        for (name, rec) in &dev_builds {
            ui.line(&format!("  {:<16} {} {}", name, sys::tilde(&rec.checkout), ui.dim(&rec.revision)));
        }
        ui.line(&format!("  {}", ui.dim("back to the release: cc-pkg-mng dev --off")));
    }
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
            .filter(|l| !dev::is_dev_link(&l.dst) && plan::link_state(&l.src, &l.dst) != plan::LinkState::Ok)
            .count();
        let health = if broken > 0 {
            ui.red(&format!("{broken} link(s) broken"))
        } else if dev_builds.iter().any(|(n, _)| n == name) {
            ui.yellow("dev build running")
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
