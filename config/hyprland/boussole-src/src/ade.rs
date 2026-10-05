//! Timetables from an iCal feed (ADE, or any other).
//!
//! A promotion-wide feed holds every group's courses. Rather than a pattern
//! the user would have to write, the group tokens of the titles ("TD 1",
//! "TP2:", "Groupe B") are gathered into families, and the user ticks a value
//! in each. Only the SUMMARY is read for groups: ADE's descriptions list every
//! group of an exam room and would match anyone.
//!
//! ADE does not mark cancellations, a cancelled course just disappears, and a
//! failed or empty download must never wipe the timetable: `reconcile` keeps
//! the last good snapshot and says why.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::model::{Course, CourseKind, Deadline, DeadlineKind, Domain, Source};
use crate::time::{Date, Hm, Local, Tz};

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Event {
    pub uid: String,
    pub summary: String,
    #[serde(default)]
    pub location: String,
    #[serde(default)]
    pub description: String,
    /// Instants, seconds since the epoch.
    pub start: i64,
    pub end: i64,
}

// ─── Parsing ─────────────────────────────────────────────────────────────────

fn unescape(v: &str) -> String {
    let mut out = String::with_capacity(v.len());
    let mut it = v.chars();
    while let Some(c) = it.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match it.next() {
            Some('n' | 'N') => out.push('\n'),
            Some(o) => out.push(o),
            None => {}
        }
    }
    out
}

/// `20261211T144500Z`, `20261211T154500` (in `tz`) or `20261211` (all day).
fn parse_stamp(value: &str, params: &str, local: &Tz) -> Option<i64> {
    let zone = params
        .split(';')
        .find_map(|p| p.strip_prefix("TZID="))
        .and_then(|name| Tz::named(name.trim_matches('"')));
    let tz = zone.as_ref().unwrap_or(local);
    let v = value.trim();
    let date = Date::ymd(v.get(0..4)?.parse().ok()?, v.get(4..6)?.parse().ok()?, v.get(6..8)?.parse().ok()?);
    let Some(t) = v.get(9..15) else {
        return Some(tz.to_utc(Local::new(date, Hm(0))));
    };
    let (h, m, s): (i64, i64, i64) = (t[0..2].parse().ok()?, t[2..4].parse().ok()?, t[4..6].parse().ok()?);
    if v.ends_with('Z') {
        return Some(date.0 as i64 * 86_400 + h * 3600 + m * 60 + s);
    }
    Some(tz.to_utc(Local::new(date, Hm((h * 60 + m) as i32))) + s)
}

/// Every VEVENT of a calendar. Floating times are read in `local`.
pub fn parse(text: &str, local: &Tz) -> Result<Vec<Event>, String> {
    if !text.trim_start().starts_with("BEGIN:VCALENDAR") {
        return Err("not an iCal calendar".into());
    }
    // Unfold: a line starting with a space or a tab continues the previous one.
    let mut lines: Vec<String> = Vec::new();
    for raw in text.split('\n') {
        let raw = raw.strip_suffix('\r').unwrap_or(raw);
        match raw.strip_prefix([' ', '\t']) {
            Some(rest) if !lines.is_empty() => lines.last_mut().unwrap().push_str(rest),
            _ => lines.push(raw.to_string()),
        }
    }
    let mut events = Vec::new();
    let mut cur: Option<BTreeMap<String, (String, String)>> = None;
    for line in &lines {
        match line.as_str() {
            "BEGIN:VEVENT" => cur = Some(BTreeMap::new()),
            "END:VEVENT" => {
                let Some(f) = cur.take() else { continue };
                let get = |k: &str| f.get(k).map(|(_, v)| unescape(v)).unwrap_or_default();
                let stamp = |k: &str| f.get(k).and_then(|(p, v)| parse_stamp(v, p, local));
                let Some(start) = stamp("DTSTART") else { continue };
                let end = stamp("DTEND").unwrap_or(start + 3600);
                events.push(Event {
                    uid: get("UID"),
                    summary: squash(&get("SUMMARY")),
                    location: get("LOCATION"),
                    description: get("DESCRIPTION"),
                    start,
                    end,
                });
            }
            _ => {
                if let (Some(f), Some((key, value))) = (cur.as_mut(), line.split_once(':')) {
                    let (name, params) = key.split_once(';').unwrap_or((key, ""));
                    f.insert(name.to_ascii_uppercase(), (params.to_string(), value.to_string()));
                }
            }
        }
    }
    Ok(events)
}

