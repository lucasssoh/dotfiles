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
use std::time::Instant;

use anyhow::{Context, Result, bail};
use unicode_width::UnicodeWidthChar;

pub struct Ui {
    pub color: bool,
    pub quiet: bool,
    pub verbose: bool,
    pub tty: bool,
    log: Option<(PathBuf, File)>,
}

impl Ui {
    pub fn new(no_color: bool, quiet: bool, verbose: bool) -> Ui {
        let tty = std::io::stdout().is_terminal();
        let color = tty && !no_color && std::env::var_os("NO_COLOR").is_none();
        Ui { color, quiet, verbose, tty, log: None }
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
        if !self.quiet {
            println!("\n{}", self.bold(s));
        }
    }

    pub fn line(&mut self, s: &str) {
        self.log(s);
        if !self.quiet {
            println!("{s}");
        }
    }

    pub fn ok(&mut self, label: &str) {
        self.log(&format!("ok   {label}"));
        if !self.quiet {
            println!("  {} {label}", self.green("✓"));
        }
    }

    pub fn skip(&mut self, label: &str) {
        self.log(&format!("skip {label}"));
        if !self.quiet {
            println!("  {} {label}", self.dim("○"));
        }
    }

    pub fn warn(&mut self, msg: &str) {
        self.log(&format!("warn {msg}"));
        eprintln!("  {} {msg}", self.yellow("!"));
    }

    pub fn fail(&mut self, label: &str) {
        self.log(&format!("FAIL {label}"));
        eprintln!("  {} {label}", self.red("✗"));
    }

    /// Run `cmd` as one step. stdin closed, output to the log with a live
    /// detail line on a terminal. On failure, prints the last lines.
    pub fn run(&mut self, label: &str, cmd: &mut Command) -> Result<()> {
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
}
