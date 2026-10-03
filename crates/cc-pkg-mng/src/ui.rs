//! Terminal output, and running external commands with a live detail line.
//!
//! Commands run with stdout/stderr piped (never on the terminal), so dnf,
//! cargo and friends drop their own progress bars; every line goes to the
//! log, and on a terminal the latest one is shown dimmed under the step,
//! escape codes stripped, `\r` redraws collapsed, cut to the current width.
//! stdin is closed: nothing a command runs can wait for an answer.

use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, BufReader, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use unicode_width::UnicodeWidthChar;

pub struct Ui {
    pub color: bool,
    pub quiet: bool,
    pub verbose: bool,
    pub tty: bool,
    log: Option<(PathBuf, File)>,
    /// What the run is, for the progress board's title ("install",
    /// "upgrade v1.2.1 → v1.2.2").
    title: String,
    board: Option<Board>,
}

/// The coucou mark, two rows of half blocks.
pub const LOGO: [&str; 2] = ["▄▀▀ ▄▀▄ █ █ ▄▀▀ ▄▀▄ █ █", "▀▄▄ ▀▄▀ ▀▄█ ▀▄▄ ▀▄▀ ▀▄█"];

// ───────────────────────────── the board ─────────────────────────────
//
// While `apply` works on a terminal, its output is a live list redrawn in
// place instead of a scroll of lines: every piece of work is listed from
// the start (○ to do), the one in progress is unfolded with its steps and
// a spinner (⠼), finished ones fold to one line (✓, ✗). A bar at the top
// counts them. Off a terminal, with --verbose or -q, there is no board and
// output is the plain line-by-line kind, which is also what the log gets.

#[derive(Clone, Copy, PartialEq)]
enum Mark {
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
    /// The latest line the running command printed.
    detail: String,
    /// A `[ n/m]` counter found in that line (dnf prints them).
    count: Option<(u64, u64)>,
}

struct Entry {
    name: String,
    note: String,
    mark: Mark,
    steps: Vec<Step>,
    started: Option<Instant>,
    took: Option<u64>,
    /// The last lines of the command that failed.
    tail: Vec<String>,
}

struct Board {
    entries: Vec<Entry>,
    current: Option<usize>,
    start: Instant,
    /// Rows drawn last time, to move back over them.
    drawn: usize,
}

impl Board {
    fn finish_current(&mut self) {
        if let Some(i) = self.current.take() {
            let e = &mut self.entries[i];
            if e.mark == Mark::Run {
                e.mark = Mark::Done;
            }
            e.took = e.started.map(|t| t.elapsed().as_secs());
        }
    }

    fn entry(&mut self) -> Option<&mut Entry> {
        let i = self.current?;
        self.entries.get_mut(i)
    }

    fn push(&mut self, label: &str, mark: Mark) {
        if let Some(e) = self.entry() {
            e.steps.push(Step { label: label.to_string(), mark, took: None, detail: String::new(), count: None });
        }
    }
}

const SPINNER: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

fn clock(secs: u64) -> String {
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
        if let Some((a, b)) = inside.split_once('/') {
            if let (Ok(n), Ok(m)) = (a.trim().parse::<u64>(), b.trim().parse::<u64>()) {
                if m > 0 && n <= m {
                    let rest = format!("{}{}", &text[..open], &text[open + len + 1..]);
                    return Some((n, m, rest.trim().to_string()));
                }
            }
        }
        from = open + 1;
    }
    None
}

impl Ui {
    pub fn new(no_color: bool, quiet: bool, verbose: bool) -> Ui {
        let tty = std::io::stdout().is_terminal();
        let color = tty && !no_color && std::env::var_os("NO_COLOR").is_none();
        Ui { color, quiet, verbose, tty, log: None, title: "install".into(), board: None }
    }

    pub fn set_title(&mut self, title: &str) {
        self.title = title.to_string();
    }

    /// Start the live board with every piece of work to come, as
    /// (name, note). Nothing happens off a terminal or in -q/--verbose.
    pub fn board_begin(&mut self, entries: Vec<(String, String)>) {
        if !self.tty || self.quiet || self.verbose || entries.is_empty() {
            return;
        }
        println!();
        self.board = Some(Board {
            entries: entries
                .into_iter()
                .map(|(name, note)| Entry { name, note, mark: Mark::Todo, steps: Vec::new(), started: None, took: None, tail: Vec::new() })
                .collect(),
            current: None,
            start: Instant::now(),
            drawn: 0,
        });
        self.draw();
    }

