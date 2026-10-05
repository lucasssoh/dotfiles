//! Following a session, without judging the window in front.
//!
//! The user often reads with a browser in front, so the focused window
//! means nothing. What counts:
//!   - Liseuse visible on screen (not necessarily focused): pages it shows
//!     get reading time;
//!   - no keyboard or mouse for 5 minutes (reported by the bar): the time
//!     is not counted;
//!   - a game running: the session waits, its time is taken out;
//!   - media playing (reported by the bar): counted apart, and asked about
//!     once at "Close" ("a video played 14 min: for the course?").
//! Closing Liseuse ends nothing: work goes on on paper. After 18 minutes
//! without the sheet, one question; 15 minutes after the planned end, the
//! closing window opens. Only "Close" ends a session.
//!
//! A page shown under 30 seconds was skimmed, not read: skimming the whole
//! document, which the user does to size the work, is never counted as
//! reading but gives an estimate from the measured pace. No title, no
//! history of windows: only durations per category and pages per file.
//!
//! Pure: every call gets the time.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::liseuse::Map;
use crate::plan::{Session, Work};
use crate::store::PartReport;

/// Seconds on a page before it counts as read.
pub const READ_SECS: i64 = 30;
/// Without the sheet for this long, one question.
pub const AWAY_SECS: i64 = 18 * 60;
/// The closing window opens this long after the planned end.
pub const CLOSING_SECS: i64 = 15 * 60;
/// A skim: this many seconds at most to go through most pages.
const SKIM_WINDOW: i64 = 180;

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct Open {
    pub item: String,
    /// 1-based.
    pub page: u32,
    pub pages: u32,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct Flags {
    pub visible: bool,
    pub idle: bool,
    pub game: bool,
    pub media: bool,
    pub paused: bool,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Skim {
    pub item: String,
    pub at: i64,
    pub pages: u32,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Tracker {
    /// None while reading outside a session.
    pub session: Option<String>,
    pub since: i64,
    pub last: i64,
    pub effective: i64,
    pub idle_secs: i64,
    pub game_secs: i64,
    pub paused_secs: i64,
    pub media_secs: i64,
    pub flags: Flags,
    pub doc: Option<Open>,
    /// Seconds Liseuse showed each page, per file.
    pub dwell: BTreeMap<String, BTreeMap<u32, i64>>,
    /// Recent page changes (time, file, page), for skims.
    pub visits: Vec<(i64, String, u32)>,
    /// Without a sheet on screen since then.
    pub away_since: Option<i64>,
    pub asked: bool,
    pub skims: Vec<Skim>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Prompt {
    /// "Still on the exercises?"
    StillWorking,
    /// The closing window is open.
    Closing,
}

impl Tracker {
    pub fn start(session: Option<String>, now: i64) -> Tracker {
        Tracker { session, since: now, last: now, away_since: Some(now), ..Tracker::default() }
    }

    fn reading(&self) -> bool {
        self.doc.is_some() && self.flags.visible && !self.flags.idle && !self.flags.game && !self.flags.paused
    }

    /// Accounts the time since the last call under the current state.
    pub fn advance(&mut self, now: i64) {
        let dt = (now - self.last).max(0);
        self.last = now;
        if dt == 0 {
            return;
        }
        if self.flags.game {
            self.game_secs += dt;
        } else if self.flags.paused {
            self.paused_secs += dt;
        } else if self.flags.idle {
            self.idle_secs += dt;
        } else {
            self.effective += dt;
            if self.flags.media {
                self.media_secs += dt;
            }
        }
        if self.reading() {
            let d = self.doc.as_ref().unwrap();
            *self.dwell.entry(d.item.clone()).or_default().entry(d.page).or_default() += dt;
        }
    }

    fn away(&mut self, now: i64) {
        let on_screen = self.doc.is_some() && self.flags.visible;
        match (on_screen, self.away_since) {
            (true, _) => {
                self.away_since = None;
                self.asked = false;
            }
            (false, None) => self.away_since = Some(now),
            _ => {}
        }
    }

    /// Liseuse shows `page` of `item` (a new file, or a page turned).
    pub fn page(&mut self, now: i64, item: &str, page: u32, pages: u32) {
        self.advance(now);
        self.doc = Some(Open { item: item.into(), page, pages });
        self.visits.push((now, item.into(), page));
        self.visits.retain(|(t, _, _)| now - t <= SKIM_WINDOW);
        self.away(now);
        self.detect_skim(now, item, pages);
    }

    pub fn closed(&mut self, now: i64) {
        self.advance(now);
        self.doc = None;
        self.away(now);
    }

    pub fn set(&mut self, now: i64, f: impl FnOnce(&mut Flags)) {
        self.advance(now);
        f(&mut self.flags);
        self.away(now);
    }

    fn detect_skim(&mut self, now: i64, item: &str, pages: u32) {
        if pages < 4 || self.skims.iter().any(|s| s.item == item && now - s.at < 600) {
            return;
        }
        let seen: BTreeSet<u32> = self.visits.iter().filter(|(_, i, _)| i == item).map(|(_, _, p)| *p).collect();
        let dwell = self.dwell.get(item);
        let quick = seen.iter().filter(|p| dwell.and_then(|d| d.get(p)).copied().unwrap_or(0) < READ_SECS).count();
        if quick as u32 * 10 >= pages * 6 {
            self.skims.push(Skim { item: item.into(), at: now, pages });
        }
    }

    /// Pages read and skimmed in a file.
    pub fn pages(&self, item: &str) -> (BTreeSet<u32>, BTreeSet<u32>) {
        let mut read = BTreeSet::new();
        let mut skimmed = BTreeSet::new();
        for (p, s) in self.dwell.get(item).into_iter().flatten() {
            if *s >= READ_SECS {
                read.insert(*p);
            } else if *s > 0 {
                skimmed.insert(*p);
            }
        }
        (read, skimmed)
    }

    /// The question due now, if any. `end`: the planned end (instant).
    pub fn prompt(&self, now: i64, end: i64) -> Option<Prompt> {
        self.session.as_ref()?;
        if now >= end + CLOSING_SECS {
            return Some(Prompt::Closing);
        }
        let away = self.away_since.is_some_and(|t| now - t >= AWAY_SECS);
        (away && !self.asked && !self.flags.paused && !self.flags.game).then_some(Prompt::StillWorking)
    }

    /// When the next question can fall.
    pub fn next_prompt(&self, now: i64, end: i64) -> Option<i64> {
        self.session.as_ref()?;
        let mut t = vec![end + CLOSING_SECS];
        if let (Some(a), false) = (self.away_since, self.asked) {
            t.push(a + AWAY_SECS);
        }
        t.into_iter().filter(|t| *t > now).min()
    }

    /// "No" to "still working?": the time since the sheet went away is not counted.
    pub fn not_working(&mut self, now: i64) {
        self.advance(now);
        if let Some(a) = self.away_since {
            let gone = (now - a).max(0).min(self.effective);
            self.effective -= gone;
            self.idle_secs += gone;
        }
        self.asked = true;
        self.flags.idle = true;
    }
}

/// What "Close" starts from, to be confirmed by the user.
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct Draft {
    pub session: String,
    pub effective_minutes: i32,
    /// Media played during the session: asked about.
    pub media_minutes: i32,
    pub game_minutes: i32,
    pub parts: Vec<PartReport>,
    /// Per file: pages read and skimmed, and what was read before the
    /// session (free reading), to confirm.
    pub files: Vec<FileReading>,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct FileReading {
    pub item: String,
    pub read: Vec<u32>,
    pub skimmed: Vec<u32>,
    pub read_upto: Option<u32>,
    /// Read before, outside a session: (date, § reached).
    pub before: Option<(crate::time::Date, u32)>,
}

/// The pre-filled close. `maps`: the section map of each file seen;
/// `free`: § reached in earlier free reading, per file.
pub fn draft(
    tr: &Tracker,
    session: &Session,
    maps: &BTreeMap<String, Map>,
    free: &BTreeMap<String, (crate::time::Date, u32)>,
    objective_upto: impl Fn(&str) -> Option<u32>,
) -> Draft {
    let minutes = |s: i64| ((s + 30) / 60) as i32;
    let effective = minutes(tr.effective);
    let planned: i32 = session.parts.iter().map(|p| p.minutes).sum::<i32>().max(1);
    let mut files: Vec<FileReading> = Vec::new();
    for item in tr.dwell.keys() {
        let (read, skimmed) = tr.pages(item);
        // Only the reading sections count: the exercises are declared.
        let upto = maps.get(item).map(|m| {
            let r = m.read_upto(&read);
            objective_upto(item).map_or(r, |cap| r.min(cap))
        });
        files.push(FileReading {
            item: item.clone(),
            read: read.into_iter().collect(),
            skimmed: skimmed.into_iter().collect(),
            read_upto: upto.filter(|u| *u > 0),
            before: free.get(item).copied(),
        });
    }
    let parts = session
        .parts
        .iter()
        .map(|p| {
            let share = (effective as i64 * p.minutes as i64 / planned as i64) as i32;
            let mut r = PartReport { task: p.task.clone(), minutes: share, planned: p.minutes, done: false, ..PartReport::default() };
            match &p.work {
                Work::Study { item, .. } => {
                    let seen = files.iter().find(|f| f.item == *item);
                    r.read_upto = seen.and_then(|f| f.read_upto).or(free.get(item).map(|b| b.1));
                }
                Work::Read { item } => r.done = files.iter().any(|f| f.item == *item && !f.read.is_empty()),
                _ => r.done = share * 2 >= p.minutes,
            }
            r
        })
        .collect();
    Draft {
        session: session.id.clone(),
        effective_minutes: effective,
        media_minutes: minutes(tr.media_secs),
        game_minutes: minutes(tr.game_secs),
        parts,
        files,
    }
}

/// Minutes per page for a skimmed file, at the measured pace.
pub fn estimate(pages: u32, minutes_per_page: f32) -> i32 {
    ((pages as f32 * minutes_per_page) / 5.0).round() as i32 * 5
}
