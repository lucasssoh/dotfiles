//! The planner: a pure function from what is known (timetable, deadlines,
//! projects, what was done, settings, the time) to a plan, and the
//! differences with the previous one. No clock, no file, no randomness: the
//! same input always gives the same plan, which is what the tests rely on.
//!
//! In order:
//!   1. the slots of every day up to the horizon (journee);
//!   2. what cannot move: pinned sessions, campaign time, interview
//!      preparation, then projects and hand-ins, spread evenly up to 3 days
//!      before they are due. Untouchable: when time runs short, course
//!      sessions give way, never these;
//!   3. counted slots: tutorial preparations and tasks first, then the rest
//!      of the slot to one subject. Subjects share the time by weight, the
//!      level said ("behind" weighs most) times how close its exam is, and
//!      take turns from one session to the next;
//!   4. optional slots (gaps at school, Saturday, a free evening near an
//!      exam) offer the next counted work as a head start;
//!   5. what moved since the previous plan.
//!
//! What a session of a subject holds is the course's business (Boussole
//! for a subject that is there): the plan only says which subject, when,
//! and for how long.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::journee::{self, Place, Slot, SlotKind};
use crate::model::*;
use crate::time::{Date, Hm, Local};

/// Everything the planner reads. Borrowed: the service owns the state.
pub struct Input<'a> {
    pub now: Local,
    pub settings: &'a Settings,
    pub domains: &'a [Domain],
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
    /// Tasks done with for today, said "not tonight" or closed: they do
    /// not come back before tomorrow.
    pub away_today: &'a [String],
    /// Time found on the spot.
    pub extra: &'a [journee::Extra],
    /// Learnt evening start per weekday (journee::learn_start).
    pub learned: [Option<Hm>; 7],
    /// Sessions already over (closed, skipped, missed): their slot is not reused.
    pub spent: &'a [String],
    /// Per subject, its sessions closed: (day, minutes), oldest first.
    pub done: &'a BTreeMap<String, Vec<(Date, i32)>>,
    pub previous: Option<&'a Plan>,
}

/// A session the user fixed: it does not move, the rest goes around it.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Pin {
    pub task: String,
    pub date: Date,
    pub start: Hm,
    pub minutes: i32,
    /// None for a pin of a task that no longer exists (a course file
    /// of the planner before Programme): it is let go.
    #[serde(default, deserialize_with = "crate::store::lenient")]
    pub work: Option<Work>,
    #[serde(default)]
    pub domain: Option<String>,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "work", rename_all = "kebab-case")]
pub enum Work {
    /// A session of the subject's course, whatever it holds.
    Course,
    Prepare { course: String, title: String, at: Local },
    Project { project: String, step: String },
    Campaign { campaign: String },
    Interview { campaign: String, company: String },
    Chore { chore: String, title: String },
}

/// The task key of a subject's sessions.
pub fn course_task(domain: &str) -> String {
    format!("course:{domain}")
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Part {
    /// The task this belongs to, stable from one plan to the next.
    pub task: String,
    pub domain: Option<String>,
    pub minutes: i32,
    #[serde(flatten)]
    pub work: Work,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "why", rename_all = "kebab-case")]
pub enum Reason {
    Deadline { title: String, date: Date, days: i32 },
    /// The subject had nothing since `last`: subjects take turns.
    Rotation { domain: String, last: Option<Date> },
    /// The user said they are behind in it.
    SaidBehind { domain: String },
    Prepare { at: Local },
    ProjectDue { name: String, due: Date },
    Pinned,
    /// An optional slot: doing it gives a head start.
    HeadStart,
    /// The day's time for a campaign.
    CampaignTime,
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

impl Session {
    /// The slot it was cut from: tasks of one evening share it.
    pub fn slot(&self) -> &str {
        self.id.split('~').next().unwrap_or(&self.id)
    }