    /// Close the board: the entry still running is done, and the last
    /// drawing stays on screen. Returns how long the board ran, if any.
    pub fn board_end(&mut self) -> Option<u64> {
        let b = self.board.as_mut()?;
        b.finish_current();
        let secs = b.start.elapsed().as_secs();
        self.draw();
        self.board = None;
        Some(secs)
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
        let total = b.entries.len();
        let finished = b.entries.iter().filter(|e| matches!(e.mark, Mark::Done | Mark::Fail)).count();
        let failed = b.entries.iter().any(|e| e.mark == Mark::Fail);
        let fit = |s: String| truncate(&s, width);

        // Top: what this is, a bar of the entries done, and the time.
        let cells = 16;
        let filled = if total == 0 { cells } else { cells * finished / total };
        let bar_fill = "▰".repeat(filled);
        let bar_fill = if failed { self.red(&bar_fill) } else if finished == total { self.green(&bar_fill) } else { bar_fill };
        let mut rows = vec![format!(
            " {}   {}{}  {}  {}",
            self.bold(&self.title),
            bar_fill,
            self.dim(&"▱".repeat(cells - filled)),
            format!("{finished}/{total}"),
            self.dim(&clock(elapsed.as_secs()))
        )];
        rows.push(String::new());

        let name_w = b.entries.iter().map(|e| e.name.chars().count()).max().unwrap_or(8).max(8) + 2;
        let line_for = |e: &Entry| -> String {
            let icon = match e.mark {
                Mark::Todo => self.dim("○"),
                Mark::Run => self.yellow(spin),
                Mark::Done | Mark::Skip => self.green("✓"),
                Mark::Warn => self.yellow("!"),
                Mark::Fail => self.red("✗"),
            };
            let name = format!("{:<name_w$}", e.name);
            let name = match e.mark {
                Mark::Todo => self.dim(&name),
                Mark::Run => self.bold(&name),
                _ => name,
            };
            let note = match e.mark {
                Mark::Done if !e.steps.is_empty() => {
                    let n = e.steps.len();
                    format!("{} · {n} step{}", e.note, if n == 1 { "" } else { "s" })
                }
                _ => e.note.clone(),
            };
            let took = e.took.map(|t| format!("  {}", clock(t))).unwrap_or_default();
            fit(format!("  {icon} {name}{}{}", self.dim(&note), self.dim(&took)))
        };

        let mut body: Vec<String> = Vec::new();
        let mut done_folded = 0usize;
        // Folding plan for a short terminal: finished entries collapse to a
        // single count first, then the tail of the to-do list is cut.
        let unfolded_rows = |e: &Entry| -> usize {
            match e.mark {
                Mark::Run => 1 + e.steps.len() + 1,
                Mark::Fail => 1 + e.steps.len() + e.tail.len() + 1,
                _ => 1 + e.steps.iter().filter(|s| s.mark == Mark::Warn).count(),
            }
        };
        let budget = height.saturating_sub(4).max(6);
        let needed: usize = b.entries.iter().map(unfolded_rows).sum();
        let fold_done = needed > budget;

        for e in &b.entries {
            if fold_done && e.mark == Mark::Done && !e.steps.iter().any(|s| s.mark == Mark::Warn) {
                done_folded += 1;
                continue;
            }
            body.push(line_for(e));
            let unfold = matches!(e.mark, Mark::Run | Mark::Fail);
            for s in &e.steps {
                if !unfold && s.mark != Mark::Warn {
                    continue;
                }
                let icon = match s.mark {
                    Mark::Run => self.yellow(spin),
                    Mark::Done => self.green("✓"),
                    Mark::Skip | Mark::Todo => self.dim("○"),
                    Mark::Warn => self.yellow("!"),
                    Mark::Fail => self.red("✗"),
                };
                let took = match (s.mark, s.took) {
                    (Mark::Run, _) => format!("  {}", self.dim(&clock(e.started.map(|t| t.elapsed().as_secs()).unwrap_or(0)))),
                    (_, Some(t)) if t >= 2 => format!("  {}", self.dim(&clock(t))),
                    _ => String::new(),
                };
                body.push(fit(format!("      {icon} {}{took}", s.label)));
                if s.mark == Mark::Run && !s.detail.is_empty() {
                    let detail = match s.count {
                        Some((n, m)) => {
                            let cells = 12;
                            let f = (cells as u64 * n / m) as usize;
                            format!("{}{}  {n}/{m}  {}", "▰".repeat(f), self.dim(&"▱".repeat(cells - f)), self.dim(&s.detail))
                        }
                        None => self.dim(&s.detail),
                    };
                    body.push(fit(format!("          {detail}")));
                }
            }
            if e.mark == Mark::Fail {
                for l in &e.tail {
                    body.push(fit(format!("          {}", self.dim(l))));
                }
            }
        }
        if done_folded > 0 {
            body.insert(0, fit(format!("  {} {}", self.green("✓"), self.dim(&format!("{done_folded} done")))));
        }
        if body.len() > budget {
            let keep = budget.saturating_sub(1);
            let cut = body.len() - keep;
            body.truncate(keep);
            body.push(fit(format!("  {} {}", self.dim("○"), self.dim(&format!("… {cut} more")))));
        }
        rows.extend(body);
        rows
    }

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

