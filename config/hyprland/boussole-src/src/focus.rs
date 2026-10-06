//! Focus mode: a session happens in a study dimension.
//!
//!   dimension  workspaces STUDY_FIRST..=STUDY_LAST, kept for study. Starting
//!              a session takes you there (the last one you used, the first
//!              otherwise) and opens its file in Liseuse; your own
//!              workspaces are left as they are. Pause and Close bring you
//!              back where you came from; Resume takes you there again.
//!   panel      the bar shows the session's panel on every study workspace,
//!              a fixed panel down the left edge that keeps its room:
//!              Liseuse and whatever else tiles beside it.
//!   next       "Next file" closes the session and starts the next one of
//!              the same evening in place: a new Liseuse window opens where
//!              the old one was, which then closes.
//!   counts     anything focused on a study workspace is for the session,
//!              asked nothing. Elsewhere, a detour: the question comes after
//!              the stake's delay.
//!
//! Detours: what is focused instead, as a `seance::Context`. Neovim says
//! which file it edits (config/nvim/lua/boussole.lua) and is believed while
//! its window has the focus; any other window is named by its title. A file
//! under the course folder is never a detour: it counts for its course.
//! Answers are kept in the journal (`Event::Context`).
//!
//! Hyprland is driven over its socket with Lua dispatchers (`eval …`), one
//! request each, in order: the workspace has to be focused before Liseuse
//! starts, or the window opens on the old one.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::daemon::{now_secs, which, Job, Service};
use crate::i18n;
use crate::model::{Lang, Level};
use crate::plan::{Reason, Session, Work};
use crate::seance::{self, Context, Detour, Prompt, Stake};
use crate::store::{self, Event, Outcome, Verdict};
use crate::time::Local;

/// The study dimension's workspaces.
pub const STUDY_FIRST: i32 = 11;
pub const STUDY_LAST: i32 = 14;
const ZATHURA_CLASS: &str = "org.pwmt.zathura";