    /// The subject of its course session, if it is one.
    pub fn course(&self) -> Option<&str> {
        self.parts.iter().find(|p| p.work == Work::Course).and_then(|p| p.domain.as_deref())
    }
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(tag = "change", rename_all = "kebab-case")]
pub enum Change {
    /// A task's first session moved.
    Moved { task: String, work: Work, domain: Option<String>, from: Date, to: Date },
    /// Planned before, now past the horizon.
    Unplaced { task: String, work: Work, domain: Option<String>, was: Date },
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

/// A piece of work other than a course session: a tutorial to prepare, a
/// task typed by hand.
#[derive(Clone, Debug)]
struct Task {
    key: String,
    domain: Option<String>,
    minutes: i32,
    /// Must be done on a date strictly before it.
    before: Option<Date>,
    /// Soft due date, for priority.
    due: Option<Date>,
    available: Date,
    work: Work,
    reason: Option<Reason>,
    done: bool,
}

fn level(input: &Input, domain: &str) -> Level {
    input.domains.iter().find(|d| d.id == domain).map_or(Level::Fine, |d| d.level)
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

fn tasks(input: &Input, today: Date) -> Vec<Task> {
    let pace = &input.settings.pace;
    let mut out = Vec::new();
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
        out.push(Task {
            key: format!("prepare:{}", c.uid),
            domain: c.domain.clone(),
            minutes: pace.td_prep,
            before: Some(c.start.date),
            due: Some(c.start.date),
            available: c.start.date.add(-3),
            work: Work::Prepare { course: c.uid.clone(), title: c.title.clone(), at: c.start },
            reason: Some(Reason::Prepare { at: c.start }),
            done: false,
        });
    }
    for c in input.chores.iter().filter(|c| !c.done) {
        out.push(Task {
            key: format!("chore:{}", c.id),
            domain: c.domain.clone(),
            minutes: c.minutes,
            before: c.due.map(|d| d.add(1)),
            due: c.due,
            available: Date(i32::MIN),
            work: Work::Chore { chore: c.id.clone(), title: c.title.clone() },
            reason: None,
            done: false,
        });
    }
    out
}

// ─── Allocation ──────────────────────────────────────────────────────────────

struct Cell {
    slot: Slot,
    id: String,
    cap: i32,
    parts: Vec<Part>,
    /// Why, per task (None: the whole slot).
    why: Vec<(Option<String>, Reason)>,
    pinned: bool,
}

impl Cell {
    fn free(&self) -> i32 {
        self.cap - self.parts.iter().map(|p| p.minutes).sum::<i32>()
    }

    fn push(&mut self, p: Part) {
        self.parts.push(p);
    }

    fn because(&mut self, task: &str, r: Reason) {
        let w = (Some(task.to_string()), r);
        if !self.why.contains(&w) {
            self.why.push(w);
        }
    }

