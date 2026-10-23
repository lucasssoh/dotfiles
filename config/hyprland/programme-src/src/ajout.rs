//! Quick add: one line, understood or not at all.
//!
//!   examen L&MC 18/12          exam / partiel
//!   cc OC 12/11 14h            contrôle / test
//!   rendu ARGOS 12/11 30h      due: a hand-in and its hours of work
//!   indispo sam 14h-18h        busy
//!   tâche relire TD3 A&C 45m   task
//!   candidature Entreprise F   apply
//!   libre 1h [école]           free: a gap nobody planned
//!
//! The sentence understood is shown before anything is saved. A line that is
//! not fully understood is never guessed at: the caller opens the form.

use crate::i18n;
use crate::journee::Place;
use crate::model::{Busy, Campaign, Chore, Deadline, DeadlineKind, Lang, Source};
use crate::time::{Date, Hm, Local};

#[derive(Clone, PartialEq, Debug)]
pub enum Action {
    Deadline(Deadline),
    Busy(Busy),
    Chore(Chore),
    Apply { campaign: String, company: String },
    Free { minutes: i32, place: Place },
}

#[derive(Clone, PartialEq, Debug)]
pub struct Understood {
    pub action: Action,
    pub sentence: String,
}

#[derive(Clone, PartialEq, Debug)]
pub enum Unclear {
    Empty,
    /// The first word is not a known kind.
    Kind(String),
    /// Something needed is missing: "date", "domain", "time", "duration", "name".
    Missing(&'static str),
    /// A word left over that means nothing here.
    Extra(String),
    NoCampaign,
}

pub struct Context<'a> {
    pub today: Date,
    pub lang: Lang,
    pub domains: &'a [String],
    /// (id, name, domain) of the projects.
    pub projects: &'a [(String, String, Option<String>)],
    pub campaigns: &'a [Campaign],
}

const DAYS: [[&str; 4]; 7] = [
    ["lun", "lundi", "mon", "monday"],
    ["mar", "mardi", "tue", "tuesday"],
    ["mer", "mercredi", "wed", "wednesday"],
    ["jeu", "jeudi", "thu", "thursday"],
    ["ven", "vendredi", "fri", "friday"],
    ["sam", "samedi", "sat", "saturday"],
    ["dim", "dimanche", "sun", "sunday"],
];

fn lower(s: &str) -> String {
    s.to_lowercase().trim_end_matches('.').to_string()
}

fn date(word: &str, today: Date) -> Option<Date> {
    let w = lower(word);
    match w.as_str() {
        "auj" | "aujourd'hui" | "today" => return Some(today),
        "demain" | "tomorrow" => return Some(today.add(1)),
        _ => {}
    }
    if let Some(wd) = DAYS.iter().position(|names| names.contains(&w.as_str())) {
        return Some(today.add((wd as i32 - today.weekday() as i32).rem_euclid(7)));
    }
    let parts: Vec<&str> = w.split('/').collect();
    let num = |s: &str| s.parse::<u32>().ok();
    let (d, m) = (num(parts.first()?)?, num(parts.get(1)?)?);
    let y = match parts.get(2) {
        Some(y) => {
            let y: i32 = y.parse().ok()?;
            if y < 100 {
                2000 + y
            } else {
                y
            }
        }
        None => {
            // The next one: a date already past this year means next year.
            let this = Date::parse(&format!("{}-{m:02}-{d:02}", today.year()))?;
            if this < today {
                today.year() + 1
            } else {
                today.year()
            }
        }
    };
    Date::parse(&format!("{y}-{m:02}-{d:02}"))
}

/// "14h", "14h30", "14:30".
fn time(word: &str) -> Option<Hm> {
    let w = lower(word);
    if !w.chars().next()?.is_ascii_digit() || !(w.contains('h') || w.contains(':')) {
        return None;
    }
    let (h, m) = w.split_once(['h', ':'])?;
    let h: i32 = h.parse().ok()?;
    let m: i32 = if m.is_empty() { 0 } else { m.parse().ok()? };
    (h < 24 && m < 60).then(|| Hm::new(h, m))
}

