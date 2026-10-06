//! Alerts in the bar's central island, as alerting as Veille.
//!
//! The start of a session, its reminder, "still on the exercises?" and
//! "close it?" are not notifications: the bar opens them in its central
//! island with a chime, and they stay until answered. The service only
//! says what to show; the bar decides when it can (never over a fullscreen
//! game, nothing in zen mode, where the bar is paused) and sends back the
//! button pressed. One alert at a time: a newer one replaces it. Without a
//! bar listening, the alert falls back to a notification with the same
//! buttons.

use serde_json::{json, Value};

use crate::daemon::Service;
use crate::i18n;
use crate::journee::{self, SlotKind};
use crate::model::Lang;
use crate::plan::{Session, Work};
use crate::store::Outcome;
use crate::time::{Hm, Local};

impl Service {
    fn t(&self, en: &str, fr: &str) -> String {
        if self.lang() == Lang::Fr { fr } else { en }.to_string()
    }

    /// "A&C · 32 Analyse 2 − 1/m ★": the session's main work, in a line.
    pub(crate) fn headline(&self, s: &Session) -> String {
        let Some(p) = s.parts.first() else { return String::new() };
        let what = match &p.work {
            Work::Study { item, .. } | Work::Read { item } | Work::Review { item, .. } | Work::Redo { item, .. } | Work::ExamSubject { item, .. } => {
                let star = self.catalogue.get(item).is_some_and(|i| i.starred);
                format!("{}{}", i18n::item_name(item), if star { " ★" } else { "" })
            }
            w => i18n::work(w, self.lang()),
        };
        match &p.domain {
            Some(d) => format!("{d} · {what}"),
            None => what,
        }
    }

    /// A few words for the bar: the subject, else what it is about
    /// ("Alternance", a project's name, a company).
    pub(crate) fn short_label(&self, s: &Session) -> String {
        let Some(p) = s.parts.first() else { return String::new() };
        if let Some(d) = &p.domain {
            return d.clone();
        }
        let st = &self.store.state;
        match &p.work {
            Work::Campaign { campaign } | Work::Interview { campaign, .. } => {
                st.campaigns.iter().find(|c| &c.id == campaign).map_or_else(|| campaign.clone(), |c| c.name.clone())
            }
            Work::Project { project, .. } => st.projects.iter().find(|x| &x.id == project).map_or_else(|| project.clone(), |x| x.name.clone()),
            w => i18n::work(w, self.lang()).chars().take(24).collect(),
        }
    }

    fn actions(&self, s: &Session, from: Hm, start: bool) -> Vec<Value> {
        let r = &self.store.settings.rhythm;
        let slot = journee::Slot {
            date: s.date,
            start: s.start,
            end: s.end,
            kind: s.kind,
            counted: true,
            place: s.place,
            shortened: s.shortened,
            limit: if s.kind == SlotKind::Block { r.block_range.1 } else { r.latest_end },
        };
        let mut a = vec![json!({ "id": "start", "label": self.t("Start", "Commencer"), "primary": true })];
        for (t, _) in journee::later_options(&slot, from, s.end.0 - s.start.0, r.min_session).into_iter().take(if start { 2 } else { 1 }) {
            a.push(json!({ "id": format!("later:{t}"), "label": self.t(&format!("At {t}"), &format!("À {t}")) }));
        }
        a.push(json!({ "id": "skip", "label": self.t("Not tonight", "Pas ce soir") }));
        a
    }