    fn paint(&self, code: &str, s: &str) -> String {
        if self.color { format!("\x1b[{code}m{s}\x1b[0m") } else { s.to_string() }
    }
    pub fn bold(&self, s: &str) -> String { self.paint("1", s) }
    pub fn dim(&self, s: &str) -> String { self.paint("2", s) }
    pub fn green(&self, s: &str) -> String { self.paint("32", s) }
    pub fn yellow(&self, s: &str) -> String { self.paint("33", s) }
    pub fn red(&self, s: &str) -> String { self.paint("31", s) }

    pub fn heading(&mut self, s: &str) {
        self.log(&format!("== {s}"));
        if let Some(b) = self.board.as_mut() {
            b.finish_current();
            let i = match b.entries.iter().position(|e| e.name.eq_ignore_ascii_case(s)) {
                Some(i) => i,
                None => {
                    b.entries.push(Entry { name: s.to_string(), note: String::new(), mark: Mark::Todo, steps: Vec::new(), started: None, took: None, tail: Vec::new() });
                    b.entries.len() - 1
                }
            };
            b.entries[i].mark = Mark::Run;
            b.entries[i].started = Some(Instant::now());
            b.current = Some(i);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("\n{}", self.bold(s));
        }
    }

    /// `init`'s step header: ● ● ○ ○  2/4  Channel.
    pub fn step(&mut self, n: usize, total: usize, label: &str) {
        self.log(&format!("== step {n}/{total} {label}"));
        if self.quiet {
            return;
        }
        let dots: Vec<String> = (1..=total).map(|i| if i <= n { self.bold("●") } else { self.dim("○") }).collect();
        println!("\n   {}  {}  {}", dots.join(" "), self.dim(&format!("{n}/{total}")), self.bold(label));
    }

    /// `init`'s welcome: the logo and what is about to happen.
    pub fn welcome(&mut self) {
        if self.quiet {
            return;
        }
        println!();
        println!("   {}  {}", self.bold(LOGO[0]), self.dim("shell"));
        println!("   {}", self.bold(LOGO[1]));
        println!();
        println!("   A Fedora + Hyprland desktop. A few questions, then it installs.");
        println!("   {}", self.dim("Nothing changes before the summary."));
    }

    pub fn line(&mut self, s: &str) {
        self.log(s);
        if !self.quiet {
            println!("{s}");
        }
    }

    pub fn ok(&mut self, label: &str) {
        self.log(&format!("ok   {label}"));
        if let Some(b) = self.board.as_mut() {
            b.push(label, Mark::Done);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("  {} {label}", self.green("✓"));
        }
    }

    pub fn skip(&mut self, label: &str) {
        self.log(&format!("skip {label}"));
        if let Some(b) = self.board.as_mut() {
            b.push(label, Mark::Skip);
            self.draw();
            return;
        }
        if !self.quiet {
            println!("  {} {label}", self.dim("○"));
        }
    }

    pub fn warn(&mut self, msg: &str) {
        self.log(&format!("warn {msg}"));
        if let Some(b) = self.board.as_mut() {
            if b.current.is_some() {
                b.push(msg, Mark::Warn);
                self.draw();
                return;
            }
        }
        eprintln!("  {} {msg}", self.yellow("!"));
    }

    pub fn fail(&mut self, label: &str) {
        self.log(&format!("FAIL {label}"));
        if let Some(b) = self.board.as_mut() {
            if let Some(e) = b.entry() {
                // A failed command already marked its own step; the unit's
                // summary of that failure adds nothing on screen.
                if e.mark != Mark::Fail {
                    e.mark = Mark::Fail;
                    e.steps.push(Step { label: label.to_string(), mark: Mark::Fail, took: None, detail: String::new(), count: None });
                }
                self.draw();
                return;
            }
        }
        eprintln!("  {} {label}", self.red("✗"));
    }

