//! The library: the course folder as the bar's picker and the drawer's
//! "I have time" show it.
//!
//!   files     every file of the catalogue, by subject and chapter in work
//!             order, with its sections and where you are in it. A sheet's
//!             sections come from its Markdown; a PDF's from its outline,
//!             or for slides without one, from each page's first line (the
//!             slide's title), the first page giving the title. mutool
//!             reads one file at a time in the background (~20 ms each),
//!             kept in outlines.json while the file keeps its mtime.
//!   next      per subject, what the plan does next, with its reason; and
//!             across subjects, what would help most.
//!   start     "I have time" on any file: the plan's own task for it when
//!             it has one, else time found on the spot to read it. Opening
//!             a file in Liseuse never starts anything.

use std::collections::BTreeMap;
use std::process::Command;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::catalogue::{Inclusion, Item, ItemKind};
use crate::daemon::{which, Job, Service};
use crate::i18n;
use crate::journee::{Extra, Place};
use crate::model::{Lang, Level};
use crate::plan::{Part, Pin, Session, Work};
use crate::store::{self, Event};
use crate::time::Local;

/// A PDF as it was at `mtime`: its title and headings, (depth, title, page).
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Outline {
    pub mtime: i64,
    pub title: Option<String>,
    pub headings: Vec<(usize, String, u32)>,
}

/// What mutool printed: the outline, a record separator, the text with
/// pages separated by form feeds. The outline when there is one, else
/// each page's first line, repeats (a slide continued) left out.
pub fn read_pdf(out: &str, mtime: i64) -> Outline {
    let (outline, text) = out.split_once('\u{1e}').unwrap_or((out, ""));
    let worth = |l: &str| l.chars().filter(|c| c.is_alphabetic()).count() >= 4;
    let firsts: Vec<Vec<&str>> = text.split('\u{c}').map(|p| p.lines().map(str::trim).filter(|l| !l.is_empty()).take(2).collect()).collect();
    let title = firsts.first().and_then(|l| {
        let t = match l.as_slice() {
            [a, b] if b.starts_with('(') => format!("{a} {b}"),
            [a, ..] => a.to_string(),
            [] => return None,
        };
        (worth(&t) && t.chars().count() <= 90).then_some(t)
    });
    let mut headings: Vec<(usize, String, u32)> = crate::liseuse::parse_outline(outline).into_iter().map(|h| (h.depth, h.title, h.page)).collect();
    if headings.is_empty() {
        for (n, l) in firsts.iter().enumerate().skip(1) {
            let Some(t) = l.first().filter(|t| worth(t) && t.chars().count() <= 90) else { continue };
            if headings.last().is_none_or(|h| h.1 != *t) {
                headings.push((0, t.to_string(), n as u32 + 1));
            }
        }
    }
    Outline { mtime, title, headings }
}

pub type Outlines = BTreeMap<String, Outline>;

fn is_pdf(id: &str) -> bool {
    id.rsplit_once('.').is_some_and(|(_, e)| e.eq_ignore_ascii_case("pdf"))
}

fn mtime(path: &std::path::Path) -> i64 {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs() as i64)
}

/// "31_Algorithme_LS.md" → "31".
fn number(id: &str) -> String {
    let file = id.rsplit('/').next().unwrap_or(id);
    file.chars().take_while(|c| c.is_ascii_digit()).collect()
}

/// "Cours_03_Approximation" → "Cours 03 Approximation".
fn chapter_name(chapter: &str) -> String {
    chapter.rsplit('/').next().unwrap_or(chapter).replace('_', " ")
}

/// A chapter's name from its map: "Carte du cours — Dualité" → "Dualité".
fn map_title(items: &[Item], chapter: &str) -> Option<String> {
    let map = items.iter().find(|i| i.kind == ItemKind::Map && i.chapter.as_deref() == Some(chapter))?;
    let mut t = map.title.split_once(" — ").map_or(map.title.as_str(), |(_, t)| t).trim();
    // "(OC, cours oc02 à oc05)": the subject again, said by the drawer already.
    if let Some((head, paren)) = t.rsplit_once(" (") {
        if paren.starts_with(&map.domain) {
            t = head.trim();
        }
    }
    (!t.is_empty()).then(|| t.to_string())
}

