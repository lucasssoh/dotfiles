//! The planner: a pure function from what is known (catalogue, progress,
//! timetable, deadlines, projects, settings, the time) to a plan, and the
//! differences with the previous one. No clock, no file, no randomness: the
//! same input always gives the same plan, which is what the tests rely on.
//!
//! In order:
//!   1. the slots of every day up to the horizon (journee);
//!   2. what cannot move: pinned sessions, the margin kept before exams,
//!      campaign time, interview preparation, then projects and hand-ins,
//!      spread evenly up to 3 days before they are due. Untouchable: when
//!      time runs short, sheets slide, never these;
//!   3. counted slots filled in order with the best task available:
//!      closest deadline, then work already started, then the domain most
//!      behind, then ★, then course order, alternating domains between
//!      sessions; short reviews and redos fill what is left of a session;
//!   4. optional slots (gaps at school, Saturday, a free evening near an
//!      exam) offer the next counted work as a head start;
//!   5. margins before each exam, and what moved since the previous plan.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::catalogue::{Catalogue, Inclusion, Item, ItemKind};
use crate::journee::{self, Place, Slot, SlotKind};
use crate::model::*;
use crate::time::{Date, Hm, Local};

/// Everything the planner reads. Borrowed: the service owns the state.
pub struct Input<'a> {
    pub now: Local,
    pub settings: &'a Settings,
    pub domains: &'a [Domain],
    pub catalogue: &'a Catalogue,
    pub progress: &'a Progress,
    /// The user's courses (already filtered to their groups).
    pub courses: &'a [Course],
    /// A calendar feed is set up (an empty one then means "no more courses").
    pub calendar: bool,
    pub busy: &'a [Busy],
    pub deadlines: &'a [Deadline],
    pub projects: &'a [Project],
    pub campaigns: &'a [Campaign],
    pub chores: &'a [Chore],
    pub pinned: &'a [Pin],
    /// Learnt evening start per weekday (journee::learn_start).
    pub learned: [Option<Hm>; 7],
    /// Counted sessions missed in a row, from the journal.
    pub missed_streak: u32,
    /// Sessions already over (closed, skipped, missed): their slot is not reused.
    pub spent: &'a [String],
    pub previous: Option<&'a Plan>,
}

/// A session the user fixed: it does not move, the rest goes around it.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Pin {
    pub task: String,
    pub date: Date,
    pub start: Hm,
    pub minutes: i32,
    #[serde(default)]
    pub work: Option<Work>,
    #[serde(default)]
    pub domain: Option<String>,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "work", rename_all = "kebab-case")]
pub enum Work {
    /// Part of a sheet or synthesis file: sections to read, exercises to do.
    Study { item: String, sections: Option<(u32, u32)>, exercises: Option<(u32, u32)> },
    /// A whole file: a map, a PDF, notes, one tutorial exercise.
    Read { item: String },
    Review { item: String, n: u32 },
    /// Exercises failed, redone without the solution.
    Redo { item: String, exercises: Vec<u32> },
    Question { item: String },
    /// One exam-type subject, in limited time.
    ExamSubject { item: String, n: u32 },
    Prepare { course: String, title: String, at: Local },
    Project { project: String, step: String },
    Campaign { campaign: String },
    Interview { campaign: String, company: String },
    Chore { chore: String, title: String },
    /// After missed sessions: ten minutes of recall to start again.
    Recall { item: Option<String> },
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Part {
    /// The task this belongs to, stable from one plan to the next.
    pub task: String,
    pub domain: Option<String>,
    pub minutes: i32,
    #[serde(flatten)]
    pub work: Work,
    #[serde(default)]
    pub timed: bool,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "why", rename_all = "kebab-case")]
pub enum Reason {
    Deadline { title: String, date: Date, days: i32, margin: Option<i32> },
    Starred { note: Option<String> },
    /// Started last time, so first in line.
    Continues,
    /// The domain had nothing since `last`: domains alternate.
    Rotation { domain: String, last: Option<Date> },
    Behind { domain: String },
    CourseOrder,
    ReviewDue { n: u32, studied: Date },
    RedoDue { since: Date },
    Prepare { at: Local },
    ProjectDue { name: String, due: Date },
    Pinned,
    Restart { missed: u32 },
    /// An optional slot: doing it gives a head start.
    HeadStart,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Session {
    /// Date, kind and rank in the day: stable while the day keeps its shape.
    pub id: String,
    pub date: Date,
    pub start: Hm,
    pub end: Hm,
    pub kind: SlotKind,
    pub counted: bool,
    pub place: Place,
    pub shortened: bool,
    pub pinned: bool,
    pub parts: Vec<Part>,
    pub reasons: Vec<Reason>,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Margin {
    pub deadline: String,
    pub title: String,
    pub date: Date,
    pub domain: Option<String>,
    /// Counted sessions to spare before it; negative when work does not fit.
    pub sessions: i32,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "change", rename_all = "kebab-case")]
pub enum Change {
    /// A task's first session moved.
    Moved { task: String, work: Work, domain: Option<String>, from: Date, to: Date },
    /// Planned before, now past the horizon.
    Unplaced { task: String, work: Work, domain: Option<String>, was: Date },
    Margin { deadline: String, title: String, from: i32, to: i32 },
    /// Untouchable work that no longer fits before its date.
    AtRisk { task: String, work: Work, due: Date, missing_minutes: i32 },
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct Plan {
    pub made: Option<Local>,
    pub paused: bool,
    pub sessions: Vec<Session>,
    /// Optional slots and what they could hold.
    pub offers: Vec<Session>,
    pub margins: Vec<Margin>,
    pub changes: Vec<Change>,
}

impl Plan {
    /// The first counted date of each task.
    pub fn first_dates(&self, from: Date) -> BTreeMap<String, (Date, Work, Option<String>)> {
        let mut m = BTreeMap::new();
        for s in self.sessions.iter().filter(|s| s.date >= from) {
            for p in &s.parts {
                m.entry(p.task.clone()).or_insert((s.date, p.work.clone(), p.domain.clone()));
            }
        }
        m
    }