/// "45m", "45min", "1h", "1h30", "2 h" is not supported: one word.
fn duration(word: &str) -> Option<i32> {
    let w = lower(word);
    if let Some(m) = w.strip_suffix("min").or_else(|| w.strip_suffix('m')) {
        return m.parse().ok().filter(|m| *m > 0);
    }
    let (h, m) = w.split_once('h')?;
    let h: i32 = h.parse().ok()?;
    let m: i32 = if m.is_empty() { 0 } else { m.parse().ok()? };
    Some(h * 60 + m).filter(|t| *t > 0)
}

fn domain(word: &str, domains: &[String]) -> Option<String> {
    domains.iter().find(|d| d.eq_ignore_ascii_case(word)).cloned()
}

fn slug(s: &str) -> String {
    let mut out = String::new();
    for c in crate::ade::normalize(s).chars() {
        out.push(if c.is_alphanumeric() { c } else { '-' });
    }
    out
}

pub fn parse(line: &str, cx: &Context) -> Result<Understood, Unclear> {
    let mut u = parse_raw(line, cx)?;
    // A sentence ending on an abbreviation ("ven. 18 déc.") takes no second period.
    if u.sentence.ends_with("..") {
        u.sentence.pop();
    }
    Ok(u)
}

fn parse_raw(line: &str, cx: &Context) -> Result<Understood, Unclear> {
    let fr = cx.lang == Lang::Fr;
    let words: Vec<&str> = line.split_whitespace().collect();
    let Some(first) = words.first() else { return Err(Unclear::Empty) };
    let rest = &words[1..];
    let kind = lower(first);
    let when = |d: Date, t: Option<Hm>| match t {
        Some(t) => i18n::local(Local::new(d, t), cx.lang),
        None => i18n::date(d, cx.lang),
    };

    match kind.as_str() {
        "examen" | "exam" | "partiel" | "cc" | "contrôle" | "controle" | "test" => {
            let exam = matches!(kind.as_str(), "examen" | "exam" | "partiel");
            let (mut dom, mut day, mut at) = (None, None, None);
            for w in rest {
                if let (None, Some(d)) = (&dom, domain(w, cx.domains)) {
                    dom = Some(d);
                } else if let (None, Some(d)) = (day, date(w, cx.today)) {
                    day = Some(d);
                } else if let (None, Some(t)) = (at, time(w)) {
                    at = Some(t);
                } else {
                    return Err(Unclear::Extra(w.to_string()));
                }
            }
            let dom = dom.ok_or(Unclear::Missing("domain"))?;
            let day = day.ok_or(Unclear::Missing("date"))?;
            let title = match (exam, fr) {
                (true, true) => format!("Examen {dom}"),
                (true, false) => format!("{dom} exam"),
                (false, true) => format!("Contrôle {dom}"),
                (false, false) => format!("{dom} test"),
            };
            let sentence = format!("{title}, {}.", when(day, at));
            Ok(Understood {
                action: Action::Deadline(Deadline {
                    id: format!("{}:{}:{day}", if exam { "exam" } else { "cc" }, slug(&dom)),
                    domain: Some(dom),
                    kind: if exam { DeadlineKind::Exam } else { DeadlineKind::Cc },
                    at: Local::new(day, at.unwrap_or(Hm::new(8, 0))),
                    title,
                    source: Source::Manual,
                    hours: None,
                    spent_minutes: 0,
                }),
                sentence,
            })
        }
        "rendu" | "due" | "rendre" => {
            let mut name: Vec<&str> = Vec::new();
            let (mut day, mut times, mut hours) = (None, Vec::new(), None);
            for w in rest {
                if let (None, Some(d)) = (day, date(w, cx.today)) {
                    day = Some(d);
                } else if let Some(h) = lower(w).strip_suffix('h').and_then(|h| h.parse::<f32>().ok().or_else(|| h.replace(',', ".").parse().ok())) {
                    times.push((w, h));
                } else if time(w).is_some() {
                    times.push((w, -1.0));
                } else if day.is_none() && times.is_empty() {
                    name.push(w);
                } else {
                    return Err(Unclear::Extra(w.to_string()));
                }
            }
            // The last bare "Nh" is the work, one before it the time.
            let mut at = None;
            if let Some(&(_, h)) = times.last() {
                if h >= 0.0 {
                    hours = Some(h);
                    times.pop();
                }
            }
            if let Some((w, _)) = times.pop() {
                at = Some(time(w).ok_or(Unclear::Extra(w.to_string()))?);
            }
            if let Some((w, _)) = times.pop() {
                return Err(Unclear::Extra(w.to_string()));
            }
            let day = day.ok_or(Unclear::Missing("date"))?;
            if name.is_empty() {
                return Err(Unclear::Missing("name"));
            }
            let name = name.join(" ");
            let project = cx.projects.iter().find(|(id, n, _)| id.eq_ignore_ascii_case(&name) || n.eq_ignore_ascii_case(&name));
            let dom = project.and_then(|p| p.2.clone()).or_else(|| domain(&name, cx.domains));
            let work = hours.map(|h| {
                let h = format!("{h}").replace('.', if fr { "," } else { "." });
                if fr {
                    format!(", {h} h de travail")
                } else {
                    format!(", {h} h of work")
                }
            });
            let sentence = if fr {
                format!("Rendu {name}, {}{}.", when(day, at), work.unwrap_or_default())
            } else {
                format!("{name} due {}{}.", when(day, at), work.unwrap_or_default())
            };
            Ok(Understood {
                action: Action::Deadline(Deadline {
                    id: format!("due:{}:{day}", slug(&name)),
                    domain: dom,
                    kind: DeadlineKind::Due,
                    at: Local::new(day, at.unwrap_or(Hm::new(23, 59))),
                    title: name,
                    source: Source::Manual,
                    hours,
                    spent_minutes: 0,
                }),
                sentence,
            })
        }
        "indispo" | "busy" | "unavailable" | "occupé" | "occupe" => {
            let (mut day, mut range) = (None, None);
            for w in rest {
                if let (None, Some(d)) = (day, date(w, cx.today)) {
                    day = Some(d);
                } else if let (None, Some((a, b))) = (range, w.split_once('-')) {
                    let (a, b) = (time(a).ok_or(Unclear::Extra(w.to_string()))?, time(b).ok_or(Unclear::Extra(w.to_string()))?);
                    if b <= a {
                        return Err(Unclear::Extra(w.to_string()));
                    }
                    range = Some((a, b));
                } else {
                    return Err(Unclear::Extra(w.to_string()));
                }
            }
            let day = day.unwrap_or(cx.today);
            let (a, b) = range.ok_or(Unclear::Missing("time"))?;
            let sentence = if fr {
                format!("Indisponible {} de {a} à {b}.", i18n::date(day, cx.lang))
            } else {
                format!("Unavailable {} from {a} to {b}.", i18n::date(day, cx.lang))
            };
            Ok(Understood {
                action: Action::Busy(Busy { start: Local::new(day, a), end: Local::new(day, b), title: String::new() }),
                sentence,
            })
        }
        "tâche" | "tache" | "task" | "todo" => {
            let (mut title, mut dom, mut minutes, mut due) = (Vec::new(), None, None, None);
            for w in rest {
                if let (None, Some(d)) = (&dom, domain(w, cx.domains)) {
                    dom = Some(d);
                } else if let (None, Some(m)) = (minutes, duration(w)) {
                    minutes = Some(m);
                } else if let (None, Some(d)) = (due, date(w, cx.today).filter(|_| w.contains('/') || DAYS.iter().any(|n| n.contains(&lower(w).as_str())))) {
                    due = Some(d);
                } else {
                    title.push(*w);
                }
            }
            if title.is_empty() {
                return Err(Unclear::Missing("name"));
            }
            let minutes = minutes.ok_or(Unclear::Missing("duration"))?;
            let title = title.join(" ");
            let mut sentence = match (&dom, fr) {
                (Some(d), true) => format!("Tâche « {title} » en {d}, {} min", minutes),
                (None, true) => format!("Tâche « {title} », {} min", minutes),
                (Some(d), false) => format!("Task “{title}” in {d}, {} min", minutes),
                (None, false) => format!("Task “{title}”, {} min", minutes),
            };
            if let Some(d) = due {
                sentence += &if fr { format!(", avant le {}", i18n::date(d, cx.lang)) } else { format!(", before {}", i18n::date(d, cx.lang)) };
            }
            sentence.push('.');
            Ok(Understood {
                action: Action::Chore(Chore {
                    id: format!("{}-{}", slug(&title), cx.today),
                    title,
                    domain: dom,
                    file: None,
                    minutes,
                    due,
                    done: false,
                }),
                sentence,
            })
        }
        "candidature" | "apply" | "application" => {
            if rest.is_empty() {
                return Err(Unclear::Missing("name"));
            }
            let c = cx
                .campaigns
                .iter()
                .filter(|c| !c.closed && c.end >= cx.today)
                .min_by_key(|c| c.end)
                .ok_or(Unclear::NoCampaign)?;
            let company = rest.join(" ");
            let sentence = if fr {
                format!("Candidature {company} ajoutée à « {} », à envoyer.", c.name)
            } else {
                format!("Application {company} added to “{}”, to send.", c.name)
            };
            Ok(Understood { action: Action::Apply { campaign: c.id.clone(), company }, sentence })
        }
        "libre" | "free" => {
            let (mut minutes, mut place) = (None, Place::Home);
            for w in rest {
                match lower(w).as_str() {
                    "école" | "ecole" | "school" | "fac" => place = Place::School,
                    "maison" | "home" | "calme" => place = Place::Home,
                    _ => match (minutes, duration(w)) {
                        (None, Some(m)) => minutes = Some(m),
                        _ => return Err(Unclear::Extra(w.to_string())),
                    },
                }
            }
            let minutes = minutes.ok_or(Unclear::Missing("duration"))?;
            let sentence = if fr {
                format!("{minutes} min de libre maintenant : voici ce qui tient.")
            } else {
                format!("{minutes} free minutes now: here is what fits.")
            };
            Ok(Understood { action: Action::Free { minutes, place }, sentence })
        }
        _ => Err(Unclear::Kind(first.to_string())),
    }
}

