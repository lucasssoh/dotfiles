//! What the planner is told: settings, domains, deadlines, projects,
//! campaigns, progress. Generic on purpose: a domain is a subject while
//! studying, a deadline an exam; the words "subject" and "exam" only exist in
//! the interface's study mode.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::time::{Date, Hm, Local};

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Lang {
    #[default]
    En,
    Fr,
}

/// How far ahead the plan works: Pass / Ranked / Podium.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Objective {
    Pass,
    Ranked,
    #[default]
    Podium,
}

impl Objective {
    /// Weeks before an exam that timed exam-type subjects start.
    pub fn exam_practice_weeks(self) -> i32 {
        match self {
            Objective::Pass => 2,
            Objective::Ranked => 3,
            Objective::Podium => 4,
        }
    }

    /// Counted sessions kept free just before each exam.
    pub fn margin_sessions(self) -> usize {
        match self {
            Objective::Pass => 0,
            Objective::Ranked => 1,
            Objective::Podium => 2,
        }
    }

    /// An exercise done with the solution open counts as acquired.
    pub fn solution_counts(self) -> bool {
        self != Objective::Podium
    }
}

#[derive(Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Status {
    /// Full-time studies.
    #[default]
    Initial,
    /// Work-study: from `since`, a weekday of a week without any course is a
    /// day at the company.
    Alternance { since: Date, work_start: Hm, work_end: Hm },
}

/// What a weekday normally holds.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DayKind {
    /// One session in the evening, within [back home … latest end].
    Evening,
    /// Nothing counted (a short optional evening near an exam).
    Free,
    /// Optional blocks: anything done there is a head start, never counted.
    Bonus,
    /// Counted blocks at fixed times.
    Blocks,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Rhythm {
    /// Monday first.
    pub week: [DayKind; 7],
    pub wake: Hm,
    pub bedtime: Hm,
    /// No session ends after this.
    pub latest_end: Hm,
    /// When the evening alert falls before anything has been learnt.
    pub evening_target: Hm,
    pub evening_minutes: i32,
    /// Shorter than this, a slot is not worth a session.
    pub min_session: i32,
    pub commute: i32,
    pub shower: i32,
    pub dinner: i32,
    /// When the morning routine is over.
    pub morning_ready: Hm,
    pub morning_minutes: i32,
    /// A morning block needs at least this long between `morning_ready` and leaving.
    pub morning_lead: i32,
    /// Never offered for work (the gym), weekdays.
    pub midday: Option<(Hm, Hm)>,
    /// A gap between two courses offered for work from this length.
    pub gap_min: i32,
    pub blocks: Vec<Hm>,
    pub block_minutes: i32,
    /// Where blocks may slide when something is in the way.
    pub block_range: (Hm, Hm),
    /// A free evening offers a short session when an exam is this close.
    pub exam_soon_days: i32,
    pub short_minutes: i32,
    /// The morning block of a "morning block" period.
    pub period_morning_minutes: i32,
}