    pub fn session(&self, id: &str) -> Option<&Session> {
        self.sessions.iter().chain(&self.offers).find(|s| s.id == id)
    }
}

// ─── Tasks ───────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Unit {
    Section(u32),
    Exercise(u32),
}

#[derive(Clone, Debug)]
struct Task {
    key: String,
    domain: Option<String>,
    item: Option<String>,
    kind: TaskKind,
    /// Whole-task minutes (the overhead included); for a sheet, see `units`.
    minutes: i32,
    /// What is left of a sheet, in order, with minutes each.
    units: Vec<(Unit, i32)>,
    overhead: i32,
    available: Date,
    /// Must be done on a date strictly before it.
    before: Option<Date>,
    /// Soft due date, for priority.
    due: Option<Date>,
    timed: bool,
    short: bool,
    starred: bool,
    star_note: Option<String>,
    in_progress: bool,
    order: usize,
    work: Work,
    reason: Option<Reason>,
    /// Part of a domain's sequence (one at a time, in course order).
    seq: bool,
    done: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum TaskKind {
    Sheet,
    Whole,
    Short,
    Exam,
    Prepare,
    Chore,
}

fn factor(input: &Input, domain: &str) -> f32 {
    input.settings.pace.domain_factor.get(domain).copied().unwrap_or(1.0)
}

fn scaled(m: i32, f: f32) -> i32 {
    ((m as f32 * f).round() as i32).max(1)
}

/// Exam or test of a domain, the next one on or after `date`.
fn domain_deadline<'a>(input: &'a Input, domain: &str, date: Date) -> Option<&'a Deadline> {
    input
        .deadlines
        .iter()
        .filter(|d| matches!(d.kind, DeadlineKind::Exam | DeadlineKind::Cc))
        .filter(|d| d.domain.as_deref() == Some(domain) && d.at.date >= date)
        .min_by_key(|d| d.at)
}

fn sheet_task(input: &Input, item: &Item, p: &ItemProgress, order: usize) -> Option<Task> {
    let pace = &input.settings.pace;
    let f = factor(input, &item.domain);
    let mut units = Vec::new();
    let to_read: Vec<u32> = item.sections.iter().map(|s| s.num).filter(|&n| n > p.read_upto).collect();
    if !to_read.is_empty() {
        let per = (pace.reading / item.sections.len().max(1) as i32).max(2);
        for (i, n) in to_read.iter().enumerate() {
            // Recall comes once the last section is read.
            let extra = if i + 1 == to_read.len() { pace.recall } else { 0 };
            units.push((Unit::Section(*n), scaled(per + extra, f)));
        }
    }
    let per_ex = if item.kind == ItemKind::Synthesis { pace.exercise * 2 } else { pace.exercise };
    for n in 1..=item.exercises {
        if !p.exercises.contains_key(&n) {
            units.push((Unit::Exercise(n), scaled(per_ex, f)));
        }
    }
    if units.is_empty() {
        return None;
    }
    Some(Task {
        key: format!("study:{}", item.id),
        domain: Some(item.domain.clone()),
        item: Some(item.id.clone()),
        kind: TaskKind::Sheet,
        minutes: 0,
        overhead: pace.overhead,
        units,
        available: Date(i32::MIN),
        before: None,
        due: None,
        timed: false,
        short: false,
        starred: item.starred,
        star_note: item.star_note.clone(),
        in_progress: p.read_upto > 0 || !p.exercises.is_empty(),
        order,
        work: Work::Study { item: item.id.clone(), sections: None, exercises: None },
        reason: None,
        seq: true,
        done: false,
    })
}

fn simple(key: String, domain: Option<String>, item: Option<String>, kind: TaskKind, minutes: i32, work: Work) -> Task {
    Task {
        key,
        domain,
        item,
        kind,
        minutes,
        units: Vec::new(),
        overhead: 0,
        available: Date(i32::MIN),
        before: None,
        due: None,
        timed: false,
        short: kind == TaskKind::Short,
        starred: false,
        star_note: None,
        in_progress: false,
        order: usize::MAX,
        work,
        reason: None,
        seq: false,
        done: false,
    }
}

