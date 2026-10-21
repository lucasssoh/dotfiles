//! A session under way: its command, and the time in front of the course.
//!
//! Starting a session of a subject runs the subject's command (`launch` in
//! its settings: Boussole open on the subject, where it was left). While the
//! session runs, Hyprland's event socket says which window has the focus,
//! and the session's time counts while it is the course's: Firefox on
//! Boussole. Anywhere else nothing counts, and the bar shows notifications
//! again. A subject without a command has no window to watch: its time is
//! the session's own.
//!
//! The socket is only open during a session; outside one, nothing is
//! watched at all.

use std::io::{ErrorKind, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::Command;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::daemon::{now_secs, set_nonblocking, which, Job, Service};
use crate::store::{self, Outcome};

/// The course's window: Boussole, in Firefox.
pub const WINDOW_CLASS: &str = "org.mozilla.firefox";
pub const WINDOW_TITLE: &str = "Boussole";

/// Whether a window is the course's.
pub fn is_course_window(class: &str, title: &str) -> bool {
    class == WINDOW_CLASS && title.contains(WINDOW_TITLE)
}

/// The session followed, kept in watch.json so that a restart of the
/// service loses nothing of its count.
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Watch {
    pub session: String,
    /// Its subject has a command, hence a window to watch.
    pub watched: bool,
    /// Seconds counted before `since`.
    pub counted: i64,
    /// Counting since then: the course's window has the focus (or, for a
    /// session without a window, the session runs).
    pub since: Option<i64>,
}

impl Watch {
    pub fn effective(&self, now: i64) -> i64 {
        self.counted + self.since.map_or(0, |s| (now - s).max(0))
    }

    pub fn set_counting(&mut self, on: bool, now: i64) {
        match (on, self.since) {
            (true, None) => self.since = Some(now),
            (false, Some(s)) => {
                self.counted += (now - s).max(0);
                self.since = None;
            }
            _ => {}
        }
    }
}

#[derive(Default)]
pub struct Watcher {
    pub watch: Option<Watch>,
    pub hypr: Option<UnixStream>,
    buf: Vec<u8>,
}

pub(crate) fn hypr_dir() -> Option<PathBuf> {
    let run = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?).join("hypr");
    if let Some(sig) = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE") {
        return Some(run.join(sig));
    }
    // A user service may start without Hyprland's environment: the newest instance.
    std::fs::read_dir(&run)
        .ok()?
        .flatten()
        .filter(|e| e.path().join(".socket2.sock").exists())
        .max_by_key(|e| e.metadata().and_then(|m| m.modified()).ok())
        .map(|e| e.path())
}

/// The focused window's class and title, asked once (~1 ms).
fn active_window() -> Option<(String, String)> {
    let mut s = UnixStream::connect(hypr_dir()?.join(".socket.sock")).ok()?;
    let _ = s.set_read_timeout(Some(std::time::Duration::from_millis(500)));
    s.write_all(b"j/activewindow").ok()?;
    let mut out = Vec::new();
    let _ = s.read_to_end(&mut out);
    let v: Value = serde_json::from_slice(&out).ok()?;
    Some((v["class"].as_str()?.to_string(), v["title"].as_str().unwrap_or("").to_string()))
}

impl Service {
    fn watch_path(&self) -> PathBuf {
        self.store.paths.data.join("watch.json")
    }

    fn watch_save(&self) {
        match &self.watcher.watch {
            Some(w) => drop(store::write_json(&self.watch_path(), w)),
            None => drop(std::fs::remove_file(self.watch_path())),
        }
    }

    /// At start: the session followed before a restart, if it still runs.
    pub(crate) fn watch_load(&mut self) {
        let w: Option<Watch> = store::read_json(&self.watch_path());
        self.watcher.watch = w.filter(|w| matches!(self.store.state.outcomes.get(&w.session), Some(Outcome::Started { .. })));
        if self.watcher.watch.is_some() {
            self.watch_connect();
        } else {
            self.watch_save();
        }
    }

    /// The subject's command, `{folder}` filled in.
    pub(crate) fn launch_args(&self, session: &str) -> Option<Vec<String>> {
        let s = self.session_any(session)?;
        let domain = s.course()?;
        let d = self.store.settings.domains.iter().find(|d| d.id == domain)?;
        d.launch_args(self.store.settings.courses.as_deref())
    }

