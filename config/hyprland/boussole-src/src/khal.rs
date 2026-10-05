//! khal, both ways.
//!
//! Out: the planned sessions in the `etude` calendar and the filtered
//! courses in `cours`, one .ics per event (a vdir holds one UID per file)
//! with a stable UID. A file is only rewritten when its text changes, and
//! files Boussole did not write are never touched.
//!
//! In: the personal calendars count as busy. They are read through
//! `khal list`, which expands recurrences; without `--once`, which would
//! show a weekly event only the first time.

use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use crate::i18n;
use crate::model::{Busy, Course, Lang};
use crate::plan::Session;
use crate::time::{Date, Hm, Local, Tz};

pub const STUDY: &str = "etude";
pub const COURSES: &str = "cours";
const PREFIX: &str = "boussole-";

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace(';', "\\;").replace(',', "\\,").replace('\n', "\\n")
}

fn stamp(tz: &Tz, l: Local) -> String {
    let t = tz.to_utc(l);
    let d = Date(t.div_euclid(86_400) as i32);
    let s = t.rem_euclid(86_400);
    let (y, m, day) = d.parts();
    format!("{y:04}{m:02}{day:02}T{:02}{:02}{:02}Z", s / 3600, s % 3600 / 60, s % 60)
}

/// Lines folded at 75 octets, as RFC 5545 wants.
fn fold(line: &str) -> String {
    let mut out = String::new();
    let mut width = 0;
    for c in line.chars() {
        let w = c.len_utf8();
        if width + w > 75 {
            out.push_str("\r\n ");
            width = 1;
        }
        out.push(c);
        width += w;
    }
    out.push_str("\r\n");
    out
}

fn vevent(tz: &Tz, uid: &str, start: Local, end: Local, summary: &str, location: &str, description: &str) -> String {
    let mut s = String::from("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//coucou-shell//Boussole//EN\r\nBEGIN:VEVENT\r\n");
    s += &fold(&format!("UID:{uid}"));
    // Stable, so an unchanged event gives an unchanged file.
    s += &format!("DTSTAMP:{}\r\n", stamp(tz, Local::new(start.date, Hm(0))));
    s += &format!("DTSTART:{}\r\nDTEND:{}\r\n", stamp(tz, start), stamp(tz, end));
    s += &fold(&format!("SUMMARY:{}", escape(summary)));
    if !location.is_empty() {
        s += &fold(&format!("LOCATION:{}", escape(location)));
    }
    if !description.is_empty() {
        s += &fold(&format!("DESCRIPTION:{}", escape(description)));
    }
    s += "END:VEVENT\r\nEND:VCALENDAR\r\n";
    s
}

fn file_name(uid: &str) -> String {
    let safe: String = uid.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '_' }).collect();
    format!("{PREFIX}{safe}.ics")
}

/// The `etude` calendar's files: name → text.
pub fn study_files(sessions: &[Session], tz: &Tz, lang: Lang) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for s in sessions.iter().filter(|s| s.counted && !s.parts.is_empty()) {
        let uid = format!("{PREFIX}{}@coucou-shell", s.id);
        let main = &s.parts[0];
        let title = match &main.domain {
            Some(d) => format!("{d} · {}", i18n::work(&main.work, lang)),
            None => i18n::work(&main.work, lang),
        };
        let more = s.parts.len() - 1;
        let summary = if more > 0 { format!("{title} (+{more})") } else { title };
        let description: Vec<String> = s
            .parts
            .iter()
            .map(|p| format!("{} ({} min)", i18n::work(&p.work, lang), p.minutes))
            .chain(s.reasons.iter().map(|r| format!("· {}", i18n::reason(r, lang))))
            .collect();
        let text = vevent(tz, &uid, Local::new(s.date, s.start), Local::new(s.date, s.end), &summary, "", &description.join("\n"));
        out.insert(file_name(&s.id), text);
    }
    out
}

/// The `cours` calendar's files.
pub fn course_files(courses: &[Course], tz: &Tz) -> BTreeMap<String, String> {
    courses
        .iter()
        .map(|c| {
            let uid = format!("{PREFIX}{}", c.uid);
            (file_name(&c.uid), vevent(tz, &uid, c.start, c.end, &c.title, "", ""))
        })
        .collect()
}

/// Makes a folder hold exactly `files` among Boussole's own. True when
/// something changed.
pub fn sync(dir: &Path, files: &BTreeMap<String, String>) -> io::Result<bool> {
    std::fs::create_dir_all(dir)?;
    let mut changed = false;
    for entry in std::fs::read_dir(dir)?.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with(PREFIX) && name.ends_with(".ics") && !files.contains_key(&name) {
            std::fs::remove_file(entry.path())?;
            changed = true;
        }
    }
    for (name, text) in files {
        let path = dir.join(name);
        if std::fs::read_to_string(&path).ok().as_deref() == Some(text.as_str()) {
            continue;
        }
        let tmp = dir.join(format!(".{name}.tmp"));
        std::fs::write(&tmp, text)?;
        std::fs::rename(tmp, path)?;
        changed = true;
    }
    Ok(changed)
}