pub fn is_study(ws: i64) -> bool {
    (STUDY_FIRST as i64..=STUDY_LAST as i64).contains(&ws)
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct FocusState {
    /// A session holds the dimension.
    pub active: bool,
    /// Where you were before it: Pause and Close go back there.
    pub origin: Option<String>,
    /// The study workspace last used.
    pub last: Option<i32>,
    /// Your own workspace last used, to come back to.
    pub last_normal: Option<String>,
    /// The Liseuse window to close once the next file is open (its pid).
    pub replace: Option<u32>,
    /// A close followed by the next session: the dimension is kept.
    #[serde(skip)]
    pub chaining: bool,
}

/// Neovim, as its plugin last reported.
#[derive(Clone, PartialEq, Debug, Default)]
pub struct Editor {
    pub file: PathBuf,
    pub focused: bool,
}

fn socket() -> Option<UnixStream> {
    let dir = crate::suivi::hypr_dir()?;
    let s = UnixStream::connect(dir.join(".socket.sock")).ok()?;
    let _ = s.set_read_timeout(Some(std::time::Duration::from_millis(500)));
    Some(s)
}

/// A request to Hyprland's socket, its reply.
fn hypr(req: &str) -> Option<Vec<u8>> {
    let mut s = socket()?;
    s.write_all(req.as_bytes()).ok()?;
    let mut out = Vec::new();
    let _ = s.read_to_end(&mut out);
    Some(out)
}

fn query(what: &str) -> Value {
    hypr(&format!("j/{what}")).and_then(|o| serde_json::from_slice(&o).ok()).unwrap_or(Value::Null)
}

/// A Lua string literal: quoted, with what could end it escaped.
fn lua(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

fn dispatch(dsp: &str) {
    let _ = hypr(&format!("eval hl.dispatch({dsp})"));
}

fn go_to(workspace: &str) {
    dispatch(&format!("hl.dsp.focus({{ workspace = {} }})", lua(workspace)));
}

fn focus_window(address: &str) {
    dispatch(&format!("hl.dsp.focus({{ window = {} }})", lua(&format!("address:{address}"))));
}

fn close_window(address: &str) {
    dispatch(&format!("hl.dsp.window.close({{ window = {} }})", lua(&format!("address:{address}"))));
}

fn clients() -> Vec<Value> {
    query("clients").as_array().cloned().unwrap_or_default()
}

fn ws_id(c: &Value) -> i64 {
    c["workspace"]["id"].as_i64().unwrap_or(0)
}

/// The focused workspace: (id, name).
fn current() -> (i64, String) {
    let w = query("activeworkspace");
    (w["id"].as_i64().unwrap_or(0), w["name"].as_str().unwrap_or("").to_string())
}

/// "~/code/dotfiles" for a path under the home folder.
fn tilde(p: &Path) -> String {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    match p.strip_prefix(&home) {
        Ok(rest) if !home.as_os_str().is_empty() => format!("~/{}", rest.display()),
        _ => p.display().to_string(),
    }
}

/// What a file belongs to: its repository, else its folder.
fn project_of(file: &Path) -> PathBuf {
    let dir = file.parent().unwrap_or(file);
    dir.ancestors().find(|d| d.join(".git").exists()).unwrap_or(dir).to_path_buf()
}

/// A window title without its browser's name.
fn page_title(title: &str) -> String {
    let mut t = title.trim();
    for tail in [" — Mozilla Firefox", " - Mozilla Firefox", " — Firefox", " - Chromium", " - Google Chrome", " — Zen Browser"] {
        t = t.strip_suffix(tail).unwrap_or(t);
    }
    t.to_string()
}

impl Service {
    fn focus_save(&self) {
        let _ = store::write_json(&self.store.paths.data.join("focus.json"), &self.focus);
    }

    pub(crate) fn focus_load(&mut self) {
        self.focus = store::read_json(&self.store.paths.data.join("focus.json")).unwrap_or_default();
    }

    pub(crate) fn focus_active(&self) -> bool {
        self.focus.active
    }

    /// The session's file, as a path to open.
    fn session_path(&self, session: &str) -> Option<PathBuf> {
        let root = self.store.settings.courses.clone()?;
        let s = self.session_any(session)?;
        s.parts.iter().find_map(|p| match &p.work {
            Work::Study { item, .. } | Work::Read { item } | Work::Review { item, .. } | Work::Redo { item, .. } | Work::ExamSubject { item, .. } => {
                Some(root.join(item))
            }
            // A task can name the file it is about.
            Work::Chore { chore, .. } => self.store.state.chores.iter().find(|c| &c.id == chore)?.file.as_ref().map(|f| root.join(f)),
            _ => None,
        })
    }

    fn open_in_liseuse(&mut self, path: &Path) {
        let opener = which("liseuse").unwrap_or_else(|| PathBuf::from("xdg-open"));
        // Liseuse's own helpers live beside it, out of the service's PATH.
        let mut cmd = Command::new(opener);
        if let (Some(home), Some(path_var)) = (std::env::var_os("HOME"), std::env::var_os("PATH")) {
            let dirs = std::iter::once(PathBuf::from(home).join(".local/bin")).chain(std::env::split_paths(&path_var));
            if let Ok(joined) = std::env::join_paths(dirs) {
                cmd.env("PATH", joined);
            }
        }
        self.spawn(cmd.arg(path), Job::Quiet);
    }

    /// Into the dimension, on the study workspace last used.
    fn enter_dimension(&mut self) -> i32 {
        let (id, name) = current();
        if !is_study(id) {
            if !self.focus.active || self.focus.origin.is_none() {
                self.focus.origin = Some(name);
            }
            let w = self.focus.last.filter(|w| is_study(*w as i64)).unwrap_or(STUDY_FIRST);
            go_to(&w.to_string());
            self.focus.last = Some(w);
            w
        } else {
            self.focus.last = Some(id as i32);
            id as i32
        }
    }

    /// Opens a session's file: in focus mode, in the study dimension; the
    /// next file of the evening in place of the one before.
    pub(crate) fn focus_open(&mut self, session: &str) {
        let path = self.session_path(session);
        if !self.store.settings.focus.enabled || crate::suivi::hypr_dir().is_none() {
            if let Some(p) = path {
                self.open_in_liseuse(&p);
            }
            return;
        }
        let chained = self.focus.active;
        let w = self.enter_dimension();
        self.focus.active = true;
        let all = clients();
        // The sheet already open in the dimension comes forward rather than twice.
        let item = path.as_ref().and_then(|p| {
            let root = self.store.settings.courses.as_ref()?;
            p.strip_prefix(root).ok().map(|i| i.to_string_lossy().to_string())
        });
        let pids: Vec<u32> = self.suivi.docs.values().filter(|d| d.item.is_some() && d.item == item).map(|d| d.pid).collect();
        let open = all
            .iter()
            .find(|c| is_study(ws_id(c)) && c["class"] == ZATHURA_CLASS && c["pid"].as_u64().is_some_and(|p| pids.contains(&(p as u32))));
        match (open, path) {
            (Some(c), _) => focus_window(c["address"].as_str().unwrap_or("")),
            (None, Some(p)) => {
                // "Next file": the new one opens where the old one is.
                let old = all.iter().find(|c| ws_id(c) == w as i64 && c["class"] == ZATHURA_CLASS);
                if let (true, Some(old)) = (chained, old) {
                    focus_window(old["address"].as_str().unwrap_or(""));
                    self.focus.replace = old["pid"].as_u64().map(|p| p as u32);
                }
                self.open_in_liseuse(&p);
            }
            (None, None) => {}
        }
        self.focus_save();
        self.push_status();
    }

    /// Whether a session has a file to open.
    pub(crate) fn session_has_file(&self, session: &str) -> bool {
        self.session_path(session).is_some()
    }

    /// "Open the sheet again": the session's file, in the dimension (zathura
    /// remembers the page).
    pub(crate) fn focus_reopen(&mut self) {
        let Some(s) = self.suivi.tracker.as_ref().and_then(|t| t.session.clone()) else { return };
        let Some(p) = self.session_path(&s) else { return };
        if self.focus.active && crate::suivi::hypr_dir().is_some() {
            // Still open on another study workspace: there, not twice.
            if let Some(c) = clients().into_iter().find(|c| is_study(ws_id(c)) && c["class"] == ZATHURA_CLASS) {
                focus_window(c["address"].as_str().unwrap_or(""));
                return;
            }
            self.enter_dimension();
        }
        self.open_in_liseuse(&p);
    }

    /// Pause goes back where you came from; Resume into the dimension again,
    /// the file reopened if its window was closed meanwhile.
    pub(crate) fn focus_pause(&mut self, paused: bool) {
        if !self.store.settings.focus.enabled || crate::suivi::hypr_dir().is_none() {
            return;
        }
        let session = self.suivi.tracker.as_ref().and_then(|t| t.session.clone());
        if paused {
            if !self.focus.active {
                return;
            }
            let (id, _) = current();
            if is_study(id) {
                self.focus.last = Some(id as i32);
                if let Some(o) = self.focus.origin.clone() {
                    go_to(&o);
                }
            }
        } else if let Some(s) = session {
            self.enter_dimension();
            self.focus.active = true;
            // The sheet anywhere in the dimension stays where you left it:
            // reopened only if it is gone.
            let sheet = clients().iter().any(|c| is_study(ws_id(c)) && c["class"] == ZATHURA_CLASS);
            if !sheet {
                if let Some(p) = self.session_path(&s) {
                    self.open_in_liseuse(&p);
                }
            }
        }
        self.focus_save();
        self.push_status();
    }

    /// The session over: back where you came from. What is open in the
    /// dimension stays there.
    pub(crate) fn focus_end(&mut self) {
        if !self.focus.active || self.focus.chaining {
            return;
        }
        let (id, _) = current();
        if is_study(id) {
            self.focus.last = Some(id as i32);
            if let Some(o) = self.focus.origin.clone() {
                go_to(&o);
            }
        }
        self.focus.active = false;
        self.focus.origin = None;
        self.focus.replace = None;
        self.focus_save();
        self.push_status();
    }

    /// The guard: only Boussole crosses between your workspaces and the
    /// study ones. Landing in the dimension by hand (a swipe past 10, a
    /// click) without a session under way takes you back; leaving it by
    /// hand during one takes you back in. Pause and Close are the way out,
    /// Start and Resume the way in.
    pub(crate) fn focus_guard(&mut self, ws: i64) {
        if !self.store.settings.focus.enabled || ws <= 0 {
            return;
        }
        let paused = self.suivi.tracker.as_ref().is_some_and(|t| t.flags.paused);
        let inside = self.focus.active && !paused;
        if is_study(ws) && !inside {
            let back = self.focus.last_normal.clone().or(self.focus.origin.clone()).unwrap_or_else(|| "1".into());
            go_to(&back);
        } else if !is_study(ws) && inside {
            let back = self.focus.last.filter(|w| is_study(*w as i64)).unwrap_or(STUDY_FIRST);
            go_to(&back.to_string());
        } else if is_study(ws) {
            self.focus.last = Some(ws as i32);
        } else {
            self.focus.last_normal = Some(ws.to_string());
        }
    }

    /// On window events: the file left behind by "next" closes once the
    /// new one is open.
    pub(crate) fn focus_arrange(&mut self) {
        let Some(pid) = self.focus.replace else { return };
        let all = clients();
        let readers: Vec<&Value> = all.iter().filter(|c| is_study(ws_id(c)) && c["class"] == ZATHURA_CLASS).collect();
        if readers.iter().any(|c| c["pid"].as_u64() != Some(pid as u64)) {
            if let Some(old) = readers.iter().find(|c| c["pid"].as_u64() == Some(pid as u64)) {
                close_window(old["address"].as_str().unwrap_or(""));
            }
            self.focus.replace = None;
            self.focus_save();
        }
    }

    // ─── Detours ─────────────────────────────────────────────────────────

    /// Neovim's report: the file it edits, focused or not, lines written.
    pub(crate) fn editor(&mut self, file: Option<PathBuf>, focused: bool, written: i64) {
        if let Some(f) = &file {
            if written > 0 {
                if let Some(t) = self.suivi.tracker.as_mut() {
                    *t.written.entry(tilde(f)).or_default() += written;
                }
            }
        }
        self.suivi.editor = file.map(|file| Editor { file, focused });
        self.look_around();
    }

    /// What is on instead of the sheet, if it is a detour at all: media
    /// playing first (a video beside the sheet is still one), then the
    /// focused window. Liseuse, a course file in Neovim, and what was
    /// answered as for a course never are.
    fn context_now(&self) -> Option<Context> {
        let remembered = |key: String, label: String, editor: bool, media: bool| match self.store.state.contexts.get(&key) {
            Some((_, Verdict::Course)) => None,
            known => Some(Context { key, label, editor, personal: known.is_some(), media }),
        };
        if self.suivi.media && !self.suivi.media_title.trim().is_empty() {
            let t = self.suivi.media_title.trim().to_string();
            if let Some(c) = remembered(format!("media:{t}"), t, false, true) {
                return Some(c);
            }
        }
        let active = query("activewindow");
        let class = active["class"].as_str().unwrap_or("");
        let title = active["title"].as_str().unwrap_or("");
        if class.is_empty() || class == ZATHURA_CLASS || class.contains("quickshell") {
            return None;
        }
        let editor = self.suivi.editor.as_ref().filter(|e| e.focused && title.ends_with("NVIM"));
        match editor {
            Some(e) => {
                // A course file counts for its course.
                if self.store.settings.courses.as_ref().is_some_and(|r| e.file.starts_with(r)) {
                    return None;
                }
                let p = project_of(&e.file);
                remembered(format!("dir:{}", p.display()), tilde(&p), true, false)
            }
            None => {
                let t = page_title(title);
                let label = if t.is_empty() { class.to_string() } else { t };
                remembered(format!("win:{class}:{label}"), label, false, false)
            }
        }
    }

    /// The session's stake and what it comes from: (stake, subject,
    /// days to its exam, sessions to spare, behind).
    fn stake_of(&self, s: &Session) -> (Stake, Option<String>, Option<i32>, Option<i32>, bool) {
        let today = self.now().date;
        let domain = s.parts.first().and_then(|p| p.domain.clone());
        let behind = domain.as_ref().is_some_and(|d| self.store.settings.domains.iter().any(|x| &x.id == d && x.level == Level::Behind));
        let exam = match &domain {
            Some(d) => self
                .plan
                .margins
                .iter()
                .filter(|m| m.domain.as_ref() == Some(d) && m.date >= today)
                .min_by_key(|m| m.date)
                .map(|m| (today.days_until(m.date), Some(m.sessions))),
            None => s.reasons.iter().find_map(|r| match r {
                Reason::Deadline { days, margin, .. } => Some((*days, *margin)),
                _ => None,
            }),
        };
        let st = seance::stake(behind, exam);
        (st, domain, exam.map(|e| e.0), exam.and_then(|e| e.1), behind)
    }

    fn tracked_session(&self) -> Option<Session> {
        let id = self.suivi.tracker.as_ref()?.session.clone()?;
        self.session_any(&id)
    }

    /// Looks at what is on screen and keeps the detour count up to date.
    pub(crate) fn look_around(&mut self) {
        if self.suivi.tracker.is_none() {
            return;
        }
        // At work in the dimension on something known (Liseuse, a course
        // file, what was answered as for the session): no "still on the
        // exercises?". Anything else there is asked about like anywhere.
        let ctx = self.context_now();
        let active = query("activewindow");
        let known = ctx.is_none() || ctx.as_ref().is_some_and(|c| self.suivi.tracker.as_ref().is_some_and(|t| t.for_session.contains(&c.key)));
        if self.focus.active && known && is_study(active["workspace"]["id"].as_i64().unwrap_or(0)) && !active["class"].as_str().unwrap_or("").is_empty() {
            if let Some(t) = self.suivi.tracker.as_mut() {
                t.at_work(now_secs());
            }
        }
        let delay = self.tracked_session().map_or(Stake::Calm, |s| self.stake_of(&s).0).delay();
        let now = now_secs();
        let focus = self.focus.active;
        let Some(t) = self.suivi.tracker.as_mut() else { return };
        // In the dimension, the sheet closed is asked about after the
        // stake's delay rather than after 18 minutes.
        t.away_delay = if focus { delay } else { 0 };
        let before = t.elsewhere.clone();
        // A video is asked about after half a minute ("6 min c'est trop
        // long, 30 sec"); a window keeps the stake's delay, so a quick look
        // at a definition asks nothing.
        let wait = if ctx.as_ref().is_some_and(|c| c.media) { seance::MEDIA_DELAY } else { delay };
        t.look(now, ctx, wait);
        if t.elsewhere != before {
            self.arm();
        }
    }

    /// "Is it for this session?", or a reminder for something personal.
    pub(crate) fn elsewhere_alert(&mut self) {
        let Some(t) = self.suivi.tracker.as_mut() else { return };
        let Some(e) = t.elsewhere.as_mut() else { return };
        e.asked = true;
        let e = e.clone();
        let Some(s) = self.tracked_session() else { return };
        let fr = self.lang() == Lang::Fr;
        let mins = ((now_secs() - e.since) / 60).max(1);
        let c = &e.context;
        let title = match (c.personal, c.editor, fr) {
            (true, _, true) => format!("{} depuis {mins} min, pendant la séance", c.label),
            (true, _, false) => format!("{} for {mins} min, during the session", c.label),
            (false, true, true) => format!("Tu es sur {} depuis {mins} min. C'est en lien avec la séance ?", c.label),
            (false, true, false) => format!("You have been on {} for {mins} min. Is it for the session?", c.label),
            (false, false, true) if c.media => format!("« {} » joue depuis {mins} min. C'est en lien avec la séance ?", c.label),
            (false, false, false) if c.media => format!("“{}” has been playing for {mins} min. Is it for the session?", c.label),
            (false, false, true) => format!("« {} » est à l'écran depuis {mins} min. C'est en lien avec la séance ?", c.label),
            (false, false, false) => format!("“{}” has been on screen for {mins} min. Is it for the session?", c.label),
        };
        let left = (Local::new(s.date, s.end).minutes() - self.now().minutes()).max(0);
        let (stake, domain, days, margin, behind) = self.stake_of(&s);
        let subject = domain.clone().unwrap_or_else(|| self.short_label(&s));
        let body = match (stake, fr) {
            (Stake::Urgent, true) => match (days, margin) {
                (Some(d), Some(m)) => format!("Examen de {subject} dans {d} jours. Marge : {m} séances. Cette séance compte."),
                (Some(d), None) => format!("{subject} : échéance dans {d} jours. Cette séance compte."),
                _ => format!("{subject} : cette séance compte."),
            },
            (Stake::Urgent, false) => match (days, margin) {
                (Some(d), Some(m)) => format!("{subject} exam in {d} days. Margin: {m} sessions. This session counts."),
                (Some(d), None) => format!("{subject}: due in {d} days. This session counts."),
                _ => format!("{subject}: this session counts."),
            },
            (Stake::Tight, true) if behind => format!("{subject} est une matière où tu es en retard. Il reste {left} min dans cette séance."),
            (Stake::Tight, false) if behind => format!("You are behind in {subject}. {left} min left in this session."),
            (Stake::Tight, true) => format!("Marge serrée en {subject}. Il reste {left} min dans cette séance."),
            (Stake::Tight, false) => format!("A tight margin in {subject}. {left} min left in this session."),
            (Stake::Calm, true) => match days {
                Some(d) => format!("Examen de {subject} dans {d} jours, la marge est confortable."),
                None => format!("Séance de {subject}, rien ne presse."),
            },
            (Stake::Calm, false) => match days {
                Some(d) => format!("{subject} exam in {d} days, a comfortable margin."),
                None => format!("A {subject} session, nothing pressing."),
            },
        };
        let t = |en: &str, f: &str| if fr { f.to_string() } else { en.to_string() };
        let actions = if c.personal {
            vec![
                json!({ "id": "detour:back", "label": t("I'm going back", "Je reviens"), "primary": true }),
                json!({ "id": "detour:pause", "label": t("Pause the session", "Mettre en pause") }),
                json!({ "id": "detour:session", "label": t("It's for the session", "C'est pour la séance") }),
            ]
        } else {
            vec![
                json!({ "id": "detour:session", "label": t("For this session", "Pour cette séance"), "primary": true }),
                json!({ "id": "detour:course", "label": t("Another course or project", "Un autre cours ou projet") }),
                json!({ "id": "detour:back", "label": t("Personal, I'm going back", "Perso, je reviens") }),
                json!({ "id": "detour:pause", "label": t("Personal, pause", "Perso, je mets en pause") }),
            ]
        };
        let now = self.now();
        let alert = json!({
            "key": format!("elsewhere:{}@{}", s.id, now.time),
            "kind": "elsewhere",
            "session": s.id,
            "time": now.time.to_string(),
            "title": title,
            "body": body,
            "stake": stake,
            "actions": actions,
            "chime": stake != Stake::Calm,
        });
        self.raise(alert);
    }

    /// The answer to the detour question; what the island says after it.
    pub(crate) fn detour_answer(&mut self, session: &str, action: &str) -> String {
        let fr = self.lang() == Lang::Fr;
        let t = |en: &str, f: &str| if fr { f.to_string() } else { en.to_string() };
        let Some(e) = self.suivi.tracker.as_ref().and_then(|t| t.elsewhere.clone()) else { return String::new() };
        let answer = match action {
            "session" => Detour::Session,
            "course" => Detour::Course,
            "back" => Detour::Back,
            _ => Detour::Pause,
        };
        let now = self.now();
        let verdict = match answer {
            Detour::Course => Some(Verdict::Course),
            Detour::Back | Detour::Pause if !e.context.personal => Some(Verdict::Personal),
            _ => None,
        };
        if let Some(v) = verdict {
            let ev = Event::Context { key: e.context.key.clone(), label: e.context.label.clone(), verdict: v };
            let _ = self.store.record(ev, now);
        }
        let gone = ((now_secs() - e.since) / 60).max(0);
        if let Some(tr) = self.suivi.tracker.as_mut() {
            tr.detour(now_secs(), answer);
        }
        if answer == Detour::Pause {
            let _ = self.store.record(Event::Paused { session: session.into(), at: now }, now);
            self.session_paused(true);
            self.focus_pause(true);
            self.replan();
        }
        self.arm();
        self.push_status();
        let stake = self.tracked_session().map_or(Stake::Calm, |s| self.stake_of(&s).0);
        match answer {
            Detour::Session => t("Noted, it counts for the session.", "Noté, ça compte pour la séance."),
            Detour::Course => t("Noted, it counts. You will say which at Close.", "Noté, ça compte. Tu diras pour quoi à Clore."),
            Detour::Pause => t("Session paused. The clock stops, nothing is lost.", "Séance en pause. Le chrono s'arrête, rien n'est perdu."),
            Detour::Back => {
                let mut s = if fr {
                    format!("D'accord. {gone} min hors séance, retirées du temps effectif.")
                } else {
                    format!("All right. {gone} min away, taken out of the effective time.")
                };
                if stake == Stake::Urgent {
                    s.push_str(&t(" Asked again in 3 min if you leave again.", " Si tu repars, Boussole redemande dans 3 min."));
                }
                s
            }
        }
    }

    /// The column's view, for the bar.
    pub(crate) fn focus_status(&self) -> Value {
        let st = &self.store.state;
        // Under way today, from the plan or as it was when started (a
        // "Next file" the plan has moved since).
        let today = self.now().date.to_string();
        let active: Option<Session> = st
            .outcomes
            .iter()
            .find(|(id, o)| matches!(o, Outcome::Started { .. } | Outcome::Paused { .. }) && id.starts_with(&today))
            .and_then(|(id, _)| self.session_any(id));
        let active = active.as_ref();
        let queue: Vec<Value> = active
            .map(|a| {
                let mut row: Vec<&Session> = self
                    .plan
                    .sessions
                    .iter()
                    .filter(|s| s.id != a.id && s.date == a.date && s.slot() == a.slot() && !s.parts.is_empty())
                    .filter(|s| !matches!(st.outcomes.get(&s.id), Some(Outcome::Skipped | Outcome::Missed)))
                    .chain(std::iter::once(a))
                    .collect();
                row.sort_by_key(|s| s.start);
                row.into_iter()
                    .map(|s| {
                        let state = if s.id == a.id {
                            "current"
                        } else if matches!(st.outcomes.get(&s.id), Some(Outcome::Closed { .. })) {
                            "done"
                        } else {
                            "next"
                        };
                        json!({ "session": s.id, "title": self.headline(s), "start": s.start, "end": s.end, "state": state })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let next = queue.iter().find(|q| q["state"] == "next").and_then(|q| q["session"].as_str()).map(String::from);
        let objective = active.and_then(|s| s.parts.first()).and_then(|p| {
            let w = i18n::work(&p.work, self.lang());
            w.split_once(" · ").map(|(_, o)| o.to_string())
        });
        json!({
            "enabled": self.store.settings.focus.enabled,
            "active": self.focus.active,
            "file": active.is_some_and(|s| self.session_has_file(&s.id)),
            "study": [STUDY_FIRST, STUDY_LAST],
            "queue": queue,
            "next": next,
            "objective": objective,
            "title": active.map(|s| self.headline(s)),
            "end": active.map(|s| s.end),
            "elsewhere": self.suivi.tracker.as_ref().and_then(|t| t.elsewhere.as_ref()).map(|e| json!({ "label": e.context.label, "since": e.since })),
        })
    }
}

/// The alert's prompt kind is asked once per detour by the tracker itself.
pub(crate) fn asked_by_tracker(p: Prompt) -> bool {
    p == Prompt::Elsewhere
}