fn tasks(input: &Input, today: Date) -> Vec<Task> {
    let pace = &input.settings.pace;
    let objective = input.settings.objective;
    let mut out = Vec::new();
    let empty = ItemProgress::default();
    for d in input.domains.iter().filter(|d| !d.archived) {
        let f = factor(input, &d.id);
        let exam = domain_deadline(input, &d.id, today);
        for (order, item) in input.catalogue.ordered(d).iter().enumerate() {
            if input.progress.files.get(&item.id) != Some(&Inclusion::Planned) {
                continue;
            }
            let p = input.progress.items.get(&item.id).unwrap_or(&empty);
            let studied = p.done || p.studied_on.is_some();
            match item.kind {
                ItemKind::Sheet | ItemKind::Synthesis if !studied => {
                    if let Some(t) = sheet_task(input, item, p, order) {
                        out.push(t);
                    }
                }
                ItemKind::Map | ItemKind::Pdf | ItemKind::Notes | ItemKind::TdExercise if !studied => {
                    let m = match item.kind {
                        ItemKind::Map => pace.map,
                        ItemKind::Pdf => pace.pdf,
                        ItemKind::TdExercise => pace.exercise * 2,
                        _ => pace.notes,
                    };
                    let mut t = simple(
                        format!("read:{}", item.id),
                        Some(d.id.clone()),
                        Some(item.id.clone()),
                        TaskKind::Whole,
                        scaled(m, f),
                        Work::Read { item: item.id.clone() },
                    );
                    t.seq = true;
                    t.order = order;
                    t.starred = item.starred;
                    t.star_note = item.star_note.clone();
                    out.push(t);
                }
                ItemKind::ExamPractice => {
                    // Time-limited subjects only make sense against an exam date.
                    let Some(exam) = exam else { continue };
                    let from = exam.at.date.add(-7 * objective.exam_practice_weeks());
                    for n in p.subjects_done + 1..=item.subjects {
                        let mut t = simple(
                            format!("exam:{}#{n}", item.id),
                            Some(d.id.clone()),
                            Some(item.id.clone()),
                            TaskKind::Exam,
                            scaled(pace.exam_subject, f),
                            Work::ExamSubject { item: item.id.clone(), n },
                        );
                        t.available = from;
                        t.before = Some(exam.at.date);
                        t.due = Some(exam.at.date);
                        t.timed = true;
                        t.order = order;
                        out.push(t);
                    }
                }
                _ => {}
            }

            // Spaced reviews: J+7 (J+3 when "to review"), then J+21.
            if let (true, Some(on)) = (d.spaced, p.studied_on) {
                let n = p.reviews_done.len() as u32;
                let offset = match n {
                    0 if p.assessment == Some(Assessment::Review) => Some(3),
                    0 => Some(7),
                    1 => Some(21),
                    _ => None,
                };
                if let Some(offset) = offset {
                    let mut t = simple(
                        format!("review{}:{}", n + 1, item.id),
                        Some(d.id.clone()),
                        Some(item.id.clone()),
                        TaskKind::Short,
                        scaled(pace.review, f),
                        Work::Review { item: item.id.clone(), n: n + 1 },
                    );
                    t.available = on.add(offset);
                    t.due = Some(on.add(offset + 7));
                    t.reason = Some(Reason::ReviewDue { n: n + 1, studied: on });
                    out.push(t);
                }
            }
            // Failed exercises come back at J+3, without the solution.
            let failed: Vec<u32> = p
                .exercises
                .iter()
                .filter(|(_, e)| {
                    **e == Exercise::Failed || (**e == Exercise::WithSolution && !objective.solution_counts())
                })
                .map(|(n, _)| *n)
                .collect();
            if let (false, Some(last)) = (failed.is_empty(), p.last_on) {
                let mut t = simple(
                    format!("redo:{}", item.id),
                    Some(d.id.clone()),
                    Some(item.id.clone()),
                    TaskKind::Short,
                    scaled(pace.redo, f).max(scaled(pace.exercise, f) * failed.len().min(3) as i32),
                    Work::Redo { item: item.id.clone(), exercises: failed },
                );
                t.available = last.add(3);
                t.due = Some(last.add(10));
                t.reason = Some(Reason::RedoDue { since: last });
                out.push(t);
            }
            if p.question_open {
                out.push(simple(
                    format!("ask:{}", item.id),
                    Some(d.id.clone()),
                    Some(item.id.clone()),
                    TaskKind::Short,
                    pace.question,
                    Work::Question { item: item.id.clone() },
                ));
            }
        }
    }

    // Tutorials prepared before the session; two back to back on the same
    // day are one tutorial to prepare.
    let mut seen_td: BTreeSet<(Option<String>, Date)> = BTreeSet::new();
    for c in input.courses {
        if c.kind != CourseKind::Tutorial || c.start <= input.now || c.start.date > today.add(14) {
            continue;
        }
        if input.progress.prepared.contains(&c.uid) || !seen_td.insert((c.domain.clone(), c.start.date)) {
            continue;
        }
        let mut t = simple(
            format!("prepare:{}", c.uid),
            c.domain.clone(),
            None,
            TaskKind::Prepare,
            pace.td_prep,
            Work::Prepare { course: c.uid.clone(), title: c.title.clone(), at: c.start },
        );
        t.available = c.start.date.add(-3);
        t.before = Some(c.start.date);
        t.due = Some(c.start.date);
        t.reason = Some(Reason::Prepare { at: c.start });
        out.push(t);
    }

    for c in input.chores.iter().filter(|c| !c.done) {
        let mut t = simple(
            format!("chore:{}", c.id),
            c.domain.clone(),
            c.file.clone(),
            if c.minutes <= 15 { TaskKind::Short } else { TaskKind::Chore },
            c.minutes,
            Work::Chore { chore: c.id.clone(), title: c.title.clone() },
        );
        t.due = c.due;
        t.before = c.due.map(|d| d.add(1));
        out.push(t);
    }
    out
}

// ─── Allocation ──────────────────────────────────────────────────────────────

struct Cell {
    slot: Slot,
    id: String,
    cap: i32,
    parts: Vec<Part>,
    reasons: Vec<Reason>,
    pinned: bool,
    /// Nothing else goes in (the short restart session).
    closed: bool,
}

impl Cell {
    fn free(&self) -> i32 {
        if self.closed {
            0
        } else {
            self.cap - self.parts.iter().map(|p| p.minutes).sum::<i32>()
        }
    }

    fn push(&mut self, p: Part) {
        self.parts.push(p);
    }

