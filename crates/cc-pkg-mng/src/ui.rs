//! Terminal output, and running external commands with a live detail line.
//!
//! Commands run with stdout/stderr piped (never on the terminal), so dnf,
//! cargo and friends drop their own progress bars; every line goes to the
//! log, and on a terminal the latest one is shown dimmed under the step,
//! escape codes stripped, `\r` redraws collapsed, cut to the current width.
//! stdin is closed: nothing a command runs can wait for an answer.

use std::collections::VecDeque;
use std::fmt;
use std::fs::File;
use std::io::{BufRead, BufReader, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

pub struct Ui {
    pub color: bool,
    pub quiet: bool,
    pub verbose: bool,
    pub tty: bool,
    /// Off the live rail but on a static one (init's questions): steps
    /// print with the rail's bar in front.
    pub rail: bool,
    log: Option<(PathBuf, File)>,
    board: Option<Board>,
}

// ───────────────────────────── errors ─────────────────────────────

/// An error with its way out: a title, a few lines of detail, and
/// `(what, command)` hints. main prints it as
///
/// ```text
///  ✗ Uncommitted changes in ~/coucou-shell.
///    M config/hyprland/hypr/hyprland.lua
///    commit or stash   git -C ~/coucou-shell stash
/// ```
#[derive(Debug, Default)]
pub struct Stop {
    pub warn: bool,
    pub title: String,
    pub detail: Vec<String>,
    pub hints: Vec<(String, String)>,
}

impl Stop {
    pub fn new(title: impl Into<String>) -> Stop {
        Stop { title: title.into(), ..Default::default() }
    }
    pub fn detail(mut self, line: impl Into<String>) -> Stop {
        self.detail.push(line.into());
        self
    }
    pub fn hint(mut self, what: impl Into<String>, command: impl Into<String>) -> Stop {
        self.hints.push((what.into(), command.into()));
        self
    }
}

impl fmt::Display for Stop {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.title)?;
        for d in &self.detail {
            write!(f, "\n  {d}")?;
        }
        for (what, cmd) in &self.hints {
            write!(f, "\n  {what}: {cmd}")?;
        }
        Ok(())
    }
}

impl std::error::Error for Stop {}

/// The failure is already on screen (the board's closing line said it):
/// exit 1 without printing anything more.
#[derive(Debug)]
pub struct Shown;

impl fmt::Display for Shown {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("failed")
    }
}

impl std::error::Error for Shown {}

/// A command that exited non-zero, with what it printed (for dnf's
/// problems to be read back).
#[derive(Debug)]
pub struct CmdFailed {
    pub label: String,
    pub status: ExitStatus,
    pub output: Vec<String>,
}

impl fmt::Display for CmdFailed {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.status.code() {
            Some(c) => write!(f, "{} failed (exit {c})", self.label),
            None => write!(f, "{} was interrupted", self.label),
        }
    }
}

impl std::error::Error for CmdFailed {}

// ───────────────────────────── the rail ─────────────────────────────
//
// While work runs on a terminal, the output is a rail redrawn in place:
//
//    ┌  upgrade v2.5.0 → v2.6.0                         0:41
//    │
//    ◇  check · published                               0:04
//    ◆  packages
//    │    ✓ cc-pkg-mng 2.6.0
//    │    ⠼ dnf upgrade  6/9  roue-2.6.0-1.fc45
//    │      ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱
//    ○  units · 4
//    └
//
// Every phase is listed from the start (○), the running one unfolds (◆),
// finished ones fold to one line (◇), a failed one stays open (■) with the
// last lines of its command. In the units phase each unit is an item: the
// running one shows its steps, finished ones share a line. Off a terminal,
// with --verbose or -q, there is no rail and output is one line per step,
// which is also what the log gets.

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Mark {
    Todo,
    Run,
    Done,
    Skip,
    Warn,
    Fail,
}

struct Step {
    label: String,
    mark: Mark,
    took: Option<u64>,
    /// 0: a step of the phase (or an item, in the units phase); 1: a step
    /// of the current item.
    depth: u8,
    /// The latest line the running command printed.
    detail: String,
    /// A `[ n/m]` counter found in that line (dnf prints them).
    count: Option<(u64, u64)>,
    started: Instant,
}

struct Phase {
    name: String,
    note: String,
    mark: Mark,
    steps: Vec<Step>,
    started: Option<Instant>,
    took: Option<u64>,
    /// The last lines of the command that failed.
    tail: Vec<String>,
    /// Index of the running item (units phase).
    item: Option<usize>,
}