fn kind_name(k: ItemKind) -> &'static str {
    match k {
        ItemKind::Map => "map",
        ItemKind::Sheet => "sheet",
        ItemKind::Synthesis => "synthesis",
        ItemKind::ExamPractice => "exam",
        ItemKind::TdExercise => "td",
        ItemKind::Pdf => "pdf",
        ItemKind::Notes => "notes",
    }
}

impl Service {
    pub(crate) fn outlines_load(&mut self) {
        self.outlines = store::read_json(&self.store.paths.data.join("outlines.json")).unwrap_or_default();
    }

    /// The next PDF whose outline is missing or stale, read in the
    /// background; one at a time, each result starting the next.
    pub(crate) fn outlines_refresh(&mut self) {
        if self.children.iter().any(|c| matches!(c.job, Job::Outline { .. })) || which("mutool").is_none() {
            return;
        }
        let root = &self.catalogue.root;
        let pdfs: Vec<&Item> = self.catalogue.items.iter().filter(|i| is_pdf(&i.id)).collect();
        let before = self.outlines.len();
        self.outlines.retain(|id, _| pdfs.iter().any(|i| &i.id == id));
        if self.outlines.len() != before {
            let _ = store::write_json(&self.store.paths.data.join("outlines.json"), &self.outlines);
        }
        let stale = pdfs.iter().map(|i| (i.id.clone(), mtime(&root.join(&i.id)))).find(|(id, m)| self.outlines.get(id).is_none_or(|o| o.mtime != *m));
        if let Some((item, mtime)) = stale {
            let path = self.catalogue.root.join(&item);
            let script = "mutool show \"$1\" outline 2>/dev/null; printf '\\036'; mutool draw -q -F txt -o - \"$1\" 2>/dev/null";
            self.spawn(Command::new("sh").arg("-c").arg(script).arg("sh").arg(path), Job::Outline { item, mtime });
        }
    }

    /// An outline read: kept even when empty (a PDF without one is not
    /// read again until it changes).
    pub(crate) fn outline_done(&mut self, item: String, mtime: i64, text: Option<String>) {
        let o = text.map(|t| read_pdf(&t, mtime)).unwrap_or(Outline { mtime, ..Default::default() });
        self.outlines.insert(item, o);
        let _ = store::write_json(&self.store.paths.data.join("outlines.json"), &self.outlines);
        self.outlines_refresh();
    }

    pub(crate) fn subject_name(&self, d: &str) -> String {
        if d == "RESEAUX" {
            self.t("Networks", "Réseaux")
        } else {
            d.to_string()
        }
    }

    /// The plan's parts still ahead, in its order, with their session.
    fn ahead(&self) -> Vec<(&Session, &Part)> {
        let now = self.now();
        let st = &self.store.state;
        self.plan
            .sessions
            .iter()
            .filter(|x| Local::new(x.date, x.end) > now && !st.outcomes.contains_key(&x.id))
            .flat_map(|x| x.parts.iter().map(move |p| (x, p)))
            .collect()
    }

    /// One suggestion, as the drawer shows it.
    fn pick_json(&self, p: &Part, title: String, why: String, hot: bool, minutes: i32) -> Value {
        json!({
            "task": p.task,
            "item": p.work.item(),
            "domain": p.domain,
            "title": title,
            "detail": format!("{minutes} min"),
            "why": why,
            "hot": hot,
            "minutes": minutes,
        })
    }