    /// The start of a session (`reminder`: 15 minutes on, nothing begun).
    pub(crate) fn session_alert(&mut self, s: &Session, at: Local, reminder: bool) {
        let lang = self.lang();
        let (title, body) = if reminder {
            (
                self.t("The sheet is waiting", "La fiche t'attend"),
                self.t(
                    "Open it and read only the header table. That is all that is asked for now.",
                    "Ouvre-la et lis seulement le tableau d'en-tête. C'est tout ce qu'on te demande pour l'instant.",
                ),
            )
        } else {
            let when = match s.kind {
                SlotKind::Evening => self.t("Tonight: ", "Ce soir : "),
                _ => String::new(),
            };
            // The title already names the first task: its objective, then
            // the others with their subject.
            let lines: Vec<String> = s
                .parts
                .iter()
                .enumerate()
                .filter_map(|(i, p)| {
                    let w = i18n::work(&p.work, lang);
                    if i == 0 {
                        return w.split_once(" · ").map(|(_, objective)| objective.to_string());
                    }
                    Some(match &p.domain {
                        Some(d) => format!("{d} · {w}"),
                        None => w,
                    })
                })
                .collect();
            (format!("{when}{}", self.headline(s)), lines.join(" · "))
        };
        // Where Liseuse will open.
        let hint = s.parts.iter().find_map(|p| match &p.work {
            Work::Study { sections: Some((a, _)), .. } => {
                Some(self.t(&format!("Opens in Liseuse, at §{a}."), &format!("S'ouvre dans Liseuse, au début du §{a}.")))
            }
            _ => None,
        });
        let alert = json!({
            "key": format!("{}:{}@{}", if reminder { "remind" } else { "start" }, s.id, at.time),
            "kind": if reminder { "reminder" } else { "start" },
            "session": s.id,
            "time": at.time.max(s.start).to_string(),
            "until": s.end.to_string(),
            "minutes": s.end.0 - at.time.max(s.start).0,
            "title": title,
            "body": body,
            "hint": hint,
            "actions": self.actions(s, self.now().time, !reminder),
            "chime": true,
        });
        self.raise(alert);
    }

    /// "Still on the exercises?" and "close it?".
    pub(crate) fn prompt_alert(&mut self, session: &str, closing: bool) {
        let now = self.now();
        let (title, body, actions) = if closing {
            let body = self.draft(session).map_or(String::new(), |d| {
                let upto = d.parts.iter().filter_map(|p| p.read_upto).max();
                let mins = format!("{} h {:02}", d.effective_minutes / 60, d.effective_minutes % 60);
                match (upto, self.lang()) {
                    (Some(u), Lang::Fr) => format!("Ce que Liseuse a vu est prérempli : §1-{u} lus, {mins} effective. Tu confirmes les exercices."),
                    (None, Lang::Fr) => format!("Prérempli : {mins} effective. Tu confirmes ce qui a été fait."),
                    (Some(u), Lang::En) => format!("Pre-filled from what Liseuse saw: §1-{u} read, {mins} effective. You confirm the exercises."),
                    (None, Lang::En) => format!("Pre-filled: {mins} effective. You confirm what was done."),
                }
            });
            (
                self.t("Session over: close it?", "Séance finie : la clore ?"),
                body,
                vec![
                    json!({ "id": "close", "label": self.t("Close", "Clore"), "primary": true }),
                    json!({ "id": "dismiss", "label": self.t("Later", "Plus tard") }),
                ],
            )
        } else if self.focus_active() && self.session_has_file(session) {
            // Focus mode: the sheet was closed in the study dimension.
            (
                self.t("The sheet is closed", "La fiche est fermée"),
                self.t(
                    "The session goes on. Open it again, or go on on paper: that time counts.",
                    "La séance continue. Rouvre-la, ou continue sur papier : ce temps compte.",
                ),
                vec![
                    json!({ "id": "reopen", "label": self.t("Open the sheet again", "Rouvrir la fiche"), "primary": true }),
                    json!({ "id": "still:yes", "label": self.t("On paper", "Sur papier") }),
                    json!({ "id": "pause", "label": self.t("Pause", "Pause") }),
                    json!({ "id": "still:no", "label": self.t("I stopped", "J'ai arrêté") }),
                ],
            )
        } else {
            (
                self.t("Still on the exercises?", "Toujours sur les exercices ?"),
                self.t(
                    "Nothing stops for all that. If you stopped, that time does not count.",
                    "Rien n'est arrêté pour autant. Si tu as décroché, ce temps-là ne compte pas.",
                ),
                vec![
                    json!({ "id": "still:yes", "label": self.t("Yes, on paper", "Oui, sur papier"), "primary": true }),
                    json!({ "id": "still:no", "label": self.t("No, I stopped", "Non, j'ai arrêté") }),
                ],
            )
        };
        let alert = json!({
            "key": format!("{}:{session}@{}", if closing { "closing" } else { "still" }, now.time),
            "kind": if closing { "closing" } else { "still" },
            "session": session,
            "time": now.time.to_string(),
            "title": title,
            "body": body,
            "actions": actions,
            "chime": false,
        });
        self.raise(alert);
    }