    fn session(self) -> Session {
        let used: i32 = self.parts.iter().map(|p| p.minutes).sum();
        // A session ends with its work, unless it is pinned.
        let end = if self.slot.counted && used > 0 && used < self.slot.minutes() && !self.pinned {
            self.slot.start.plus(used)
        } else {
            self.slot.end
        };
        Session {
            id: self.id,
            date: self.slot.date,
            start: self.slot.start,
            end,
            kind: self.slot.kind,
            counted: self.slot.counted,
            place: self.slot.place,
            shortened: self.slot.shortened,
            pinned: self.pinned,
            parts: self.parts,
            reasons: self.reasons,
        }
    }
}

fn bucket(days: Option<i32>) -> u8 {
    match days {
        Some(d) if d <= 3 => 0,
        Some(d) if d <= 7 => 1,
        Some(d) if d <= 14 => 2,
        Some(d) if d <= 28 => 3,
        _ => 4,
    }
}

/// How many units of a sheet, from the front, fit in `cap` minutes. A piece
/// shorter than half an hour is not worth splitting a sheet for, unless it
/// is the end of it.
fn chunk(t: &Task, cap: i32) -> usize {
    let mut used = t.overhead;
    let mut n = 0;
    for (_, m) in &t.units {
        if used + m > cap {
            break;
        }
        used += m;
        n += 1;
    }
    if n < t.units.len() && used < 30 {
        0
    } else {
        n
    }
}

fn progress_started(input: &Input, t: &Task) -> bool {
    let p = t.item.as_ref().and_then(|i| input.progress.items.get(i));
    p.is_some_and(|p| p.read_upto > 0 || !p.exercises.is_empty())
}

fn study_part(t: &Task, units: &[(Unit, i32)]) -> Work {
    let range = |f: &dyn Fn(&Unit) -> Option<u32>| {
        let v: Vec<u32> = units.iter().filter_map(|(u, _)| f(u)).collect();
        Some((*v.first()?, *v.last()?))
    };
    Work::Study {
        item: t.item.clone().unwrap_or_default(),
        sections: range(&|u| match u {
            Unit::Section(n) => Some(*n),
            _ => None,
        }),
        exercises: range(&|u| match u {
            Unit::Exercise(n) => Some(*n),
            _ => None,
        }),
    }
}

