//! A school week, three subjects and a builder for the planner's input.

#![allow(dead_code)]

use std::collections::BTreeMap;

use boussole::model::*;
use boussole::plan::{self, Input, Pin, Plan};
use boussole::time::{Date, Hm, Local};

/// Monday 5 October 2026.
pub const MON: Date = Date(20_731);

pub fn at(date: Date, hm: &str) -> Local {
    Local::new(date, Hm::parse(hm).unwrap())
}

pub fn hm(s: &str) -> Hm {
    Hm::parse(s).unwrap()
}

pub fn course(date: Date, from: &str, to: &str, kind: CourseKind, domain: &str) -> Course {
    Course {
        uid: format!("{date}-{from}-{domain}"),
        start: at(date, from),
        end: at(date, to),
        kind,
        domain: Some(domain.into()),
        title: format!("{kind:?} {domain}"),
        room: String::new(),
    }
}

/// A school week from `monday`:
///   Mon 08:00-10:00 CM ALGO, 13:30-15:30 TD ALGO
///   Tue 08:00-12:00 CM LOGIC
///   Wed 13:30-17:30 TP NET           (free morning)
///   Thu 08:00-10:00 CM NET, 15:45-17:45 TD LOGIC   (gap 10:00-15:45, minus 12:00-13:30)
///   Fri 08:00-12:00 CM ALGO
pub fn week(monday: Date) -> Vec<Course> {
    use CourseKind::*;
    vec![
        course(monday, "08:00", "10:00", Lecture, "ALGO"),
        course(monday, "13:30", "15:30", Tutorial, "ALGO"),
        course(monday.add(1), "08:00", "12:00", Lecture, "LOGIC"),
        course(monday.add(2), "13:30", "17:30", Lab, "NET"),
        course(monday.add(3), "08:00", "10:00", Lecture, "NET"),
        course(monday.add(3), "15:45", "17:45", Tutorial, "LOGIC"),
        course(monday.add(4), "08:00", "12:00", Lecture, "ALGO"),
    ]
}

pub fn weeks(monday: Date, n: i32) -> Vec<Course> {
    (0..n).flat_map(|w| week(monday.add(7 * w))).collect()
}

pub struct Fx {
    pub settings: Settings,
    pub domains: Vec<Domain>,
    pub progress: Progress,
    pub courses: Vec<Course>,
    pub calendar: bool,
    pub busy: Vec<Busy>,
    pub deadlines: Vec<Deadline>,
    pub projects: Vec<Project>,
    pub campaigns: Vec<Campaign>,
    pub chores: Vec<Chore>,
    pub pinned: Vec<Pin>,
    pub away_today: Vec<String>,
    pub extra: Vec<boussole::journee::Extra>,
    pub learned: [Option<Hm>; 7],
    pub spent: Vec<String>,
    pub done: BTreeMap<String, Vec<(Date, i32)>>,
}

impl Fx {
    /// Three subjects, ten school weeks.
    pub fn new(_name: &str) -> Fx {
        let domains = ["ALGO", "LOGIC", "NET"].iter().map(|id| Domain { id: id.to_string(), ..Domain::default() }).collect();
        Fx {
            settings: Settings::default(),
            domains,
            progress: Progress::default(),
            courses: weeks(MON, 10),
            calendar: true,
            busy: Vec::new(),
            deadlines: Vec::new(),
            projects: Vec::new(),
            campaigns: Vec::new(),
            chores: Vec::new(),
            pinned: Vec::new(),
            away_today: Vec::new(),
            extra: Vec::new(),
            learned: [None; 7],
            spent: Vec::new(),
            done: BTreeMap::new(),
        }
    }

    pub fn input<'a>(&'a self, now: Local, previous: Option<&'a Plan>) -> Input<'a> {
        Input {
            now,
            settings: &self.settings,
            domains: &self.domains,
            progress: &self.progress,
            courses: &self.courses,
            calendar: self.calendar,
            busy: &self.busy,
            deadlines: &self.deadlines,
            projects: &self.projects,
            campaigns: &self.campaigns,
            chores: &self.chores,
            pinned: &self.pinned,
            away_today: &self.away_today,
            extra: &self.extra,
            learned: self.learned,
            spent: &self.spent,
            done: &self.done,
            previous,
        }
    }

    pub fn plan(&self, now: Local) -> Plan {
        plan::plan(&self.input(now, None))
    }

    pub fn replan(&self, now: Local, previous: &Plan) -> Plan {
        plan::plan(&self.input(now, Some(previous)))
    }

    pub fn exam(&mut self, domain: &str, date: Date) {
        self.deadlines.push(Deadline {
            id: format!("exam-{domain}"),
            domain: Some(domain.into()),
            kind: DeadlineKind::Exam,
            at: at(date, "08:00"),
            title: format!("Exam {domain}"),
            source: Source::Manual,
            hours: None,
            spent_minutes: 0,
        });
    }
}

/// Every part of a plan's counted sessions, with its date.
pub fn parts(p: &Plan) -> Vec<(Date, &boussole::plan::Session, &boussole::plan::Part)> {
    p.sessions.iter().flat_map(|s| s.parts.iter().map(move |part| (s.date, s, part))).collect()
}

pub fn first_date(p: &Plan, task: &str) -> Option<Date> {
    parts(p).into_iter().find(|(_, _, part)| part.task == task).map(|(d, _, _)| d)
}
