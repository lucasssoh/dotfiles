//! Civil dates, times of day and the local time zone.
//!
//! The planner works on local dates and minutes of the day only: a session is
//! "Tuesday 20:30", never an instant. Instants (seconds since the epoch, UTC)
//! appear where the outside world speaks them, ADE's `…Z` times and the alarm
//! clock, and `Tz` converts at that border.

use std::fmt;
use std::path::Path;

use serde::de::{self, Deserializer};
use serde::{Deserialize, Serialize, Serializer};

/// A civil date, stored as days since 1970-01-01.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct Date(pub i32);

/// Minutes since midnight, 0..=1440.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Default)]
pub struct Hm(pub i32);

/// A local date and time of day.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct Local {
    pub date: Date,
    pub time: Hm,
}

// Howard Hinnant's days_from_civil / civil_from_days.
fn days_from_civil(y: i32, m: u32, d: u32) -> i32 {
    let (m, d) = (m as i32, d as i32);
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn civil_from_days(z: i32) -> (i32, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m as u32, d as u32)
}

fn days_in_month(y: i32, m: u32) -> u32 {
    let next = if m == 12 { days_from_civil(y + 1, 1, 1) } else { days_from_civil(y, m + 1, 1) };
    (next - days_from_civil(y, m, 1)) as u32
}

impl Date {
    pub fn ymd(y: i32, m: u32, d: u32) -> Date {
        Date(days_from_civil(y, m, d))
    }

    pub fn parts(self) -> (i32, u32, u32) {
        civil_from_days(self.0)
    }

    pub fn year(self) -> i32 {
        self.parts().0
    }

    /// 0 = Monday … 6 = Sunday.
    pub fn weekday(self) -> u32 {
        (self.0 + 3).rem_euclid(7) as u32
    }

    pub fn add(self, days: i32) -> Date {
        Date(self.0 + days)
    }

    pub fn days_until(self, other: Date) -> i32 {
        other.0 - self.0
    }

    /// The Monday of this date's week.
    pub fn monday(self) -> Date {
        self.add(-(self.weekday() as i32))
    }

    /// ISO 8601 week number.
    pub fn iso_week(self) -> u32 {
        let thursday = self.add(3 - self.weekday() as i32);
        let jan1 = Date::ymd(thursday.year(), 1, 1);
        (jan1.days_until(thursday) / 7 + 1) as u32
    }

    pub fn parse(s: &str) -> Option<Date> {
        let mut it = s.trim().splitn(3, '-');
        let y = it.next()?.parse().ok()?;
        let m: u32 = it.next()?.parse().ok()?;
        let d: u32 = it.next()?.parse().ok()?;
        if !(1..=12).contains(&m) || d == 0 || d > days_in_month(y, m) {
            return None;
        }
        Some(Date::ymd(y, m, d))
    }
}

impl fmt::Display for Date {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let (y, m, d) = self.parts();
        write!(f, "{y:04}-{m:02}-{d:02}")
    }
}

impl Hm {
    pub const fn new(h: i32, m: i32) -> Hm {
        Hm(h * 60 + m)
    }

    pub fn h(self) -> i32 {
        self.0 / 60
    }

    pub fn m(self) -> i32 {
        self.0 % 60
    }

    pub fn plus(self, minutes: i32) -> Hm {
        Hm(self.0 + minutes)
    }

    /// Rounded up to the next multiple of `step` minutes.
    pub fn ceil(self, step: i32) -> Hm {
        Hm((self.0 + step - 1).div_euclid(step) * step)
    }

    pub fn parse(s: &str) -> Option<Hm> {
        let s = s.trim();
        let (h, m) = s.split_once(':').or_else(|| s.split_once('h')).unwrap_or((s, "0"));
        let h: i32 = h.trim().parse().ok()?;
        let m: i32 = if m.trim().is_empty() { 0 } else { m.trim().parse().ok()? };
        if !(0..=24).contains(&h) || !(0..60).contains(&m) || h * 60 + m > 1440 {
            return None;
        }
        Some(Hm::new(h, m))
    }
}

impl fmt::Display for Hm {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{:02}:{:02}", self.h(), self.m())
    }
}

impl Local {
    pub fn new(date: Date, time: Hm) -> Local {
        Local { date, time }
    }

    /// Minutes since the epoch on the local wall clock (not an instant).
    pub fn minutes(self) -> i64 {
        self.date.0 as i64 * 1440 + self.time.0 as i64
    }

    pub fn from_minutes(m: i64) -> Local {
        Local { date: Date(m.div_euclid(1440) as i32), time: Hm(m.rem_euclid(1440) as i32) }
    }

    pub fn plus(self, minutes: i64) -> Local {
        Local::from_minutes(self.minutes() + minutes)
    }