pub fn plan(input: &Input) -> Plan {
    let s = input.settings;
    let r = &s.rhythm;
    let today = input.now.date;
    let now = input.now.time;

    let mut plan = Plan { made: Some(input.now), paused: journee::paused(input, today), ..Plan::default() };
    if plan.paused && (0..s.horizon_days).all(|i| journee::paused(input, today.add(i))) {
        return plan;
    }

    // 1. Slots up to the horizon, which always reaches the last deadline.
    let last_deadline = input
        .deadlines
        .iter()
        .map(|d| d.at.date)
        .chain(input.projects.iter().filter(|p| !p.archived).map(|p| p.due.date))
        .filter(|&d| d >= today && d <= today.add(150))
        .max()
        .unwrap_or(today);
    let horizon = today.add(s.horizon_days).max(last_deadline.add(1));
    let mut cells: Vec<Cell> = Vec::new();
    let mut offers: Vec<Cell> = Vec::new();
    let mut d = today;
    while d < horizon {
        let day = journee::day(input, d);
        let mut rank: BTreeMap<SlotKind, u32> = BTreeMap::new();
        for mut slot in day.slots {
            let n = rank.entry(slot.kind).or_default();
            *n += 1;
            let id = format!("{}-{}{}", slot.date, serde_json::to_value(slot.kind).unwrap().as_str().unwrap(), n);
            if d == today {
                if slot.end <= now {
                    continue;
                }
                if slot.start < now {
                    slot.start = now.ceil(5);
                    slot.shortened = true;
                    if slot.minutes() < r.min_session {
                        continue;
                    }
                }
            }
            if input.spent.contains(&id) {
                continue;
            }
            let cell = Cell { cap: slot.minutes(), slot, id, parts: Vec::new(), reasons: Vec::new(), pinned: false, closed: false };
            if cell.slot.counted {
                cells.push(cell);
            } else {
                offers.push(cell);
            }
        }
        d = d.add(1);
    }

    let mut all = tasks(input, today);
    let mut pinned_keys = BTreeSet::new();

    // 2a. Pinned sessions take their place first.
    for pin in input.pinned {
        let cell = cells.iter_mut().find(|c| {
            c.slot.date == pin.date && c.slot.start.0 <= pin.start.0 + pin.minutes && c.slot.end > pin.start
        });
        let Some(cell) = cell else { continue };
        let task = all.iter_mut().find(|t| t.key == pin.task);
        let (work, domain) = match (&pin.work, task.as_deref()) {
            (Some(w), t) => (w.clone(), t.and_then(|t| t.domain.clone()).or_else(|| pin.domain.clone())),
            (None, Some(t)) => (t.work.clone(), t.domain.clone()),
            (None, None) => continue,
        };
        if let Some(t) = all.iter_mut().find(|t| t.key == pin.task) {
            t.done = true;
        }
        pinned_keys.insert(pin.task.clone());
        // At the time asked for, when the slot holds it.
        if !cell.pinned && pin.start > cell.slot.start && pin.start.plus(r.min_session) <= cell.slot.end {
            cell.slot.start = pin.start;
            cell.cap = cell.slot.minutes();
        }
        cell.pinned = true;
        cell.reasons.push(Reason::Pinned);
        cell.push(Part { task: pin.task.clone(), domain, minutes: pin.minutes.min(cell.cap), work, timed: false });
    }

    // 2b. After two missed sessions in a row, the next one is ten minutes of recall.
    if input.missed_streak >= 2 {
        let last = input
            .progress
            .items
            .iter()
            .filter_map(|(id, p)| p.last_on.map(|d| (d, id.clone())))
            .max()
            .map(|(_, id)| id);
        if let Some(cell) = cells.iter_mut().find(|c| !c.pinned) {
            cell.cap = 10.min(cell.cap);
            cell.reasons.push(Reason::Restart { missed: input.missed_streak });
            cell.push(Part {
                task: "recall".into(),
                domain: last.as_ref().and_then(|id| input.catalogue.get(id)).map(|i| i.domain.clone()),
                minutes: cell.cap,
                work: Work::Recall { item: last },
                timed: false,
            });
            cell.closed = true;
        }
    }

    let mut exams: Vec<&Deadline> = input
        .deadlines
        .iter()
        .filter(|d| matches!(d.kind, DeadlineKind::Exam | DeadlineKind::Cc) && d.at.date > today)
        .collect();
    exams.sort_by_key(|d| d.at);

    // 2c. Campaigns: time on each school day (a gap at school if one is long
    // enough, else the start of the evening), the whole of their own slots,
    // and 45 minutes the day before an interview.
    for c in input.campaigns.iter().filter(|c| !c.closed) {
        let mut day = today.max(c.start);
        while day <= c.end.min(horizon) {
            let worked = input.progress.campaign_days.iter().any(|(id, d)| *id == c.id && *d == day);
            let own = cells.iter_mut().find(|x| x.slot.date == day && x.slot.kind == SlotKind::Campaign);
            if let Some(cell) = own {
                if !worked {
                    let m = cell.free();
                    cell.push(Part {
                        task: format!("campaign:{}:{day}", c.id),
                        domain: None,
                        minutes: m,
                        work: Work::Campaign { campaign: c.id.clone() },
                        timed: false,
                    });
                }
                day = day.add(1);
                continue;
            }
            let school = input.courses.iter().any(|x| x.start.date == day);
            let morning_block = cells.iter().any(|x| x.slot.date == day && x.slot.kind == SlotKind::Morning);
            if worked || !school || day.weekday() >= 5 || morning_block && !school {
                day = day.add(1);
                continue;
            }
            let part = Part {
                task: format!("campaign:{}:{day}", c.id),
                domain: None,
                minutes: c.school_day_minutes,
                work: Work::Campaign { campaign: c.id.clone() },
                timed: false,
            };
            if let Some(i) = offers.iter().position(|o| {
                o.slot.date == day && o.slot.kind == SlotKind::Gap && o.slot.minutes() >= c.school_day_minutes
            }) {
                // The gap becomes a counted session of its own.
                let mut gap = offers.remove(i);
                gap.slot.counted = true;
                gap.slot.end = gap.slot.start.plus(c.school_day_minutes);
                gap.cap = c.school_day_minutes;
                gap.push(part);
                cells.push(gap);
            } else if let Some(cell) = cells.iter_mut().find(|x| {
                x.slot.date == day && x.slot.kind == SlotKind::Evening && x.free() >= c.school_day_minutes
            }) {
                cell.push(part);
            }
            day = day.add(1);
        }
        for row in &c.rows {
            let Some(at) = row.interview else { continue };
            if at <= input.now || input.progress.interviews_prepared.iter().any(|(id, n)| *id == c.id && *n == row.name) {
                continue;
            }
            let eve = at.date.add(-1);
            let m = input.settings.pace.interview_prep;
            if let Some(cell) = cells.iter_mut().find(|x| x.slot.date == eve.max(today) && x.free() >= m.min(x.cap)) {
                let minutes = m.min(cell.free());
                cell.parts.insert(0, Part {
                    task: format!("interview:{}:{}", c.id, row.name),
                    domain: None,
                    minutes,
                    work: Work::Interview { campaign: c.id.clone(), company: row.name.clone() },
                    timed: false,
                });
            }
        }
    }
    cells.sort_by_key(|c| (c.slot.date, c.slot.start));

    // 2d. Projects and hand-ins, earliest due first, spread evenly.
    let mut hard: Vec<(String, String, Date, Vec<(String, i32)>, Option<String>)> = Vec::new();
    for p in input.projects.iter().filter(|p| !p.archived) {
        let steps: Vec<(String, i32)> = p
            .steps
            .iter()
            .filter(|st| !st.done)
            .map(|st| (st.name.clone(), ((st.hours * 60.0 * s.project_bias).round() as i32 - st.spent_minutes).max(0)))
            .filter(|(_, m)| *m > 0)
            .collect();
        hard.push((p.id.clone(), p.name.clone(), p.work_due(), steps, p.domain.clone()));
    }
    for d in input.deadlines.iter().filter(|d| d.kind == DeadlineKind::Due) {
        if let Some(h) = d.hours {
            let m = ((h * 60.0 * s.project_bias).round() as i32 - d.spent_minutes).max(0);
            if m > 0 {
                hard.push((d.id.clone(), d.title.clone(), d.work_due(), vec![(d.title.clone(), m)], d.domain.clone()));
            }
        }
    }
    hard.sort_by_key(|h| h.2);
    for (id, name, due, steps, domain) in hard {
        let need: i32 = steps.iter().map(|s| s.1).sum();
        if need == 0 {
            continue;
        }
        let open: Vec<usize> = (0..cells.len())
            .filter(|&i| cells[i].slot.date <= due && cells[i].free() >= r.min_session && cells[i].slot.place == Place::Home)
            .collect();
        let avg = if open.is_empty() { 1 } else { open.iter().map(|&i| cells[i].free()).sum::<i32>() / open.len() as i32 };
        let mut n = ((need + avg - 1) / avg.max(1)) as usize;
        let chosen = loop {
            n = n.min(open.len());
            let pick: Vec<usize> = (0..n).map(|k| open[((2 * k + 1) * open.len()) / (2 * n.max(1))]).collect();
            let cap: i32 = pick.iter().map(|&i| cells[i].free()).sum();
            if cap >= need || n == open.len() {
                break pick;
            }
            n += 1;
        };
        let mut steps = steps.into_iter().peekable();
        let mut left_in_step = steps.peek().map_or(0, |s| s.1);
        for i in chosen {
            let cell = &mut cells[i];
            while cell.free() > 0 {
                let Some((step, _)) = steps.peek() else { break };
                let m = left_in_step.min(cell.free());
                cell.push(Part {
                    task: format!("project:{id}:{step}"),
                    domain: domain.clone(),
                    minutes: m,
                    work: Work::Project { project: id.clone(), step: step.clone() },
                    timed: false,
                });
                if cell.reasons.is_empty() {
                    cell.reasons.push(Reason::ProjectDue { name: name.clone(), due: due.add(3) });
                }
                left_in_step -= m;
                if left_in_step == 0 {
                    steps.next();
                    left_in_step = steps.peek().map_or(0, |s| s.1);
                }
            }
        }
        let rest: Vec<(String, i32)> = steps.collect();
        if let Some((step, _)) = rest.first() {
            let missing = left_in_step + rest[1..].iter().map(|s| s.1).sum::<i32>();
            plan.changes.push(Change::AtRisk {
                task: format!("project:{id}:{step}"),
                work: Work::Project { project: id.clone(), step: step.clone() },
                due: due.add(3),
                missing_minutes: missing,
            });
        }
    }

    // 3. Fill the counted slots.
    let targets = domain_targets(input, &cells, today);
    let pressure = domain_pressure(input, &all, &cells, &targets);
    let mut last_study: Option<String> = None;
    let mut last_seen: BTreeMap<String, Date> = input
        .progress
        .items
        .iter()
        .filter_map(|(id, p)| Some((input.catalogue.get(id)?.domain.clone(), p.last_on?)))
        .fold(BTreeMap::new(), |mut m, (d, on)| {
            let e = m.entry(d).or_insert(on);
            *e = (*e).max(on);
            m
        });
    for ci in 0..cells.len() {
        let date = cells[ci].slot.date;
        let place = cells[ci].slot.place;
        let mut main = false;
        let mut studied: Option<String> = None;
        loop {
            let free = cells[ci].free();
            if free < 10 || (!main && free < r.min_session.min(cells[ci].cap)) {
                break;
            }
            let heads: BTreeSet<usize> = seq_heads(&all);
            let mut cands: Vec<usize> = (0..all.len())
                .filter(|&i| {
                    let t = &all[i];
                    !t.done
                        && t.available <= date
                        && t.before.is_none_or(|b| date < b)
                        && (!t.seq || heads.contains(&i))
                        && (!t.timed || (place == Place::Home && t.minutes <= free))
                        && match t.kind {
                            TaskKind::Sheet => chunk(t, free) > 0,
                            _ => t.minutes <= free,
                        }
                })
                .collect();
            if cands.is_empty() {
                break;
            }
            let due_of = |t: &Task| t.due.or_else(|| t.domain.as_ref().and_then(|d| targets.get(d)).copied());
            // What is left of every slot from this one on, for the tasks
            // that must be done before a date.
            let room: Vec<(Date, i32, Place)> = cells[ci..].iter().map(|c| (c.slot.date, c.free(), c.slot.place)).collect();
            let key = |i: &usize| {
                let t = &all[*i];
                let tier = bucket(due_of(t).map(|d| date.days_until(d)));
                // Due before a date and the slots left barely cover what is
                // due by then: it goes first, whatever else is pressing.
                let forced = t.before.is_some_and(|before| {
                    let fits = |&&(d, free, place): &&(Date, i32, Place)| {
                        d < before && free >= t.minutes && (!t.timed || place == Place::Home)
                    };
                    let left = room.iter().filter(fits).count();
                    let pending = all
                        .iter()
                        .filter(|o| !o.done && o.timed == t.timed && o.before.is_some_and(|b| b <= before))
                        .count();
                    left <= pending
                });
                let p = t.domain.as_ref().and_then(|d| pressure.get(d)).copied().unwrap_or(0.0);
                (
                    // Once a session has its main work, short tasks fill it.
                    main && !t.short && !forced,
                    !forced,
                    tier,
                    !(t.in_progress && t.kind == TaskKind::Sheet),
                    -(p * 1000.0) as i64,
                    !t.starred,
                    t.order,
                    t.key.clone(),
                )
            };
            cands.sort_by_key(key);
            let mut pick = cands[0];
            // Domains take turns from one session to the next, within the
            // same urgency; a sheet already started keeps its place.
            let turn = |i: usize| all[i].seq && !(all[i].in_progress && all[i].kind == TaskKind::Sheet);
            if turn(pick) && all[pick].domain.is_some() && all[pick].domain == last_study {
                let tier = key(&pick).2;
                if let Some(&other) = cands.iter().find(|&&i| all[i].seq && all[i].domain != last_study && key(&i).2 == tier) {
                    pick = other;
                }
            }
            let t = &mut all[pick];
            let part = match t.kind {
                TaskKind::Sheet => {
                    let n = chunk(t, free);
                    let units: Vec<(Unit, i32)> = t.units.drain(..n).collect();
                    let minutes = t.overhead + units.iter().map(|u| u.1).sum::<i32>();
                    let work = study_part(t, &units);
                    if t.units.is_empty() {
                        t.done = true;
                    } else {
                        // What is left is the head of the line next time.
                        t.in_progress = true;
                    }
                    Part { task: t.key.clone(), domain: t.domain.clone(), minutes, work, timed: false }
                }
                _ => {
                    t.done = true;
                    Part { task: t.key.clone(), domain: t.domain.clone(), minutes: t.minutes, work: t.work.clone(), timed: t.timed }
                }
            };
            let t = &all[pick];
            let cell = &mut cells[ci];
            let first_study = t.seq && studied.is_none();
            if !main || first_study {
                let mut why = Vec::new();
                if let Some(reason) = &t.reason {
                    why.push(reason.clone());
                }
                if let Some(dl) = t.domain.as_deref().and_then(|d| domain_deadline(input, d, date)) {
                    why.push(Reason::Deadline {
                        title: dl.title.clone(),
                        date: dl.at.date,
                        days: date.days_until(dl.at.date),
                        margin: None,
                    });
                }
                if t.kind == TaskKind::Sheet && progress_started(input, t) {
                    why.push(Reason::Continues);
                }
                if t.starred {
                    why.push(Reason::Starred { note: t.star_note.clone() });
                }
                if let (Some(dm), true) = (&t.domain, t.seq) {
                    if last_study.as_ref() != Some(dm) {
                        why.push(Reason::Rotation { domain: dm.clone(), last: last_seen.get(dm).copied() });
                    }
                    let p = pressure.get(dm).copied().unwrap_or(0.0);
                    if p > 1.0 && pressure.values().all(|&o| o <= p) {
                        why.push(Reason::Behind { domain: dm.clone() });
                    }
                }
                if why.is_empty() {
                    why.push(Reason::CourseOrder);
                }
                for w in why {
                    if !cell.reasons.contains(&w) {
                        cell.reasons.push(w);
                    }
                }
                main = true;
            }
            if t.seq && studied.is_none() {
                studied = t.domain.clone();
            }
            cell.push(part);
        }
        if let Some(d) = studied {
            last_seen.insert(d.clone(), date);
            last_study = Some(d);
        }
    }

    // Untouchable work that found no room before its date.
    for t in all.iter().filter(|t| !t.done && t.before.is_some()) {
        let due = t.before.unwrap();
        if due > today && due <= horizon && matches!(t.kind, TaskKind::Prepare | TaskKind::Chore | TaskKind::Exam) {
            let missing = if t.kind == TaskKind::Sheet { t.units.iter().map(|u| u.1).sum() } else { t.minutes };
            plan.changes.push(Change::AtRisk { task: t.key.clone(), work: t.work.clone(), due, missing_minutes: missing });
        }
    }

    // 4. Offers: the next counted work that fits the optional slot.
    let counted: Vec<Session> = cells.into_iter().map(Cell::session).collect();
    let mut offered: BTreeSet<String> = BTreeSet::new();
    for mut o in offers {
        let after = |s: &Session| (s.date, s.start) > (o.slot.date, o.slot.start);
        let mut free = o.slot.minutes();
        for s in counted.iter().filter(|s| after(s)) {
            for p in &s.parts {
                let movable = !matches!(
                    p.work,
                    Work::Campaign { .. } | Work::Interview { .. } | Work::Recall { .. }
                );
                let fits = p.minutes <= free && p.minutes > 0;
                let school_ok = o.slot.place == Place::Home || (!p.timed && !matches!(p.work, Work::Project { .. }));
                let key = format!("{}#{}", p.task, s.id);
                if movable && fits && school_ok && !offered.contains(&key) && !pinned_keys.contains(&p.task) {
                    if let Work::Prepare { at, .. } = &p.work {
                        if *at <= Local::new(o.slot.date, o.slot.end) {
                            continue;
                        }
                    }
                    free -= p.minutes;
                    offered.insert(key);
                    o.parts.push(p.clone());
                }
            }
            if free < 10 || o.parts.len() >= 3 {
                break;
            }
        }
        if !o.parts.is_empty() {
            o.reasons.push(Reason::HeadStart);
            plan.offers.push(o.session());
        }
    }
    plan.sessions = counted;

    // 5. Margins and changes.
    plan.margins = margins(input, &plan, &all, &exams, today);
    for sess in plan.sessions.iter_mut() {
        for reason in sess.reasons.iter_mut() {
            if let Reason::Deadline { date, margin, title, .. } = reason {
                *margin = plan.margins.iter().find(|m| m.date == *date && m.title == *title).map(|m| m.sessions);
            }
        }
    }
    let mut changes = diff(input, &plan, today);
    changes.append(&mut plan.changes);
    plan.changes = changes;
    plan
}

