//! cc-pkg-mng 2 — the coucou-shell package manager.
//! Design: docs/design/cc-pkg-mng-2.md.

mod dev;
mod dnf;
mod git;
mod lifecycle;
mod logo;
mod manifest;
mod ops;
mod pipeline;
mod plan;
mod resolve;
mod state;
mod sys;
mod ui;

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Result, bail};
use clap::{Parser, Subcommand};

use manifest::{Layer, Units};
use state::State;
use ui::{Stop, Ui};

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
    /// Let dnf remove or replace packages that block the transaction.
    #[arg(long, global = true)]
    allow_erasing: bool,
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
            ui.log(&format!("error: {e:#}"));
            ui.report(&e);
            ExitCode::FAILURE
        }
    }
}

fn run(cli: &Cli, ui: &mut Ui) -> Result<()> {
    let flags = lifecycle::Flags { dry_run: cli.dry_run, yes: cli.yes, allow_erasing: cli.allow_erasing, again: false };
    // One run changing the machine at a time.
    let changes = !cli.dry_run && !matches!(cli.cmd, Cmd::List { .. } | Cmd::Info { .. } | Cmd::Status);
    let _lock = if changes { Some(state::Lock::take(command_name(&cli.cmd))?) } else { None };
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
        Cmd::Install { units: names } => lifecycle::install_units(ui, &flags, &repo, &mut state, names, &lifecycle::Answers::new()),
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

fn command_name(cmd: &Cmd) -> &'static str {
    match cmd {
        Cmd::List { .. } => "list",
        Cmd::Info { .. } => "info",
        Cmd::Install { .. } => "install",
        Cmd::Remove { .. } => "remove",
        Cmd::Status => "status",
        Cmd::Init { .. } => "init",
        Cmd::Channel { .. } => "channel",
        Cmd::Upgrade { .. } => "upgrade",
        Cmd::Rollback => "rollback",
        Cmd::Dev { .. } => "dev",
        Cmd::Set { .. } => "set",
    }
}

/// The manager's own version: the RPM's when it runs from it, the crate's
/// for a build.
fn manager_version() -> String {
    if sys::running_from_rpm()
        && let Some(v) = sys::rpm_version("cc-pkg-mng") {
            return v;
        }
    format!("{} (build)", env!("CARGO_PKG_VERSION"))
}

