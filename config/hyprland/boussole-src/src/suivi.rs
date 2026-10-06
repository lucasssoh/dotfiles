//! The service's side of session tracking: what feeds `seance::Tracker`.
//!
//!   zathura   one resident `busctl monitor`, matched by the bus itself on
//!             zathura's names coming and going and on its page changes,
//!             so it sleeps until a page turns. Properties are read once
//!             per new window. The PDF's outline (mutool, ~15 ms) once per file.
//!   Hyprland  its event socket, only while a sheet is open or a session
//!             runs; any window or workspace event asks `j/clients` which
//!             windows are visible (~4 ms).
//!   games     a look at /proc's process names when a window opens or
//!             closes and when a session starts.
//!   idle, media  reported by the bar over the socket.
//!
//! Outside a session, a sheet open in Liseuse is free reading: kept, never
//! marked done, used only to pre-fill the next close; and when that sheet
//! has a session planned, it is offered ("start Wednesday's session now?").

use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::{ErrorKind, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::Command;

use serde_json::{json, Value};

use crate::daemon::{now_secs, set_nonblocking, which, Job, Service};
use crate::liseuse::{self, Map};
use crate::plan::Work;
use crate::seance::{self, Draft, Prompt, Tracker};
use crate::store::{self, Event, Outcome, Tracking};
use crate::time::Local;

const ZATHURA: &str = "org.pwmt.zathura";

#[derive(Clone, Debug)]
pub struct Doc {
    pub pid: u32,
    pub file: PathBuf,
    pub item: Option<String>,
    /// 1-based.
    pub page: u32,
    pub pages: u32,
}

#[derive(Default)]
pub struct Suivi {
    /// Open zathura windows, by unique bus name.
    pub docs: HashMap<String, Doc>,
    pub maps: HashMap<PathBuf, Map>,
    /// The session under way.
    pub tracker: Option<Tracker>,
    /// Reading outside any session.
    pub free: Option<Tracker>,
    pub hypr: Option<UnixStream>,
    hypr_buf: Vec<u8>,
    pub visible: HashSet<u32>,
    pub game: bool,
    pub idle: bool,
    pub media: bool,
    /// Go to this section once the file is open: (item, §).
    pub goto: Option<(String, u32)>,
    /// A planned session for the sheet being read freely: (session, item).
    pub offer: Option<(String, String)>,
    /// The last question asked, so it is asked once.
    pub asked: Option<Prompt>,
    pub saved: i64,
    pub bus_alive: bool,
    /// Neovim, as its plugin last reported.
    pub editor: Option<crate::focus::Editor>,
    /// What the media playing is (its title), from the bar.
    pub media_title: String,
}

pub(crate) fn hypr_dir() -> Option<PathBuf> {
    let run = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?).join("hypr");
    if let Some(sig) = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE") {
        return Some(run.join(sig));
    }
    // A user service may start without Hyprland's environment: the newest instance.
    std::fs::read_dir(&run)
        .ok()?
        .flatten()
        .filter(|e| e.path().join(".socket2.sock").exists())
        .max_by_key(|e| e.metadata().and_then(|m| m.modified()).ok())
        .map(|e| e.path())
}

fn busctl_json(args: &[&str]) -> Vec<Value> {
    let Ok(out) = Command::new("busctl").args(["--user", "--json=short"]).args(args).output() else { return Vec::new() };
    String::from_utf8_lossy(&out.stdout).lines().filter_map(|l| serde_json::from_str(l).ok()).collect()
}

impl Service {
    /// Hyprland's events: while tracking, and always in focus mode (its
    /// guard watches the dimensions).
    pub(crate) fn hypr_wanted(&self) -> bool {
        self.tracking_wanted() || self.store.settings.focus.enabled
    }

    fn tracking_wanted(&self) -> bool {
        self.suivi.tracker.is_some() || self.suivi.docs.values().any(|d| d.item.is_some())
    }