    /// Run `cmd` as one step. stdin closed, output to the log with a live
    /// detail line on a terminal. On failure, prints the last lines.
    pub fn run(&mut self, label: &str, cmd: &mut Command) -> Result<()> {
        if self.board.as_ref().is_some_and(|b| b.current.is_some()) {
            return self.run_on_board(label, cmd);
        }
        self.log(&format!("---- {label}: {cmd:?}"));
        let start = Instant::now();
        let live = self.tty && !self.quiet && !self.verbose;
        if live {
            print!("  {} {label}\n", self.dim("…"));
            let _ = std::io::stdout().flush();
        } else if self.verbose {
            println!("  {} {label}", self.dim("…"));
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

        let mut tail: VecDeque<String> = VecDeque::with_capacity(20);
        for raw in rx {
            let text = clean(&raw);
            self.log(&format!("     {text}"));
            if text.trim().is_empty() {
                continue;
            }
            if tail.len() == 20 {
                tail.pop_front();
            }
            tail.push_back(text.clone());
            if live {
                let width = terminal_width().saturating_sub(6).max(10);
                print!("\x1b[2K\r      {}", self.dim(&truncate(&text, width)));
                let _ = std::io::stdout().flush();
            } else if self.verbose {
                println!("      {text}");
            }
        }
        for p in pumps {
            let _ = p.join();
        }
        let status = child.wait()?;
        let secs = start.elapsed().as_secs();
        let took = if secs >= 2 { format!(" {}", self.dim(&format!("({secs}s)"))) } else { String::new() };

        if live {
            // Back up to the "…" line, rewrite it, clear the detail line.
            print!("\x1b[2K\r\x1b[1A\x1b[2K\r");
        }
        if status.success() {
            self.log(&format!("ok   {label} ({secs}s)"));
            if !self.quiet {
                println!("  {} {label}{took}", self.green("✓"));
            }
            Ok(())
        } else {
            self.fail(&format!("{label}{took}"));
            for l in &tail {
                eprintln!("      {}", self.dim(l));
            }
            if let Some(p) = self.log_path() {
                eprintln!("      {}", self.dim(&format!("full log: {}", p.display())));
            }
            bail!("{label} failed ({status})")
        }
    }
}

impl Ui {
    /// `run`, as one step of the board's current entry: the spinner turns
    /// while the command works, its latest line shows under it (with a bar
    /// when the line carries a `[ n/m]` counter), and a failure keeps the
    /// last lines and the log's path on screen.
    fn run_on_board(&mut self, label: &str, cmd: &mut Command) -> Result<()> {
        self.log(&format!("---- {label}: {cmd:?}"));
        let start = Instant::now();
        if let Some(b) = self.board.as_mut() {
            b.push(label, Mark::Run);
        }
        self.draw();

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

        let mut tail: VecDeque<String> = VecDeque::with_capacity(6);
        loop {
            match rx.recv_timeout(Duration::from_millis(100)) {
                Ok(raw) => {
                    let text = clean(&raw);
                    self.log(&format!("     {text}"));
                    if text.trim().is_empty() {
                        continue;
                    }
                    if tail.len() == 6 {
                        tail.pop_front();
                    }
                    tail.push_back(text.clone());
                    if let Some(s) = self.board.as_mut().and_then(|b| b.entry()).and_then(|e| e.steps.last_mut()) {
                        match counter_at(&text) {
                            Some((n, m, rest)) => {
                                s.count = Some((n, m));
                                s.detail = rest;
                            }
                            None => s.detail = text,
                        }
                    }
                    self.draw();
                }
                Err(mpsc::RecvTimeoutError::Timeout) => self.draw(),
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
        for p in pumps {
            let _ = p.join();
        }
        let status = child.wait()?;
        let secs = start.elapsed().as_secs();
        let log = self.log_path().map(|p| p.display().to_string());
        if let Some(e) = self.board.as_mut().and_then(|b| b.entry()) {
            if let Some(s) = e.steps.last_mut() {
                s.mark = if status.success() { Mark::Done } else { Mark::Fail };
                s.took = Some(secs);
                s.detail.clear();
            }
            if !status.success() {
                e.mark = Mark::Fail;
                e.tail = tail.into_iter().collect();
                if let Some(l) = log {
                    e.tail.push(format!("full log: {l}"));
                }
            }
        }
        self.draw();
        if status.success() {
            self.log(&format!("ok   {label} ({secs}s)"));
            Ok(())
        } else {
            self.log(&format!("FAIL {label} ({secs}s)"));
            bail!("{label} failed ({status})")
        }
    }
}

pub fn terminal_width() -> usize {
    terminal_size::terminal_size().map(|(w, _)| w.0 as usize).unwrap_or(80)
}

/// Strip escape sequences and keep what a `\r` redraw would leave visible.
pub fn clean(raw: &str) -> String {
    let last = raw.split('\r').filter(|s| !s.trim().is_empty()).last().unwrap_or("");
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

/// Cut to `width` terminal columns, with an ellipsis.
pub fn truncate(s: &str, width: usize) -> String {
    let mut used = 0;
    let mut out = String::new();
    for c in s.chars() {
        let w = c.width().unwrap_or(0);
        if used + w > width.saturating_sub(1) {
            out.push('…');
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
}
