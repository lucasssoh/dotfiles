//! Alerts in the bar's central island, as alerting as Veille.
//!
//! The start of a session, its reminder and "done?" at its end are not
//! notifications: the bar opens them in its central
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
    /// It names the module only: what to do is the course's business.
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

    /// The session under way reached its end: done?
    pub(crate) fn closing_check(&mut self) {
        let now = self.now();
        let Some(id) = self.watcher.watch.as_ref().map(|w| w.session.clone()) else { return };
        let Some(s) = self.session_any(&id) else { return };
        let key = format!("closing:{id}");
        if Local::new(s.date, s.end) > now || self.sent.contains_key(&key) || self.alert.as_ref().is_some_and(|a| a["key"] == key.as_str()) {
            return;
        }
        self.sent.insert(key.clone(), now.date);
        let mins = self.watcher.watch.as_ref().map_or(0, |w| w.effective(crate::daemon::now_secs()) / 60);
        let body = if self.lang() == Lang::Fr { format!("{} h {:02} effectives.", mins / 60, mins % 60) } else { format!("{} h {:02} effective.", mins / 60, mins % 60) };
        let alert = json!({
            "key": key,
            "kind": "closing",
            "session": id,
            "time": now.time.to_string(),
            "title": self.t(&format!("{} · done?", self.headline(&s)), &format!("{} · fini ?", self.headline(&s))),
            "body": body,
            "actions": [
                json!({ "id": "close", "label": self.t("Done", "Fini"), "primary": true }),
                json!({ "id": "dismiss", "label": self.t("Not yet", "Pas encore") }),
            ],
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
        self.on_action(&session, action);
        let fr = self.lang() == Lang::Fr;
        let text = if action == "start" {
            self.t("Off you go.", "C'est parti.")
        } else if action.starts_with("away:") {
            let label = self.away().map(|u| self.until_label(u)).unwrap_or_default();
            if fr { format!("Rien {label}.") } else { format!("Nothing {label}.") }
        } else if action == "close" {
            self.t("Session done.", "Séance finie.")
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

    /// A task of a session, for the day's list.
    fn part_row(&self, p: &Part, lang: Lang) -> Value {
        json!({ "domain": p.domain, "what": i18n::work(&p.work, lang), "minutes": p.minutes })
    }

    /// Whether a session's subject has a command ("Launch").
    fn launchable(&self, s: &Session) -> bool {
        s.course().is_some_and(|d| self.store.settings.domains.iter().any(|x| x.id == d && x.launch.as_deref().is_some_and(|l| !l.trim().is_empty())))
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
                    "launch": self.launchable(s),
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
                        "launch": self.launchable(s),
                    }),
                ));
            }
        }
        rows.sort_by_key(|r| r.0);
        Value::Array(rows.into_iter().map(|r| r.1).collect())
    }

    /// The first run's suggestions: for each course folder, the timetable's
    /// course names that look like it ("Logique et modèles de calculs" for
    /// L&MC). To confirm, never applied on their own.
    pub(crate) fn suggestions(&self) -> Value {
        let folders = self.course_folders();
        let ids: Vec<&str> = folders.iter().map(String::as_str).collect();
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
}
