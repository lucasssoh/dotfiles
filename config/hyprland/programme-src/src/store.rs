//! What Programme remembers.
//!
//!   ~/.local/share/programme/journal.jsonl  one fact per line, appended: the
//!       source of truth. The state is rebuilt from it, an undo is one more
//!       line, and the measured pace and the Sunday review read it.
//!   ~/.local/share/programme/state.json     the rebuilt state, a cache.
//!   ~/.local/share/programme/plan.json      the last plan, to tell what moved.
//!   ~/.local/share/programme/ade.json       the last good timetable download.
//!   ~/.config/programme/settings.json       settings, written by the app.
//!
//! Whole files are written to a temporary name and renamed over the old one,
//! so a crash never leaves half a file. The course folder is never written.

use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::model::*;
use crate::plan::Pin;
use crate::time::{Date, Hm, Local};

#[derive(Clone, Debug)]
pub struct Paths {
    pub data: PathBuf,
    pub config: PathBuf,
    pub runtime: PathBuf,
    /// khal's calendars folder (`etude/` and `cours/` are Programme's).
    pub khal: PathBuf,
}

impl Paths {
    /// The XDG folders, or PROGRAMME_DATA_DIR, PROGRAMME_CONFIG_DIR and
    /// PROGRAMME_KHAL_DIR for a second instance with data of its own (a test
    /// with made-up courses): moving XDG_CONFIG_HOME instead would move it
    /// for everything the service starts too, Liseuse included, which then
    /// loses the desktop's settings (dark mode first).
    pub fn from_env() -> Paths {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let env = |k: &str, d: PathBuf| std::env::var_os(k).map(PathBuf::from).unwrap_or(d);
        let data = env("XDG_DATA_HOME", home.join(".local/share"));
        Paths {
            data: env("PROGRAMME_DATA_DIR", data.join("programme")),
            config: env("PROGRAMME_CONFIG_DIR", env("XDG_CONFIG_HOME", home.join(".config")).join("programme")),
            runtime: env("XDG_RUNTIME_DIR", std::env::temp_dir()),
            khal: env("PROGRAMME_KHAL_DIR", data.join("khal/calendars")),
        }
    }

    /// Everything under one folder, for tests.
    pub fn under(root: &Path) -> Paths {
        Paths {
            data: root.join("data"),
            config: root.join("config"),
            runtime: root.join("run"),
            khal: root.join("khal"),
        }
    }

    pub fn socket(&self) -> PathBuf {
        self.runtime.join("programme.sock")
    }
}

/// How a part of a session went, from "Done".
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PartReport {
    pub task: String,
    pub minutes: i32,
    /// What the plan gave it.
    pub planned: i32,
    /// Finished (a preparation, a step, a task…).
    pub done: bool,
    pub note: Option<String>,
}

/// A value that may not read any more (written by an older planner): None
/// rather than the whole line lost.
pub fn lenient<'de, D: serde::Deserializer<'de>, T: DeserializeOwned>(d: D) -> Result<Option<T>, D::Error> {
    let v = serde_json::Value::deserialize(d)?;
    Ok(serde_json::from_value(v).ok())
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "ev", rename_all = "kebab-case")]
pub enum Event {
    Started {
        session: String,
        at: Local,
        /// The session as planned when it started, to close it on another day.
        #[serde(default, deserialize_with = "lenient")]
        planned: Option<Box<crate::plan::Session>>,
    },
    /// "Later": always to a precise time.
    Postponed { session: String, to: Local },
    /// "Not tonight", for one task: the others of the evening stay.
    Skipped {
        session: String,
        /// Its task, kept away until tomorrow.
        #[serde(default)]
        tasks: Vec<String>,
        /// The session as it was, to show it and bring it back.
        #[serde(default, deserialize_with = "lenient")]
        planned: Option<Box<crate::plan::Session>>,
    },
    /// "Later, until…": nothing planned, rung or offered from now until
    /// then. Its time is taken out of the plan like a busy one.
    Away { until: Local },
    /// Back before the time said: what is left of it is free again.
    Back { at: Local },
    /// Time found on the spot ("I have time"): a session from `start`.
    Extra { extra: crate::journee::Extra },
    /// Its time went by without a start.
    Missed { session: String },
    /// Stopped before the end, to take up again (the planner before Programme paused
    /// a session for a game; read as it was).
    Paused { session: String, at: Local },
    Resumed { session: String, at: Local },
    Closed {
        session: String,
        at: Local,
        /// The time in front of the course (the window of its command),
        /// else the time the session lasted.
        minutes: i32,
        parts: Vec<PartReport>,
    },
    Deadline { deadline: Deadline },
    DeadlineRemoved { id: String },
    Project { project: Project },
    ProjectRemoved { id: String },
    Campaign { campaign: Campaign },
    Chore { chore: Chore },
    Busy { busy: Busy },
    BusyRemoved { start: Local },
    Pin { pin: Pin },
    Unpin { task: String },
    Undo { of: u64 },
    /// A line of the journal this version no longer reads (the old planner's
    /// course files, reading and contexts): kept in the file, its number
    /// counted, nothing else.
    #[serde(skip)]
    Legacy { ev: String },
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub seq: u64,
    /// When it was written (events carry their own times too).
    #[serde(rename = "logged")]
    pub at: Local,
    #[serde(flatten)]
    pub event: Event,
}