    /// What would help most, at most three: the nearest tutorial to
    /// prepare, the subject furthest behind its exam, the subjects said
    /// to be behind. `span`: the time there is.
    pub(crate) fn picks(&self, span: i32) -> Vec<Value> {
        let fr = self.fr();
        let lang = self.lang();
        let now = self.now();
        let ahead: Vec<&Part> = self.ahead().into_iter().map(|(_, p)| p).collect();
        let mut recs: Vec<Value> = Vec::new();
        let mut taken: Vec<String> = Vec::new();
        let mut push = |p: &Part, title: String, why: String, hot: bool, recs: &mut Vec<Value>| {
            if taken.contains(&p.task) || recs.len() >= 3 {
                return;
            }
            taken.push(p.task.clone());
            recs.push(self.pick_json(p, title, why, hot, p.minutes.min(span)));
        };
        // 1. The nearest tutorial to prepare, today's first.
        let mut prep: Vec<(&Part, Local)> = ahead
            .iter()
            .filter_map(|p| match &p.work {
                Work::Prepare { at, .. } if at.date.0 - now.date.0 <= 3 && *at > now => Some((*p, *at)),
                _ => None,
            })
            .collect();
        prep.sort_by_key(|(_, at)| *at);
        for (p, at) in prep.iter().take(2) {
            let d = self.subject_name(p.domain.as_deref().unwrap_or(""));
            let today = at.date == now.date;
            let when = if today { at.time.to_string() } else { i18n::date(at.date, lang) };
            let title = if fr { format!("{d} · préparer le TD {}{when}", if today { "de " } else { "du " }) } else { format!("{d} · prepare the tutorial {}{when}", if today { "at " } else { "on " }) };
            let weekday = i18n::date(at.date, lang).split(' ').next().unwrap_or("").trim_end_matches('.').to_string();
            let why = if today {
                self.t(&format!("tutorial at {}", at.time), &format!("TD à {}", at.time))
            } else {
                let full = |w: &str| match w { "lun" => "lundi", "mar" => "mardi", "mer" => "mercredi", "jeu" => "jeudi", "ven" => "vendredi", "sam" => "samedi", "dim" => "dimanche", x => x }.to_string();
                if fr { format!("TD {}", full(&weekday)) } else { format!("tutorial {weekday}") }
            };
            push(p, title, why, false, &mut recs);
        }
        // 2. The subject furthest behind its exam.
        if let Some(m) = self.plan.margins.iter().filter(|m| m.sessions < 0 && m.date >= now.date).min_by_key(|m| m.sessions) {
            if let Some(p) = ahead.iter().find(|p| p.domain == m.domain && !matches!(p.work, Work::Prepare { .. })) {
                let d = self.subject_name(p.domain.as_deref().unwrap_or(""));
                let why = if fr { format!("−{} séances", -m.sessions) } else { format!("−{} sessions", -m.sessions) };
                push(p, format!("{d} · {}", i18n::work(&p.work, lang)), why, true, &mut recs);
            }
        }
        // 3. A subject said to be behind.
        for dom in self.store.settings.domains.iter().filter(|d| d.level == Level::Behind && !d.archived) {
            if let Some(p) = ahead.iter().find(|p| p.domain.as_deref() == Some(&dom.id) && !matches!(p.work, Work::Prepare { .. })) {
                push(p, format!("{} · {}", self.subject_name(&dom.id), i18n::work(&p.work, lang)), self.t("behind", "en retard"), false, &mut recs);
            }
        }
        recs
    }

    /// A subject's next three tasks, in the plan's order, each with its reason.
    fn next_of(&self, domain: &str) -> Vec<Value> {
        let lang = self.lang();
        let mut out = Vec::new();
        let mut seen: Vec<&str> = Vec::new();
        for (s, p) in self.ahead() {
            if p.domain.as_deref() != Some(domain) || seen.contains(&p.task.as_str()) {
                continue;
            }
            seen.push(&p.task);
            let why = s.reasons.first().map(|r| i18n::reason(r, lang)).unwrap_or_else(|| self.t("Next in the plan.", "La suite du programme."));
            out.push(self.pick_json(p, i18n::work(&p.work, lang), why, false, p.minutes));
            if out.len() == 3 {
                break;
            }
        }
        out
    }