/// The calendars declared in khal's config, and its date and datetime formats.
pub struct Config {
    pub calendars: Vec<String>,
    pub dateformat: String,
    pub datetimeformat: String,
}

pub fn read_config(text: &str) -> Config {
    let mut c = Config { calendars: Vec::new(), dateformat: "%d/%m/%Y".into(), datetimeformat: "%d/%m/%Y %H:%M".into() };
    for line in text.lines().map(str::trim) {
        if let Some(name) = line.strip_prefix("[[").and_then(|l| l.strip_suffix("]]")) {
            c.calendars.push(name.trim().to_string());
        } else if let Some((k, v)) = line.split_once('=') {
            match k.trim() {
                "dateformat" => c.dateformat = v.trim().to_string(),
                "datetimeformat" => c.datetimeformat = v.trim().to_string(),
                _ => {}
            }
        }
    }
    c
}

/// `%d/%m/%Y` and the like, with %d %m %Y %H %M only.
pub fn format(fmt: &str, l: Local) -> String {
    let (y, m, d) = l.date.parts();
    fmt.replace("%d", &format!("{d:02}"))
        .replace("%m", &format!("{m:02}"))
        .replace("%Y", &format!("{y:04}"))
        .replace("%H", &format!("{:02}", l.time.h()))
        .replace("%M", &format!("{:02}", l.time.m()))
}

/// The reverse of `format`, for the same five fields.
pub fn parse_with(fmt: &str, s: &str) -> Option<Local> {
    let (mut y, mut mo, mut d, mut h, mut mi) = (None, None, None, 0, 0);
    let (f, s) = (fmt.as_bytes(), s.as_bytes());
    let (mut i, mut j) = (0, 0);
    while i < f.len() {
        if f[i] == b'%' && i + 1 < f.len() {
            let width = if f[i + 1] == b'Y' { 4 } else { 2 };
            let n: i32 = std::str::from_utf8(s.get(j..j + width)?).ok()?.parse().ok()?;
            match f[i + 1] {
                b'Y' => y = Some(n),
                b'm' => mo = Some(n as u32),
                b'd' => d = Some(n as u32),
                b'H' => h = n,
                b'M' => mi = n,
                _ => return None,
            }
            i += 2;
            j += width;
        } else {
            if s.get(j) != Some(&f[i]) {
                return None;
            }
            i += 1;
            j += 1;
        }
    }
    let date = Date::parse(&format!("{:04}-{:02}-{:02}", y?, mo?, d?))?;
    Some(Local::new(date, Hm::new(h, mi)))
}

/// The arguments of `khal list` for the personal calendars.
pub fn list_args(cfg: &Config, from: Date, days: i32) -> Vec<String> {
    let mut a: Vec<String> = ["list", "--json", "uid", "--json", "title", "--json", "start", "--json", "end", "--json", "all-day"]
        .map(String::from)
        .to_vec();
    for own in [STUDY, COURSES] {
        if cfg.calendars.iter().any(|c| c == own) {
            a.push("-d".into());
            a.push(own.into());
        }
    }
    a.push(format(&cfg.dateformat, Local::new(from, Hm(0))));
    a.push(format!("{days}d"));
    a
}

/// `khal list --json` output (one JSON array per day) into busy time.
pub fn parse_list(out: &str, cfg: &Config) -> Vec<Busy> {
    let mut seen = std::collections::BTreeSet::new();
    let mut busy = Vec::new();
    for line in out.lines().map(str::trim).filter(|l| l.starts_with('[')) {
        let Ok(serde_json::Value::Array(events)) = serde_json::from_str(line) else { continue };
        for e in events {
            let get = |k: &str| e.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();
            let all_day = get("all-day") == "True";
            let (start, end) = if all_day {
                let s = parse_with(&cfg.dateformat, &get("start"));
                // khal prints an all-day event's last day, inclusive.
                let e = parse_with(&cfg.dateformat, &get("end")).map(|l| Local::new(l.date.add(1), Hm(0)));
                (s, e)
            } else {
                (parse_with(&cfg.datetimeformat, &get("start")), parse_with(&cfg.datetimeformat, &get("end")))
            };
            let (Some(start), Some(end)) = (start, end) else { continue };
            if seen.insert((get("uid"), start)) {
                busy.push(Busy { start, end, title: get("title") });
            }
        }
    }
    busy.sort_by_key(|b| b.start);
    busy
}