/// The head of each domain's sequence: a sheet already started, else its
/// first unfinished item.
fn seq_heads(all: &[Task]) -> BTreeSet<usize> {
    let mut heads: BTreeMap<&str, usize> = BTreeMap::new();
    for (i, t) in all.iter().enumerate() {
        let Some(d) = t.domain.as_deref().filter(|_| t.seq && !t.done) else { continue };
        match heads.get(d) {
            None => {
                heads.insert(d, i);
            }
            Some(&h) if t.in_progress && !all[h].in_progress => {
                heads.insert(d, i);
            }
            _ => {}
        }
    }
    heads.into_values().collect()
}

/// The date each domain's work aims at, for priority: before an exam, the
/// day of the k-th last counted session (k = the objective's margin); for a
/// test, 3 days ahead. A domain without a date aims at the end of its
/// courses, or at the last exam known, so that every domain weighs the same.
fn domain_targets(input: &Input, cells: &[Cell], today: Date) -> BTreeMap<String, Date> {
    let k = input.settings.objective.margin_sessions();
    let last_exam = input.deadlines.iter().filter(|d| d.kind == DeadlineKind::Exam).map(|d| d.at.date).max();
    let mut out = BTreeMap::new();
    for d in input.domains.iter().filter(|d| !d.archived) {
        let target = match domain_deadline(input, &d.id, today) {
            Some(dl) if dl.kind == DeadlineKind::Exam => {
                let before: Vec<Date> = cells.iter().filter(|c| c.slot.date < dl.at.date).map(|c| c.slot.date).collect();
                Some(if k > 0 && before.len() >= k { before[before.len() - k] } else { dl.at.date })
            }
            Some(dl) => Some(dl.work_due()),
            None => {
                let end = input.courses.iter().filter(|c| c.domain.as_deref() == Some(&d.id)).map(|c| c.end.date).max();
                end.max(last_exam).filter(|&e| e >= today)
            }
        };
        if let Some(t) = target {
            out.insert(d.id.clone(), t);
        }
    }
    out
}