    /// Runs the session's command ("Launch"). False when it has none, or
    /// the program cannot be found.
    pub(crate) fn launch(&mut self, session: &str) -> bool {
        let Some(args) = self.launch_args(session) else { return false };
        let Some((prog, rest)) = args.split_first() else { return false };
        let Some(path) = which(prog).or_else(|| prog.contains('/').then(|| PathBuf::from(prog))) else { return false };
        self.spawn(Command::new(path).args(rest), Job::Quiet);
        true
    }

    /// A session starts being followed.
    pub(crate) fn watch_start(&mut self, session: &str) {
        let now = now_secs();
        let watched = self.launch_args(session).is_some();
        let mut w = Watch { session: session.to_string(), watched, ..Watch::default() };
        w.set_counting(!watched, now);
        self.watcher.watch = Some(w);
        self.watch_connect();
        self.watch_save();
    }

    /// The session ends: the minutes counted.
    pub(crate) fn watch_stop(&mut self, session: &str) -> Option<i32> {
        let w = self.watcher.watch.take().filter(|w| w.session == session);
        self.watcher.hypr = None;
        self.watcher.buf.clear();
        self.watch_save();
        w.map(|w| ((w.effective(now_secs()) + 30) / 60) as i32)
    }

    fn watch_connect(&mut self) {
        let watched = self.watcher.watch.as_ref().is_some_and(|w| w.watched);
        if !watched || self.watcher.hypr.is_some() {
            return;
        }
        let Some(dir) = hypr_dir() else { return };
        if let Ok(s) = UnixStream::connect(dir.join(".socket2.sock")) {
            set_nonblocking(s.as_raw_fd());
            self.watcher.hypr = Some(s);
        }
        let on = active_window().is_some_and(|(c, t)| is_course_window(&c, &t));
        self.watch_focus(on);
    }

    fn watch_focus(&mut self, on: bool) {
        let now = now_secs();
        let Some(w) = self.watcher.watch.as_mut() else { return };
        if w.since.is_some() == on {
            return;
        }
        w.set_counting(on, now);
        self.watch_save();
        self.push_status();
    }

    /// Hyprland's events: only `activewindow` (class, title) matters.
    pub(crate) fn read_hypr(&mut self) {
        let Some(s) = self.watcher.hypr.as_mut() else { return };
        let mut buf = [0u8; 8192];
        let mut gone = false;
        loop {
            match s.read(&mut buf) {
                Ok(0) => {
                    gone = true;
                    break;
                }
                Ok(n) => self.watcher.buf.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => {
                    gone = true;
                    break;
                }
            }
        }
        if gone {
            // Hyprland restarted: connected again at the next wake.
            self.watcher.hypr = None;
        }
        let mut focus = None;
        while let Some(nl) = self.watcher.buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.watcher.buf.drain(..=nl).collect();
            let line = String::from_utf8_lossy(&line);
            if let Some(rest) = line.trim_end().strip_prefix("activewindow>>") {
                let (class, title) = rest.split_once(',').unwrap_or((rest, ""));
                focus = Some(is_course_window(class, title));
            }
        }
        if let Some(on) = focus {
            self.watch_focus(on);
        }
    }

    /// On every wake: a session closed or undone elsewhere stops being
    /// followed; a lost socket is opened again.
    pub(crate) fn watch_tick(&mut self) {
        let Some(id) = self.watcher.watch.as_ref().map(|w| w.session.clone()) else { return };
        if !matches!(self.store.state.outcomes.get(&id), Some(Outcome::Started { .. })) {
            self.watcher.watch = None;
            self.watcher.hypr = None;
            self.watch_save();
            return;
        }
        if self.watcher.hypr.is_none() {
            self.watch_connect();
        }
    }

    /// For the bar: the session followed, its seconds as of now and
    /// whether they still count.
    pub(crate) fn watch_status(&self) -> Value {
        let now = now_secs();
        match &self.watcher.watch {
            Some(w) => json!({
                "session": w.session,
                "watched": w.watched,
                "counting": w.since.is_some(),
                "effective_secs": w.effective(now),
                "as_of": now,
                "launch": self.launch_args(&w.session).is_some(),
            }),
            None => Value::Null,
        }
    }
}