    /// To the bar, or as a notification when no bar listens.
    pub(crate) fn raise(&mut self, alert: Value) {
        if self.clients.iter().any(|c| c.bar) {
            self.alert = Some(alert);
            self.push_status();
            return;
        }
        let actions: Vec<(String, String)> = alert["actions"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|a| (a["id"].as_str().unwrap_or("").to_string(), a["label"].as_str().unwrap_or("").to_string()))
            .filter(|(id, _)| id != "dismiss")
            .collect();
        let title = alert["title"].as_str().unwrap_or("").to_string();
        let body = [alert["body"].as_str(), alert["hint"].as_str()].into_iter().flatten().collect::<Vec<_>>().join("\n");
        let session = alert["session"].as_str().map(String::from);
        self.notify(&title, &body, &actions, session);
    }

    /// A button of the island's alert. "dismiss": closed without an
    /// answer; the reminder will come back. Returns what was done, which
    /// the island shows a moment before closing.
    pub(crate) fn answer(&mut self, key: &str, action: &str) -> Result<String, String> {
        let Some(alert) = self.alert.take() else { return Err("no alert".into()) };
        if alert["key"] != key {
            self.alert = Some(alert);
            return Err("an older alert".into());
        }
        let session = alert["session"].as_str().unwrap_or("").to_string();
        if action == "dismiss" {
            self.push_status();
            return Ok(String::new());
        }
        if let Some(a) = action.strip_prefix("detour:") {
            return Ok(self.detour_answer(&session, a));
        }
        self.on_action(&session, action);
        let fr = self.lang() == Lang::Fr;
        let text = if action == "start" {
            self.t("Off you go.", "C'est parti.")
        } else if let Some(t) = action.strip_prefix("later:") {
            self.t(&format!("Noted, at {t}."), &format!("C'est noté, à {t}."))
        } else if action == "skip" {
            // What moved, the nearest first.
            let moved = i18n::changes(&self.plan.changes, self.now().date, self.lang());
            match moved.lines().next() {
                Some(l) if fr => format!("Pas ce soir. {l}"),
                Some(l) => format!("Not tonight. {l}"),
                None => self.t("Not tonight. The session is placed again.", "Pas ce soir. La séance est replacée."),
            }
        } else if action == "still:yes" {
            self.t("Noted, on paper: the time counts.", "Noté, sur papier : le temps compte.")
        } else if action == "reopen" {
            self.t("The sheet opens again.", "La fiche se rouvre.")
        } else if action == "pause" {
            self.t("Session paused.", "Séance en pause.")
        } else if action == "still:no" {
            self.t("Noted, that time is taken out.", "Noté, ce temps est retiré.")
        } else if action == "close" {
            self.t("Session closed.", "Séance close.")
        } else {
            String::new()
        };
        Ok(text)
    }

    /// The island's alert stops being worth showing once its session is
    /// over, answered, or no longer planned.
    pub(crate) fn expire_alert(&mut self) {
        let Some(alert) = &self.alert else { return };
        let id = alert["session"].as_str().unwrap_or("");
        let now = self.now();
        let kind = alert["kind"].as_str().unwrap_or("");
        let session = self.plan.sessions.iter().find(|s| s.id == id);
        let outcome = self.store.state.outcomes.get(id);
        let gone = match kind {
            "start" | "reminder" => {
                session.is_none_or(|s| Local::new(s.date, s.end) <= now)
                    || matches!(outcome, Some(Outcome::Started { .. } | Outcome::Closed { .. } | Outcome::Skipped))
            }
            // Back on the sheet (or on paper): nothing left to ask.
            "still" => {
                !matches!(outcome, Some(Outcome::Started { .. }))
                    || self.suivi.tracker.as_ref().is_none_or(|t| t.away_since.is_none() || t.paper)
            }
            "elsewhere" => {
                !matches!(outcome, Some(Outcome::Started { .. })) || self.suivi.tracker.as_ref().is_none_or(|t| t.elsewhere.is_none())
            }
            _ => !matches!(outcome, Some(Outcome::Started { .. } | Outcome::Paused { .. })),
        };
        if gone {
            self.alert = None;
        }
    }

    /// Today, for the drawer's first page: courses, sessions and offers in
    /// order, each with what it is and how it went.
    pub(crate) fn today(&self) -> Value {
        self.day_rows(self.now().date)
    }