fn remaining(t: &Task) -> i32 {
    if t.kind == TaskKind::Sheet {
        t.overhead + t.units.iter().map(|u| u.1).sum::<i32>()
    } else {
        t.minutes
    }
}

/// A domain's remaining study over its fair share of the counted time left
/// before its target: above 1, it is behind.
fn domain_pressure(input: &Input, all: &[Task], cells: &[Cell], targets: &BTreeMap<String, Date>) -> BTreeMap<String, f32> {
    let active = input.domains.iter().filter(|d| !d.archived).count().max(1) as f32;
    targets
        .iter()
        .map(|(d, &target)| {
            let need: i32 = all.iter().filter(|t| t.domain.as_deref() == Some(d) && t.seq && !t.done).map(remaining).sum();
            let room: i32 = cells.iter().filter(|c| c.slot.date <= target).map(|c| c.free()).sum();
            (d.clone(), need as f32 / (room as f32 / active).max(1.0))
        })
        .collect()
}

/// Counted sessions between the end of a domain's work and its exam; when
/// work is left unplaced, minus the sessions it would need.
fn margins(input: &Input, plan: &Plan, all: &[Task], exams: &[&Deadline], today: Date) -> Vec<Margin> {
    let r = &input.settings.rhythm;
    exams
        .iter()
        .map(|e| {
            let required = |p: &Part| {
                p.domain == e.domain && (p.task.starts_with("study:") || p.task.starts_with("read:") || p.task.starts_with("exam:"))
            };
            let last = plan
                .sessions
                .iter()
                .filter(|s| s.date < e.at.date && s.parts.iter().any(required))
                .map(|s| (s.date, s.start))
                .max();
            let left: i32 = all
                .iter()
                .filter(|t| !t.done && t.domain == e.domain && (t.seq || t.kind == TaskKind::Exam))
                .map(remaining)
                .sum();
            let sessions = if left > 0 {
                -((left + r.evening_minutes - 1) / r.evening_minutes)
            } else {
                let from = last.unwrap_or((today.add(-1), Hm(1440)));
                plan.sessions.iter().filter(|s| (s.date, s.start) > from && s.date < e.at.date).count() as i32
            };
            Margin { deadline: e.id.clone(), title: e.title.clone(), date: e.at.date, domain: e.domain.clone(), sessions }
        })
        .collect()
}