impl Entry {
    /// A journal line: as written, else as a line kept for its number.
    pub fn read(line: &str) -> Option<Entry> {
        if let Ok(e) = serde_json::from_str::<Entry>(line) {
            return Some(e);
        }
        #[derive(Deserialize)]
        struct Raw {
            seq: u64,
            logged: Local,
            ev: String,
        }
        let r: Raw = serde_json::from_str(line).ok()?;
        Some(Entry { seq: r.seq, at: r.logged, event: Event::Legacy { ev: r.ev } })
    }
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "outcome", rename_all = "kebab-case")]
pub enum Outcome {
    Started { at: Local },
    Postponed { to: Local },
    Skipped,
    Missed,
    Paused { at: Local },
    Closed { at: Local },
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct State {
    /// The last journal sequence number.
    pub seq: u64,
    pub progress: Progress,
    pub deadlines: Vec<Deadline>,
    pub projects: Vec<Project>,
    pub campaigns: Vec<Campaign>,
    pub chores: Vec<Chore>,
    pub busy: Vec<Busy>,
    pub pins: Vec<Pin>,
    /// What became of each session.
    pub outcomes: BTreeMap<String, Outcome>,
    /// Real evening start times, to learn from.
    pub starts: Vec<(Date, Hm)>,
    pub missed_streak: u32,
    /// Notes left at "Done", per task.
    pub notes: Vec<(String, Date, String)>,
    /// Sessions as they were when started (until closed).
    pub started: BTreeMap<String, crate::plan::Session>,
    /// Sessions said "not tonight": their day, their tasks, how they were.
    pub skipped: BTreeMap<String, (Date, Vec<String>, Option<crate::plan::Session>)>,
    /// Sessions closed: their day and their tasks.
    pub closed: BTreeMap<String, (Date, Vec<String>)>,
    /// Per subject, its sessions closed: (day, minutes), oldest first.
    pub course_days: BTreeMap<String, Vec<(Date, i32)>>,
    /// Time found on the spot.
    pub extra: Vec<crate::journee::Extra>,
    /// "Later, until…": from when it was said to when it ends.
    pub away: Vec<Busy>,
    /// The slot of the last miss counted, so that several tasks of one
    /// evening count as one session missed.
    pub last_missed_slot: String,
}

/// A miss counts once per slot, however many tasks it held.
fn missed(st: &mut State, session: &str) {
    let slot = session.split('~').next().unwrap_or(session);
    if st.last_missed_slot != slot {
        st.missed_streak += 1;
        st.last_missed_slot = slot.to_string();
    }
}

fn session_date(id: &str) -> Option<Date> {
    id.get(..10).and_then(Date::parse)
}

fn apply_part(st: &mut State, date: Date, r: &PartReport) {
    let (kind, rest) = r.task.split_once(':').unwrap_or((r.task.as_str(), ""));
    match kind {
        "course" if r.minutes > 0 => st.course_days.entry(rest.to_string()).or_default().push((date, r.minutes)),
        "prepare" if r.done => st.progress.prepared.push(rest.to_string()),
        "campaign" if r.done => {
            let id = rest.rsplit_once(':').map_or(rest, |(c, _)| c);
            st.progress.campaign_days.push((id.to_string(), date));
        }
        "interview" if r.done => {
            if let Some((c, name)) = rest.split_once(':') {
                st.progress.interviews_prepared.push((c.to_string(), name.to_string()));
            }
        }
        "chore" if r.done => {
            if let Some(c) = st.chores.iter_mut().find(|c| c.id == rest) {
                c.done = true;
            }
        }
        "project" => {
            let Some((pid, step)) = rest.split_once(':') else { return };
            if let Some(p) = st.projects.iter_mut().find(|p| p.id == pid) {
                if let Some(s) = p.steps.iter_mut().find(|s| s.name == step) {
                    s.spent_minutes += r.minutes;
                    s.done |= r.done;
                }
            } else if let Some(d) = st.deadlines.iter_mut().find(|d| d.id == pid) {
                d.spent_minutes += r.minutes;
                if r.done {
                    d.hours = Some(0.0);
                }
            }
        }
        // The old planner's course files: a session on one counts for its subject.
        "study" | "read" | "redo" | "ask" | "exam" if r.minutes > 0 => {
            if let Some(d) = rest.split('/').next().filter(|d| !d.is_empty()) {
                st.course_days.entry(d.to_string()).or_default().push((date, r.minutes));
            }
        }
        _ => {}
    }
    if let Some(n) = r.note.as_ref().filter(|n| !n.trim().is_empty()) {
        st.notes.push((r.task.clone(), date, n.clone()));
    }
}

fn upsert<T>(v: &mut Vec<T>, item: T, same: impl Fn(&T, &T) -> bool) {
    match v.iter_mut().find(|x| same(x, &item)) {
        Some(x) => *x = item,
        None => v.push(item),
    }
}

/// The state, from the journal. An undone entry is as if never written.
pub fn reduce(entries: &[Entry]) -> State {
    let undone: BTreeSet<u64> = entries
        .iter()
        .filter_map(|e| match e.event {
            Event::Undo { of } => Some(of),
            _ => None,
        })
        .collect();
    let mut st = State::default();
    for e in entries {
        st.seq = st.seq.max(e.seq);
        if undone.contains(&e.seq) {
            continue;
        }
        match &e.event {
            Event::Started { session, at, planned } => {
                st.outcomes.insert(session.clone(), Outcome::Started { at: *at });
                if let Some(p) = planned {
                    st.started.insert(session.clone(), (**p).clone());
                }
                // The evening's first start only: the next task of the
                // same evening says nothing of when it begins.
                if session.contains("-evening") && !st.starts.iter().any(|(d, _)| *d == at.date) {
                    st.starts.push((at.date, at.time));
                }
                st.missed_streak = 0;
                st.last_missed_slot.clear();
            }
            Event::Resumed { session, at } => {
                st.outcomes.insert(session.clone(), Outcome::Started { at: *at });
            }
            Event::Postponed { session, to } => {
                st.outcomes.insert(session.clone(), Outcome::Postponed { to: *to });
            }
            Event::Skipped { session, tasks, planned } => {
                st.outcomes.insert(session.clone(), Outcome::Skipped);
                let date = session_date(session).unwrap_or(e.at.date);
                st.skipped.insert(session.clone(), (date, tasks.clone(), planned.as_deref().cloned()));
                missed(&mut st, session);
            }
            Event::Missed { session } => {
                st.outcomes.insert(session.clone(), Outcome::Missed);
                missed(&mut st, session);
            }
            Event::Extra { extra } => st.extra.push(extra.clone()),
            Event::Away { until } => {
                if *until > e.at {
                    st.away.push(Busy { start: e.at, end: *until, title: String::new() });
                }
            }
            Event::Back { at } => {
                st.away.retain(|a| a.start < *at);
                for a in st.away.iter_mut().filter(|a| a.end > *at) {
                    a.end = *at;
                }
            }
            Event::Paused { session, at } => {
                st.outcomes.insert(session.clone(), Outcome::Paused { at: *at });
            }
            Event::Closed { session, at, parts, .. } => {
                let date = session_date(session).unwrap_or(at.date);
                // A session started late at night still belongs to its day.
                st.outcomes.insert(session.clone(), Outcome::Closed { at: *at });
                st.started.remove(session);
                st.closed.insert(session.clone(), (date, parts.iter().map(|p| p.task.clone()).collect()));
                for p in parts {
                    apply_part(&mut st, date, p);
                }
                st.missed_streak = 0;
                st.last_missed_slot.clear();
            }
            Event::Deadline { deadline } => upsert(&mut st.deadlines, deadline.clone(), |a, b| a.id == b.id),
            Event::DeadlineRemoved { id } => st.deadlines.retain(|d| d.id != *id),
            Event::Project { project } => upsert(&mut st.projects, project.clone(), |a, b| a.id == b.id),
            Event::ProjectRemoved { id } => st.projects.retain(|p| p.id != *id),
            Event::Campaign { campaign } => upsert(&mut st.campaigns, campaign.clone(), |a, b| a.id == b.id),
            Event::Chore { chore } => upsert(&mut st.chores, chore.clone(), |a, b| a.id == b.id),
            Event::Busy { busy } => st.busy.push(busy.clone()),
            Event::BusyRemoved { start } => st.busy.retain(|b| b.start != *start),
            Event::Pin { pin } => upsert(&mut st.pins, pin.clone(), |a, b| a.task == b.task),
            Event::Unpin { task } => st.pins.retain(|p| p.task != *task),
            Event::Undo { .. } | Event::Legacy { .. } => {}
        }
    }
    st
}

pub fn read_json<T: DeserializeOwned>(path: &Path) -> Option<T> {
    let text = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

/// Written to a temporary file, then renamed over the old one.
pub fn write_json<T: Serialize>(path: &Path, value: &T) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    let mut f = std::fs::File::create(&tmp)?;
    serde_json::to_writer_pretty(&mut f, value)?;
    f.write_all(b"\n")?;
    f.sync_all()?;
    std::fs::rename(tmp, path)
}

pub struct Store {
    pub paths: Paths,
    pub settings: Settings,
    pub entries: Vec<Entry>,
    pub state: State,
}

impl Store {
    pub fn open(paths: Paths) -> io::Result<Store> {
        std::fs::create_dir_all(&paths.data)?;
        let settings = read_json(&paths.config.join("settings.json")).unwrap_or_default();
        let mut entries = Vec::new();
        if let Ok(f) = std::fs::File::open(paths.data.join("journal.jsonl")) {
            for line in io::BufReader::new(f).lines().map_while(Result::ok) {
                // A line cut by a crash is skipped, never fatal.
                if let Some(e) = Entry::read(&line) {
                    entries.push(e);
                }
            }
        }
        let state = reduce(&entries);
        Ok(Store { paths, settings, entries, state })
    }