fn squash(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Lowercase, without accents or punctuation, for loose comparisons.
pub fn normalize(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars().flat_map(char::to_lowercase) {
        let c = match c {
            'à' | 'â' | 'ä' | 'á' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' | 'í' => 'i',
            'ô' | 'ö' | 'ó' => 'o',
            'ù' | 'û' | 'ü' | 'ú' => 'u',
            'ç' => 'c',
            'œ' => 'o',
            c if c.is_alphanumeric() || c == '&' => c,
            _ => ' ',
        };
        out.push(c);
    }
    squash(&out)
}

// ─── Titles: kind, groups, name ──────────────────────────────────────────────

const FAMILIES: [&str; 6] = ["TD", "TP", "TPL", "G", "GR", "GROUPE"];

#[derive(Clone, PartialEq, Debug)]
pub struct Title {
    pub kind: CourseKind,
    /// (family, value): ("TD", "1"), ("GROUPE", "B").
    pub groups: Vec<(String, String)>,
    /// What is left once kind and groups are gone: the course's name.
    pub name: String,
}

fn group_value(word: &str) -> Option<String> {
    if !word.is_empty() && word.len() <= 2 && word.chars().all(|c| c.is_ascii_digit()) {
        let v = word.trim_start_matches('0');
        return Some(if v.is_empty() { "0" } else { v }.to_string());
    }
    let mut cs = word.chars();
    match (cs.next(), cs.next()) {
        (Some(c), None) if c.is_ascii_uppercase() => Some(c.to_string()),
        _ => None,
    }
}

pub fn read_title(summary: &str) -> Title {
    let lower = normalize(summary);
    let kind = if ["examen", "partiel", "test oral", "controle", "soutenance", "epreuve"]
        .iter()
        .any(|k| lower.contains(k))
    {
        CourseKind::Exam
    } else {
        let first = summary.split([' ', ':']).next().unwrap_or("").to_ascii_uppercase();
        match first.trim_end_matches(|c: char| c.is_ascii_digit()) {
            "CM" => CourseKind::Lecture,
            "TD" => CourseKind::Tutorial,
            "TP" | "TPL" => CourseKind::Lab,
            _ => CourseKind::Other,
        }
    };

    let words: Vec<&str> = summary.split([' ', ':', ',']).filter(|w| !w.is_empty()).collect();
    let mut groups = Vec::new();
    let mut used = vec![false; words.len()];
    let mut i = 0;
    while i < words.len() {
        let up = words[i].to_ascii_uppercase();
        // "TD1", "TPL02", "G1"
        let split = up.find(|c: char| c.is_ascii_digit()).filter(|&p| p > 0);
        if let Some(p) = split {
            if let Some(v) = group_value(&up[p..]).filter(|_| FAMILIES.contains(&&up[..p])) {
                groups.push((up[..p].to_string(), v));
                used[i] = true;
                i += 1;
                continue;
            }
        }
        // "TD 1", "Groupe B"
        if FAMILIES.contains(&up.as_str()) {
            if let Some(v) = words.get(i + 1).and_then(|w| group_value(w)) {
                groups.push((up, v));
                used[i] = true;
                used[i + 1] = true;
                i += 2;
                continue;
            }
        }
        i += 1;
    }

    let noise = ["CM", "TD", "TP", "TPL", "TEST", "ORAL", "EXAMEN", "ÉCRIT", "ECRIT", "PARTIEL", "--", "-", "—"];
    let name: Vec<&str> = words
        .iter()
        .enumerate()
        .filter(|(i, w)| !used[*i] && !noise.contains(&w.to_uppercase().as_str()))
        .map(|(_, w)| *w)
        .collect();
    Title { kind, groups, name: name.join(" ") }
}

/// A group family seen in the feed, with the values it takes.
#[derive(Clone, PartialEq, Debug, Serialize)]
pub struct Family {
    pub name: String,
    /// (value, number of events), sorted by value.
    pub values: Vec<(String, usize)>,
    /// A few titles, for the preview.
    pub examples: Vec<String>,
}

/// The families worth asking about: those with at least two values.
pub fn families(events: &[Event]) -> Vec<Family> {
    let mut seen: BTreeMap<String, (BTreeMap<String, usize>, BTreeSet<String>)> = BTreeMap::new();
    for e in events {
        for (fam, val) in read_title(&e.summary).groups {
            let entry = seen.entry(fam).or_default();
            *entry.0.entry(val).or_default() += 1;
            if entry.1.len() < 4 {
                entry.1.insert(e.summary.clone());
            }
        }
    }
    seen.into_iter()
        .filter(|(_, (vals, _))| vals.len() >= 2)
        .map(|(name, (vals, ex))| Family { name, values: vals.into_iter().collect(), examples: ex.into_iter().collect() })
        .collect()
}

/// Ticked values per family. A family left out keeps all its values.
pub type Selection = BTreeMap<String, Vec<String>>;

pub fn keeps(selection: &Selection, title: &Title) -> bool {
    title.groups.iter().all(|(fam, val)| match selection.get(fam) {
        Some(chosen) if !chosen.is_empty() => chosen.contains(val),
        _ => true,
    })
}

// ─── Courses ↔ domains ───────────────────────────────────────────────────────

fn contains_words(hay: &[&str], needle: &[&str]) -> bool {
    !needle.is_empty() && hay.windows(needle.len()).any(|w| w == needle)
}

/// The domain whose calendar name appears in the title, as whole words. The
/// longest name wins ("ACL" against a whole course title).
pub fn match_domain<'a>(summary: &str, domains: &'a [Domain]) -> Option<&'a Domain> {
    let hay = normalize(summary);
    let hay: Vec<&str> = hay.split(' ').collect();
    domains
        .iter()
        .filter(|d| !d.archived)
        .flat_map(|d| d.calendar_names.iter().map(move |n| (d, normalize(n))))
        .filter(|(_, n)| contains_words(&hay, &n.split(' ').collect::<Vec<_>>()))
        .max_by_key(|(_, n)| n.len())
        .map(|(d, _)| d)
}

