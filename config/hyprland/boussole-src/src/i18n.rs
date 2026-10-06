//! Sentences the service builds (notifications, changes, reasons), in
//! English or French. Fixed labels live in the QML; each text exists in one
//! place only. File and domain names are shown as they are.

use crate::model::Lang;
use crate::plan::{Change, Reason, Work};
use crate::time::{Date, Hm, Local};

const DAYS_EN: [&str; 7] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const DAYS_FR: [&str; 7] = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."];
const MONTHS_EN: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MONTHS_FR: [&str; 12] =
    ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];

/// "Mon Oct 5" / "lun. 5 oct."
pub fn date(d: Date, lang: Lang) -> String {
    let (_, m, day) = d.parts();
    let wd = d.weekday() as usize;
    match lang {
        Lang::En => format!("{} {} {day}", DAYS_EN[wd], MONTHS_EN[m as usize - 1]),
        Lang::Fr => format!("{} {day} {}", DAYS_FR[wd], MONTHS_FR[m as usize - 1]),
    }
}

pub fn time(t: Hm) -> String {
    t.to_string()
}

pub fn local(l: Local, lang: Lang) -> String {
    format!("{} {}", date(l.date, lang), time(l.time))
}

/// "A&C/…/32_Entiers_de_Church.md" → "32 Entiers de Church".
pub fn item_name(id: &str) -> String {
    let file = id.rsplit('/').next().unwrap_or(id);
    let stem = file.rsplit_once('.').map_or(file, |(s, _)| s);
    stem.replace('_', " ")
}

fn range(prefix: &str, r: (u32, u32)) -> String {
    if r.0 == r.1 {
        format!("{prefix}{}", r.0)
    } else {
        format!("{prefix}{}-{}", r.0, r.1)
    }
}

/// What a part of a session is, in a line: "32 Entiers de Church · §1-2, ex. 1-3".
pub fn work(w: &Work, lang: Lang) -> String {
    let fr = lang == Lang::Fr;
    match w {
        Work::Study { item, sections, exercises } => {
            let mut what = Vec::new();
            if let Some(s) = sections {
                what.push(range("§", *s));
            }
            if let Some(e) = exercises {
                what.push(range("ex. ", *e));
            }
            format!("{} · {}", item_name(item), what.join(", "))
        }
        Work::Read { item } => item_name(item),
        Work::Review { item, n } => {
            if fr {
                format!("{} · révision {n}", item_name(item))
            } else {
                format!("{} · review {n}", item_name(item))
            }
        }
        Work::Redo { item, exercises } => {
            let list: Vec<String> = exercises.iter().map(u32::to_string).collect();
            if fr {
                format!("{} · refaire ex. {} sans corrigé", item_name(item), list.join(", "))
            } else {
                format!("{} · redo ex. {} without the solution", item_name(item), list.join(", "))
            }
        }
        Work::Question { item } => {
            if fr {
                format!("{} · poser la question", item_name(item))
            } else {
                format!("{} · ask the question", item_name(item))
            }
        }
        Work::ExamSubject { item, n } => {
            if fr {
                format!("{} · sujet {n} en temps limité", item_name(item))
            } else {
                format!("{} · subject {n}, timed", item_name(item))
            }
        }
        Work::Prepare { at, .. } => {
            // The subject is shown beside it: the day and hour are enough.
            if fr {
                format!("préparer le TD du {}", local(*at, lang))
            } else {
                format!("prepare the tutorial, {}", local(*at, lang))
            }
        }
        Work::Project { project, step } => format!("{project} · {step}"),
        Work::Campaign { campaign } => {
            if fr {
                format!("{campaign} · candidatures")
            } else {
                format!("{campaign} · applications")
            }
        }
        Work::Interview { company, .. } => {
            if fr {
                format!("préparer l'entretien {company}")
            } else {
                format!("prepare the {company} interview")
            }
        }
        Work::Chore { title, .. } => title.clone(),
        Work::Recall { item } => {
            let what = item.as_deref().map(item_name).unwrap_or_default();
            if fr {
                format!("10 min de rappel actif {what}")
            } else {
                format!("10 min of active recall {what}")
            }
        }
    }
}

fn sessions(n: i32, lang: Lang) -> String {
    match (lang, n.abs()) {
        (Lang::Fr, 1) => format!("{n} séance"),
        (Lang::Fr, _) => format!("{n} séances"),
        (Lang::En, 1) => format!("{n} session"),
        (Lang::En, _) => format!("{n} sessions"),
    }
}

/// A sentence ending on an abbreviation ("oct.") takes no second period.
fn tidy(mut s: String) -> String {
    if s.ends_with("..") {
        s.pop();
    }
    s
}

/// One line of "Why this session?".
pub fn reason(r: &Reason, lang: Lang) -> String {
    tidy(reason_raw(r, lang))
}