    /// Several days from `from`, each with its name and its rows.
    pub(crate) fn week(&self, from: crate::time::Date, days: i32) -> Value {
        let lang = self.lang();
        Value::Array(
            (0..days)
                .map(|i| from.add(i))
                .map(|d| json!({ "date": d.to_string(), "label": i18n::date(d, lang), "rows": self.day_rows(d) }))
                .collect(),
        )
    }

    fn day_rows(&self, date: crate::time::Date) -> Value {
        let lang = self.lang();
        let now = self.now();
        let (courses, _) = self.timetable();
        let mut rows: Vec<(Hm, Value)> = Vec::new();
        for c in courses.iter().filter(|c| c.start.date == date) {
            rows.push((
                c.start.time,
                json!({ "type": "course", "start": c.start.time.to_string(), "end": c.end.time.to_string(), "title": c.title, "past": c.end <= now }),
            ));
        }
        for s in self.plan.sessions.iter().chain(&self.plan.offers).filter(|s| s.date == date && !s.parts.is_empty()) {
            let state = match self.store.state.outcomes.get(&s.id) {
                Some(Outcome::Closed { .. }) => "closed",
                Some(Outcome::Skipped) => "skipped",
                Some(Outcome::Missed) => "missed",
                Some(Outcome::Started { .. }) => "started",
                Some(Outcome::Paused { .. }) => "paused",
                Some(Outcome::Postponed { .. }) => "postponed",
                None => "planned",
            };
            let parts: Vec<Value> = s
                .parts
                .iter()
                .map(|p| json!({ "domain": p.domain, "what": i18n::work(&p.work, lang), "minutes": p.minutes }))
                .collect();
            let why: Vec<String> = s.reasons.iter().map(|r| i18n::reason(r, lang)).collect();
            rows.push((
                s.start,
                json!({
                    "type": if s.counted { "session" } else { "offer" },
                    "id": s.id,
                    "kind": s.kind,
                    "start": s.start.to_string(),
                    "end": s.end.to_string(),
                    "title": self.headline(s),
                    "parts": parts,
                    "why": why,
                    "state": state,
                    "shortened": s.shortened,
                    "past": Local::new(s.date, s.end) <= now,
                }),
            ));
        }
        // Said "not tonight": no longer in the plan, still shown, to be
        // brought back.
        for (id, (day, _, planned)) in &self.store.state.skipped {
            if *day != date || self.plan.sessions.iter().any(|s| &s.id == id) {
                continue;
            }
            let Some(s) = planned else { continue };
            let parts: Vec<Value> = s
                .parts
                .iter()
                .map(|p| json!({ "domain": p.domain, "what": i18n::work(&p.work, lang), "minutes": p.minutes }))
                .collect();
            rows.push((
                s.start,
                json!({
                    "type": "session",
                    "id": id,
                    "kind": s.kind,
                    "start": s.start.to_string(),
                    "end": s.end.to_string(),
                    "title": self.headline(s),
                    "parts": parts,
                    "why": [],
                    "state": "skipped",
                    "shortened": false,
                    "past": Local::new(s.date, s.end) <= now,
                }),
            ));
        }
        rows.sort_by_key(|r| r.0);
        Value::Array(rows.into_iter().map(|r| r.1).collect())
    }