    pub(crate) fn suivi_start(&mut self) {
        // A session under way when the service stopped goes on.
        let active = self
            .store
            .state
            .outcomes
            .iter()
            .find(|(id, o)| matches!(o, Outcome::Started { .. } | Outcome::Paused { .. }) && id.starts_with(&self.now().date.to_string()))
            .map(|(id, _)| id.clone());
        if let Some(id) = active {
            let saved: Option<Tracker> = store::read_json(&self.store.paths.data.join("seance.json"));
            self.suivi.tracker = Some(saved.filter(|t| t.session.as_ref() == Some(&id)).unwrap_or_else(|| Tracker::start(Some(id), now_secs())));
        }
        self.spawn_bus();
        for v in busctl_json(&["list"]) {
            for row in v.as_array().into_iter().flatten() {
                let name = row["name"].as_str().unwrap_or("");
                let unique = row["connection"].as_str().unwrap_or("");
                if name.starts_with(ZATHURA) && !unique.is_empty() {
                    self.register(unique, name);
                }
            }
        }
        self.refresh_hypr();
        // After a restart, what runs now decides, not what ran before.
        if self.suivi.tracker.is_some() {
            self.check_games();
        }
        self.connect_hypr();
    }

    fn spawn_bus(&mut self) {
        if which("busctl").is_none() || self.children.iter().any(|c| matches!(c.job, Job::Bus)) {
            return;
        }
        let props = "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/pwmt/zathura'";
        let names = format!("type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged',arg0namespace='{ZATHURA}'");
        let mut cmd = Command::new("busctl");
        cmd.args(["--user", "monitor", "--json=short", &format!("--match={props}"), &format!("--match={names}")]);
        self.spawn(&mut cmd, Job::Bus);
        self.suivi.bus_alive = true;
    }

    /// Called with each line `busctl monitor` prints.
    pub(crate) fn bus_line(&mut self, line: &str) {
        let Ok(v) = serde_json::from_str::<Value>(line) else { return };
        let data = &v["payload"]["data"];
        match v["member"].as_str() {
            Some("NameOwnerChanged") => {
                let name = data[0].as_str().unwrap_or("");
                let (old, new) = (data[1].as_str().unwrap_or(""), data[2].as_str().unwrap_or(""));
                if !new.is_empty() {
                    self.register(new, name);
                } else if !old.is_empty() {
                    self.unregister(old);
                }
            }
            Some("PropertiesChanged") => {
                let sender = v["sender"].as_str().unwrap_or("").to_string();
                let changed = &data[1];
                let Some(doc) = self.suivi.docs.get_mut(&sender) else { return };
                if let Some(p) = changed["pagenumber"]["data"].as_u64() {
                    doc.page = p as u32 + 1;
                }
                if let Some(n) = changed["numberofpages"]["data"].as_u64() {
                    doc.pages = n as u32;
                }
                if let Some(f) = changed["filename"]["data"].as_str() {
                    doc.file = PathBuf::from(f);
                    doc.item = None;
                    self.resolve(&sender);
                }
                self.doc_moved(&sender);
            }
            _ => {}
        }
    }

    fn register(&mut self, unique: &str, name: &str) {
        let pid = name.rsplit("PID-").next().and_then(|p| p.parse().ok()).unwrap_or(0);
        let mut doc = Doc { pid, file: PathBuf::new(), item: None, page: 1, pages: 0 };
        let props = busctl_json(&["get-property", name, "/org/pwmt/zathura", ZATHURA, "filename", "pagenumber", "numberofpages"]);
        if let [f, p, n] = props.as_slice() {
            doc.file = PathBuf::from(f["data"].as_str().unwrap_or(""));
            doc.page = p["data"].as_u64().unwrap_or(0) as u32 + 1;
            doc.pages = n["data"].as_u64().unwrap_or(0) as u32;
        }
        self.suivi.docs.insert(unique.to_string(), doc);
        self.resolve(unique);
        self.refresh_hypr();
        self.doc_moved(unique);
    }

