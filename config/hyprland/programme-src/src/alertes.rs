//! When to say what. Pure: the plan, what became of each session and the
//! alerts already sent give the alerts due now and the next time to wake.
//!
//!   recap    the evening before: tomorrow's sessions and gaps at school;
//!            at the end of that evening's session, else at `recap`;
//!   start    when a session starts (or at the time chosen with "later");
//!   reminder 15 minutes on, if it has not started.
//!
//! Nothing between the latest end and the morning. Coming back from sleep
//! never brings a burst: an alert whose moment has passed is dropped (a
//! session over by then goes to the check-in), and of several due at once
//! only the newest of each kind is sent.

use std::collections::BTreeSet;

use crate::model::Settings;
use crate::plan::{Plan, Session};
use crate::store::{Outcome, State};
use crate::time::{Date, Local};

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub enum Kind {
    Recap,
    Start,
    Reminder,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Alert {
    /// Sent once: "start:2026-10-05-evening1@20:30".
    pub key: String,
    pub at: Local,
    pub kind: Kind,
    pub session: Option<String>,
    /// For a recap, the day it is about.
    pub day: Option<Date>,
}

/// How long after its moment an alert is still worth sending.
const FRESH: i64 = 20;
const REMIND_AFTER: i64 = 15;

fn waiting(state: &State, s: &Session) -> Option<Local> {
    let start = Local::new(s.date, s.start);
    match state.outcomes.get(&s.id) {
        None | Some(Outcome::Missed) => Some(start),
        Some(Outcome::Postponed { to }) => Some(*to),
        _ => None,
    }
}

/// Every alert of today and tomorrow.
pub fn planned(plan: &Plan, state: &State, settings: &Settings, today: Date) -> Vec<Alert> {
    let mut out = Vec::new();
    let worth = |s: &&Session| s.counted && !s.parts.is_empty();
    // One thing at a time: while a session is under way, the next ones of
    // the evening keep quiet.
    let busy = plan
        .sessions
        .iter()
        .any(|s| matches!(state.outcomes.get(&s.id), Some(Outcome::Started { .. } | Outcome::Paused { .. })));
    for s in plan.sessions.iter().filter(worth).filter(|s| !busy && (s.date == today || s.date == today.add(1))) {
        let Some(at) = waiting(state, s) else { continue };
        let tag = format!("{}@{}", s.id, at.time);
        out.push(Alert { key: format!("start:{tag}"), at, kind: Kind::Start, session: Some(s.id.clone()), day: None });
        out.push(Alert {
            key: format!("remind:{tag}"),
            at: at.plus(REMIND_AFTER),
            kind: Kind::Reminder,
            session: Some(s.id.clone()),
            day: None,
        });
    }
    for day in [today, today.add(1)] {
        let next = day.add(1);
        let has_next = plan.sessions.iter().any(|s| s.date == next && worth(&s)) || plan.offers.iter().any(|o| o.date == next);
        if !has_next {
            continue;
        }
        // After the day's last evening session, or at the recap time.
        let end = plan
            .sessions
            .iter()
            .filter(|s| s.date == day && s.counted && s.start >= settings.rhythm.evening_target.plus(-120))
            .map(|s| s.end)
            .max()
            .unwrap_or(settings.recap)
            .min(settings.rhythm.latest_end);
        out.push(Alert { key: format!("recap:{next}"), at: Local::new(day, end), kind: Kind::Recap, session: None, day: Some(next) });
    }
    out.sort_by_key(|a| (a.at, a.kind));
    out
}

fn quiet(settings: &Settings, t: Local) -> bool {
    t.time > settings.rhythm.latest_end || t.time < settings.rhythm.wake
}

/// The alerts to send now, already thinned out.
pub fn due(plan: &Plan, state: &State, settings: &Settings, sent: &BTreeSet<String>, now: Local) -> Vec<Alert> {
    if quiet(settings, now) {
        return Vec::new();
    }
    let all = planned(plan, state, settings, now.date);
    let mut out: Vec<Alert> = Vec::new();
    for a in all.into_iter().filter(|a| a.at <= now && !sent.contains(&a.key)) {
        let stale = now.minutes() - a.at.minutes() > FRESH;
        let session = a.session.as_ref().and_then(|id| plan.sessions.iter().find(|s| s.id == *id));
        let over = session.is_some_and(|s| now >= Local::new(s.date, s.end));
        match a.kind {
            Kind::Recap if stale => continue,
            Kind::Start | Kind::Reminder if over => continue,
            // A late start replaces its reminder, and vice versa.
            Kind::Reminder if stale => continue,
            _ => {}
        }
        out.retain(|o| !(o.session.is_some() && o.session == a.session));
        out.retain(|o| o.kind != a.kind || a.kind == Kind::Recap && o.day != a.day);
        out.push(a);
    }
    out
}

/// The alerts that will never be sent (their time is gone), to mark sent.
pub fn expired(plan: &Plan, state: &State, settings: &Settings, sent: &BTreeSet<String>, now: Local) -> Vec<String> {
    let keep: BTreeSet<String> = due(plan, state, settings, sent, now).into_iter().map(|a| a.key).collect();
    planned(plan, state, settings, now.date)
        .into_iter()
        .filter(|a| a.at <= now && !sent.contains(&a.key) && !keep.contains(&a.key))
        .filter(|_| !quiet(settings, now))
        .map(|a| a.key)
        .collect()
}

/// The next moment an alert falls, if any, moved out of the quiet hours.
pub fn next(plan: &Plan, state: &State, settings: &Settings, sent: &BTreeSet<String>, now: Local) -> Option<Local> {
    let mut times: Vec<Local> = planned(plan, state, settings, now.date)
        .into_iter()
        .filter(|a| !sent.contains(&a.key) && a.at > now)
        .map(|a| a.at)
        .collect();
    // The end of a session opens its closing window; tell the bar then.
    times.extend(
        plan.sessions
            .iter()
            .filter(|s| s.date >= now.date)
            .map(|s| Local::new(s.date, s.end).plus(15))
            .filter(|t| *t > now),
    );
    let t = times.into_iter().min()?;
    Some(if quiet(settings, t) && t.time < settings.rhythm.wake {
        Local::new(t.date, settings.rhythm.wake)
    } else {
        t
    })
}