    pub fn parse(s: &str) -> Option<Local> {
        let (d, t) = s.trim().split_once(['T', ' '])?;
        Some(Local { date: Date::parse(d)?, time: Hm::parse(t)? })
    }
}

impl fmt::Display for Local {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}T{}", self.date, self.time)
    }
}

macro_rules! serde_as_string {
    ($t:ty, $what:literal) => {
        impl Serialize for $t {
            fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
                s.collect_str(self)
            }
        }
        impl<'de> Deserialize<'de> for $t {
            fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
                let s = String::deserialize(d)?;
                <$t>::parse(&s).ok_or_else(|| de::Error::custom(concat!("not ", $what)))
            }
        }
    };
}
serde_as_string!(Date, "a date (YYYY-MM-DD)");
serde_as_string!(Hm, "a time (HH:MM)");
serde_as_string!(Local, "a date and time (YYYY-MM-DDTHH:MM)");

// ─── Time zone ───────────────────────────────────────────────────────────────

/// A POSIX TZ rule, `CET-1CEST,M3.5.0,M10.5.0/3`: the part of a TZif file
/// that covers every year after its last listed transition.
#[derive(Clone, Debug)]
struct Rule {
    std: i32,
    dst: Option<(i32, MRule, MRule)>,
}

/// `Mm.w.d/time`: weekday d (0 = Sunday) of week w (5 = last) of month m.
#[derive(Clone, Copy, Debug)]
struct MRule {
    month: u32,
    week: u32,
    wday: u32,
    secs: i32,
}

impl MRule {
    fn date(self, year: i32) -> Date {
        let first = Date::ymd(year, self.month, 1);
        // weekday() counts from Monday, POSIX from Sunday.
        let first_wday = (first.weekday() + 1) % 7;
        let mut day = 1 + (self.wday + 7 - first_wday) % 7 + (self.week - 1) * 7;
        let len = days_in_month(year, self.month);
        while day > len {
            day -= 7;
        }
        Date::ymd(year, self.month, day)
    }
}

#[derive(Clone, Debug)]
pub struct Tz {
    /// (instant, UTC offset in seconds from then on), sorted.
    transitions: Vec<(i64, i32)>,
    rule: Option<Rule>,
}

impl Tz {
    pub fn utc() -> Tz {
        Tz { transitions: Vec::new(), rule: None }
    }

    /// A zone from the system database, `Europe/Paris`.
    pub fn named(name: &str) -> Option<Tz> {
        let data = std::fs::read(Path::new("/usr/share/zoneinfo").join(name)).ok()?;
        Tz::from_tzif(&data)
    }

    /// The session's zone: `$TZ`, else /etc/localtime, else UTC.
    pub fn local() -> Tz {
        if let Some(tz) = std::env::var("TZ").ok().and_then(|n| Tz::named(n.trim_start_matches(':'))) {
            return tz;
        }
        std::fs::read("/etc/localtime").ok().and_then(|d| Tz::from_tzif(&d)).unwrap_or_else(Tz::utc)
    }

    pub fn from_tzif(data: &[u8]) -> Option<Tz> {
        let be32 = |b: &[u8]| i32::from_be_bytes([b[0], b[1], b[2], b[3]]);
        let header = |b: &[u8]| -> Option<[usize; 6]> {
            if b.len() < 44 || &b[..4] != b"TZif" {
                return None;
            }
            let mut c = [0usize; 6];
            for (i, v) in c.iter_mut().enumerate() {
                *v = be32(&b[20 + i * 4..]) as usize;
            }
            Some(c)
        };
        let [isut, isstd, leap, timecnt, typecnt, charcnt] = header(data)?;
        let version = data[4];
        let v1_len = timecnt * 5 + typecnt * 6 + charcnt + leap * 8 + isstd + isut;
        let (body, width, [isut, isstd, leap, timecnt, typecnt, charcnt]) = if version >= b'2' {
            let second = data.get(44 + v1_len..)?;
            (second.get(44..)?, 8, header(second)?)
        } else {
            (data.get(44..)?, 4, [isut, isstd, leap, timecnt, typecnt, charcnt])
        };
        let times = body.get(..timecnt * width)?;
        let idx = body.get(timecnt * width..timecnt * (width + 1))?;
        let types = body.get(timecnt * (width + 1)..timecnt * (width + 1) + typecnt * 6)?;
        let offset_of = |i: usize| be32(&types[i * 6..]);
        let mut transitions = Vec::with_capacity(timecnt);
        for i in 0..timecnt {
            let t = if width == 8 {
                i64::from_be_bytes(times[i * 8..i * 8 + 8].try_into().ok()?)
            } else {
                be32(&times[i * 4..]) as i64
            };
            transitions.push((t, offset_of(*idx.get(i)? as usize)));
        }
        let mut rule = None;
        if width == 8 {
            let end = timecnt * (width + 1) + typecnt * 6 + charcnt + leap * 12 + isstd + isut;
            if let Some(footer) = body.get(end..) {
                let footer = String::from_utf8_lossy(footer);
                rule = parse_posix(footer.trim_matches('\n'));
            }
        }
        if transitions.is_empty() && rule.is_none() && typecnt > 0 {
            rule = Some(Rule { std: offset_of(0), dst: None });
        }
        Some(Tz { transitions, rule })
    }