    /// The close form of a session: what Liseuse saw, in a sentence, and per
    /// task what can be declared, pre-filled. Sheets get their sections and
    /// exercises; anything else is done or not.
    pub(crate) fn closing(&mut self, id: &str) -> Option<Value> {
        let s = self.session_any(id)?;
        let d = self.draft(id)?;
        let lang = self.lang();
        let fr = lang == Lang::Fr;
        let span = |r: &[u32]| match (r.first(), r.last()) {
            (Some(a), Some(b)) if a == b => format!("p. {a}"),
            (Some(a), Some(b)) => format!("p. {a}-{b}"),
            _ => String::new(),
        };
        let seen: Vec<String> = d
            .files
            .iter()
            .map(|f| {
                let name = i18n::item_name(&f.item);
                let read = match (f.read_upto, f.read.is_empty()) {
                    (Some(u), _) if fr => format!("§1-{u} lus ({})", span(&f.read)),
                    (Some(u), _) => format!("§1-{u} read ({})", span(&f.read)),
                    (None, false) if fr => format!("{} pages lues", f.read.len()),
                    (None, false) => format!("{} pages read", f.read.len()),
                    _ => String::new(),
                };
                let skim = match (f.skimmed.len(), fr) {
                    (0, _) => String::new(),
                    (n, true) => format!("{n} pages survolées"),
                    (n, false) => format!("{n} pages skimmed"),
                };
                let what: Vec<String> = [read, skim].into_iter().filter(|x| !x.is_empty()).collect();
                format!("{name}{}{}", if fr { " : " } else { ": " }, what.join(", "))
            })
            .collect();
        let parts: Vec<Value> = s
            .parts
            .iter()
            .zip(&d.parts)
            .map(|(p, r)| {
                let label = match &p.domain {
                    Some(dm) => format!("{dm} · {}", i18n::work(&p.work, lang)),
                    None => i18n::work(&p.work, lang),
                };
                match &p.work {
                    Work::Study { item, sections, exercises } => {
                        let it = self.catalogue.get(item);
                        let secs: Vec<Value> = it
                            .map(|i| i.sections.iter().map(|x| json!({ "num": x.num, "title": x.title })).collect())
                            .unwrap_or_default();
                        let seen_upto = d.files.iter().find(|f| f.item == *item).and_then(|f| f.read_upto);
                        let done_before = self.store.state.progress.items.get(item).map_or(0, |pg| pg.read_upto);
                        json!({
                            "kind": "study",
                            "task": p.task,
                            "label": label,
                            "planned": p.minutes,
                            "sections": secs,
                            "planned_sections": sections,
                            "read_upto": r.read_upto.unwrap_or(done_before).max(done_before),
                            "seen_upto": seen_upto,
                            "exercises": it.map_or(0, |i| i.exercises),
                            "planned_exercises": exercises,
                            "already": self.store.state.progress.items.get(item).map(|pg| &pg.exercises),
                        })
                    }
                    _ => json!({ "kind": "other", "task": p.task, "label": label, "planned": p.minutes, "done": r.done }),
                }
            })
            .collect();
        let minutes = |m: i32| format!("{} h {:02}", m / 60, m % 60);
        Some(json!({
            "session": s.id,
            "title": self.headline(&s),
            "start": s.start.to_string(),
            "end": s.end.to_string(),
            "date": s.date.to_string(),
            "effective": d.effective_minutes,
            "effective_text": minutes(d.effective_minutes),
            "media_minutes": d.media_minutes,
            "game_minutes": d.game_minutes,
            "seen": seen,
            "parts": parts,
        }))
    }

    /// The Files page: new files first, then every file by subject, with
    /// what was decided and when it comes next.
    pub(crate) fn files_view(&self) -> Value {
        use crate::catalogue::{Inclusion, ItemKind};
        let lang = self.lang();
        let today = self.now().date;
        let first = self.plan.first_dates(today);
        let kind = |k: ItemKind| match k {
            ItemKind::Pdf => "PDF",
            ItemKind::Notes => "MD",
            ItemKind::Map => self_t(lang, "Map", "Carte"),
            ItemKind::Sheet => self_t(lang, "Sheet", "Fiche"),
            ItemKind::Synthesis => self_t(lang, "Exercises", "Exercices"),
            ItemKind::ExamPractice => self_t(lang, "Exam-type", "Type examen"),
            ItemKind::TdExercise => "TD",
        };
        let decisions = &self.store.state.progress.files;
        let row = |i: &crate::catalogue::Item| {
            let dir = i.id.rsplit_once('/').map_or("", |(d, _)| d);
            let next = ["study:", "read:"].iter().find_map(|p| first.get(&format!("{p}{}", i.id))).map(|(d, _, _)| i18n::date(*d, lang));
            let done = self.store.state.progress.items.get(&i.id).is_some_and(|p| p.done || p.studied_on.is_some());
            json!({
                "id": i.id,
                "title": i18n::item_name(&i.id),
                "kind": kind(i.kind),
                "dir": dir,
                "inclusion": decisions.get(&i.id).map(|d| if *d == Inclusion::Planned { "planned" } else { "ignored" }),
                "next": next,
                "done": done,
                "star": i.starred,
            })
        };
        let undecided: Vec<Value> = self.catalogue.pending(decisions, &self.store.settings.domains).into_iter().map(row).collect();
        let mut by_domain: Vec<Value> = Vec::new();
        for d in self.catalogue.domains() {
            let items: Vec<Value> = self.catalogue.items.iter().filter(|i| i.domain == d).map(row).collect();
            by_domain.push(json!({ "domain": d, "items": items }));
        }
        json!({
            "root": self.store.settings.courses,
            "count": self.catalogue.items.len(),
            "undecided": undecided,
            "domains": by_domain,
        })
    }