const STOPWORDS: [&str; 10] = ["et", "de", "des", "du", "la", "le", "les", "d", "l", "en"];

/// The folder a course name most likely belongs to, for the first run:
/// "Logique et modèles de calculs" → L&MC (initials), "Réseaux" → RESEAUX.
pub fn suggest_domain<'a>(name: &str, ids: &[&'a str]) -> Option<&'a str> {
    let words: Vec<String> = normalize(name)
        .split(' ')
        .filter(|w| !STOPWORDS.contains(w) && !w.chars().all(|c| c.is_ascii_digit()))
        .map(String::from)
        .collect();
    let initials: String = words.iter().filter(|w| w.len() > 2).filter_map(|w| w.chars().next()).collect();
    let letters = |id: &str| normalize(id).chars().filter(|c| c.is_alphanumeric()).collect::<String>();
    ids.iter()
        .copied()
        .find(|id| words.iter().any(|w| *w == letters(id)))
        .or_else(|| ids.iter().copied().find(|id| letters(id).len() >= 2 && initials.ends_with(&letters(id))))
}

/// The user's courses, in local time, and the exams among them as deadlines
/// (one per domain and day: ADE lists an exam once per room or slot).
pub fn timetable(events: &[Event], selection: &Selection, domains: &[Domain], tz: &Tz) -> (Vec<Course>, Vec<Deadline>) {
    let mut courses = Vec::new();
    let mut exams: BTreeMap<(String, Date), Deadline> = BTreeMap::new();
    for e in events {
        let title = read_title(&e.summary);
        if !keeps(selection, &title) {
            continue;
        }
        let domain = match_domain(&e.summary, domains).map(|d| d.id.clone());
        let course = Course {
            uid: e.uid.clone(),
            start: tz.to_local(e.start),
            end: tz.to_local(e.end),
            kind: title.kind,
            domain: domain.clone(),
            title: e.summary.clone(),
        };
        if title.kind == CourseKind::Exam {
            let key = (domain.clone().unwrap_or_default(), course.start.date);
            let d = exams.entry(key).or_insert_with(|| Deadline {
                id: format!("cal:{}:{}", domain.clone().unwrap_or_default(), course.start.date),
                domain: domain.clone(),
                kind: DeadlineKind::Exam,
                at: course.start,
                title: e.summary.clone(),
                source: Source::Calendar,
                hours: None,
                spent_minutes: 0,
            });
            d.at = d.at.min(course.start);
        }
        courses.push(course);
    }
    courses.sort_by_key(|c| (c.start, c.end));
    (courses, exams.into_values().collect())
}

// ─── Downloads ───────────────────────────────────────────────────────────────