/// `cc-pkg-mng`, `--help`: the bird, then the commands by what they are
/// for. Each command's own options are in `cc-pkg-mng <command> --help`.
fn front_page(ui: &Ui) {
    let groups: [(&str, &[(&str, &str)]); 5] = [
        ("everyday", &[
            ("upgrade", "move to the latest release"),
            ("status", "what is installed, and whether it is healthy"),
            ("install <unit>…", "add units, and what they need"),
            ("remove <unit>…", "unlink, and put back what they replaced"),
        ]),
        ("releases", &[
            ("channel [stable|edge]", "which updates this machine follows"),
            ("rollback", "back to the previous release"),
        ]),
        ("explore", &[
            ("list", "every unit"),
            ("info <unit>", "what a unit contains"),
        ]),
        ("working on the shell", &[
            ("dev <unit>…", "run an app built from a checkout (stable)"),
            ("set <unit> <q> <value>", "change an answer; install applies it"),
        ]),
        ("first time", &[("init", "set up this machine")]),
    ];
    println!();
    let head = [String::new(), format!("{} {}", ui.bold("cc-pkg-mng"), manager_version()), ui.dim("installs and updates coucou-shell")];
    for row in logo::beside(&logo::SMALL, |s| ui.bold(s), &head) {
        println!("{row}");
    }
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

/// What `--version` and `status` say about the machine.
struct Facts {
    shell: String,
    channel: Option<String>,
    repo: Option<PathBuf>,
    /// The checkout's release ("2.6.0") on stable.
    release: Option<String>,
    latest: Option<String>,
    /// (rpm, installed version) of every unit's Rust app, on stable.
    apps: Vec<(String, Option<String>)>,
    units: usize,
    /// (unit, what is wrong, broken: red rather than yellow)
    unit_issues: Vec<(String, String, bool)>,
    dev: Vec<(String, dev::Record)>,
    upgrading: Option<state::Upgrading>,
}

impl Facts {
    fn gather(state: &State) -> Facts {
        let repo = state.repo.clone().filter(|r| r.join("units").is_dir());
        let units = repo.as_deref().and_then(|r| manifest::load_all(r).ok()).unwrap_or_default();
        let release = repo.as_deref().and_then(|r| plan::release_of(r, state));
        let apps = match &release {
            Some(_) => {
                let rpms: Vec<&str> = units
                    .values()
                    .filter(|u| state.installed(&u.name))
                    .filter_map(|u| u.binaries.as_ref().map(|b| b.rpm.as_str()))
                    .collect();
                let versions = sys::rpm_versions(&rpms);
                rpms.into_iter().map(str::to_string).zip(versions).collect()
            }
            None => Vec::new(),
        };
        let dev = dev::active();
        let mut unit_issues = Vec::new();
        if let Some(r) = &repo {
            for (name, rec) in &state.units {
                let Some(u) = units.get(name) else {
                    unit_issues.push((name.clone(), "no longer in this version".into(), false));
                    continue;
                };
                let broken: Vec<&state::LinkRecord> = rec
                    .links
                    .iter()
                    .filter(|l| !dev::is_dev_link(&l.dst) && plan::link_state(&l.src, &l.dst) != plan::LinkState::Ok)
                    .collect();
                if let Some(first) = broken.first() {
                    let what = match broken.len() {
                        1 => format!("{} points elsewhere", sys::tilde(&first.dst)),
                        n => format!("{n} links point elsewhere"),
                    };
                    unit_issues.push((name.clone(), what, true));
                    continue;
                }
                let fp = plan::with_answers(sys::fingerprint(r, &plan::fingerprint_paths(r, u)), &rec.answers);
                if fp != rec.fingerprint && !dev.iter().any(|(n, _)| n == name) {
                    unit_issues.push((name.clone(), "changed, not applied".into(), false));
                }
            }
        }
        Facts {
            shell: repo.as_deref().map(git::describe).unwrap_or_else(|| "—".into()),
            channel: state.channel.clone(),
            latest: repo.as_deref().and_then(|r| git::release_tags(r).ok()).and_then(|t| t.into_iter().next()),
            repo,
            release,
            apps,
            units: state.units.len(),
            unit_issues,
            dev,
            upgrading: state.upgrading.clone(),
        }
    }

    /// Apps whose package is not at the checkout's release.
    fn behind(&self) -> Vec<&(String, Option<String>)> {
        match &self.release {
            Some(v) => self.apps.iter().filter(|(_, have)| have.as_deref() != Some(v.as_str())).collect(),
            None => Vec::new(),
        }
    }

    fn healthy(&self) -> bool {
        self.behind().is_empty() && self.unit_issues.is_empty() && self.upgrading.is_none()
    }

    /// The lines beside the big bird.
    fn card(&self, ui: &Ui) -> Vec<String> {
        let info = |k: &str, v: String| format!("{}{v}", ui.dim(&format!("{k:<11}")));
        let title = format!("coucou-shell {}", self.shell);
        let mut lines = vec![ui.bold(&title), ui.dim(&"─".repeat(ui::width_of(&title)))];
        lines.push(info("channel", match self.channel.as_deref() {
            Some(c) => ui.green(c),
            None => ui.yellow("not set up"),
        }));
        if let Some(r) = &self.repo {
            lines.push(info("checkout", sys::tilde(r)));
        }
        lines.push(info("manager", format!("cc-pkg-mng {}", manager_version())));
        if let Some(v) = &self.release {
            let behind = self.behind();
            lines.push(info("packages", if behind.is_empty() {
                format!("{} {} all on {v}", self.apps.len(), ui.dim("·"))
            } else {
                format!("{} {} still behind {v}", ui.yellow("!"), behind.len())
            }));
        } else if self.channel.as_deref() == Some("edge") {
            lines.push(info("apps", "built from the checkout".into()));
        }
        let broken = self.unit_issues.iter().filter(|i| i.2).count();
        let pending = self.unit_issues.len() - broken;
        lines.push(info("units", match (broken, pending) {
            (0, 0) => format!("{} {} up to date", self.units, ui.dim("·")),
            (0, p) => format!("{} {} {} {} not applied", self.units, ui.dim("·"), ui.yellow("!"), p),
            (b, 0) => format!("{} {} {} {} broken", self.units, ui.dim("·"), ui.red("✗"), b),
            (b, p) => format!("{} {} {} {} not applied {} {} broken", self.units, ui.dim("·"), ui.yellow("!"), p, ui.red("✗"), b),
        }));
        for (unit, rec) in &self.dev {
            lines.push(info("dev", format!("{unit} {}", ui.dim(&format!("from {}", sys::tilde(&rec.checkout))))));
        }
        if let Some(u) = &self.upgrading {
            lines.push(info("unfinished", format!("{} {} {} → {}", ui.yellow("!"), u.kind, u.from, u.to)));
        }
        match (self.channel.as_deref(), &self.latest) {
            (Some("stable"), Some(latest)) if Some(latest.trim_start_matches('v')) == self.release.as_deref() => {
                lines.push(info("latest", format!("{latest} {}", ui.green("up to date"))));
            }
            (Some("stable"), Some(latest)) => lines.push(info("latest", format!("{} {}", ui.bold(latest), ui.dim("· cc-pkg-mng upgrade")))),
            (Some("edge"), _) => {
                if let Some(b) = self.repo.as_deref().and_then(git::branch) {
                    lines.push(info("follows", b));
                }
            }
            _ => {}
        }
        let v = sys::rpm_versions(&["hyprland", "quickshell"]);
        let mut sys_line = Vec::new();
        if let Some(f) = sys::fedora() {
            sys_line.push(format!("Fedora {f}"));
        }
        if let Some(h) = &v[0] {
            sys_line.push(format!("Hyprland {h}"));
        }
        if let Some(q) = &v[1] {
            sys_line.push(format!("quickshell {q}"));
        }
        lines.push(ui.dim(&sys_line.join(" · ")));
        lines
    }
}

/// `--version`: the big bird and what this machine runs. `-V` keeps the
/// bare line, for scripts.
fn long_version(ui: &Ui) {
    let state = State::load().unwrap_or_default();
    let facts = Facts::gather(&state);
    println!();
    for row in logo::beside(logo::big(), |s| ui.bold(s), &facts.card(ui)) {
        println!("{row}");
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
        bail!(Stop::new("No coucou-shell checkout known.").hint("set up this machine", "cc-pkg-mng init").hint("or name one", "--dir PATH"));
    };
    std::fs::canonicalize(&dir).map_err(|_| Stop::new(format!("{} does not exist.", dir.display())).hint("name another", "--dir PATH").into())
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
                extra.push_str(" · optional");
            }
            if u.layer == Layer::Apps && u.default == Some(false) {
                extra.push_str(" · not default");
            }
            let summary = ui::truncate(&format!("{}{extra}", u.summary), width.saturating_sub(22).max(20));
            ui.line(&format!("  {mark} {:<16} {}", u.name, ui.dim(&summary)));
        }
    }
    Ok(())
}