    /// The Progress page: per subject, sheets studied, exercises solved
    /// alone, reviews due, and the next exam with its margin.
    pub(crate) fn progress_view(&self) -> Value {
        use crate::catalogue::{Inclusion, ItemKind};
        use crate::model::Exercise;
        let lang = self.lang();
        let today = self.now().date;
        let st = &self.store.state;
        let mut out = Vec::new();
        for d in self.store.settings.domains.iter().filter(|d| !d.archived) {
            let items: Vec<&crate::catalogue::Item> = self
                .catalogue
                .items
                .iter()
                .filter(|i| i.domain == d.id && st.progress.files.get(&i.id) == Some(&Inclusion::Planned))
                .filter(|i| matches!(i.kind, ItemKind::Sheet | ItemKind::Synthesis | ItemKind::Map | ItemKind::TdExercise | ItemKind::Pdf | ItemKind::Notes))
                .collect();
            if items.is_empty() {
                continue;
            }
            let prog = |i: &crate::catalogue::Item| st.progress.items.get(&i.id);
            let studied = items.iter().filter(|i| prog(i).is_some_and(|p| p.done || p.studied_on.is_some())).count();
            let ex_total: u32 = items.iter().map(|i| i.exercises).sum();
            let ex_solo: usize = items
                .iter()
                .filter_map(|i| prog(i))
                .map(|p| p.exercises.values().filter(|e| **e == Exercise::Solo).count())
                .sum();
            // Reviews due: a first pass done, and its J+7 (or J+3) passed.
            let due = items
                .iter()
                .filter_map(|i| prog(i))
                .filter(|p| d.spaced && p.studied_on.is_some_and(|on| {
                    let wait = if p.assessment == Some(crate::model::Assessment::Review) { 3 } else { 7 };
                    p.reviews_done.is_empty() && on.add(wait) <= today
                }))
                .count();
            let exam = self.plan.margins.iter().filter(|m| m.domain.as_deref() == Some(&d.id)).min_by_key(|m| m.date);
            out.push(json!({
                "domain": d.id,
                "studied": studied,
                "total": items.len(),
                "exercises_solo": ex_solo,
                "exercises": ex_total,
                "reviews_due": due,
                "exam": exam.map(|m| json!({
                    "title": m.title,
                    "date": i18n::date(m.date, lang),
                    "days": today.days_until(m.date),
                    "margin": m.sessions,
                })),
            }));
        }
        Value::Array(out)
    }

    /// The first run's suggestions: for each course folder, the timetable's
    /// course names that look like it ("Logique et modèles de calculs" for
    /// L&MC). To confirm, never applied on their own.
    pub(crate) fn suggestions(&self) -> Value {
        let ids = self.catalogue.domains();
        let mut out: std::collections::BTreeMap<String, Vec<String>> = ids.iter().map(|d| (d.to_string(), Vec::new())).collect();
        if let Some(snap) = &self.ade {
            for e in &snap.events {
                let name = crate::ade::read_title(&e.summary).name;
                if let Some(id) = crate::ade::suggest_domain(&name, &ids) {
                    let v = out.entry(id.to_string()).or_default();
                    if !name.is_empty() && !v.contains(&name) {
                        v.push(name);
                    }
                }
            }
        }
        json!(out)
    }

    /// Plans every structured file (maps, sheets, exercises) still waiting,
    /// leaving PDFs and notes to decide one by one.
    pub(crate) fn plan_structured(&mut self) -> std::io::Result<usize> {
        use crate::catalogue::{Inclusion, ItemKind};
        let items: Vec<String> = self
            .catalogue
            .pending(&self.store.state.progress.files, &self.store.settings.domains)
            .into_iter()
            .filter(|i| !matches!(i.kind, ItemKind::Pdf | ItemKind::Notes))
            .map(|i| i.id.clone())
            .collect();
        let n = items.len();
        if n > 0 {
            let now = self.now();
            self.store.record(crate::store::Event::Files { items, inclusion: Inclusion::Planned }, now)?;
            self.replan();
        }
        Ok(n)
    }
}

fn self_t(lang: Lang, en: &'static str, fr: &'static str) -> &'static str {
    if lang == Lang::Fr {
        fr
    } else {
        en
    }
}