    /// UTC offset in seconds at an instant.
    pub fn offset(&self, t: i64) -> i32 {
        if let Some(&(last, _)) = self.transitions.last() {
            if t < last || self.rule.is_none() {
                let i = self.transitions.partition_point(|&(at, _)| at <= t);
                return self.transitions[i.saturating_sub(1)].1;
            }
        }
        match &self.rule {
            None => 0,
            Some(Rule { std, dst: None }) => *std,
            Some(Rule { std, dst: Some((dst, start, end)) }) => {
                let year = Local::from_minutes((t + *std as i64).div_euclid(60)).date.year();
                let at = |r: MRule, off: i32| r.date(year).0 as i64 * 86_400 + r.secs as i64 - off as i64;
                let (s, e) = (at(*start, *std), at(*end, *dst));
                let in_dst = if s < e { t >= s && t < e } else { t >= s || t < e };
                if in_dst {
                    *dst
                } else {
                    *std
                }
            }
        }
    }

    pub fn to_local(&self, t: i64) -> Local {
        Local::from_minutes((t + self.offset(t) as i64).div_euclid(60))
    }

    /// The instant of a wall-clock time. Inside a DST change (the skipped
    /// spring hour, the repeated autumn one) it is off by at most that hour,
    /// which no session ever sits in.
    pub fn to_utc(&self, l: Local) -> i64 {
        let wall = l.minutes() * 60;
        wall - self.offset(wall - self.offset(wall) as i64) as i64
    }
}

fn parse_posix(s: &str) -> Option<Rule> {
    let mut p = Posix { s: s.as_bytes(), i: 0 };
    p.name()?;
    let std = -p.offset()?;
    if p.i >= p.s.len() {
        return Some(Rule { std, dst: None });
    }
    p.name()?;
    let dst = if p.peek().is_some_and(|c| c != b',') { -p.offset()? } else { std + 3600 };
    p.eat(b',')?;
    let start = p.mrule()?;
    p.eat(b',')?;
    let end = p.mrule()?;
    Some(Rule { std, dst: Some((dst, start, end)) })
}

struct Posix<'a> {
    s: &'a [u8],
    i: usize,
}

impl Posix<'_> {
    fn peek(&self) -> Option<u8> {
        self.s.get(self.i).copied()
    }

    fn eat(&mut self, c: u8) -> Option<()> {
        (self.peek()? == c).then(|| self.i += 1)
    }

    fn name(&mut self) -> Option<()> {
        if self.peek()? == b'<' {
            while self.peek()? != b'>' {
                self.i += 1;
            }
            self.i += 1;
        } else {
            let from = self.i;
            while self.peek().is_some_and(|c| c.is_ascii_alphabetic()) {
                self.i += 1;
            }
            if self.i - from < 3 {
                return None;
            }
        }
        Some(())
    }

    fn num(&mut self) -> Option<i32> {
        let from = self.i;
        while self.peek().is_some_and(|c| c.is_ascii_digit()) {
            self.i += 1;
        }
        std::str::from_utf8(&self.s[from..self.i]).ok()?.parse().ok()
    }

    /// `[+-]hh[:mm[:ss]]`, in seconds.
    fn offset(&mut self) -> Option<i32> {
        let sign = match self.peek()? {
            b'-' => {
                self.i += 1;
                -1
            }
            b'+' => {
                self.i += 1;
                1
            }
            _ => 1,
        };
        let mut secs = self.num()? * 3600;
        if self.eat(b':').is_some() {
            secs += self.num()? * 60;
            if self.eat(b':').is_some() {
                secs += self.num()?;
            }
        }
        Some(sign * secs)
    }

    fn mrule(&mut self) -> Option<MRule> {
        self.eat(b'M')?;
        let month = self.num()? as u32;
        self.eat(b'.')?;
        let week = self.num()? as u32;
        self.eat(b'.')?;
        let wday = self.num()? as u32;
        let secs = if self.eat(b'/').is_some() { self.offset()? } else { 7200 };
        let valid = (1..=12).contains(&month) && (1..=5).contains(&week) && wday <= 6;
        valid.then_some(MRule { month, week, wday, secs })
    }
}