    fn default_minutes(&self, k: ItemKind) -> i32 {
        let pace = &self.store.settings.pace;
        match k {
            ItemKind::Map => pace.map,
            ItemKind::Pdf => pace.pdf,
            ItemKind::Notes => pace.notes,
            ItemKind::Sheet => pace.reading,
            ItemKind::Synthesis | ItemKind::TdExercise => pace.exercise * 2,
            ItemKind::ExamPractice => pace.exam_subject,
        }
        .clamp(10, 90)
    }

    fn item_json(&self, i: &Item, task: Option<&Part>, next: bool) -> Value {
        let lang = self.lang();
        let fr = lang == Lang::Fr;
        let st = &self.store.state;
        let p = st.progress.items.get(&i.id);
        let read_on = p.filter(|p| p.done || p.studied_on.is_some()).map(|p| p.studied_on.or(p.last_on));
        let (state, detail) = match (read_on, p.map_or(0, |p| p.read_upto)) {
            (Some(on), _) => ("read", on.map_or_else(|| self.t("read", "lue"), |d| if fr { format!("lue le {}", i18n::date(d, lang)) } else { format!("read {}", i18n::date(d, lang)) })),
            _ if next => ("next", self.t("next", "la suite")),
            (None, n) if n > 0 => ("progress", format!("§{n} / {}", i.sections.len().max(n as usize))),
            _ => ("", String::new()),
        };
        let sections: Vec<Value> = if is_pdf(&i.id) {
            let hs = self.outlines.get(&i.id).map(|o| o.headings.as_slice()).unwrap_or(&[]);
            let top = hs.iter().map(|h| h.0).min().unwrap_or(0);
            hs.iter().filter(|h| h.0 <= top + 1).map(|(d, t, pg)| json!({ "title": t, "page": pg, "sub": *d > top })).collect()
        } else {
            // Opened at a heading by the start of its text, before any
            // maths: the rendered PDF's outline spells formulas its own way.
            let key = |t: &str| t.split(['(', '\\']).next().unwrap_or(t).trim().to_string();
            i.headings.iter().map(|(l, t)| json!({ "title": t, "heading": key(t), "sub": *l > 2 })).collect()
        };
        json!({
            "id": i.id,
            "path": self.catalogue.root.join(&i.id),
            "title": self.outlines.get(&i.id).and_then(|o| o.title.clone()).unwrap_or_else(|| i.title.clone()),
            "file": i.id.rsplit('/').next().unwrap_or(&i.id),
            "num": number(&i.id),
            "kind": kind_name(i.kind),
            "planned": st.progress.files.get(&i.id) == Some(&Inclusion::Planned),
            "state": state,
            "detail": detail,
            "sections": sections,
            "exercises": i.exercises,
            "task": task.map(|p| p.task.clone()),
            "minutes": task.map_or_else(|| self.default_minutes(i.kind), |p| p.minutes),
            "starred": i.starred,
        })
    }

