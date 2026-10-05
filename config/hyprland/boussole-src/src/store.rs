//! What Boussole remembers.
//!
//!   ~/.local/share/boussole/journal.jsonl  one fact per line, appended: the
//!       source of truth. The state is rebuilt from it, an undo is one more
//!       line, and the measured pace and the Sunday review read it.
//!   ~/.local/share/boussole/state.json     the rebuilt state, a cache.
//!   ~/.local/share/boussole/plan.json      the last plan, to tell what moved.
//!   ~/.local/share/boussole/ade.json       the last good timetable download.
//!   ~/.config/boussole/settings.json       settings, written by the app.
//!
//! Whole files are written to a temporary name and renamed over the old one,
//! so a crash never leaves half a file. The course folder is never written.

use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::catalogue::Inclusion;
use crate::model::*;
use crate::plan::Pin;
use crate::time::{Date, Hm, Local};

#[derive(Clone, Debug)]
pub struct Paths {
    pub data: PathBuf,
    pub config: PathBuf,
    pub runtime: PathBuf,
    /// khal's calendars folder (`etude/` and `cours/` are Boussole's).
    pub khal: PathBuf,
}

impl Paths {
    pub fn from_env() -> Paths {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let env = |k: &str, d: PathBuf| std::env::var_os(k).map(PathBuf::from).unwrap_or(d);
        let data = env("XDG_DATA_HOME", home.join(".local/share"));
        Paths {
            data: data.join("boussole"),
            config: env("XDG_CONFIG_HOME", home.join(".config")).join("boussole"),
            runtime: env("XDG_RUNTIME_DIR", std::env::temp_dir()),
            khal: data.join("khal/calendars"),
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
        self.runtime.join("boussole.sock")
    }
}

/// How a part of a session went, from "Close" or a check-in.
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PartReport {
    pub task: String,
    pub minutes: i32,
    /// Finished (a sheet's first pass, a review, a step…).
    pub done: bool,
    pub read_upto: Option<u32>,
    #[serde(with = "number_keys")]
    pub exercises: BTreeMap<u32, Exercise>,
    pub assessment: Option<Assessment>,
    pub note: Option<String>,
}

/// Exercise numbers as JSON keys. Inside a tagged enum serde buffers the
/// map and no longer turns "2" back into 2 on its own.
mod number_keys {
    use std::collections::BTreeMap;

    use serde::{Deserialize, Deserializer, Serialize, Serializer};

    use crate::model::Exercise;

    pub fn serialize<S: Serializer>(m: &BTreeMap<u32, Exercise>, s: S) -> Result<S::Ok, S::Error> {
        m.iter().map(|(k, v)| (k.to_string(), *v)).collect::<BTreeMap<String, Exercise>>().serialize(s)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<BTreeMap<u32, Exercise>, D::Error> {
        let m = BTreeMap::<String, Exercise>::deserialize(d)?;
        m.into_iter()
            .map(|(k, v)| k.parse().map(|k| (k, v)).map_err(serde::de::Error::custom))
            .collect()
    }
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "ev", rename_all = "kebab-case")]
pub enum Event {
    Started { session: String, at: Local },
    /// "Later": always to a precise time.
    Postponed { session: String, to: Local },
    /// "Not tonight".
    Skipped { session: String },
    /// Its time went by without a start.
    Missed { session: String },
    /// A game launched anyway: the session waits.
    Paused { session: String, at: Local },
    Closed { session: String, at: Local, minutes: i32, parts: Vec<PartReport> },
    Files { items: Vec<String>, inclusion: Inclusion },
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
    /// Notes left at "Close", per task.
    pub notes: Vec<(String, Date, String)>,
}

fn session_date(id: &str) -> Option<Date> {
    id.get(..10).and_then(Date::parse)
}

fn apply_part(st: &mut State, date: Date, r: &PartReport) {
    let (kind, rest) = r.task.split_once(':').unwrap_or((r.task.as_str(), ""));
    fn item<'a>(st: &'a mut State, id: &str) -> &'a mut ItemProgress {
        st.progress.items.entry(id.to_string()).or_default()
    }
    match kind {
        "study" | "read" | "redo" => {
            let p = item(st, rest);
            if let Some(n) = r.read_upto {
                p.read_upto = p.read_upto.max(n);
            }
            p.exercises.extend(r.exercises.iter().map(|(k, v)| (*k, *v)));
            p.last_on = Some(date);
            if let Some(a) = r.assessment {
                p.assessment = Some(a);
                if a == Assessment::Blocked {
                    p.question_open = true;
                }
            }
            if r.done && kind != "redo" {
                p.studied_on.get_or_insert(date);
                if kind == "read" {
                    p.done = true;
                }
            }
        }
        k if k.starts_with("review") => {
            let p = item(st, rest);
            p.exercises.extend(r.exercises.iter().map(|(k, v)| (*k, *v)));
            p.last_on = Some(date);
            if let Some(a) = r.assessment {
                p.assessment = Some(a);
                p.question_open |= a == Assessment::Blocked;
            }
            if r.done {
                p.reviews_done.push(date);
            }
        }
        "ask" if r.done => item(st, rest).question_open = false,
        "exam" if r.done => {
            let (id, n) = rest.rsplit_once('#').unwrap_or((rest, "1"));
            let p = item(st, id);
            p.subjects_done = p.subjects_done.max(n.parse().unwrap_or(1));
            p.last_on = Some(date);
        }
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
            Event::Started { session, at } => {
                st.outcomes.insert(session.clone(), Outcome::Started { at: *at });
                if session.contains("-evening") {
                    st.starts.push((at.date, at.time));
                }
                st.missed_streak = 0;
            }
            Event::Postponed { session, to } => {
                st.outcomes.insert(session.clone(), Outcome::Postponed { to: *to });
            }
            Event::Skipped { session } => {
                st.outcomes.insert(session.clone(), Outcome::Skipped);
                st.missed_streak += 1;
            }
            Event::Missed { session } => {
                st.outcomes.insert(session.clone(), Outcome::Missed);
                st.missed_streak += 1;
            }
            Event::Paused { session, at } => {
                st.outcomes.insert(session.clone(), Outcome::Paused { at: *at });
            }
            Event::Closed { session, at, parts, .. } => {
                let date = session_date(session).unwrap_or(at.date);
                // A session started late at night still belongs to its day.
                st.outcomes.insert(session.clone(), Outcome::Closed { at: *at });
                for p in parts {
                    apply_part(&mut st, date, p);
                }
                st.missed_streak = 0;
            }
            Event::Files { items, inclusion } => {
                for i in items {
                    st.progress.files.insert(i.clone(), *inclusion);
                }
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
            Event::Undo { .. } => {}
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
                if let Ok(e) = serde_json::from_str::<Entry>(&line) {
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
            .find(|e| !matches!(e.event, Event::Undo { .. } | Event::Missed { .. }) && !undone.contains(&e.seq))
            .cloned();
        if let Some(t) = &target {
            self.record(Event::Undo { of: t.seq }, now)?;
        }
        Ok(target)
    }

    /// The last changes, newest first (for the history list).
    pub fn history(&self, n: usize) -> Vec<&Entry> {
        self.entries.iter().rev().filter(|e| !matches!(e.event, Event::Missed { .. })).take(n).collect()
    }

    pub fn save_settings(&self) -> io::Result<()> {
        write_json(&self.paths.config.join("settings.json"), &self.settings)
    }
}
