//! The real shape of a day: when the user can work, and where.
//!
//! An evening is a range, not an hour: from back home (last course, commute,
//! shower, dinner) to the latest end before bed. The session starts at the
//! learnt start time when the range allows it, later when it does not, and
//! is shortened rather than pushed past the latest end.

use serde::{Deserialize, Serialize};

use crate::model::{DayKind, DeadlineKind, PeriodRule, Status};
use crate::plan::Input;
use crate::time::{Date, Hm};

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SlotKind {
    Evening,
    Morning,
    Block,
    /// Between two courses, at school.
    Gap,
    /// A Saturday-like block: optional.
    Bonus,
    /// A short optional evening near an exam.
    Short,
    /// Time kept for a campaign on a day free of study.
    Campaign,
    /// Time found on the spot ("I have time").
    Extra,
}

/// Time the user found on the spot: a counted slot from `start`, whatever
/// the day was meant to hold.
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Extra {
    pub date: Date,
    pub start: Hm,
    pub minutes: i32,
    pub place: Place,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Place {
    Home,
    School,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Slot {
    pub date: Date,
    pub start: Hm,
    pub end: Hm,
    pub kind: SlotKind,
    /// Counted slots carry the plan; the others only receive offers, and
    /// what is done there is a head start.
    pub counted: bool,
    pub place: Place,
    /// Shorter than usual (late return, something in the way).
    pub shortened: bool,
    /// The latest a session in it may end ("later" never goes past it).
    pub limit: Hm,
}

impl Slot {
    pub fn minutes(&self) -> i32 {
        self.end.0 - self.start.0
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Mode {
    Normal,
    /// A weekday at the company (work-study).
    Company,
    /// A weekday of a week without courses, full-time studies.
    Home,
    Period(PeriodRule),
    Paused,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Day {
    pub date: Date,
    pub mode: Mode,
    /// Leaving home in the morning.
    pub leave: Option<Hm>,
    /// Back home, before shower and dinner.
    pub home: Option<Hm>,
    pub slots: Vec<Slot>,
}

/// Busy minutes of a date, sorted and merged.
fn busy_on(input: &Input, date: Date, with_courses: bool) -> Vec<(i32, i32)> {
    let mut v: Vec<(i32, i32)> = Vec::new();
    let mut add = |s: crate::time::Local, e: crate::time::Local| {
        if s.date > date || e.date < date {
            return;
        }
        let a = if s.date < date { 0 } else { s.time.0 };
        let b = if e.date > date { 1440 } else { e.time.0 };
        if b > a {
            v.push((a, b));
        }
    };
    for b in input.busy {
        add(b.start, b.end);
    }
    if with_courses {
        for c in input.courses {
            add(c.start, c.end);
        }
    }
    v.sort();
    let mut merged: Vec<(i32, i32)> = Vec::new();
    for (a, b) in v {
        match merged.last_mut() {
            Some(last) if a <= last.1 => last.1 = last.1.max(b),
            _ => merged.push((a, b)),
        }
    }
    merged
}

/// The first `len` minutes from `start` clear of `busy`, sliding past what is
/// in the way and cut at `limit`; None under `min` minutes.
fn place(start: i32, len: i32, min: i32, limit: i32, busy: &[(i32, i32)]) -> Option<(i32, i32, bool)> {
    let mut s = start;
    loop {
        let e = (s + len).min(limit);
        if e - s < min {
            return None;
        }
        match busy.iter().find(|&&(a, b)| a < e && b > s) {
            // Something starts inside: shorten rather than push back, when
            // what is left before it is still worth a session.
            Some(&(a, _)) if a > s && a - s >= min => return Some((s, a, true)),
            Some(&(_, b)) => s = b,
            None => return Some((s, e, e - s < len)),
        }
    }
}

pub fn paused(input: &Input, date: Date) -> bool {
    let s = input.settings;
    if s.paused_until.is_some_and(|until| date <= until) {
        return true;
    }
    if s.periods.iter().any(|p| p.rule == PeriodRule::Pause && p.start <= date && date <= p.end) {
        return true;
    }
    // After the exams: nothing ahead in the calendar, neither course nor exam.
    s.auto_pause && input.calendar && !input.courses.iter().any(|c| c.end.date >= date)
}

fn period(input: &Input, date: Date) -> Option<PeriodRule> {
    input.settings.periods.iter().find(|p| p.start <= date && date <= p.end).map(|p| p.rule)
}

/// No course from Monday to Friday of that week, while the term goes on.
fn courseless_week(input: &Input, date: Date) -> bool {
    let mon = date.monday();
    let fri = mon.add(4);
    let in_week = input.courses.iter().any(|c| c.start.date >= mon && c.start.date <= fri);
    let later = input.courses.iter().any(|c| c.start.date > fri);
    input.calendar && !in_week && later
}

fn exam_soon(input: &Input, date: Date) -> bool {
    let days = input.settings.rhythm.exam_soon_days;
    input.deadlines.iter().any(|d| {
        matches!(d.kind, DeadlineKind::Exam | DeadlineKind::Cc) && (1..=days).contains(&date.days_until(d.at.date))
    })
}

fn campaign_minutes(input: &Input, date: Date, free_day: bool) -> i32 {
    input
        .campaigns
        .iter()
        .filter(|c| !c.closed && c.start <= date && date <= c.end)
        .map(|c| if free_day { c.free_day_minutes } else { c.school_day_minutes })
        .max()
        .unwrap_or(0)
}

/// The day's slots, before "now" is taken into account, with the time found
/// on the spot: it takes its place, and what it overlaps gives way.
pub fn day(input: &Input, date: Date) -> Day {
    let mut out = planned_day(input, date);
    let min = input.settings.rhythm.min_session;
    for x in input.extra.iter().filter(|x| x.date == date) {
        let (a, b) = (x.start.0, x.start.0 + x.minutes);
        out.slots = out
            .slots
            .drain(..)
            .flat_map(|s| {
                if s.end.0 <= a || s.start.0 >= b {
                    return vec![s];
                }
                let mut v = Vec::new();
                if a - s.start.0 >= min {
                    v.push(Slot { end: Hm(a), shortened: true, ..s.clone() });
                }
                if s.end.0 - b >= min {
                    v.push(Slot { start: Hm(b), shortened: true, ..s.clone() });
                }
                v
            })
            .collect();
        out.slots.push(Slot {
            date,
            start: x.start,
            end: Hm(b),
            kind: SlotKind::Extra,
            counted: true,
            place: x.place,
            shortened: false,
            limit: Hm(b),
        });
    }
    out.slots.sort_by_key(|s| s.start);
    out
}

fn planned_day(input: &Input, date: Date) -> Day {
    let r = &input.settings.rhythm;
    let wd = date.weekday();
    let weekday = wd < 5;
    let mut out = Day { date, mode: Mode::Normal, leave: None, home: None, slots: Vec::new() };
    if paused(input, date) {
        out.mode = Mode::Paused;
        return out;
    }

    let mut busy = busy_on(input, date, true);
    if weekday {
        if let Some((a, b)) = r.midday {
            busy.push((a.0, b.0));
            busy.sort();
        }
    }
    let slot = |start: i32, end: i32, kind: SlotKind, counted: bool, place: Place, shortened: bool, limit: Hm| Slot {
        date,
        start: Hm(start),
        end: Hm(end),
        kind,
        counted,
        place,
        shortened,
        limit,
    };
    let blocks = |counted: bool, kind: SlotKind, busy: &mut Vec<(i32, i32)>| -> Vec<Slot> {
        let mut v = Vec::new();
        for b in &r.blocks {
            let start = b.0.max(r.block_range.0 .0);
            if let Some((s, e, short)) = place(start, r.block_minutes, r.min_session, r.block_range.1 .0, busy) {
                busy.push((s, e));
                busy.sort();
                v.push(slot(s, e, kind, counted, Place::Home, short, r.block_range.1));
            }
        }
        v
    };

    if let Some(rule) = period(input, date) {
        out.mode = Mode::Period(rule);
        match rule {
            PeriodRule::Normal => out.mode = Mode::Normal,
            PeriodRule::Pause => return out,
            PeriodRule::BonusOnly => {
                out.slots = blocks(false, SlotKind::Bonus, &mut busy);
                return out;
            }
            PeriodRule::Free => {
                let m = campaign_minutes(input, date, true);
                if weekday && m > 0 {
                    let limit = r.midday.map_or(r.latest_end, |(a, _)| a);
                    if let Some((s, e, short)) = place(r.morning_ready.0, m, r.min_session, limit.0, &busy) {
                        out.slots.push(slot(s, e, SlotKind::Campaign, true, Place::Home, short, limit));
                    }
                }
                return out;
            }
            PeriodRule::MorningBlock if weekday => {
                let limit = r.midday.map_or(r.latest_end, |(a, _)| a);
                let len = r.period_morning_minutes;
                if let Some((s, e, short)) = place(r.morning_ready.0, len, r.min_session, limit.0, &busy) {
                    out.slots.push(slot(s, e, SlotKind::Morning, true, Place::Home, short, limit));
                    busy.push((s, e));
                    busy.sort();
                }
                let m = campaign_minutes(input, date, false);
                if m > 0 {
                    if let Some((s, e, short)) = place(r.morning_ready.0, m, r.min_session, limit.0, &busy) {
                        out.slots.push(slot(s, e, SlotKind::Campaign, true, Place::Home, short, limit));
                    }
                }
                return out;
            }
            PeriodRule::MorningBlock => {}
        }
    }

    let today: Vec<_> = input.courses.iter().filter(|c| c.start.date == date).collect();
    let company = weekday
        && match &input.settings.status {
            Status::Alternance { since, .. } => *since <= date && courseless_week(input, date),
            Status::Initial => false,
        };
    let home_day = weekday && !company && courseless_week(input, date);
    if company {
        out.mode = Mode::Company;
    } else if home_day {
        out.mode = Mode::Home;
    }

    // Leaving and coming back.
    let (first, last) = if let (true, Status::Alternance { work_start, work_end, .. }) = (company, &input.settings.status) {
        (Some(work_start.0), Some(work_end.0))
    } else {
        (today.iter().map(|c| c.start.time.0).min(), today.iter().map(|c| c.end.time.0).max())
    };
    if let (Some(first), Some(last)) = (first, last) {
        let mut leave = first - r.commute;
        if let Some((a, _)) = r.midday {
            if weekday && first > a.0 {
                leave = leave.min(a.0 - r.commute);
            }
        }
        out.leave = Some(Hm(leave));
        out.home = Some(Hm(last + r.commute));
        // At school or work, none of the day is free at home.
        busy.push((leave, last + r.commute));
        busy.sort();
    }

    let kind = r.week[wd as usize];
    let evening = |len: i32, counted: bool, kind: SlotKind, busy: &[(i32, i32)]| -> Option<Slot> {
        let ready = out.home.map_or(0, |h| h.0 + r.shower + r.dinner);
        let target = input.learned[wd as usize].unwrap_or(r.evening_target).0;
        let start = Hm(target.max(ready)).ceil(5).0;
        let (s, e, short) = place(start, len, r.min_session, r.latest_end.0, busy)?;
        Some(slot(s, e, kind, counted, Place::Home, short || start > target, r.latest_end))
    };

    match kind {
        DayKind::Evening => {
            if let Some(s) = evening(r.evening_minutes, true, SlotKind::Evening, &busy) {
                out.slots.push(s);
            }
            // Courses over by the midday break: the afternoon at home is a
            // real block, half an hour after the gym or the way back, and
            // done before dinner.
            let noon = r.midday.map_or(13 * 60, |(a, _)| a.0 + 30);
            let last = today.iter().map(|c| c.end.time.0).max();
            if let (false, Some(last), Some(home), true) = (company, last, out.home, r.half_day_minutes > 0) {
                if last <= noon {
                    let start = home.0.max(r.midday.map_or(0, |(_, b)| b.0)) + 30;
                    let limit = out.slots.iter().find(|s| s.kind == SlotKind::Evening).map_or(r.evening_target, |s| s.start).0 - r.dinner;
                    if let Some((s, e, short)) = place(start, r.half_day_minutes, r.min_session, limit, &busy) {
                        out.slots.push(slot(s, e, SlotKind::Block, true, Place::Home, short, Hm(limit)));
                    }
                }
            }
            if !company {
                let leave = out.leave.map_or(r.midday.map_or(r.latest_end.0, |(a, _)| a.0), |l| l.0);
                if leave - r.morning_ready.0 >= r.morning_lead {
                    let limit = Hm(leave);
                    if let Some((s, e, short)) = place(r.morning_ready.0, r.morning_minutes, r.min_session, leave, &busy) {
                        out.slots.push(slot(s, e, SlotKind::Morning, true, Place::Home, short, limit));
                    }
                }
            }
        }
        DayKind::Free => {
            if exam_soon(input, date) {
                if let Some(s) = evening(r.short_minutes, false, SlotKind::Short, &busy) {
                    out.slots.push(s);
                }
            }
            // A free evening stays free, campaign or not: a school day's
            // campaign time goes to a gap that day, or is not owed.
        }
        DayKind::Bonus => out.slots.extend(blocks(false, SlotKind::Bonus, &mut busy)),
        DayKind::Blocks => out.slots.extend(blocks(true, SlotKind::Block, &mut busy)),
    }

    // Gaps between courses, at school, around the midday break.
    if !company && today.len() >= 2 {
        let mut spans: Vec<(i32, i32)> = today
            .iter()
            .map(|c| (c.start.time.0, c.end.time.0))
            .collect();
        spans.sort();
        let personal = busy_on(input, date, false);
        let mut prev_end = spans[0].1;
        for &(a, b) in &spans[1..] {
            if a > prev_end {
                let mut pieces = vec![(prev_end, a)];
                let mut blockers = personal.clone();
                if let Some((x, y)) = r.midday {
                    blockers.push((x.0, y.0));
                }
                for (x, y) in blockers {
                    pieces = pieces
                        .into_iter()
                        .flat_map(|(p, q)| {
                            if y <= p || x >= q {
                                vec![(p, q)]
                            } else {
                                vec![(p, x.max(p)), (y.min(q), q)]
                            }
                        })
                        .filter(|(p, q)| q > p)
                        .collect();
                }
                for (p, q) in pieces {
                    if q - p >= r.gap_min {
                        out.slots.push(slot(p, q, SlotKind::Gap, false, Place::School, false, Hm(q)));
                    }
                }
            }
            prev_end = prev_end.max(b);
        }
    }
    out.slots.sort_by_key(|s| s.start);
    out
}

/// "Later" is always a precise time: the half hours from now on where the
/// session still fits a useful length before the slot's limit.
pub fn later_options(slot: &Slot, now: Hm, len: i32, min: i32) -> Vec<(Hm, Hm)> {
    let mut v = Vec::new();
    let mut t = now.plus(10).ceil(30).max(slot.start.plus(1).ceil(30));
    while t.0 + min <= slot.limit.0 && v.len() < 3 {
        v.push((t, Hm((t.0 + len).min(slot.limit.0))));
        t = t.plus(30);
    }
    v
}

/// The start time to expect on a weekday, from the real starts in the
/// journal: the median of the last four, rounded to 5 minutes.
pub fn learn_start(starts: &[(Date, Hm)], weekday: u32) -> Option<Hm> {
    let mut last: Vec<(Date, Hm)> = starts.iter().copied().filter(|(d, _)| d.weekday() == weekday).collect();
    last.sort();
    let mut times: Vec<i32> = last.iter().rev().take(4).map(|(_, t)| t.0).collect();
    if times.is_empty() {
        return None;
    }
    times.sort();
    let n = times.len();
    let median = if n % 2 == 1 { times[n / 2] } else { (times[n / 2 - 1] + times[n / 2]) / 2 };
    Some(Hm(median).ceil(5))
}