    fn unregister(&mut self, unique: &str) {
        let Some(doc) = self.suivi.docs.remove(unique) else { return };
        let now = now_secs();
        let current = |t: &Tracker| t.doc.as_ref().is_some_and(|o| Some(&o.item) == doc.item.as_ref());
        if let Some(t) = self.suivi.tracker.as_mut().filter(|t| current(t)) {
            t.closed(now);
        }
        if self.suivi.free.as_ref().is_some_and(current) {
            self.flush_free();
        }
        if !self.hypr_wanted() {
            self.suivi.hypr = None;
        }
        self.push_status();
    }

    /// Which sheet a window shows, and where its sections start.
    fn resolve(&mut self, unique: &str) {
        let Some(root) = self.store.settings.courses.clone() else { return };
        let Some(doc) = self.suivi.docs.get_mut(unique) else { return };
        doc.item = liseuse::item_of(&doc.file, &root).filter(|i| self.catalogue.get(i).is_some());
        let (file, pages) = (doc.file.clone(), doc.pages);
        if doc.item.is_some() && !self.suivi.maps.contains_key(&file) && which("mutool").is_some() {
            if let Ok(out) = Command::new("mutool").arg("show").arg(&file).arg("outline").output() {
                let outline = liseuse::parse_outline(&String::from_utf8_lossy(&out.stdout));
                self.suivi.maps.insert(file, liseuse::map(&outline, pages));
            }
        }
    }

    fn map_of(&self, item: &str) -> Option<&Map> {
        let doc = self.suivi.docs.values().find(|d| d.item.as_deref() == Some(item))?;
        self.suivi.maps.get(&doc.file)
    }

    /// A window opened, turned a page or changed file.
    fn doc_moved(&mut self, unique: &str) {
        let Some(doc) = self.suivi.docs.get(unique).cloned() else { return };
        let Some(item) = doc.item.clone() else { return };
        let now = now_secs();
        let visible = self.suivi.visible.contains(&doc.pid);

        // "Start" asked for a section: take the window there, once.
        if let Some((goto_item, section)) = self.suivi.goto.clone() {
            if goto_item == item {
                self.suivi.goto = None;
                if let Some(page) = self.suivi.maps.get(&doc.file).and_then(|m| m.page_of(section)).filter(|p| *p > 1) {
                    let name = format!("{ZATHURA}.PID-{}", doc.pid);
                    self.spawn(
                        Command::new("busctl").args(["--user", "call", &name, "/org/pwmt/zathura", ZATHURA, "GotoPage", "u", &(page - 1).to_string()]),
                        Job::Quiet,
                    );
                }
            }
        }

        // A hidden window never takes the place of the one on screen.
        let shown = |t: &Tracker| t.flags.visible && t.doc.as_ref().is_some_and(|o| o.item != item);
        if !visible && self.suivi.tracker.as_ref().or(self.suivi.free.as_ref()).is_some_and(shown) {
            return;
        }
        if let Some(t) = self.suivi.tracker.as_mut() {
            t.set(now, |f| f.visible = visible);
            t.page(now, &item, doc.page, doc.pages);
        } else {
            let t = self.suivi.free.get_or_insert_with(|| Tracker::start(None, now));
            t.set(now, |f| f.visible = visible);
            t.page(now, &item, doc.page, doc.pages);
            // A planned session on this sheet: offer to start it now.
            let today = self.now();
            let offer = self
                .plan
                .sessions
                .iter()
                .filter(|s| Local::new(s.date, s.end) > today && !self.store.state.outcomes.contains_key(&s.id))
                .find(|s| s.parts.iter().any(|p| matches!(&p.work, Work::Study { item: i, .. } | Work::Read { item: i } if *i == item)))
                .map(|s| (s.id.clone(), item.clone()));
            if offer != self.suivi.offer {
                self.suivi.offer = offer;
            }
        }
        if self.suivi.hypr.is_none() {
            self.connect_hypr();
        }
        self.look_around();
        self.save_tracker(false);
        self.push_status();
    }

