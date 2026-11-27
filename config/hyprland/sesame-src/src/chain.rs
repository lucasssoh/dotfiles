//! "Asked by": the processes above the one that wants a secret, read from
//! /proc, outermost first, each with its whole command and the folder it
//! runs in, e.g. claude › git push origin main › ssh git@github.com
//! git-receive-pack 'u/repo.git', the last in ~/code/repo. The card shows
//! one line of each and unrolls them on demand.

use std::fs;

/// Where the walk stops: the session, the terminal, the desktop. What lies
/// above them says nothing about who asked.
const STOP: &[&str] = &[
    "systemd", "Hyprland", "Hyprland-bin", "wezterm-gui", "wezterm-mux-ser", "kitty", "foot", "alacritty",
    "ghostty", "konsole", "gnome-terminal-", "ptyxis", "tmux: server", "sshd", "sshd-session", "login",
    "greetd", "quickshell", "qs", "uwsm",
];
const SHELLS: &[&str] = &["bash", "zsh", "sh", "dash", "fish"];
/// Only against a runaway argv (a script fed a whole file): the card
/// unrolls the command, it does not need it cut.
const MAX_LEN: usize = 2000;
const MAX_STEPS: usize = 4;

/// One process of the chain.
#[derive(Clone, Debug, PartialEq)]
pub struct Step {
    /// The program's name, then its arguments, the home folder as ~.
    pub cmd: String,
    /// The folder it runs in, the home folder as ~; empty when unreadable.
    pub cwd: String,
}

fn tilde(s: String) -> String {
    match std::env::var("HOME") {
        Ok(home) if !home.is_empty() => s.replace(&home, "~"),
        _ => s,
    }
}

pub fn ppid(pid: u32) -> Option<u32> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    // pid (comm) state ppid …; comm can hold spaces and parentheses.
    let rest = &stat[stat.rfind(')')? + 2..];
    rest.split(' ').nth(1)?.parse().ok()
}

fn comm(pid: u32) -> String {
    fs::read_to_string(format!("/proc/{pid}/comm")).unwrap_or_default().trim().to_string()
}

fn argv(pid: u32) -> Vec<String> {
    let raw = fs::read(format!("/proc/{pid}/cmdline")).unwrap_or_default();
    raw.split(|&b| b == 0).filter(|a| !a.is_empty()).map(|a| String::from_utf8_lossy(a).into_owned()).collect()
}

/// One step as it reads: the program's name, then its arguments.
fn describe(argv: &[String]) -> String {
    let Some(first) = argv.first() else { return String::new() };
    let name = first.rsplit('/').next().unwrap_or(first);
    let mut s = tilde(std::iter::once(name.to_string()).chain(argv[1..].iter().cloned()).collect::<Vec<_>>().join(" "));
    if s.chars().count() > MAX_LEN {
        s = s.chars().take(MAX_LEN - 1).collect::<String>() + "…";
    }
    s
}

/// A shell only running what it was given (`bash -c …`, a login shell) is
/// a wrapper; a shell running a script is the script.
fn is_wrapper(comm: &str, argv: &[String]) -> bool {
    if SHELLS.contains(&comm) {
        return argv.len() < 2 || argv[1].starts_with('-');
    }
    matches!(comm, "env" | "nice" | "timeout" | "stdbuf" | "flock" | "setsid")
}

fn cwd(pid: u32) -> String {
    fs::read_link(format!("/proc/{pid}/cwd")).map(|p| tilde(p.to_string_lossy().into_owned())).unwrap_or_default()
}

pub fn from(start: u32) -> Vec<Step> {
    let mut steps = Vec::new();
    let mut pid = start;
    for _ in 0..16 {
        if pid <= 1 {
            break;
        }
        let c = comm(pid);
        if STOP.contains(&c.as_str()) {
            break;
        }
        let a = argv(pid);
        if !a.is_empty() && !is_wrapper(&c, &a) {
            steps.push(Step { cmd: describe(&a), cwd: cwd(pid) });
        }
        match ppid(pid) {
            Some(p) => pid = p,
            None => break,
        }
    }
    // The nearest steps, outermost first.
    steps.truncate(MAX_STEPS);
    steps.reverse();
    steps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrappers() {
        let v = |s: &str| s.split(' ').map(String::from).collect::<Vec<_>>();
        assert!(is_wrapper("bash", &v("bash -c git push")));
        assert!(is_wrapper("zsh", &v("-zsh")));
        assert!(!is_wrapper("bash", &v("bash packaging/make-repo.sh")));
        assert!(!is_wrapper("git", &v("git push")));
    }

    #[test]
    fn describes() {
        let v = |s: &str| s.split(' ').map(String::from).collect::<Vec<_>>();
        assert_eq!(describe(&v("/usr/bin/git push origin main")), "git push origin main");
    }

    #[test]
    fn long_commands_stay_whole() {
        let long = format!("ssh {}", "x".repeat(300));
        let v = long.split(' ').map(String::from).collect::<Vec<_>>();
        assert_eq!(describe(&v), long);
    }

    #[test]
    fn walks_this_process() {
        // The test runner itself, at least.
        let steps = from(std::process::id());
        assert!(!steps.is_empty());
        // Its folder is where cargo runs it from.
        assert!(!steps.last().unwrap().cwd.is_empty());
    }
}
