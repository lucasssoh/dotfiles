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
use crate::journee::SlotKind;
use crate::model::Lang;
use crate::plan::{Part, Session, Work};
use crate::store::Outcome;
use crate::time::{Hm, Local};

impl Service {
    pub(crate) fn t(&self, en: &str, fr: &str) -> String {
        if self.lang() == Lang::Fr { fr } else { en }.to_string()
    }

    /// "A&C · 32 Analyse 2 − 1/m ★": the session's main work, in a line.
    /// What a session is about: its module, a project's or a campaign's name.
    pub(crate) fn headline(&self, s: &Session) -> String {
        self.short_label(s)
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

    /// Start, or "Later, until…": the nearest choices, the others in the drawer.
    fn actions(&self) -> Vec<Value> {
        let mut a = vec![json!({ "id": "start", "label": self.t("Start", "Commencer"), "primary": true })];
        a.push(json!({ "id": "away:30", "label": self.t("In 30 min", "Dans 30 min") }));
        a.push(json!({ "id": "away:tomorrow", "label": self.t("Tomorrow", "Demain") }));
        a
    }

    /// The start of a session (`reminder`: 15 minutes on, nothing begun).
    /// It names the module only: what to open is put forward in the room.
    pub(crate) fn session_alert(&mut self, s: &Session, at: Local, reminder: bool) {
        let what = self.headline(s);
        let from = at.time.max(s.start);
        let len = s.end.0 - from.0;
        let len = if len >= 60 { format!("{} h {:02}", len / 60, len % 60).replace(" h 00", " h") } else { format!("{len} min") };
        let title = if reminder {
            self.t(&format!("{what} is waiting"), &format!("{what} t'attend"))
        } else if s.kind == SlotKind::Evening {
            self.t(&format!("Tonight · {what}"), &format!("Ce soir · {what}"))
        } else {
            what
        };
        let body = format!("{from} – {} · {len}", s.end);
        let hint: Option<String> = None;
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
            "actions": self.actions(),
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
        } else if action.starts_with("away:") {
            let label = self.away().map(|u| self.until_label(u)).unwrap_or_default();
            if fr { format!("Rien {label}.") } else { format!("Nothing {label}.") }
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

    /// A task of a session, for the day's list; a project with a folder
    /// brings its files, to be opened in any order.
    fn part_row(&self, p: &Part, lang: Lang) -> Value {
        let mut v = json!({ "domain": p.domain, "what": i18n::work(&p.work, lang), "minutes": p.minutes });
        if let Work::Project { project, .. } = &p.work {
            if let Some(files) = self.project_files(project) {
                v["files"] = files;
            }
        }
        v
    }

    fn day_rows(&self, date: crate::time::Date) -> Value {
        let lang = self.lang();
        let now = self.now();
        let (courses, _) = self.timetable();
        let mut rows: Vec<(Hm, Value)> = Vec::new();
        for c in courses.iter().filter(|c| c.start.date == date) {
            rows.push((
                c.start.time,
                json!({ "type": "course", "start": c.start.time.to_string(), "end": c.end.time.to_string(), "title": c.title, "room": c.short_room(), "past": c.end <= now }),
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
            let parts: Vec<Value> = s.parts.iter().map(|p| self.part_row(p, lang)).collect();
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
        // Started ahead of its day (a session of the week begun now): shown
        // today, where it is under way.
        if date == now.date {
            for (id, s) in &self.store.state.started {
                if s.date == date || s.parts.is_empty() || rows.iter().any(|r| r.1["id"] == id.as_str()) {
                    continue;
                }
                let state = match self.store.state.outcomes.get(id) {
                    Some(Outcome::Started { .. }) => "started",
                    Some(Outcome::Paused { .. }) => "paused",
                    _ => continue,
                };
                let start = now.time;
                let end = Hm((start.0 + s.end.0 - s.start.0).min(24 * 60 - 1));
                let parts: Vec<Value> = s.parts.iter().map(|p| self.part_row(p, lang)).collect();
                rows.push((
                    start,
                    json!({
                        "type": "session",
                        "id": id,
                        "kind": s.kind,
                        "start": start.to_string(),
                        "end": end.to_string(),
                        "title": self.headline(s),
                        "parts": parts,
                        "why": [],
                        "state": state,
                        "shortened": false,
                        "past": false,
                    }),
                ));
            }
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
        // Hours the plan gives a subject before its exam (or in all, without one).
        let hours = |domain: &str, until: Option<crate::time::Date>| -> f32 {
            let m: i32 = self
                .plan
                .sessions
                .iter()
                .filter(|s| until.is_none_or(|u| s.date <= u))
                .flat_map(|s| s.parts.iter())
                .filter(|p| p.domain.as_deref() == Some(domain))
                .map(|p| p.minutes)
                .sum();
            (m as f32 / 60.0 * 2.0).round() / 2.0
        };
        let exam_at = |domain: &str, date: crate::time::Date| {
            self.timetable()
                .1
                .into_iter()
                .chain(st.deadlines.iter().cloned())
                .find(|x| x.domain.as_deref() == Some(domain) && x.at.date == date)
                .map(|x| x.at.time)
        };
        for d in self.store.settings.domains.iter().filter(|d| !d.archived) {
            let items: Vec<&crate::catalogue::Item> = self
                .catalogue
                .items
                .iter()
                .filter(|i| i.domain == d.id && st.progress.files.get(&i.id) == Some(&Inclusion::Planned))
                .filter(|i| matches!(i.kind, ItemKind::Sheet | ItemKind::Synthesis | ItemKind::Map | ItemKind::TdExercise | ItemKind::Pdf | ItemKind::Notes))
                .collect();
            let exam = self.plan.margins.iter().filter(|m| m.domain.as_deref() == Some(&d.id) && m.date >= today).min_by_key(|m| m.date);
            if items.is_empty() && exam.is_none() {
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
            out.push(json!({
                "domain": d.id,
                "level": d.level,
                "lessons": d.lessons,
                "hours": hours(&d.id, exam.map(|m| m.date)),
                "iso": exam.map(|m| m.date),
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
                    "time": exam_at(&d.id, m.date),
                })),
            }));
        }
        // Exams first, the nearest first; then the subjects without one.
        out.sort_by_key(|v| v["iso"].as_str().map(String::from).unwrap_or_else(|| "9999".into()));
        Value::Array(out)
    }

    /// Week by week up to the last exam: hours planned, the two subjects
    /// taking most of them, the exams that week.
    pub(crate) fn weeks_view(&self) -> Value {
        let lang = self.lang();
        let today = self.now().date;
        let last = self.plan.margins.iter().map(|m| m.date).max().unwrap_or(today.add(42)).max(today.add(42));
        let mut out = Vec::new();
        let mut mon = today.monday();
        while mon <= last {
            let sun = mon.add(6);
            let mut per: std::collections::BTreeMap<String, i32> = std::collections::BTreeMap::new();
            for s in self.plan.sessions.iter().filter(|s| s.date >= mon && s.date <= sun) {
                for p in &s.parts {
                    *per.entry(p.domain.clone().unwrap_or_default()).or_default() += p.minutes;
                }
            }
            let total: i32 = per.values().sum();
            let mut top: Vec<(String, i32)> = per.into_iter().filter(|(k, m)| !k.is_empty() && *m >= 60).collect();
            top.sort_by(|a, b| b.1.cmp(&a.1));
            top.truncate(2);
            let exams: Vec<String> = self
                .plan
                .margins
                .iter()
                .filter(|m| m.date >= mon && m.date <= sun)
                .map(|m| format!("{} {}", m.domain.clone().unwrap_or_else(|| m.title.clone()), m.date.parts().2))
                .collect();
            out.push(json!({
                "week": i18n::date(mon, lang),
                "hours": (total as f32 / 60.0 * 2.0).round() / 2.0,
                "top": top.iter().map(|(d, m)| json!({ "domain": d, "hours": (*m as f32 / 60.0 * 2.0).round() / 2.0 })).collect::<Vec<_>>(),
                "exams": exams,
            }));
            mon = mon.add(7);
        }
        Value::Array(out)
    }

    /// Nothing planned right now and time ahead (a free period at school, an
    /// evening with nothing on): what would help most, for Today's top when
    /// the drawer is opened. Never shown on its own ("c'est moi qui décide
    /// d'ouvrir boussole"); a session planned keeps its own alerts.
    pub(crate) fn now_free(&self) -> Value {
        let lang = self.lang();
        let now = self.now();
        let st = &self.store.state;
        let r = &self.store.settings.rhythm;
        if self.plan.paused || self.suivi.tracker.is_some() {
            return Value::Null;
        }
        let open = |id: &str| !st.outcomes.contains_key(id);
        // A session due now or within half an hour: its alert speaks.
        let soon = self
            .plan
            .sessions
            .iter()
            .filter(|x| x.date == now.date && x.counted && !x.parts.is_empty() && open(&x.id))
            .filter(|x| x.end > now.time)
            .map(|x| x.start)
            .min();
        if soon.is_some_and(|t| t.0 <= now.time.0 + 30) {
            return Value::Null;
        }
        let gap = self.plan.offers.iter().find(|o| o.kind == SlotKind::Gap && o.date == now.date && o.start <= now.time && now.time < o.end);
        let (end, school) = match gap {
            Some(g) => (g.end, true),
            None => {
                let limit = soon.map_or(r.latest_end, |t| t.min(r.latest_end));
                if now.time < r.morning_ready || now.time >= limit {
                    return Value::Null;
                }
                (limit, false)
            }
        };
        let span = end.0 - now.time.0;
        if span < r.min_session {
            return Value::Null;
        }
        let recs = self.picks(span);
        let ahead: Vec<&crate::plan::Part> = self
            .plan
            .sessions
            .iter()
            .filter(|x| Local::new(x.date, x.end) > now && open(&x.id))
            .flat_map(|x| x.parts.iter())
            .collect();
        let name = |d: &str| self.subject_name(d);
        // Each subject's next task, to pick one by hand.
        let subjects: Vec<Value> = self
            .store
            .settings
            .domains
            .iter()
            .filter(|d| !d.archived)
            .filter_map(|d| {
                let p = ahead.iter().find(|p| p.domain.as_deref() == Some(&d.id))?;
                Some(json!({ "domain": d.id, "label": name(&d.id), "task": p.task, "line": format!("{} · {}", name(&d.id), i18n::work(&p.work, lang)), "minutes": p.minutes.min(span) }))
            })
            .collect();
        let day = i18n::date(now.date, lang);
        json!({
            "school": school,
            "until": end,
            "minutes": span,
            "label": if school { self.t(&format!("Free period at school · {day}"), &format!("Creux à l'école · {day}")) }
                     else if now.time.0 >= 17 * 60 { self.t(&format!("Tonight · {day}"), &format!("Ce soir · {day}")) }
                     else { self.t(&format!("Free · {day}"), &format!("Libre · {day}")) },
            "note": if school { self.t(&format!("Until {end}. Paper and pen are enough."), &format!("Jusqu'à {end}. Papier et stylo suffisent.")) }
                    else { self.t(&format!("If you want to get on anyway, what would help most until {end}:"), &format!("Si tu veux quand même avancer, ce qui servirait le plus d'ici {end} :")) },
            "recs": recs,
            "subjects": subjects,
        })
    }

    /// The most pressing margin below zero, for a line under Today; and
    /// how many subjects with something to study have no exam date.
    pub(crate) fn programme_alert(&self) -> Value {
        let lang = self.lang();
        let today = self.now().date;
        let short = self.plan.margins.iter().filter(|m| m.sessions < 0 && m.date >= today).min_by_key(|m| m.date);
        let undated = self
            .store
            .settings
            .domains
            .iter()
            .filter(|d| !d.archived && d.level.studies())
            .filter(|d| !self.plan.margins.iter().any(|m| m.domain.as_deref() == Some(&d.id)))
            .map(|d| d.id.clone())
            .collect::<Vec<_>>();
        json!({
            "short": short.map(|m| json!({ "domain": m.domain, "title": m.title, "date": i18n::date(m.date, lang), "margin": m.sessions })),
            "undated": undated,
        })
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