    /// Free reading becomes a journal line per sheet: pages read, § reached.
    pub(crate) fn flush_free(&mut self) {
        let Some(mut t) = self.suivi.free.take() else { return };
        let now = now_secs();
        t.advance(now);
        let local = self.now();
        let items: Vec<String> = t.dwell.keys().cloned().collect();
        for item in items {
            let (read, _) = t.pages(&item);
            if read.is_empty() {
                continue;
            }
            let upto = self.map_of(&item).map_or(0, |m| m.read_upto(&read));
            let secs: i64 = t.dwell[&item].values().sum();
            let ev = Event::FreeReading { item, upto, pages: read.len() as u32, minutes: (secs / 60) as i32 };
            let _ = self.store.record(ev, local);
        }
        self.suivi.offer = None;
    }

    // ─── Hyprland ────────────────────────────────────────────────────────

    fn connect_hypr(&mut self) {
        if !self.hypr_wanted() {
            return;
        }
        let Some(dir) = hypr_dir() else { return };
        if let Ok(s) = UnixStream::connect(dir.join(".socket2.sock")) {
            set_nonblocking(s.as_raw_fd());
            self.suivi.hypr = Some(s);
        }
    }

    /// Hyprland's events: on anything that can change what is on screen,
    /// ask which windows are visible; on a window opening or closing, look
    /// for a game.
    pub(crate) fn read_hypr(&mut self) {
        let Some(s) = self.suivi.hypr.as_mut() else { return };
        let mut buf = [0u8; 8192];
        let mut gone = false;
        loop {
            match s.read(&mut buf) {
                Ok(0) => {
                    gone = true;
                    break;
                }
                Ok(n) => self.suivi.hypr_buf.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => {
                    gone = true;
                    break;
                }
            }
        }
        if gone {
            self.suivi.hypr = None;
        }
        let mut screen = false;
        let mut windows = false;
        let mut landed: Option<i64> = None;
        while let Some(nl) = self.suivi.hypr_buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.suivi.hypr_buf.drain(..=nl).collect();
            let line = String::from_utf8_lossy(&line);
            let event = line.split(">>").next().unwrap_or("");
            if event == "workspacev2" {
                landed = line.split(">>").nth(1).and_then(|a| a.split(',').next()).and_then(|id| id.trim().parse().ok());
            }
            match event {
                "openwindow" | "closewindow" => {
                    windows = true;
                    screen = true;
                }
                "workspace" | "workspacev2" | "focusedmon" | "focusedmonv2" | "activewindow" | "movewindow" | "movewindowv2"
                | "fullscreen" | "changefloatingmode" | "minimized" | "activespecial" | "activespecialv2" => screen = true,
                _ => {}
            }
        }
        if let Some(ws) = landed {
            self.focus_guard(ws);
        }
        if windows {
            self.check_games();
            self.focus_arrange();
        }
        if screen {
            self.refresh_hypr();
            self.look_around();
            if !windows {
                self.focus_arrange();
            }
        }
    }

    fn refresh_hypr(&mut self) {
        let Some(dir) = hypr_dir() else { return };
        let Ok(mut s) = UnixStream::connect(dir.join(".socket.sock")) else { return };
        let _ = s.set_read_timeout(Some(std::time::Duration::from_millis(500)));
        if s.write_all(b"j/clients").is_err() {
            return;
        }
        let mut out = Vec::new();
        let _ = s.read_to_end(&mut out);
        let Ok(Value::Array(clients)) = serde_json::from_slice::<Value>(&out) else { return };
        let visible: HashSet<u32> = clients
            .iter()
            .filter(|c| c["visible"] == true && c["hidden"] != true && c["mapped"] != false)
            .filter_map(|c| c["pid"].as_u64().map(|p| p as u32))
            .collect();
        if visible == self.suivi.visible {
            return;
        }
        self.suivi.visible = visible;
        let now = now_secs();
        let shown = |t: &Tracker, docs: &HashMap<String, Doc>, vis: &HashSet<u32>| {
            t.doc.as_ref().is_some_and(|o| docs.values().any(|d| d.item.as_ref() == Some(&o.item) && vis.contains(&d.pid)))
        };
        for t in [self.suivi.tracker.as_mut(), self.suivi.free.as_mut()].into_iter().flatten() {
            let v = shown(t, &self.suivi.docs, &self.suivi.visible);
            t.set(now, |f| f.visible = v);
        }
        self.push_status();
    }

    // ─── Games ───────────────────────────────────────────────────────────

    fn check_games(&mut self) {
        let names = &self.store.settings.game_processes;
        let mut running = false;
        if let Ok(rd) = std::fs::read_dir("/proc") {
            for e in rd.flatten() {
                let n = e.file_name();
                if !n.to_string_lossy().bytes().all(|b| b.is_ascii_digit()) {
                    continue;
                }
                if let Ok(comm) = std::fs::read_to_string(e.path().join("comm")) {
                    if names.iter().any(|g| comm.trim() == g) {
                        running = true;
                        break;
                    }
                }
            }
        }
        // The saved session may still believe a game runs: compare with it too.
        let tracked = self.suivi.tracker.as_ref().is_some_and(|t| t.flags.game);
        if running == self.suivi.game && running == tracked {
            return;
        }
        self.suivi.game = running;
        let now = now_secs();
        if let Some(t) = self.suivi.tracker.as_mut() {
            t.set(now, |f| f.game = running);
            // Launched anyway from the gate: the game is over, the session goes on.
            if !running && t.flags.paused {
                t.set(now, |f| f.paused = false);
                if let Some(id) = t.session.clone() {
                    let at = self.now();
                    let _ = self.store.record(Event::Resumed { session: id, at }, at);
                }
            }
        }
        self.save_tracker(true);
        self.push_status();
    }

    // ─── Session ─────────────────────────────────────────────────────────

    /// A session started again (a close undone) is followed again.
    pub(crate) fn suivi_resume(&mut self) {
        if self.suivi.tracker.is_some() {
            return;
        }
        let today = self.now().date.to_string();
        let id = self
            .store
            .state
            .outcomes
            .iter()
            .find(|(id, o)| matches!(o, Outcome::Started { .. }) && id.starts_with(&today))
            .map(|(id, _)| id.clone());
        if let Some(id) = id {
            self.suivi.tracker = Some(Tracker::start(Some(id), now_secs()));
            self.save_tracker(true);
        }
    }

    pub(crate) fn session_started(&mut self, id: &str) {
        let now = now_secs();
        self.flush_free();
        let mut t = Tracker::start(Some(id.to_string()), now);
        t.flags.idle = self.suivi.idle;
        t.flags.media = self.suivi.media;
        self.suivi.tracker = Some(t);
        self.suivi.asked = None;
        // Go to the planned section once the sheet is open.
        let first = self.plan.sessions.iter().find(|s| s.id == id).and_then(|s| {
            s.parts.iter().find_map(|p| match &p.work {
                Work::Study { item, sections: Some((a, _)), .. } => Some((item.clone(), *a)),
                _ => None,
            })
        });
        self.suivi.goto = first;
        self.check_games();
        self.refresh_hypr();
        let open: Vec<String> = self.suivi.docs.keys().cloned().collect();
        for u in open {
            self.doc_moved(&u);
        }
        self.connect_hypr();
        self.save_tracker(true);
    }

    pub(crate) fn session_paused(&mut self, paused: bool) {
        let now = now_secs();
        if let Some(t) = self.suivi.tracker.as_mut() {
            t.set(now, |f| f.paused = paused);
        }
        self.save_tracker(true);
    }

    /// The measures kept with the close; the tracker ends.
    pub(crate) fn session_closed(&mut self, media_for_course: Option<bool>) -> Option<Tracking> {
        let mut t = self.suivi.tracker.take()?;
        t.advance(now_secs());
        let _ = std::fs::remove_file(self.store.paths.data.join("seance.json"));
        if !self.hypr_wanted() {
            self.suivi.hypr = None;
        }
        Some(Tracking {
            idle_minutes: (t.idle_secs / 60) as i32,
            game_minutes: (t.game_secs / 60) as i32,
            media_minutes: (t.media_secs / 60) as i32,
            media_for_course,
            pages: t.dwell.keys().map(|i| (i.clone(), t.pages(i).0.len() as u32)).collect(),
        })
    }

    /// A session from today's plan, or one started another day.
    pub(crate) fn session_any(&self, id: &str) -> Option<crate::plan::Session> {
        self.plan.session(id).cloned().or_else(|| self.store.state.started.get(id).cloned())
    }

    /// The pre-filled close of a session.
    pub(crate) fn draft(&mut self, id: &str) -> Option<Draft> {
        let session = self.session_any(id)?;
        let mut t = self.suivi.tracker.clone().filter(|t| t.session.as_deref() == Some(id)).unwrap_or_default();
        t.advance(now_secs());
        let maps: BTreeMap<String, Map> = t.dwell.keys().filter_map(|i| Some((i.clone(), self.map_of(i)?.clone()))).collect();
        let catalogue = &self.catalogue;
        // Reading sections only: the exercises section is declared, not read.
        let cap = |item: &str| catalogue.get(item).and_then(|i| i.sections.last().map(|s| s.num));
        Some(seance::draft(&t, &session, &maps, &self.store.state.free_reading, cap))
    }

    pub(crate) fn set_activity(&mut self, idle: Option<bool>, media: Option<bool>, title: Option<String>) {
        let now = now_secs();
        if let Some(t) = title {
            self.suivi.media_title = t;
        }
        if let Some(i) = idle {
            self.suivi.idle = i;
        }
        if let Some(m) = media {
            self.suivi.media = m;
        }
        let (i, m) = (self.suivi.idle, self.suivi.media);
        for t in [self.suivi.tracker.as_mut(), self.suivi.free.as_mut()].into_iter().flatten() {
            t.set(now, |f| {
                f.idle = i;
                f.media = m;
            });
        }
        self.look_around();
        self.save_tracker(false);
        self.push_status();
    }

    fn save_tracker(&mut self, now_please: bool) {
        let now = now_secs();
        if !now_please && now - self.suivi.saved < 60 {
            return;
        }
        if let Some(t) = &self.suivi.tracker {
            let _ = store::write_json(&self.store.paths.data.join("seance.json"), t);
            self.suivi.saved = now;
        }
    }

    fn session_end(&self) -> Option<i64> {
        let t = self.suivi.tracker.as_ref()?;
        let s = self.plan.sessions.iter().find(|s| Some(&s.id) == t.session.as_ref())?;
        Some(self.tz.to_utc(Local::new(s.date, s.end)))
    }

    /// The next question's time, for the alarm clock.
    pub(crate) fn suivi_deadline(&self) -> Option<i64> {
        let t = self.suivi.tracker.as_ref()?;
        t.next_prompt(now_secs(), self.session_end()?)
    }

    /// On every wake: questions due, the bus watched, free reading kept.
    pub(crate) fn suivi_tick(&mut self) {
        if !self.suivi.bus_alive {
            self.spawn_bus();
        }
        if self.suivi.hypr.is_none() && self.hypr_wanted() {
            self.connect_hypr();
        }
        let now = now_secs();
        // A session undone or closed elsewhere stops being followed.
        if let Some(id) = self.suivi.tracker.as_ref().and_then(|t| t.session.clone()) {
            if !matches!(self.store.state.outcomes.get(&id), Some(Outcome::Started { .. } | Outcome::Paused { .. })) {
                self.suivi.tracker = None;
            }
        }
        if self.suivi.tracker.is_none() && self.focus_active() {
            self.focus_end();
        }
        if self.suivi.free.as_ref().is_some_and(|t| self.tz.to_local(t.since).date != self.now().date) {
            self.flush_free();
        }
        let Some(end) = self.session_end() else { return };
        let Some(t) = self.suivi.tracker.as_mut() else { return };
        t.advance(now);
        let prompt = t.prompt(now, end);
        let session = t.session.clone();
        if prompt.is_some_and(crate::focus::asked_by_tracker) {
            self.elsewhere_alert();
            self.save_tracker(true);
            return;
        }
        if prompt.is_none() || prompt == self.suivi.asked {
            return;
        }
        self.suivi.asked = prompt;
        if let (Some(id), Some(p)) = (session, prompt) {
            self.prompt_alert(&id, p == Prompt::Closing);
        }
        self.push_status();
    }

    /// "Still working?" answered.
    pub(crate) fn still_working(&mut self, yes: bool) {
        let now = now_secs();
        if let Some(t) = self.suivi.tracker.as_mut() {
            if yes {
                t.on_paper(now);
            } else {
                t.not_working(now);
            }
        }
        self.save_tracker(true);
        self.push_status();
    }

    /// The status's view of the session and of free reading.
    pub(crate) fn suivi_status(&self) -> Value {
        let now = now_secs();
        let doc_json = |t: &Tracker| {
            t.doc.as_ref().map(|o| {
                let section = self.map_of(&o.item).and_then(|m| m.section_at(o.page));
                json!({ "item": o.item, "page": o.page, "pages": o.pages, "section": section })
            })
        };
        let skims = |t: &Tracker| -> Vec<Value> {
            t.skims
                .iter()
                .map(|s| {
                    let domain = s.item.split('/').next().unwrap_or("");
                    let mpp = self.store.state.minutes_per_page(domain).unwrap_or(2.0);
                    json!({ "item": s.item, "pages": s.pages, "estimate_minutes": seance::estimate(s.pages, mpp) })
                })
                .collect()
        };
        let tracking = self.suivi.tracker.as_ref().map(|t| {
            let mut t = t.clone();
            t.advance(now);
            let counting = !(t.flags.idle || t.flags.game || t.flags.paused);
            json!({
                "session": t.session,
                "effective_secs": t.effective,
                "media_secs": t.media_secs,
                // The bar counts from here, without a message every second.
                "counting": counting,
                "as_of": now,
                "flags": t.flags,
                "doc": doc_json(&t),
                "skims": skims(&t),
                "prompt": self.suivi.asked,
                "paper": t.paper,
            })
        });
        let reading = self.suivi.free.as_ref().map(|t| json!({ "doc": doc_json(t), "skims": skims(t) }));
        json!({
            "tracking": tracking,
            "reading": reading,
            "offer": self.suivi.offer.as_ref().map(|(s, i)| json!({ "session": s, "item": i })),
        })
    }
}

