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
    fn headline(&self, s: &Session) -> String {
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
    fn raise(&mut self, alert: Value) {
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
            self.t("Noted.", "Noté.")
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
            _ => !matches!(outcome, Some(Outcome::Started { .. } | Outcome::Paused { .. })),
        };
        if gone {
            self.alert = None;
        }
    }

    /// Today, for the drawer's first page: courses, sessions and offers in
    /// order, each with what it is and how it went.
    pub(crate) fn today(&self) -> Value {
        let lang = self.lang();
        let now = self.now();
        let (courses, _) = self.timetable();
        let mut rows: Vec<(Hm, Value)> = Vec::new();
        for c in courses.iter().filter(|c| c.start.date == now.date) {
            rows.push((
                c.start.time,
                json!({ "type": "course", "start": c.start.time.to_string(), "end": c.end.time.to_string(), "title": c.title, "past": c.end <= now }),
            ));
        }
        for s in self.plan.sessions.iter().chain(&self.plan.offers).filter(|s| s.date == now.date && !s.parts.is_empty()) {
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
        rows.sort_by_key(|r| r.0);
        Value::Array(rows.into_iter().map(|r| r.1).collect())
    }
}