/// Nothing skipped in silence: every task whose first session moved, and
/// every margin that changed, since the previous plan.
fn diff(input: &Input, plan: &Plan, today: Date) -> Vec<Change> {
    let Some(prev) = input.previous else { return Vec::new() };
    let before = prev.first_dates(today);
    let after = plan.first_dates(today);
    let mut out = Vec::new();
    for (task, (was, work, domain)) in &before {
        match after.get(task) {
            Some((now, work, domain)) if now != was => out.push(Change::Moved {
                task: task.clone(),
                work: work.clone(),
                domain: domain.clone(),
                from: *was,
                to: *now,
            }),
            Some(_) => {}
            None => {
                // Done in the meantime: nothing to say. Otherwise it went past the horizon.
                let still = input_still_open(input, task);
                if still {
                    out.push(Change::Unplaced { task: task.clone(), work: work.clone(), domain: domain.clone(), was: *was });
                }
            }
        }
    }
    // A task that was missed (planned before today) and comes back.
    let past: BTreeMap<String, Date> = prev
        .sessions
        .iter()
        .filter(|s| s.date < today)
        .flat_map(|s| s.parts.iter().map(move |p| (p.task.clone(), s.date)))
        .collect();
    for (task, (now, work, domain)) in &after {
        if let (Some(was), false) = (past.get(task), before.contains_key(task)) {
            out.push(Change::Moved { task: task.clone(), work: work.clone(), domain: domain.clone(), from: *was, to: *now });
        }
    }
    for m in &plan.margins {
        if let Some(old) = prev.margins.iter().find(|o| o.deadline == m.deadline) {
            if old.sessions != m.sessions {
                out.push(Change::Margin { deadline: m.deadline.clone(), title: m.title.clone(), from: old.sessions, to: m.sessions });
            }
        }
    }
    out.sort_by_key(|c| match c {
        Change::Moved { to, .. } => (0, *to),
        Change::Unplaced { was, .. } => (1, *was),
        Change::Margin { .. } => (2, Date(0)),
        Change::AtRisk { due, .. } => (3, *due),
    });
    out
}

/// Whether a task from the previous plan is still to do.
fn input_still_open(input: &Input, task: &str) -> bool {
    let today = input.now.date;
    tasks(input, today).iter().any(|t| t.key == task)
}