fn info(ui: &mut Ui, units: &Units, state: &State, name: &str) -> Result<()> {
    let u = units.get(name).ok_or_else(|| Stop::new(format!("No unit named {name}.")).hint("every unit", "cc-pkg-mng list"))?;
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
        ui.line(&format!("  binaries:  {} · RPM {} on stable, built from {} on edge", b.bins.join(", "), b.rpm, b.source));
    }
    if let Some(ask) = &u.ask {
        ui.line(&format!("  optional:  {ask}"));
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
            (None, Some(from)) => format!("  · not automated yet, done by {from}"),
            (None, None) => "  · not automated yet".to_string(),
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

/// `status`: the big bird when all is well; otherwise the small one, and
/// what needs attention under it.
fn status(ui: &mut Ui, _repo: &Path, _units: &Units, state: &State) -> Result<()> {
    let facts = Facts::gather(state);
    if facts.healthy() {
        ui.line("");
        for row in logo::beside(logo::big(), |s| ui.bold(s), &facts.card(ui)) {
            ui.line(&row);
        }
        ui.line("");
        return Ok(());
    }
    let mut head = vec![
        format!("{} {}", ui.bold("coucou-shell"), ui.bold(&facts.shell)),
        format!(
            "{} {} {}",
            ui.green(facts.channel.as_deref().unwrap_or("not set up")),
            ui.dim("·"),
            facts.repo.as_deref().map(sys::tilde).unwrap_or_default()
        ),
        String::new(),
    ];
    let behind = facts.behind();
    if let Some(u) = &facts.upgrading {
        head.push(format!("{} {}", ui.yellow("!"), ui.bold(&format!("{} {} → {} unfinished", u.kind, u.from, u.to))));
        head.push(format!("  {}  {}", ui.dim("finish"), ui.bold(&format!("cc-pkg-mng {}", if u.kind == "rollback" { "rollback" } else { "upgrade" }))));
    } else if !behind.is_empty() {
        head.push(format!("{} {}", ui.yellow("!"), ui.bold(&format!("packages behind {}", facts.release.as_deref().map(|v| format!("v{v}")).unwrap_or_default()))));
        head.push(format!("  {}  {}", ui.dim("finish"), ui.bold("cc-pkg-mng upgrade")));
    } else {
        head.push(format!("{} {}", ui.yellow("!"), ui.bold(&ops::plural(facts.unit_issues.len(), "unit needs attention", "units need attention"))));
        head.push(format!("  {}  {}", ui.dim("repair"), ui.bold("cc-pkg-mng upgrade")));
    }
    ui.line("");
    for row in logo::beside(&logo::SMALL, |s| ui.bold(s), &head) {
        ui.line(&row);
    }
    let label = |ui: &Ui, s: &str| ui.dim(&format!("  {s:<11}"));
    if !behind.is_empty() {
        let names: Vec<&str> = behind.iter().map(|(n, _)| n.as_str()).collect();
        let at: BTreeSet<&str> = behind.iter().filter_map(|(_, v)| v.as_deref()).collect();
        let at = if at.len() == 1 { format!("on {}", at.iter().next().unwrap()) } else { "behind".into() };
        ui.line("");
        ui.line(&format!("{}{} {} {}   {}", label(ui, "packages"), ui.yellow("!"), behind.len(), at, ui.dim(&names.join(" "))));
        let ok = facts.apps.len() - behind.len();
        if ok > 0 {
            ui.line(&format!("{}{} {ok} on {}", label(ui, ""), ui.green("✓"), facts.release.as_deref().unwrap_or("")));
        }
    }
    if !facts.unit_issues.is_empty() {
        ui.line("");
        let fine = facts.units.saturating_sub(facts.unit_issues.len());
        ui.line(&format!("{}{} {fine} up to date", label(ui, "units"), ui.green("✓")));
        let w = facts.unit_issues.iter().map(|i| i.0.chars().count()).max().unwrap_or(0);
        for (name, what, broken) in &facts.unit_issues {
            let mark = if *broken { ui.red("✗") } else { ui.yellow("!") };
            ui.line(&format!("{}{mark} {name:<w$}  {}", label(ui, ""), ui.dim(what)));
        }
    }
    if !facts.dev.is_empty() {
        ui.line("");
        for (i, (name, rec)) in facts.dev.iter().enumerate() {
            let l = if i == 0 { "dev" } else { "" };
            ui.line(&format!("{}{name}  {}", label(ui, l), ui.dim(&format!("from {} · {}", sys::tilde(&rec.checkout), rec.revision))));
        }
    }
    ui.line("");
    Ok(())
}