    /// One session per task, one after the other: one thing at a time,
    /// each started, put off or said "not tonight" on its own.
    fn sessions(self) -> Vec<Session> {
        let mut out = Vec::new();
        let n = self.parts.len();
        // An empty slot still shows where time was.
        if n == 0 {
            let reasons = self.why.into_iter().map(|w| w.1).collect();
            return vec![Session {
                id: self.id,
                date: self.slot.date,
                start: self.slot.start,
                end: self.slot.end,
                kind: self.slot.kind,
                counted: self.slot.counted,
                place: self.slot.place,
                shortened: self.slot.shortened,
                pinned: self.pinned,
                parts: Vec::new(),
                reasons,
            }];
        }
        let mut start = self.slot.start;
        for (i, p) in self.parts.into_iter().enumerate() {
            // The last one runs to the slot's end when it is pinned or optional.
            let end = if i + 1 == n && (self.pinned || !self.slot.counted) {
                self.slot.end
            } else {
                start.plus(p.minutes).min(self.slot.end)
            };
            let mut reasons: Vec<Reason> = Vec::new();
            for (t, r) in &self.why {
                if (t.is_none() || t.as_deref() == Some(p.task.as_str())) && !reasons.contains(r) {
                    reasons.push(r.clone());
                }
            }
            out.push(Session {
                id: format!("{}~{}", self.id, short_hash(&p.task)),
                date: self.slot.date,
                start,
                end,
                kind: self.slot.kind,
                counted: self.slot.counted,
                place: self.slot.place,
                shortened: self.slot.shortened,
                pinned: self.pinned,
                parts: vec![p],
                reasons,
            });
            start = end;
        }
        out
    }
}

/// Six hex digits of a task key, so a session's id stays the same while its
/// task stays in its slot.
fn short_hash(s: &str) -> String {
    let mut h: u32 = 0x811c9dc5;
    for b in s.bytes() {
        h ^= b as u32;
        h = h.wrapping_mul(0x01000193);
    }
    format!("{:06x}", h & 0xffffff)
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

/// How much more a subject weighs as its exam comes: ×1 six weeks ahead
/// or more, ×3 on the eve.
fn urgency(days: Option<i32>) -> f32 {
    match days {
        Some(d) if d < 42 => 1.0 + (42 - d.max(0)) as f32 / 21.0,
        _ => 1.0,
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
            let cell = Cell { cap: slot.minutes(), slot, id, parts: Vec::new(), why: Vec::new(), pinned: false };
            if cell.slot.counted {
                cells.push(cell);
            } else {
                offers.push(cell);
            }
        }
        d = d.add(1);
    }

    let mut all = tasks(input, today);

    // 2a. Pinned sessions take their place first.
    let mut pinned_keys = BTreeSet::new();
    for pin in input.pinned {
        let cell = cells.iter_mut().find(|c| {
            c.slot.date == pin.date && c.slot.start.0 <= pin.start.0 + pin.minutes && c.slot.end > pin.start
        });
        let Some(cell) = cell else { continue };
        let task = all.iter().find(|t| t.key == pin.task);
        let (work, domain) = match (&pin.work, task) {
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
        cell.because(&pin.task, Reason::Pinned);
        cell.push(Part { task: pin.task.clone(), domain, minutes: pin.minutes.min(cell.cap), work });
    }

    // 2b. Campaigns: time on each school day (a gap at school if one is long
    // enough, else a free afternoon, the morning block, the evening), the
    // whole of their own slots, and 45 minutes the day before an interview.
    for c in input.campaigns.iter().filter(|c| !c.closed) {
        let mut day = today.max(c.start);
        while day <= c.end.min(horizon) {
            let worked = input.progress.campaign_days.iter().any(|(id, d)| *id == c.id && *d == day);
            let own = cells.iter_mut().find(|x| x.slot.date == day && x.slot.kind == SlotKind::Campaign);
            let key = format!("campaign:{}:{day}", c.id);
            // Said "not tonight": not today any more.
            let skipped = day == today && input.away_today.contains(&key);
            if let Some(cell) = own {
                if !worked && !skipped {
                    let m = cell.free();
                    cell.push(Part { task: key.clone(), domain: None, minutes: m, work: Work::Campaign { campaign: c.id.clone() } });
                    cell.because(&key, Reason::CampaignTime);
                }
                day = day.add(1);
                continue;
            }
            let school = input.courses.iter().any(|x| x.start.date == day);
            let morning_block = cells.iter().any(|x| x.slot.date == day && x.slot.kind == SlotKind::Morning);
            if worked || skipped || !school || day.weekday() >= 5 || morning_block && !school {
                day = day.add(1);
                continue;
            }
            let part = Part {
                task: key.clone(),
                domain: None,
                minutes: c.school_day_minutes,
                work: Work::Campaign { campaign: c.id.clone() },
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
                gap.because(&key, Reason::CampaignTime);
                cells.push(gap);
            } else if let Some(cell) = [SlotKind::Block, SlotKind::Morning, SlotKind::Evening].iter().find_map(|&kind| {
                // Daytime first: the evening is kept for study when it can be.
                cells.iter().position(|x| x.slot.date == day && x.slot.kind == kind && x.free() >= c.school_day_minutes)
            }) {
                cells[cell].push(part);
                cells[cell].because(&key, Reason::CampaignTime);
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
            let key = format!("interview:{}:{}", c.id, row.name);
            if let Some(cell) = cells.iter_mut().find(|x| {
                x.slot.date == eve.max(today) && x.free() >= m.min(x.cap) && !(x.slot.date == today && input.away_today.contains(&key))
            }) {
                let minutes = m.min(cell.free());
                cell.because(&key, Reason::CampaignTime);
                cell.parts.insert(0, Part {
                    task: key.clone(),
                    domain: None,
                    minutes,
                    work: Work::Interview { campaign: c.id.clone(), company: row.name.clone() },
                });
            }
        }
    }
    cells.sort_by_key(|c| (c.slot.date, c.slot.start));

    // 2c. Projects and hand-ins, earliest due first, spread evenly.
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
        let not_tonight = input.away_today.iter().any(|t| t.starts_with(&format!("project:{id}:")));
        let open: Vec<usize> = (0..cells.len())
            .filter(|&i| cells[i].slot.date <= due && cells[i].free() >= r.min_session && cells[i].slot.place == Place::Home)
            .filter(|&i| !(not_tonight && cells[i].slot.date == today))
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
                });
                cell.because(&format!("project:{id}:{step}"), Reason::ProjectDue { name: name.clone(), due: due.add(3) });
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

    // 3. Fill the counted slots: tasks first, then one subject.
    let targets = domain_targets(input, &cells, today);
    // The last day a subject is worth a session: its last exam or course.
    let ends: BTreeMap<&str, Date> = input
        .domains
        .iter()
        .filter_map(|d| {
            let exams = input.deadlines.iter().filter(|x| x.domain.as_deref() == Some(&d.id)).map(|x| x.at.date);
            let courses = input.courses.iter().filter(|c| c.domain.as_deref() == Some(&d.id)).map(|c| c.end.date);
            Some((d.id.as_str(), exams.chain(courses).max()?))
        })
        .collect();
    let studied: Vec<&Domain> = input.domains.iter().filter(|d| !d.archived && d.level.studies()).collect();
    // Minutes given per subject: the last seven days', then the plan's own.
    let mut given: BTreeMap<String, i32> = BTreeMap::new();
    let mut last_seen: BTreeMap<String, Date> = BTreeMap::new();
    for (dm, days) in input.done {
        for (on, m) in days {
            if *on >= today.add(-7) && *on < today {
                *given.entry(dm.clone()).or_default() += m;
            }
            let e = last_seen.entry(dm.clone()).or_insert(*on);
            *e = (*e).max(*on);
        }
    }
    let mut last_study: Option<String> = None;
    for ci in 0..cells.len() {
        let date = cells[ci].slot.date;
        // Tutorial preparations and tasks, as soon as they can be.
        loop {
            let free = cells[ci].free();
            if free < 10 {
                break;
            }
            let mut cands: Vec<usize> = (0..all.len())
                .filter(|&i| {
                    let t = &all[i];
                    !t.done
                        && !(date == today && input.away_today.contains(&t.key))
                        && t.available <= date
                        && t.before.is_none_or(|b| date < b)
                        && t.minutes <= free
                })
                .collect();
            if cands.is_empty() {
                break;
            }
            cands.sort_by_key(|&i| (bucket(all[i].due.map(|d| date.days_until(d))), all[i].due, all[i].key.clone()));
            let t = &mut all[cands[0]];
            t.done = true;
            let part = Part { task: t.key.clone(), domain: t.domain.clone(), minutes: t.minutes, work: t.work.clone() };
            if let Some(reason) = t.reason.clone() {
                cells[ci].because(&part.task, reason);
            }
            cells[ci].push(part);
        }
        // The rest of the slot to one subject.
        let free = cells[ci].free();
        if free < r.min_session.min(cells[ci].cap) || studied.is_empty() {
            continue;
        }
        let days_to = |dm: &str| targets.get(dm).map(|t| date.days_until(*t));
        let weight = |dm: &str| level(input, dm).weight() * urgency(days_to(dm));
        let pick = studied
            .iter()
            .filter(|d| !(date == today && input.away_today.contains(&course_task(&d.id))))
            // Nothing for a subject after its last exam.
            .filter(|d| !input.calendar || ends.get(d.id.as_str()).is_some_and(|e| date <= *e))
            .min_by(|a, b| {
                let share = |d: &Domain| given.get(&d.id).copied().unwrap_or(0) as f32 / weight(&d.id).max(0.01);
                let turn = |d: &Domain| last_study.as_deref() == Some(d.id.as_str());
                let seen = |d: &Domain| last_seen.get(&d.id).copied().unwrap_or(Date(i32::MIN));
                (turn(a), share(a))
                    .partial_cmp(&(turn(b), share(b)))
                    .unwrap_or(std::cmp::Ordering::Equal)
                    .then(seen(a).cmp(&seen(b)))
                    .then(a.id.cmp(&b.id))
            });
        let Some(d) = pick else { continue };
        let task = course_task(&d.id);
        let cell = &mut cells[ci];
        if let Some(dl) = domain_deadline(input, &d.id, date).filter(|dl| date.days_until(dl.at.date) <= 42) {
            cell.because(&task, Reason::Deadline { title: dl.title.clone(), date: dl.at.date, days: date.days_until(dl.at.date) });
        }
        if d.level == Level::Behind {
            cell.because(&task, Reason::SaidBehind { domain: d.id.clone() });
        }
        cell.because(&task, Reason::Rotation { domain: d.id.clone(), last: last_seen.get(&d.id).copied() });
        cell.push(Part { task, domain: Some(d.id.clone()), minutes: free, work: Work::Course });
        *given.entry(d.id.clone()).or_default() += free;
        last_seen.insert(d.id.clone(), date);
        last_study = Some(d.id.clone());
    }

    // Untouchable work that found no room before its date.
    for t in all.iter().filter(|t| !t.done && t.before.is_some()) {
        let due = t.before.unwrap();
        if due > today && due <= horizon {
            plan.changes.push(Change::AtRisk { task: t.key.clone(), work: t.work.clone(), due, missing_minutes: t.minutes });
        }
    }

    // 4. Offers: the next counted work that fits the optional slot; a
    // subject's session, for the time the slot has.
    let counted: Vec<Session> = cells.into_iter().flat_map(Cell::sessions).collect();
    let mut offered: BTreeSet<String> = BTreeSet::new();
    for mut o in offers {
        let after = |s: &Session| (s.date, s.start) > (o.slot.date, o.slot.start);
        let mut free = o.slot.minutes();
        for s in counted.iter().filter(|s| after(s)) {
            for p in &s.parts {
                let movable = !matches!(p.work, Work::Campaign { .. } | Work::Interview { .. });
                let course = p.work == Work::Course;
                let minutes = if course { free } else { p.minutes };
                let fits = minutes <= free && minutes > 0 && (!course || minutes >= r.min_session);
                let school_ok = o.slot.place == Place::Home || !matches!(p.work, Work::Project { .. });
                let key = format!("{}#{}", p.task, s.id);
                let one_course = !course || !o.parts.iter().any(|x| x.work == Work::Course);
                if movable && fits && school_ok && one_course && !offered.contains(&key) && !pinned_keys.contains(&p.task) {
                    if let Work::Prepare { at, .. } = &p.work {
                        if *at <= Local::new(o.slot.date, o.slot.end) {
                            continue;
                        }
                    }
                    free -= minutes;
                    offered.insert(key);
                    o.parts.push(Part { minutes, ..p.clone() });
                }
            }
            if free < 10 || o.parts.len() >= 3 {
                break;
            }
        }
        if !o.parts.is_empty() {
            o.why.push((None, Reason::HeadStart));
            plan.offers.extend(o.sessions());
        }
    }
    plan.sessions = counted;

    // 5. What moved.
    let mut changes = diff(input, &plan, today);
    changes.append(&mut plan.changes);
    plan.changes = changes;
    plan
}

/// The date each domain's work aims at: before an exam, the day of the
/// k-th last counted session (k = the objective's margin); for a test,
/// 3 days ahead. A domain without a date aims at the end of its courses.
fn domain_targets(input: &Input, cells: &[Cell], today: Date) -> BTreeMap<String, Date> {
    let k = input.settings.objective.margin_sessions();
    let mut out = BTreeMap::new();
    for d in input.domains.iter().filter(|d| !d.archived) {
        let target = match domain_deadline(input, &d.id, today) {
            Some(dl) if dl.kind == DeadlineKind::Exam => {
                let before: Vec<Date> = cells.iter().filter(|c| c.slot.date < dl.at.date).map(|c| c.slot.date).collect();
                Some(if k > 0 && before.len() >= k { before[before.len() - k] } else { dl.at.date })
            }
            Some(dl) => Some(dl.work_due()),
            None => input
                .courses
                .iter()
                .filter(|c| c.domain.as_deref() == Some(&d.id))
                .map(|c| c.end.date)
                .max()
                .filter(|&e| e >= today),
        };
        if let Some(t) = target {
            out.insert(d.id.clone(), t);
        }
    }
    out
}

/// Nothing skipped in silence: every task whose first session moved since
/// the previous plan.
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
                if still_open(input, task) {
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
    out.sort_by_key(|c| match c {
        Change::Moved { to, .. } => (0, *to),
        Change::Unplaced { was, .. } => (1, *was),
        Change::AtRisk { due, .. } => (2, *due),
    });
    out
}

/// Whether a task from the previous plan is still to do.
fn still_open(input: &Input, task: &str) -> bool {
    if let Some(d) = task.strip_prefix("course:") {
        return input.domains.iter().any(|x| x.id == d && !x.archived && x.level.studies());
    }
    tasks(input, input.now.date).iter().any(|t| t.key == task)
}