/// The feed's address over a sliding window (7 days back, 120 ahead): ADE
/// rewrites the dates of a saved link. `sqlMode=true` avoids its redirect.
pub fn window_url(url: &str, today: Date) -> String {
    let (base, query) = url.split_once('?').unwrap_or((url, ""));
    let mut params: Vec<(String, String)> = query
        .split('&')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let (k, v) = p.split_once('=').unwrap_or((p, ""));
            (k.to_string(), v.to_string())
        })
        .collect();
    let is_ade = params.iter().any(|(k, _)| k == "firstDate" || k == "resources");
    if !is_ade {
        return url.to_string();
    }
    let mut set = |k: &str, v: String| match params.iter_mut().find(|(pk, _)| pk == k) {
        Some(p) => p.1 = v,
        None => params.push((k.to_string(), v)),
    };
    set("firstDate", today.add(-7).to_string());
    set("lastDate", today.add(120).to_string());
    set("sqlMode", "true".into());
    let q: Vec<String> = params.into_iter().map(|(k, v)| format!("{k}={v}")).collect();
    format!("{base}?{}", q.join("&"))
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct Snapshot {
    /// When it was downloaded (instant).
    pub fetched: i64,
    pub events: Vec<Event>,
}

#[derive(Clone, PartialEq, Debug, Serialize)]
#[serde(tag = "change", rename_all = "lowercase")]
pub enum Change {
    Added { event: Event },
    Cancelled { event: Event },
    Moved { event: Event, from_start: i64, from_end: i64 },
}

impl Change {
    pub fn event(&self) -> &Event {
        match self {
            Change::Added { event } | Change::Cancelled { event } | Change::Moved { event, .. } => event,
        }
    }

    /// Every instant it touches: the new time, and the old one for a move.
    fn instants(&self) -> Vec<i64> {
        match self {
            Change::Moved { event, from_start, .. } => vec![event.start, *from_start],
            c => vec![c.event().start],
        }
    }
}

#[derive(Clone, PartialEq, Debug)]
pub enum Outcome {
    Updated { snapshot: Snapshot, changes: Vec<Change> },
    /// The previous snapshot stays.
    Kept { reason: String },
}

/// Compares a download with the last good snapshot, from `now` on (what
/// lies before has simply left the window). Matched by UID, then by title
/// and time, then by title and day (a move whose UID changed).
pub fn reconcile(old: Option<&Snapshot>, fetched: Result<Vec<Event>, String>, now: i64) -> Outcome {
    let events = match fetched {
        Err(e) => return Outcome::Kept { reason: e },
        Ok(e) => e,
    };
    let Some(old) = old else {
        return Outcome::Updated { snapshot: Snapshot { fetched: now, events }, changes: Vec::new() };
    };
    let old_ahead: Vec<&Event> = old.events.iter().filter(|e| e.end > now).collect();
    let new_ahead: Vec<&Event> = events.iter().filter(|e| e.end > now).collect();
    if new_ahead.is_empty() && !old_ahead.is_empty() {
        return Outcome::Kept { reason: "empty".into() };
    }

    let mut old_left: Vec<Option<&Event>> = old_ahead.iter().copied().map(Some).collect();
    let mut new_left: Vec<Option<&Event>> = new_ahead.iter().copied().map(Some).collect();
    let mut changes = Vec::new();
    let mut pair = |same: &dyn Fn(&Event, &Event) -> bool, changes: &mut Vec<Change>| {
        for n in new_left.iter_mut() {
            let Some(ne) = *n else { continue };
            if let Some(o) = old_left.iter_mut().find(|o| o.is_some_and(|oe| same(oe, ne))) {
                let oe = o.take().unwrap();
                if (oe.start, oe.end) != (ne.start, ne.end) {
                    changes.push(Change::Moved { event: ne.clone(), from_start: oe.start, from_end: oe.end });
                }
                *n = None;
            }
        }
    };
    pair(&|o, n| !o.uid.is_empty() && o.uid == n.uid, &mut changes);
    pair(&|o, n| o.summary == n.summary && o.start == n.start, &mut changes);
    pair(&|o, n| o.summary == n.summary && o.start.div_euclid(86_400) == n.start.div_euclid(86_400), &mut changes);
    changes.extend(old_left.into_iter().flatten().map(|e| Change::Cancelled { event: e.clone() }));
    changes.extend(new_left.into_iter().flatten().map(|e| Change::Added { event: e.clone() }));
    changes.sort_by_key(|c| c.event().start);
    Outcome::Updated { snapshot: Snapshot { fetched: now, events }, changes }
}

/// The changes worth a notification: the user's own courses, today or tomorrow.
pub fn worth_telling<'a>(changes: &'a [Change], selection: &Selection, tz: &Tz, today: Date) -> Vec<&'a Change> {
    changes
        .iter()
        .filter(|c| keeps(selection, &read_title(&c.event().summary)))
        .filter(|c| c.instants().iter().any(|&t| (0..=1).contains(&today.days_until(tz.to_local(t).date))))
        .collect()
}