struct Board {
    title: String,
    phases: Vec<Phase>,
    current: Option<usize>,
    start: Instant,
    /// Rows drawn last time, to move back over them.
    drawn: usize,
    /// The closing line, once the work is over.
    close: Option<(Mark, String, Vec<String>)>,
}

impl Board {
    fn phase(&mut self) -> Option<&mut Phase> {
        let i = self.current?;
        self.phases.get_mut(i)
    }

    fn finish_current(&mut self) {
        if let Some(p) = self.phase() {
            p.end_item();
            if p.mark == Mark::Run {
                p.mark = if p.steps.iter().any(|s| s.mark == Mark::Fail) {
                    Mark::Fail
                } else if p.steps.iter().any(|s| s.mark == Mark::Warn) {
                    Mark::Warn
                } else {
                    Mark::Done
                };
            }
            p.took = p.started.map(|t| t.elapsed().as_secs());
        }
        self.current = None;
    }
}

impl Phase {
    fn end_item(&mut self) {
        if let Some(i) = self.item.take()
            && self.steps[i].mark == Mark::Run {
                let warned = self.steps[i + 1..].iter().any(|s| s.mark == Mark::Warn);
                self.steps[i].mark = if warned { Mark::Warn } else { Mark::Done };
            }
    }

    fn push(&mut self, label: &str, mark: Mark) {
        let depth = if self.item.is_some() { 1 } else { 0 };
        self.steps.push(Step { label: label.to_string(), mark, took: None, depth, detail: String::new(), count: None, started: Instant::now() });
    }

    /// The running item, marked failed.
    fn fail_item(&mut self) {
        if let Some(i) = self.item {
            self.steps[i].mark = Mark::Fail;
        }
    }
}

const SPINNER: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

pub fn clock(secs: u64) -> String {
    format!("{}:{:02}", secs / 60, secs % 60)
}

/// A `[ 7/12]` counter, as dnf prints it, anywhere in a line: the counter,
/// and the line without it, which the bar then stands for.
fn counter_at(text: &str) -> Option<(u64, u64, String)> {
    let mut from = 0;
    while let Some(i) = text[from..].find('[') {
        let open = from + i;
        let Some(len) = text[open..].find(']') else { break };
        let inside = &text[open + 1..open + len];
        if let Some((a, b)) = inside.split_once('/')
            && let (Ok(n), Ok(m)) = (a.trim().parse::<u64>(), b.trim().parse::<u64>())
                && m > 0 && n <= m {
                    let rest = format!("{}{}", &text[..open], &text[open + len + 1..]);
                    return Some((n, m, rest.trim().to_string()));
                }
        from = open + 1;
    }
    None
}

/// Visible width of a string that may hold colour codes.
pub fn width_of(s: &str) -> usize {
    let mut w = 0;
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            for n in chars.by_ref() {
                if n == 'm' {
                    break;
                }
            }
        } else {
            w += c.width().unwrap_or(0);
        }
    }
    w
}

/// The column right-aligned times end at.
fn right_edge() -> usize {
    terminal_width().saturating_sub(2).clamp(40, 64)
}

impl Ui {
    pub fn new(no_color: bool, quiet: bool, verbose: bool) -> Ui {
        let tty = std::io::stdout().is_terminal();
        let color = tty && !no_color && std::env::var_os("NO_COLOR").is_none();
        if !color {
            dialoguer::console::set_colors_enabled(false);
            dialoguer::console::set_colors_enabled_stderr(false);
        }
        Ui { color, quiet, verbose, tty, rail: false, log: None, board: None }
    }

    fn paint(&self, code: &str, s: &str) -> String {
        if self.color { format!("\x1b[{code}m{s}\x1b[0m") } else { s.to_string() }
    }
    pub fn bold(&self, s: &str) -> String { self.paint("1", s) }
    pub fn dim(&self, s: &str) -> String { self.paint("2", s) }
    pub fn green(&self, s: &str) -> String { self.paint("32", s) }
    pub fn yellow(&self, s: &str) -> String { self.paint("33", s) }
    pub fn red(&self, s: &str) -> String { self.paint("31", s) }
    pub fn blue(&self, s: &str) -> String { self.paint("34", s) }

    /// `left`, then `right` dimmed, ending at the rail's right edge.
    pub fn spread(&self, left: &str, right: &str) -> String {
        let gap = right_edge().saturating_sub(width_of(left) + width_of(right)).max(2);
        format!("{left}{}{}", " ".repeat(gap), self.dim(right))
    }