fn reason_raw(r: &Reason, lang: Lang) -> String {
    let fr = lang == Lang::Fr;
    match r {
        Reason::Deadline { title, days, margin, .. } => {
            let m = margin.map(|m| sessions(m, lang));
            match (fr, m) {
                (true, Some(m)) => format!("{title} dans {days} jours, marge de {m}."),
                (true, None) => format!("{title} dans {days} jours."),
                (false, Some(m)) => format!("{title} in {days} days, {m} to spare."),
                (false, None) => format!("{title} in {days} days."),
            }
        }
        Reason::Starred { note } => match (fr, note) {
            (true, Some(n)) => format!("Fiche ★ : « {n} », d'après la carte du cours."),
            (true, None) => "Fiche ★.".into(),
            (false, Some(n)) => format!("Starred: “{n}”, from the course map."),
            (false, None) => "Starred.".into(),
        },
        Reason::Continues => (if fr { "Commencée la dernière fois : elle passe en tête." } else { "Started last time, so first in line." }).into(),
        Reason::Rotation { domain, last } => match (fr, last) {
            (true, Some(d)) => format!("Pas de {domain} depuis {} : les matières alternent.", date(*d, lang)),
            (true, None) => format!("Au tour de {domain} : les matières alternent."),
            (false, Some(d)) => format!("No {domain} since {}: subjects take turns.", date(*d, lang)),
            (false, None) => format!("{domain}'s turn: subjects take turns."),
        },
        Reason::Behind { domain } => {
            if fr {
                format!("{domain} est en retard sur le temps qui reste.")
            } else {
                format!("{domain} is behind for the time left.")
            }
        }
        Reason::CampaignTime => (if fr { "Le temps de la campagne, aujourd'hui." } else { "Today's time for the campaign." }).into(),
        Reason::SaidBehind { domain } => {
            if fr {
                format!("Tu t'es noté en retard en {domain} : elle passe devant.")
            } else {
                format!("You said you are behind in {domain}: it goes first.")
            }
        }
        Reason::CourseOrder => (if fr { "Suivante dans l'ordre du cours." } else { "Next in course order." }).into(),
        Reason::ReviewDue { n, studied } => {
            if fr {
                format!("Révision {n}, la fiche a été étudiée le {}.", date(*studied, lang))
            } else {
                format!("Review {n}, the sheet was studied on {}.", date(*studied, lang))
            }
        }
        Reason::RedoDue { since } => {
            if fr {
                format!("Exercices ratés le {}, à refaire sans corrigé.", date(*since, lang))
            } else {
                format!("Exercises failed on {}, to redo without the solution.", date(*since, lang))
            }
        }
        Reason::Prepare { at } => {
            if fr {
                format!("Le TD a lieu {}.", local(*at, lang))
            } else {
                format!("The tutorial is on {}.", local(*at, lang))
            }
        }
        Reason::ProjectDue { name, due } => {
            if fr {
                format!("{name} à rendre le {}, fini 3 jours avant.", date(*due, lang))
            } else {
                format!("{name} due {}, finished 3 days ahead.", date(*due, lang))
            }
        }
        Reason::Pinned => (if fr { "Épinglée : elle ne bouge plus." } else { "Pinned: it stays here." }).into(),
        Reason::Restart { missed } => {
            if fr {
                format!("{missed} séances manquées de suite : 10 minutes suffisent pour repartir.")
            } else {
                format!("{missed} sessions missed in a row: 10 minutes are enough to start again.")
            }
        }
        Reason::HeadStart => (if fr { "Facultatif : de l'avance si tu le fais." } else { "Optional: a head start if you do it." }).into(),
    }
}

/// "What moved", in detail for the next two weeks and counted beyond.
pub fn changes(list: &[Change], today: Date, lang: Lang) -> String {
    let soon = |d: Date| today.days_until(d) <= 14;
    let near = |c: &&Change| match c {
        Change::Moved { from, to, .. } => soon(*from.min(to)),
        Change::Unplaced { was, .. } => soon(*was),
        Change::Margin { .. } | Change::AtRisk { .. } => true,
    };
    let mut lines: Vec<String> = list.iter().filter(near).map(|c| change(c, lang)).collect();
    let far = list.len() - lines.len();
    if far > 0 {
        lines.push(match (lang, far) {
            (Lang::Fr, 1) => "Et 1 décalage plus loin.".into(),
            (Lang::Fr, n) => format!("Et {n} décalages plus loin."),
            (Lang::En, 1) => "And 1 change further on.".into(),
            (Lang::En, n) => format!("And {n} changes further on."),
        });
    }
    lines.join("\n")
}

/// One line of "what moved".
pub fn change(c: &Change, lang: Lang) -> String {
    tidy(change_raw(c, lang))
}

fn change_raw(c: &Change, lang: Lang) -> String {
    let fr = lang == Lang::Fr;
    let with_domain = |w: &Work, d: &Option<String>| match d {
        Some(d) => format!("{d} {}", work(w, lang)),
        None => work(w, lang),
    };
    match c {
        Change::Moved { work: w, domain, from, to, .. } => {
            let what = with_domain(w, domain);
            match (fr, to > from) {
                (true, true) => format!("{what} : décalée de {} à {}.", date(*from, lang), date(*to, lang)),
                (true, false) => format!("{what} : avancée de {} à {}.", date(*from, lang), date(*to, lang)),
                (false, true) => format!("{what}: moved from {} to {}.", date(*from, lang), date(*to, lang)),
                (false, false) => format!("{what}: brought forward from {} to {}.", date(*from, lang), date(*to, lang)),
            }
        }
        Change::Unplaced { work: w, domain, .. } => {
            if fr {
                format!("{} : au-delà de l'horizon du plan.", with_domain(w, domain))
            } else {
                format!("{}: past the plan's horizon.", with_domain(w, domain))
            }
        }
        Change::Margin { title, from, to, .. } => {
            if fr {
                format!("Marge avant {title} : {} → {}.", from, sessions(*to, lang))
            } else {
                format!("Margin before {title}: {} → {}.", from, sessions(*to, lang))
            }
        }
        Change::AtRisk { work: w, due, missing_minutes, .. } => {
            let h = format!("{}h{:02}", missing_minutes / 60, missing_minutes % 60);
            if fr {
                format!("{} : il manque {h} avant le {}.", work(w, lang), date(*due, lang))
            } else {
                format!("{}: {h} missing before {}.", work(w, lang), date(*due, lang))
            }
        }
    }
}