    /// Every course file by subject and chapter, with the plan's next
    /// steps: for the picker and the drawer.
    pub(crate) fn library(&self) -> Value {
        let ahead = self.ahead();
        let task_of = |id: &str| ahead.iter().find(|(_, p)| p.work.item() == Some(id)).map(|(_, p)| *p);
        let mut subjects = Vec::new();
        for d in self.store.settings.domains.iter().filter(|d| !d.archived) {
            let items = self.catalogue.ordered(d);
            if items.is_empty() {
                continue;
            }
            let next = self.next_of(&d.id);
            let first = next.first().and_then(|n| n["item"].as_str()).map(String::from);
            // Chapters in work order; teachers' files and loose notes last.
            let mut chapters: Vec<(String, String, Vec<Value>)> = Vec::new();
            for i in &items {
                let (key, name) = match (&i.chapter, i.kind) {
                    (Some(c), _) => (c.clone(), map_title(&items, c).unwrap_or_else(|| chapter_name(c))),
                    (None, ItemKind::Pdf) => ("~pdf".into(), self.t("Teacher's files", "Documents du prof")),
                    (None, _) => ("~other".into(), self.t("Other files", "Autres fichiers")),
                };
                let v = self.item_json(i, task_of(&i.id), first.as_deref() == Some(&i.id));
                match chapters.iter_mut().find(|c| c.0 == key) {
                    Some(c) => c.2.push(v),
                    None => chapters.push((key, name, vec![v])),
                }
            }
            chapters.sort_by_key(|c| c.0.starts_with('~'));
            let chapters: Vec<Value> = chapters
                .into_iter()
                .map(|(key, name, items)| {
                    let read = items.iter().filter(|v| v["state"] == "read").count();
                    let count = if key == "~pdf" {
                        format!("{} PDF", items.len())
                    } else if self.fr() {
                        format!("{read} lu{} sur {}", if read > 1 { "s" } else { "" }, items.len())
                    } else {
                        format!("{read} of {} read", items.len())
                    };
                    json!({ "id": format!("{}/{key}", d.id), "name": name, "count": count, "items": items })
                })
                .collect();
            subjects.push(json!({ "id": d.id, "label": self.subject_name(&d.id), "next": next, "chapters": chapters }));
        }
        let best = {
            let mut b = self.picks(90);
            for (_, p) in &ahead {
                if b.len() >= 3 {
                    break;
                }
                if p.domain.is_some() && !b.iter().any(|x| x["task"] == p.task) {
                    let d = self.subject_name(p.domain.as_deref().unwrap_or(""));
                    b.push(self.pick_json(p, format!("{d} · {}", i18n::work(&p.work, self.lang())), self.t("next in the plan", "la suite du programme"), false, p.minutes));
                }
            }
            b
        };
        json!({ "root": self.catalogue.root, "best": best, "subjects": subjects })
    }

    /// "I have time" on one file: the plan's task for it when it has one,
    /// in its order; else time found now to read it, the plan around it
    /// left as it was.
    pub(crate) fn free_item(&mut self, minutes: i32, place: Place, item: &str) -> Result<(String, Option<String>), String> {
        let planned = self.ahead().into_iter().find(|(_, p)| p.work.item() == Some(item)).map(|(_, p)| p.task.clone());
        if let Some(task) = planned {
            return self.free_task(minutes, place, &task);
        }
        let fr = self.fr();
        let now = self.now();
        let it = self.catalogue.get(item).cloned().ok_or_else(|| format!("{item}?"))?;
        let title = self.outlines.get(item).and_then(|o| o.title.clone()).unwrap_or_else(|| it.title.clone());
        let task = format!("free:{item}");
        let extra = Extra { date: now.date, start: now.time.ceil(5), minutes: minutes.max(10), place };
        let pin = Pin { task: task.clone(), date: now.date, start: extra.start, minutes: minutes.max(10), work: Some(Work::Read { item: item.into() }), domain: Some(it.domain.clone()) };
        self.store.record(Event::Extra { extra }, now).map_err(|e| e.to_string())?;
        self.store.record(Event::Pin { pin }, now).map_err(|e| e.to_string())?;
        self.replan();
        let s = self.plan.sessions.iter().find(|s| s.date == now.date && s.parts.iter().any(|p| p.task == task) && s.end > now.time);
        Ok(match s {
            Some(s) => {
                let text = if fr { format!("{title} ({} min), maintenant.", s.parts[0].minutes) } else { format!("{title} ({} min), now.", s.parts[0].minutes) };
                (text, Some(s.id.clone()))
            }
            None => (self.t("No room for it now.", "Pas de place pour ça maintenant."), None),
        })
    }
}