    /// The questions' look, on the rail: ◆ while asked, ◇ once answered.
    pub fn theme(&self) -> dialoguer::theme::ColorfulTheme {
        use dialoguer::console::{Style, style};
        dialoguer::theme::ColorfulTheme {
            defaults_style: Style::new().for_stderr().dim(),
            prompt_style: Style::new().for_stderr().bold(),
            prompt_prefix: style(" ◆ ".to_string()).for_stderr().green(),
            prompt_suffix: style("›".to_string()).for_stderr().dim(),
            success_prefix: style(" ◇ ".to_string()).for_stderr().green(),
            success_suffix: style("·".to_string()).for_stderr().dim(),
            error_prefix: style(" ■ ".to_string()).for_stderr().red(),
            hint_style: Style::new().for_stderr().dim(),
            values_style: Style::new().for_stderr().green(),
            active_item_style: Style::new().for_stderr().bold(),
            inactive_item_style: Style::new().for_stderr(),
            active_item_prefix: style(" │  ●".to_string()).for_stderr().green(),
            inactive_item_prefix: style(" │  ○".to_string()).for_stderr().dim(),
            checked_item_prefix: style(" │  ●".to_string()).for_stderr().green(),
            unchecked_item_prefix: style(" │  ○".to_string()).for_stderr().dim(),
            ..dialoguer::theme::ColorfulTheme::default()
        }
    }

    // ── static rail, for plans ──

    pub fn rail_top(&mut self, title: &str, aside: &str) {
        let aside = if aside.is_empty() { String::new() } else { format!("  {}", self.dim(&format!("· {aside}"))) };
        self.line(&format!("\n {}  {}{aside}", self.dim("┌"), self.bold(title)));
    }
    pub fn rail_gap(&mut self) {
        self.line(&format!(" {}", self.dim("│")));
    }
    /// A section: `◆  title · note`.
    pub fn rail_section(&mut self, title: &str, note: &str) {
        let note = if note.is_empty() { String::new() } else { format!(" {}", self.dim(&format!("· {note}"))) };
        self.line(&format!(" {}  {}{note}", self.blue("◆"), self.bold(title)));
    }
    /// A line inside a section.
    pub fn rail_row(&mut self, text: &str) {
        self.line(&format!(" {}    {text}", self.dim("│")));
    }
    pub fn rail_bottom(&mut self) {
        self.line(&format!(" {}", self.dim("└")));
    }

    // ── live rail ──

    /// Start the live rail with every phase to come, as (name, note).
    /// Off a terminal or in -q/--verbose, only the title is printed.
    pub fn board_begin(&mut self, title: &str, phases: Vec<(String, String)>) {
        self.log(&format!("==== {title}"));
        if !self.tty || self.quiet || self.verbose {
            if !self.quiet {
                println!("\n{}", self.bold(title));
            }
            return;
        }
        println!();
        self.board = Some(Board {
            title: title.to_string(),
            phases: phases
                .into_iter()
                .map(|(name, note)| Phase { name, note, mark: Mark::Todo, steps: Vec::new(), started: None, took: None, tail: Vec::new(), item: None })
                .collect(),
            current: None,
            start: Instant::now(),
            drawn: 0,
            close: None,
        });
        self.draw();
    }

    /// Close the rail with its last line (`└  coucou-shell v2.6.0  1:24`)
    /// and the lines under it.
    pub fn board_end(&mut self, mark: Mark, close: &str, after: &[String]) {
        self.log(&format!("==== {close}"));
        for a in after {
            self.log(&format!("     {a}"));
        }
        if let Some(b) = self.board.as_mut() {
            b.finish_current();
            b.close = Some((mark, close.to_string(), after.to_vec()));
            self.draw();
            self.board = None;
            return;
        }
        if self.quiet && mark != Mark::Fail && mark != Mark::Warn {
            return;
        }
        let icon = self.icon(mark);
        let out = format!("\n{icon} {}", self.bold(close));
        if mark == Mark::Fail { eprintln!("{out}") } else { println!("{out}") }
        for a in after {
            if mark == Mark::Fail { eprintln!("  {a}") } else { println!("  {a}") }
        }
    }