/// Why a line was not understood, to show above the form.
pub fn explain(u: &Unclear, lang: Lang) -> String {
    let fr = lang == Lang::Fr;
    match u {
        Unclear::Empty => (if fr { "Ligne vide." } else { "Empty line." }).into(),
        Unclear::Kind(w) => {
            if fr {
                format!("« {w} » : examen, cc, rendu, indispo, tâche, candidature ou libre ?")
            } else {
                format!("“{w}”: exam, test, due, busy, task, apply or free?")
            }
        }
        Unclear::Missing(what) => {
            let w = match (*what, fr) {
                ("domain", true) => "la matière",
                ("date", true) => "la date",
                ("time", true) => "l'heure (14h-18h)",
                ("duration", true) => "la durée (45m, 1h30)",
                ("name", true) => "le nom",
                ("domain", false) => "the subject",
                ("date", false) => "the date",
                ("time", false) => "the time (14h-18h)",
                ("duration", false) => "the duration (45m, 1h30)",
                (_, false) => "the name",
                (_, true) => "le nom",
            };
            if fr {
                format!("Il manque {w}.")
            } else {
                format!("Missing {w}.")
            }
        }
        Unclear::Extra(w) => {
            if fr {
                format!("« {w} » n'est pas compris ici.")
            } else {
                format!("“{w}” is not understood here.")
            }
        }
        Unclear::NoCampaign => (if fr { "Aucune campagne en cours." } else { "No campaign under way." }).into(),
    }
}