impl Default for Rhythm {
    fn default() -> Rhythm {
        use DayKind::*;
        Rhythm {
            week: [Evening, Evening, Evening, Evening, Free, Bonus, Blocks],
            wake: Hm::new(6, 0),
            bedtime: Hm::new(22, 30),
            latest_end: Hm::new(22, 15),
            evening_target: Hm::new(20, 30),
            evening_minutes: 75,
            min_session: 20,
            commute: 45,
            shower: 10,
            dinner: 60,
            morning_ready: Hm::new(8, 30),
            morning_minutes: 45,
            morning_lead: 60,
            midday: Some((Hm::new(12, 0), Hm::new(13, 30))),
            gap_min: 30,
            blocks: vec![Hm::new(10, 0), Hm::new(15, 0)],
            block_minutes: 90,
            block_range: (Hm::new(10, 0), Hm::new(19, 0)),
            exam_soon_days: 14,
            short_minutes: 40,
            period_morning_minutes: 90,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum PeriodRule {
    Normal,
    /// No study at all.
    Free,
    /// One study block each weekday morning.
    MorningBlock,
    BonusOnly,
    Pause,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Period {
    pub name: String,
    pub start: Date,
    /// Inclusive.
    pub end: Date,
    pub rule: PeriodRule,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub lang: Lang,
    pub objective: Objective,
    pub status: Status,
    pub rhythm: Rhythm,
    pub periods: Vec<Period>,
    /// Pause on its own once the calendar holds nothing ahead.
    pub auto_pause: bool,
    /// Manual pause, until this date (inclusive).
    pub paused_until: Option<Date>,
    /// Days the plan looks ahead, at least (it always reaches the last deadline).
    pub horizon_days: i32,
    pub pace: Pace,
    /// Measured estimate bias on projects: 1.4 = takes 40 % longer than guessed.
    pub project_bias: f32,
    /// The course folder, read only.
    pub courses: Option<PathBuf>,
    pub ignore: crate::catalogue::Ignore,
    pub domains: Vec<Domain>,
    /// The timetable's iCal address (never in the repository).
    pub calendar_url: Option<String>,
    /// Group values ticked per family of the feed.
    pub groups: BTreeMap<String, Vec<String>>,
    /// When the evening recap falls if no session ends the day.
    pub recap: Hm,
    /// Ask before a game starts during a session.
    pub gate: bool,
    /// Commands the gate asks about (a word of the command line).
    pub gate_match: Vec<String>,
    /// Process names that mean a game is running (Steam's reaper, …).
    pub game_processes: Vec<String>,
}

impl Default for Settings {
    fn default() -> Settings {
        Settings {
            lang: Lang::En,
            objective: Objective::Podium,
            status: Status::Initial,
            rhythm: Rhythm::default(),
            periods: Vec::new(),
            auto_pause: true,
            paused_until: None,
            horizon_days: 28,
            pace: Pace::default(),
            project_bias: 1.0,
            courses: None,
            ignore: crate::catalogue::Ignore::default(),
            domains: Vec::new(),
            calendar_url: None,
            groups: BTreeMap::new(),
            recap: Hm::new(21, 30),
            gate: true,
            gate_match: ["steam", "lutris", "heroic", "gamescope", "umu-run", "wine"].map(String::from).to_vec(),
            game_processes: ["reaper", "gamescope", "gamescope-wl", "lutris-wrapper", "umu-run", "wine64-preloader", "wine-preloader"]
                .map(String::from)
                .to_vec(),
        }
    }
}

/// Minutes per piece of work, measured from the journal once there is one.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Pace {
    /// Opening, header table, closing.
    pub overhead: i32,
    /// Reading all of a sheet's sections (split evenly between them).
    pub reading: i32,
    pub recall: i32,
    pub exercise: i32,
    pub map: i32,
    pub pdf: i32,
    pub notes: i32,
    pub review: i32,
    pub redo: i32,
    pub question: i32,
    pub td_prep: i32,
    pub exam_subject: i32,
    pub interview_prep: i32,
    /// Per-domain multiplier, from the measured pace.
    pub domain_factor: BTreeMap<String, f32>,
}

impl Default for Pace {
    fn default() -> Pace {
        Pace {
            overhead: 10,
            reading: 20,
            recall: 10,
            exercise: 12,
            map: 20,
            pdf: 60,
            notes: 30,
            review: 15,
            redo: 15,
            question: 10,
            td_prep: 30,
            exam_subject: 90,
            interview_prep: 45,
            domain_factor: BTreeMap::new(),
        }
    }
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Domain {
    /// Also the folder name under the courses root: `A&C`.
    pub id: String,
    /// Names of its courses in the calendar feed, matched loosely.
    pub calendar_names: Vec<String>,
    /// Spaced reviews after each studied item.
    pub spaced: bool,
    pub archived: bool,
    /// Work order set by hand, item ids; the rest follows file order.
    pub order: Vec<String>,
    /// Stars set or removed by hand, over the course map's.
    pub stars: BTreeMap<String, bool>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DeadlineKind {
    Exam,
    /// Continuous assessment: untouchable, prepared 3 days ahead.
    Cc,
    /// A hand-in, with its own hours of work.
    Due,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Source {
    Calendar,
    Manual,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Deadline {
    pub id: String,
    pub domain: Option<String>,
    pub kind: DeadlineKind,
    pub at: Local,
    pub title: String,
    pub source: Source,
    /// Work it needs on its own (a hand-in), before the bias correction.
    #[serde(default)]
    pub hours: Option<f32>,
    #[serde(default)]
    pub spent_minutes: i32,
}

impl Deadline {
    /// Work for it is finished by then.
    pub fn work_due(&self) -> Date {
        match self.kind {
            DeadlineKind::Exam => self.at.date,
            DeadlineKind::Cc | DeadlineKind::Due => self.at.date.add(-3),
        }
    }
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Step {
    pub name: String,
    pub hours: f32,
    pub done: bool,
    pub spent_minutes: i32,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub domain: Option<String>,
    pub due: Local,
    pub steps: Vec<Step>,
    #[serde(default)]
    pub archived: bool,
}

impl Project {
    /// Finished 3 days before the hand-in, never squeezed.
    pub fn work_due(&self) -> Date {
        self.due.date.add(-3)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RowStatus {
    ToSend,
    Sent,
    FollowUp,
    Interview,
    Refused,
    Offer,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Row {
    pub name: String,
    pub status: RowStatus,
    #[serde(default)]
    pub sent: Option<Date>,
    #[serde(default)]
    pub interview: Option<Local>,
}

/// A recurring effort with an end: the work-study search is the first one.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Campaign {
    pub id: String,
    pub name: String,
    pub start: Date,
    pub end: Date,
    /// On a school day.
    pub school_day_minutes: i32,
    /// On a weekday free of study (first week of a holiday).
    pub free_day_minutes: i32,
    pub weekly_target: u32,
    #[serde(default)]
    pub rows: Vec<Row>,
    #[serde(default)]
    pub closed: bool,
}

/// A task typed by hand, with or without a file.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Chore {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub file: Option<String>,
    pub minutes: i32,
    #[serde(default)]
    pub due: Option<Date>,
    #[serde(default)]
    pub done: bool,
}

/// Time already taken: a personal calendar event, an "unavailable" line.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Busy {
    pub start: Local,
    pub end: Local,
    #[serde(default)]
    pub title: String,
}

/// A course from the calendar feed, already filtered to the user's groups.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Course {
    pub uid: String,
    pub start: Local,
    pub end: Local,
    pub kind: CourseKind,
    pub domain: Option<String>,
    pub title: String,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CourseKind {
    Lecture,
    Tutorial,
    Lab,
    Exam,
    Other,
}

// ─── Progress ────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Exercise {
    /// Solved without the solution.
    Solo,
    WithSolution,
    Failed,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Assessment {
    Understood,
    Review,
    Blocked,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ItemProgress {
    /// Last section really understood (§ number, 0 = none).
    pub read_upto: u32,
    pub exercises: BTreeMap<u32, Exercise>,
    /// The session that finished the item's first pass.
    pub studied_on: Option<Date>,
    /// The latest session on it.
    pub last_on: Option<Date>,
    pub assessment: Option<Assessment>,
    pub reviews_done: Vec<Date>,
    /// Exam-type subjects done (in time-limited conditions).
    pub subjects_done: u32,
    /// "Blocked" turned into a question; cleared once asked.
    pub question_open: bool,
    /// Whole item ticked off without detail (a PDF read, notes gone through).
    pub done: bool,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Progress {
    pub items: BTreeMap<String, ItemProgress>,
    /// Course uids whose preparation is done.
    pub prepared: Vec<String>,
    /// Campaign days already worked (campaign id, date).
    pub campaign_days: Vec<(String, Date)>,
    /// Interviews whose preparation is done (campaign id, row name).
    pub interviews_prepared: Vec<(String, String)>,
    /// What the user decided about each file; a file missing here is new.
    pub files: BTreeMap<String, crate::catalogue::Inclusion>,
}