    /// Set the running phase's note (`9 upgraded`).
    pub fn note(&mut self, note: &str) {
        self.log(&format!("     ({note})"));
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            p.note = note.to_string();
            self.draw();
        }
    }

    /// What goes before a step's mark off the live rail.
    fn lead(&self) -> String {
        if self.rail { format!(" {}  ", self.dim("│")) } else { "  ".to_string() }
    }

    fn icon(&self, mark: Mark) -> String {
        match mark {
            Mark::Todo | Mark::Skip => self.dim("○"),
            Mark::Run => self.yellow("…"),
            Mark::Done => self.green("✓"),
            Mark::Warn => self.yellow("!"),
            Mark::Fail => self.red("✗"),
        }
    }

    fn draw(&mut self) {
        let Some(b) = self.board.as_ref() else { return };
        let rows = self.render(b);
        let mut out = String::new();
        if b.drawn > 0 {
            out.push_str(&format!("\x1b[{}A\r", b.drawn));
        }
        for r in &rows {
            out.push_str("\x1b[2K");
            out.push_str(r);
            out.push('\n');
        }
        out.push_str("\x1b[J");
        print!("{out}");
        let _ = std::io::stdout().flush();
        if let Some(b) = self.board.as_mut() {
            b.drawn = rows.len();
        }
    }

    fn render(&self, b: &Board) -> Vec<String> {
        let width = terminal_width();
        let height = terminal_size::terminal_size().map(|(_, h)| h.0 as usize).unwrap_or(40);
        let elapsed = b.start.elapsed();
        let spin = SPINNER[(elapsed.as_millis() / 100) as usize % SPINNER.len()];
        let fit = |s: String| truncate(&s, width);
        let bar = self.dim("│");

        let mut rows = Vec::new();
        let top = format!(" {}  {}", self.dim("┌"), self.bold(&b.title));
        rows.push(fit(if b.close.is_some() { top } else { self.spread(&top, &clock(elapsed.as_secs())) }));
        rows.push(format!(" {bar}"));

        let mut body = Vec::new();
        for p in &b.phases {
            let mark = match p.mark {
                Mark::Todo | Mark::Skip => self.dim("○"),
                Mark::Run => self.yellow("◆"),
                Mark::Done => self.green("◇"),
                Mark::Warn => self.yellow("◇"),
                Mark::Fail => self.red("■"),
            };
            let note = if p.note.is_empty() { String::new() } else { format!(" · {}", p.note) };
            let line = match p.mark {
                Mark::Todo | Mark::Skip => format!(" {mark}  {}", self.dim(&format!("{}{note}", p.name))),
                Mark::Run => format!(" {mark}  {}{}", self.bold(&p.name), self.dim(&note)),
                _ => format!(" {mark}  {}{}", p.name, self.dim(&note)),
            };
            let line = match p.took {
                Some(t) if p.mark != Mark::Run && t >= 1 => self.spread(&line, &clock(t)),
                _ => line,
            };
            body.push(fit(line));

            let open = matches!(p.mark, Mark::Run | Mark::Fail);
            let items = p.steps.iter().any(|s| s.depth == 1) || p.item.is_some();
            if !open {
                for s in p.steps.iter().filter(|s| s.mark == Mark::Warn) {
                    body.push(fit(format!(" {bar}    {} {}", self.yellow("!"), s.label)));
                }
                continue;
            }
            if items {
                // Units: finished items share lines, the running or failed
                // one unfolds.
                let mut done_line = Vec::new();
                let mut i = 0;
                while i < p.steps.len() {
                    let s = &p.steps[i];
                    let children: Vec<&Step> = p.steps[i + 1..].iter().take_while(|c| c.depth == 1).collect();
                    let unfold = matches!(s.mark, Mark::Run | Mark::Fail);
                    if s.depth == 0 && !unfold {
                        let icon = match s.mark {
                            Mark::Warn => self.yellow("!"),
                            Mark::Skip | Mark::Todo => self.dim("○"),
                            _ => self.green("✓"),
                        };
                        done_line.push(format!("{icon} {}", s.label));
                    } else if s.depth == 0 {
                        flush_done(&mut body, &mut done_line, &bar, width);
                        let icon = if s.mark == Mark::Run { self.yellow(spin) } else { self.red("✗") };
                        let failed = children.iter().find(|c| c.mark == Mark::Fail).map(|c| format!("  {}", c.label)).unwrap_or_default();
                        body.push(fit(format!(" {bar}    {icon} {}{failed}", self.bold(&s.label))));
                        if s.mark == Mark::Run {
                            let shown = children.len().saturating_sub(3);
                            for c in &children[shown..] {
                                self.step_rows(&mut body, c, spin, 6);
                            }
                        } else {
                            for l in &p.tail {
                                body.push(fit(format!(" {bar}        {}", self.dim(l))));
                            }
                        }
                    }
                    i += 1 + children.len();
                }
                flush_done(&mut body, &mut done_line, &bar, width);
            } else {
                for s in &p.steps {
                    self.step_rows(&mut body, s, spin, 4);
                }
                if p.mark == Mark::Fail {
                    for l in &p.tail {
                        body.push(fit(format!(" {bar}        {}", self.dim(l))));
                    }
                }
            }
        }
        // A short terminal: drop the middle of the body, keep the start and
        // the running end.
        let budget = height.saturating_sub(6).max(8);
        if body.len() > budget {
            let cut = body.len() - budget + 1;
            let head = budget / 3;
            let mut kept: Vec<String> = body[..head].to_vec();
            kept.push(format!(" {bar}    {}", self.dim(&format!("… {cut} more"))));
            kept.extend_from_slice(&body[head + cut..]);
            body = kept;
        }
        rows.extend(body);

        match &b.close {
            None => rows.push(format!(" {}", self.dim("└"))),
            Some((mark, text, after)) => {
                rows.push(format!(" {bar}"));
                let corner = match mark {
                    Mark::Fail => self.red("└"),
                    Mark::Warn => self.yellow("└"),
                    _ => self.green("└"),
                };
                let took = format!("  {}", self.dim(&clock(elapsed.as_secs())));
                let took = if *mark == Mark::Done && elapsed.as_secs() >= 1 { took } else { String::new() };
                rows.push(fit(format!(" {corner}  {}{took}", self.bold(text))));
                for a in after {
                    rows.push(fit(format!("    {a}")));
                }
            }
        }
        rows
    }

    fn step_rows(&self, body: &mut Vec<String>, s: &Step, spin: &str, indent: usize) {
        let width = terminal_width();
        let bar = self.dim("│");
        let pad = " ".repeat(indent);
        let icon = match s.mark {
            Mark::Run => self.yellow(spin),
            Mark::Done => self.green("✓"),
            Mark::Skip | Mark::Todo => self.dim("○"),
            Mark::Warn => self.yellow("!"),
            Mark::Fail => self.red("✗"),
        };
        let line = format!(" {bar}{pad}{icon} {}", s.label);
        let line = match (s.mark, s.took) {
            (Mark::Run, _) => {
                let t = s.started.elapsed().as_secs();
                if t >= 2 { self.spread(&line, &clock(t)) } else { line }
            }
            (_, Some(t)) if t >= 2 => self.spread(&line, &clock(t)),
            _ => line,
        };
        body.push(truncate(&line, width));
        if s.mark == Mark::Run && !s.detail.is_empty() {
            let detail = match s.count {
                Some((n, m)) => {
                    let cells = 24;
                    let f = (cells as u64 * n / m) as usize;
                    body.push(truncate(&format!(" {bar}{pad}  {n}/{m}  {}", self.dim(&s.detail)), width));
                    format!("{}{}", "▰".repeat(f), self.dim(&"▱".repeat(cells - f)))
                }
                None => self.dim(&s.detail),
            };
            body.push(truncate(&format!(" {bar}{pad}  {detail}"), width));
        }
    }

    // ── logging ──

    /// Start logging to `<dir>/<timestamp>.log` and point `latest.log` at it.
    pub fn open_log(&mut self, dir: &Path, what: &str) -> Result<()> {
        std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
        let stamp = crate::sys::now().replace(':', "");
        let path = dir.join(format!("{stamp}-{what}.log"));
        let file = File::create(&path).with_context(|| format!("creating {}", path.display()))?;
        let latest = dir.join("latest.log");
        let _ = std::fs::remove_file(&latest);
        let _ = std::os::unix::fs::symlink(&path, &latest);
        self.log = Some((path, file));
        Ok(())
    }

    pub fn log_path(&self) -> Option<&Path> {
        self.log.as_ref().map(|(p, _)| p.as_path())
    }

    pub fn log(&mut self, line: &str) {
        if let Some((_, f)) = self.log.as_mut() {
            let _ = writeln!(f, "{line}");
        }
    }

    // ── lines and steps ──

    /// Start a phase of the rail (or, off the rail, a heading).
    pub fn heading(&mut self, s: &str) {
        self.log(&format!("== {s}"));
        if let Some(b) = self.board.as_mut() {
            b.finish_current();
            let i = match b.phases.iter().position(|p| p.name.eq_ignore_ascii_case(s)) {
                Some(i) => i,
                None => {
                    b.phases.push(Phase { name: s.to_string(), note: String::new(), mark: Mark::Todo, steps: Vec::new(), started: None, took: None, tail: Vec::new(), item: None });
                    b.phases.len() - 1
                }
            };
            b.phases[i].mark = Mark::Run;
            b.phases[i].started = Some(Instant::now());
            b.current = Some(i);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("\n{}", self.bold(s));
        }
    }

    /// One item of the running phase (a unit): the steps that follow
    /// belong to it.
    pub fn item(&mut self, name: &str) {
        self.log(&format!("-- {name}"));
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            p.end_item();
            p.item = None;
            p.push(name, Mark::Run);
            p.item = Some(p.steps.len() - 1);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("  {}", self.bold(name));
        }
    }

    /// `init`'s step header, on the rail.
    pub fn step(&mut self, n: usize, total: usize, label: &str) {
        self.log(&format!("== step {n}/{total} {label}"));
        if self.quiet {
            return;
        }
        println!(" {}", self.dim("│"));
        println!(" {}  {}  {}", self.blue("◆"), self.bold(label), self.dim(&format!("{n}/{total}")));
    }

    /// `init`'s welcome: the bird, and what is about to happen.
    pub fn welcome(&mut self) {
        if self.quiet {
            return;
        }
        let lines = [
            self.bold("coucou-shell"),
            self.dim(&"─".repeat(12)),
            "A Fedora + Hyprland desktop.".to_string(),
            "A few questions, then it installs.".to_string(),
            String::new(),
            self.dim("Nothing changes before the summary."),
        ];
        println!();
        for row in crate::logo::beside(crate::logo::big(), |s| self.bold(s), &lines) {
            println!("{row}");
        }
        println!("\n {}  {}", self.dim("┌"), self.bold("init"));
    }

    pub fn line(&mut self, s: &str) {
        self.log(&crate::ui::plain(s));
        if !self.quiet {
            println!("{s}");
        }
    }

    pub fn ok(&mut self, label: &str) {
        self.log(&format!("ok   {label}"));
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            p.push(label, Mark::Done);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("{}{} {label}", self.lead(), self.green("✓"));
        }
    }

    pub fn skip(&mut self, label: &str) {
        self.log(&format!("skip {label}"));
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            p.push(label, Mark::Skip);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("{}{} {label}", self.lead(), self.dim("○"));
        }
    }

    pub fn warn(&mut self, msg: &str) {
        self.log(&format!("warn {msg}"));
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            p.push(msg, Mark::Warn);
            self.draw();
            return;
        }
        eprintln!("{}{} {msg}", self.lead(), self.yellow("!"));
    }

    /// The running item (or phase) failed, with why.
    pub fn fail(&mut self, label: &str) {
        self.log(&format!("FAIL {label}"));
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            // A failed command already marked its own step; its summary
            // adds nothing on screen.
            let marked = p.steps.last().is_some_and(|s| s.mark == Mark::Fail);
            if !marked {
                p.push(label, Mark::Fail);
            }
            if p.item.is_some() {
                p.fail_item();
                p.item = None;
            } else {
                p.mark = Mark::Fail;
            }
            self.draw();
            return;
        }
        eprintln!("  {} {label}", self.red("✗"));
    }

    /// Mark the running phase failed, with the last lines of what failed.
    pub fn fail_phase(&mut self, tail: &[String]) {
        if let Some(p) = self.board.as_mut().and_then(Board::phase) {
            p.end_item();
            p.mark = Mark::Fail;
            p.tail = tail.to_vec();
            self.draw();
        }
    }

    /// Run `cmd` as one step. stdin closed, output to the log with a live
    /// detail line. A failure is a `CmdFailed` holding what it printed.
    pub fn run(&mut self, label: &str, cmd: &mut Command) -> Result<()> {
        self.run_output(label, cmd).map(|_| ())
    }

    /// `run`, handing back the lines the command printed.
    pub fn run_output(&mut self, label: &str, cmd: &mut Command) -> Result<Vec<String>> {
        self.log(&format!("---- {label}: {cmd:?}"));
        let start = Instant::now();
        let on_board = self.board.as_ref().is_some_and(|b| b.current.is_some());
        let live = !on_board && self.tty && !self.quiet && !self.verbose;
        if on_board {
            if let Some(p) = self.board.as_mut().and_then(Board::phase) {
                p.push(label, Mark::Run);
            }
            self.draw();
        } else if live {
            println!("{}{} {label}", self.lead(), self.dim("…"));
            let _ = std::io::stdout().flush();
        } else if self.verbose {
            println!("{}{} {label}", self.lead(), self.dim("…"));
        }

        let mut child = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .with_context(|| format!("starting {label}"))?;
        let (tx, rx) = mpsc::channel::<String>();
        let pumps: Vec<_> = [
            Box::new(child.stdout.take().unwrap()) as Box<dyn Read + Send>,
            Box::new(child.stderr.take().unwrap()) as Box<dyn Read + Send>,
        ]
        .into_iter()
        .map(|r| {
            let tx = tx.clone();
            std::thread::spawn(move || {
                for line in BufReader::new(r).split(b'\n').map_while(|l| l.ok()) {
                    let _ = tx.send(String::from_utf8_lossy(&line).into_owned());
                }
            })
        })
        .collect();
        drop(tx);

        // Everything it prints, for dnf's problems to be read back; the
        // last lines, for the screen.
        let mut output: Vec<String> = Vec::new();
        let mut tail: VecDeque<String> = VecDeque::with_capacity(8);
        loop {
            match rx.recv_timeout(Duration::from_millis(100)) {
                Ok(raw) => {
                    let text = clean(&raw);
                    self.log(&format!("     {text}"));
                    if text.trim().is_empty() {
                        continue;
                    }
                    if output.len() < 2000 {
                        output.push(text.clone());
                    }
                    if tail.len() == 8 {
                        tail.pop_front();
                    }
                    tail.push_back(text.clone());
                    if on_board {
                        if let Some(s) = self.board.as_mut().and_then(Board::phase).and_then(|p| p.steps.last_mut()) {
                            match counter_at(&text) {
                                Some((n, m, rest)) => {
                                    s.count = Some((n, m));
                                    s.detail = rest;
                                }
                                None => s.detail = text,
                            }
                        }
                        self.draw();
                    } else if live {
                        let width = terminal_width().saturating_sub(6).max(10);
                        print!("\x1b[2K\r      {}", self.dim(&truncate(&text, width)));
                        let _ = std::io::stdout().flush();
                    } else if self.verbose {
                        println!("      {text}");
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if on_board {
                        self.draw();
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
        for p in pumps {
            let _ = p.join();
        }
        let status = child.wait()?;
        let secs = start.elapsed().as_secs();

        if on_board {
            if let Some(s) = self.board.as_mut().and_then(Board::phase).and_then(|p| p.steps.last_mut()) {
                s.mark = if status.success() { Mark::Done } else { Mark::Fail };
                s.took = Some(secs);
                s.detail.clear();
            }
            if !status.success() {
                let lines: Vec<String> = tail.iter().cloned().collect();
                if let Some(p) = self.board.as_mut().and_then(Board::phase) {
                    p.tail = lines;
                }
            }
            self.draw();
        } else {
            if live {
                // Back up to the "…" line, rewrite it, clear the detail line.
                print!("\x1b[2K\r\x1b[1A\x1b[2K\r");
            }
            let took = if secs >= 2 { format!(" {}", self.dim(&format!("({})", clock(secs)))) } else { String::new() };
            if status.success() {
                if !self.quiet {
                    println!("{}{} {label}{took}", self.lead(), self.green("✓"));
                }
            } else {
                eprintln!("{}{} {label}{took}", self.lead(), self.red("✗"));
                for l in &tail {
                    eprintln!("      {}", self.dim(l));
                }
            }
        }
        if status.success() {
            self.log(&format!("ok   {label} ({secs}s)"));
            Ok(output)
        } else {
            self.log(&format!("FAIL {label} ({secs}s)"));
            Err(CmdFailed { label: label.to_string(), status, output }.into())
        }
    }

    /// Run `cmd` as one step, its output thrown away: for a command that
    /// leaves a daemon behind holding whatever it was given (the bar).
    pub fn run_detached(&mut self, label: &str, cmd: &mut Command) -> Result<()> {
        self.log(&format!("---- {label}: {cmd:?}"));
        let status = cmd.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().with_context(|| format!("starting {label}"))?;
        if status.success() {
            self.ok(label);
            Ok(())
        } else {
            self.warn(&format!("{label}: failed"));
            Err(CmdFailed { label: label.to_string(), status, output: Vec::new() }.into())
        }
    }

    // ── errors ──

    /// An error, as main prints it: a Stop with its hints, anything else as
    /// its message and its causes.
    pub fn report(&self, err: &anyhow::Error) {
        if err.downcast_ref::<Shown>().is_some() {
            return;
        }
        let (mark, title, detail, hints) = match err.downcast_ref::<Stop>() {
            Some(s) => (if s.warn { self.yellow("!") } else { self.red("✗") }, s.title.clone(), s.detail.clone(), s.hints.clone()),
            None => {
                let mut chain = err.chain().map(|c| c.to_string());
                let title = chain.next().unwrap_or_default();
                (self.red("✗"), title, chain.collect(), Vec::new())
            }
        };
        let mut out = format!("\n {mark} {}", self.bold(&title));
        for d in &detail {
            out.push_str(&format!("\n   {}", self.dim(d)));
        }
        let w = hints.iter().map(|(k, _)| k.width()).max().unwrap_or(0);
        for (what, cmd) in &hints {
            out.push_str(&format!("\n   {}{}  {}", what, " ".repeat(w - what.width()), self.bold(cmd)));
        }
        eprintln!("{out}");
    }

    /// Hint rows (`retry   cc-pkg-mng upgrade`), aligned.
    pub fn hints(&self, hints: &[(String, String)]) -> Vec<String> {
        let w = hints.iter().map(|(k, _)| k.width()).max().unwrap_or(0);
        hints
            .iter()
            .map(|(k, v)| {
                let v = if v.starts_with('~') || v.starts_with('/') { self.dim(v) } else { self.bold(v) };
                format!("{k}{}  {v}", " ".repeat(w - k.width()))
            })
            .collect()
    }
}

fn flush_done(body: &mut Vec<String>, done: &mut Vec<String>, bar: &str, width: usize) {
    if done.is_empty() {
        return;
    }
    let mut line = String::new();
    for d in done.drain(..) {
        if !line.is_empty() && width_of(&line) + width_of(&d) + 9 > width {
            body.push(format!(" {bar}    {line}"));
            line.clear();
        }
        if !line.is_empty() {
            line.push_str("  ");
        }
        line.push_str(&d);
    }
    body.push(format!(" {bar}    {line}"));
}

pub fn terminal_width() -> usize {
    terminal_size::terminal_size().map(|(w, _)| w.0 as usize).unwrap_or(80)
}

/// Without colour codes, for the log.
pub fn plain(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            for n in chars.by_ref() {
                if n == 'm' {
                    break;
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Strip escape sequences and keep what a `\r` redraw would leave visible.
pub fn clean(raw: &str) -> String {
    let last = raw.split('\r').rfind(|s| !s.trim().is_empty()).unwrap_or("");
    let mut out = String::with_capacity(last.len());
    let mut chars = last.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            match chars.peek() {
                Some('[') => {
                    chars.next();
                    // CSI: parameters, then one final byte in @..~
                    for n in chars.by_ref() {
                        if ('@'..='~').contains(&n) {
                            break;
                        }
                    }
                }
                Some(']') => {
                    chars.next();
                    // OSC: up to BEL or ESC \
                    while let Some(n) = chars.next() {
                        if n == '\x07' {
                            break;
                        }
                        if n == '\x1b' {
                            chars.next();
                            break;
                        }
                    }
                }
                _ => {
                    chars.next();
                }
            }
        } else if c == '\t' {
            out.push(' ');
        } else if !c.is_control() {
            out.push(c);
        }
    }
    out
}

/// Cut to `width` terminal columns, with an ellipsis. Colour codes count
/// for nothing and are kept, with a reset after the cut.
pub fn truncate(s: &str, width: usize) -> String {
    if width_of(s) <= width {
        return s.to_string();
    }
    let mut used = 0;
    let mut out = String::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            out.push(c);
            for n in chars.by_ref() {
                out.push(n);
                if n == 'm' {
                    break;
                }
            }
            continue;
        }
        let w = c.width().unwrap_or(0);
        if used + w > width.saturating_sub(1) {
            out.push('…');
            if out.contains('\x1b') {
                out.push_str("\x1b[0m");
            }
            return out;
        }
        used += w;
        out.push(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_strips_escapes_and_redraws() {
        assert_eq!(clean("\x1b[32m[ OK ]\x1b[0m done"), "[ OK ] done");
        assert_eq!(clean("  10%\r  50%\r 100% ready"), " 100% ready");
        assert_eq!(clean("\x1b]0;title\x07text"), "text");
        assert_eq!(clean("a\tb"), "a b");
    }

    #[test]
    fn truncate_counts_columns() {
        assert_eq!(truncate("abcdef", 4), "abc…");
        assert_eq!(truncate("abc", 10), "abc");
        assert_eq!(truncate("日本語テキスト", 7), "日本語…");
        assert_eq!(truncate("\x1b[2mabcdef\x1b[0m", 4), "\x1b[2mabc…\x1b[0m");
        assert_eq!(width_of("\x1b[1mab\x1b[0m"), 2);
    }

    #[test]
    fn counter_finds_dnf_progress() {
        let n = |t: &str| counter_at(t).map(|(n, m, _)| (n, m));
        assert_eq!(n("[ 7/12] Installing manette-1.2.0"), Some((7, 12)));
        assert_eq!(n("[3/3] foo 100% | 1 MiB/s"), Some((3, 3)));
        assert_eq!(n("[ OK ] done"), None);
        assert_eq!(n("no counter 3/4 here"), None);
        assert_eq!(counter_at("[ 7/12] Installing x").map(|c| c.2), Some("Installing x".to_string()));
    }

    #[test]
    fn stop_reads_as_text() {
        let s = Stop::new("v2.6.0 is not published yet.").detail("Still on v2.5.0.").hint("retry later", "cc-pkg-mng upgrade");
        assert_eq!(s.to_string(), "v2.6.0 is not published yet.\n  Still on v2.5.0.\n  retry later: cc-pkg-mng upgrade");
    }
}