    /// Appends a fact and returns its sequence number.
    pub fn record(&mut self, event: Event, now: Local) -> io::Result<u64> {
        let entry = Entry { seq: self.state.seq + 1, at: now, event };
        let mut line = serde_json::to_string(&entry)?;
        line.push('\n');
        let mut f = std::fs::OpenOptions::new().create(true).append(true).open(self.paths.data.join("journal.jsonl"))?;
        f.write_all(line.as_bytes())?;
        let seq = entry.seq;
        self.entries.push(entry);
        self.state = reduce(&self.entries);
        write_json(&self.paths.data.join("state.json"), &self.state)?;
        Ok(seq)
    }

    /// Undoes the last entry matching `which`, not already undone.
    pub fn undo_where(&mut self, now: Local, which: impl Fn(&Event) -> bool) -> io::Result<Option<Entry>> {
        let undone: BTreeSet<u64> = self
            .entries
            .iter()
            .filter_map(|e| if let Event::Undo { of } = e.event { Some(of) } else { None })
            .collect();
        let Some(e) = self.entries.iter().rev().find(|e| which(&e.event) && !undone.contains(&e.seq)).cloned() else {
            return Ok(None);
        };
        self.record(Event::Undo { of: e.seq }, now)?;
        Ok(Some(e))
    }

    /// Undoes the last change that can be undone (not an undo, not one
    /// already undone). Returns what was undone.
    pub fn undo(&mut self, now: Local) -> io::Result<Option<Entry>> {
        let undone: BTreeSet<u64> = self
            .entries
            .iter()
            .filter_map(|e| match e.event {
                Event::Undo { of } => Some(of),
                _ => None,
            })
            .collect();
        let target = self
            .entries
            .iter()
            .rev()
            .find(|e| !matches!(e.event, Event::Undo { .. } | Event::Missed { .. } | Event::Legacy { .. }) && !undone.contains(&e.seq))
            .cloned();
        if let Some(t) = &target {
            self.record(Event::Undo { of: t.seq }, now)?;
        }
        Ok(target)
    }

    /// The last changes, newest first (for the history list).
    pub fn history(&self, n: usize) -> Vec<&Entry> {
        self.entries.iter().rev().filter(|e| !matches!(e.event, Event::Missed { .. } | Event::Legacy { .. })).take(n).collect()
    }

    pub fn save_settings(&self) -> io::Result<()> {
        write_json(&self.paths.config.join("settings.json"), &self.settings)
    }
}