/// The status's text lines about tracking, for the command line.
pub(crate) fn status_lines(v: &Value, fr: bool) -> Vec<String> {
    let mut out = Vec::new();
    if let Some(t) = v.get("tracking").filter(|t| !t.is_null()) {
        let min = t["effective_secs"].as_i64().unwrap_or(0) / 60;
        let state = if t["counting"] == true { "" } else if fr { " (en pause)" } else { " (paused)" };
        out.push(if fr { format!("Séance en cours : {min} min effectives{state}.") } else { format!("Session under way: {min} effective min{state}.") });
        if let Some(d) = t.get("doc").filter(|d| !d.is_null()) {
            let sec = d["section"].as_u64().map(|s| format!(" · §{s}")).unwrap_or_default();
            out.push(format!("  {} p. {}/{}{sec}", crate::i18n::item_name(d["item"].as_str().unwrap_or("")), d["page"], d["pages"]));
        }
    }
    for s in v.pointer("/tracking/skims").or(v.pointer("/reading/skims")).and_then(Value::as_array).into_iter().flatten() {
        let name = crate::i18n::item_name(s["item"].as_str().unwrap_or(""));
        out.push(if fr {
            format!("Survol de {name} : {} pages, ~{} min à ton rythme.", s["pages"], s["estimate_minutes"])
        } else {
            format!("Skimmed {name}: {} pages, ~{} min at your pace.", s["pages"], s["estimate_minutes"])
        });
    }
    if let Some(o) = v.get("offer").filter(|o| !o.is_null()) {
        let name = crate::i18n::item_name(o["item"].as_str().unwrap_or(""));
        out.push(if fr {
            format!("Tu lis {name} : démarrer maintenant la séance {} ? (boussole start {})", o["session"].as_str().unwrap_or(""), o["session"].as_str().unwrap_or(""))
        } else {
            format!("You are reading {name}: start session {} now? (boussole start {})", o["session"].as_str().unwrap_or(""), o["session"].as_str().unwrap_or(""))
        });
    }
    out
}
