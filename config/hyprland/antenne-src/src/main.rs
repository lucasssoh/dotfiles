//! Antenne: a TV player for free channels.
//!
//! One window, fullscreen, libmpv drawing into it; a channel card that
//! shows on zap, and the guide (Super+G or Enter) to pick a channel.
//! One instance only: launching it again (Super+G) brings the TV to the
//! workspace you are on, or opens the guide when it is already in front.

mod catalog;
mod epg;
mod guide;
mod health;
mod help;
mod hypr;
mod info;
mod keys;
mod library;
mod loading;
mod logos;
mod mpris;
mod player;
mod search;
mod settings;
mod store;

use catalog::Channel;
use guide::Page;
use gtk4 as gtk;
use gtk::prelude::*;
use gtk::{gdk, gio, glib};
use health::{Health, Probe};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

const APP_ID: &str = "io.github.lucasssoh.Antenne";

enum Msg {
    Catalog(catalog::Catalog),
    /// Every channel iptv-org lists, for "Elsewhere" in the search.
    World(Vec<Channel>),
    /// A check asked from the settings is over.
    Checked(HashMap<String, Probe>),
    Health(HashMap<String, Probe>),
    Race { gen: u64, winner: Option<(usize, Probe)> },
    /// A logo decoded for the guide (None: it could not be had).
    Logo { key: String, small: Option<logos::Small> },
    /// The playing channel's logo file is on disk, for the bar.
    Art { key: String },
    /// "Watch" on a reminder's desktop notification.
    Watch { key: String },
    Guide(epg::Guide),
    /// A show listed from its link (the link, for a failure's message).
    Show(Result<library::Show, String>, String),
    /// A cover decoded for the library.
    Thumb { key: String, small: Option<logos::Small> },
    /// The gamepad service answered (its socket, to write to), or a button.
    PadLink(std::os::unix::net::UnixStream),
    Pad(String),
    PadFamily(String),
    MpvWake,
}

enum MpvEv {
    Restart,
    Failed,
    Ended,
    Reconfig,
    /// mpv waiting for the network (true), or playing again (false).
    Stall(bool),
    Error(String),
}

struct App {
    win: gtk::ApplicationWindow,
    player: Rc<player::Player>,
    guide: Rc<guide::GuideView>,
    epg: RefCell<epg::Guide>,
    u: f64,
    logo_pending: RefCell<HashSet<String>>,
    mpris_now: RefCell<String>,
    shade: gtk::Box,
    digits: gtk::Label,
    help: help::Help,
    info: info::InfoView,
    search: Rc<search::SearchView>,
    settings_view: Rc<settings::SettingsView>,
    lists: RefCell<Vec<catalog::ListStats>>,
    world: RefCell<Option<Vec<Channel>>>,
    world_loading: Cell<bool>,
    /// Channels played from "Elsewhere", so they can be found again.
    extra: RefCell<Vec<Channel>>,
    checking: Cell<bool>,
    /// The settings page `s` opens on: the last one shown.
    last_setting: Cell<Page>,
    library_view: Rc<library::LibraryView>,
    lib: RefCell<library::Library>,
    /// The show opened, and its group shown.
    lib_open: Cell<Option<usize>>,
    lib_group: Cell<usize>,
    /// Links being listed.
    lib_pending: RefCell<Vec<String>>,
    /// What each Continue watching card is: (show, group, episode).
    lib_cont: RefCell<Vec<(usize, usize, usize)>>,
    thumbs: RefCell<HashMap<String, gdk::Texture>>,
    thumb_pending: RefCell<HashSet<String>>,
    thumb_gen: Cell<u64>,
    /// The episode playing, and the line the glance says for it.
    playing_ep: Cell<Option<(usize, usize, usize)>>,
    ep_line: RefCell<HashMap<String, String>>,
    start_at: Cell<Option<f64>>,
    /// The next episode, waiting its 5 s.
    pending_next: Cell<Option<(usize, usize, usize)>>,
    next_gen: Cell<u64>,
    /// The gamepad service, to ask for the pads while Antenne is in front.
    pad: RefCell<Option<std::os::unix::net::UnixStream>>,
    /// The middle of the screen while nothing plays: loading, waiting, failed.
    loading: loading::LoadingView,
    /// What played before (Esc on a failure goes back to it).
    prev_key: RefCell<Option<String>>,
    last_error: RefCell<Option<String>>,
    stalled: Cell<bool>,
    buffer_gen: Cell<u64>,
    /// The next episode, bottom right, during the credits.
    next_card: info::NextCard,
    /// "Watch credits": no next episode this time.
    next_cancel: Cell<bool>,
    /// Episodes started on their own in a row, with no key pressed.
    autoplay_run: Cell<u32>,
    /// "Still watching?" asked, for this next episode.
    asking: Cell<Option<(usize, usize, usize)>>,
    /// What the actions menu is about: an episode, or a show (group usize::MAX).
    menu_target: Cell<Option<(usize, usize, usize)>>,
    menu_confirm: Cell<bool>,
    alarm: gtk::Box,
    alarm_title: gtk::Label,
    alarm_ch: gtk::Label,
    alarm_bar: gtk::ProgressBar,
    alarm_key: RefCell<Option<String>>,
    alarm_gen: Cell<u64>,
    toast: gtk::Label,
    toast_gen: Cell<u64>,
    mpris: Rc<mpris::Mpris>,
    paused: Cell<bool>,
    tx: async_channel::Sender<Msg>,

    channels: RefCell<Vec<Channel>>,
    health: RefCell<Health>,
    settings: RefCell<store::Settings>,
    state: RefCell<store::State>,

    cur: RefCell<Option<String>>,
    gen: Cell<u64>,
    order: RefCell<Vec<usize>>,
    tried: RefCell<Vec<usize>>,
    cur_src: Cell<Option<usize>>,
    started: Cell<bool>,

    guide_open: Cell<bool>,
    cat: RefCell<String>,
    osd_gen: Cell<u64>,
    digit_buf: RefCell<String>,
    digit_gen: Cell<u64>,
    hint_gen: Cell<u64>,
    cursor_gen: Cell<u64>,

    last_tick: Cell<i64>,
    win_size: Cell<(i32, i32)>,
    /// The picture's display aspect, from mpv (16:9 until it says).
    video_aspect: Cell<f64>,
    volume: Cell<f64>,
    volume_gen: Cell<u64>,
    stalls: RefCell<Vec<i64>>,
    stall_gen: Cell<u64>,
    weak: gtk::Box,
    weak_text: gtk::Label,
    weak_gen: Cell<u64>,
    low_quality: Cell<bool>,
    suspended: Cell<bool>,
    video_on: Cell<bool>,
    dnd_prev: Arc<Mutex<Option<bool>>>,
}

/// GTK CSS has no em that follows the screen, so sizes are written in
/// units of `u` (about 1/72 of the screen height, 15 px at 1080p) and
/// turned into pixels here: the guide reads the same on a laptop and a TV.
fn css(u: f64) -> String {
    let tpl = include_str!("style.css");
    let mut out = String::with_capacity(tpl.len());
    let mut rest = tpl;
    while let Some(i) = rest.find("{{") {
        out.push_str(&rest[..i]);
        let Some(j) = rest[i..].find("}}") else { break };
        let n: f64 = rest[i + 2..i + j].trim().parse().unwrap_or(1.0);
        out.push_str(&format!("{}px", (n * u).round().max(1.0)));
        rest = &rest[i + j + 2..];
    }
    out.push_str(rest);
    out
}

impl App {
    fn find(&self, key: &str) -> Option<Channel> {
        let own = self.channels.borrow().iter().find(|c| c.key == key).cloned();
        own.or_else(|| self.extra.borrow().iter().find(|c| c.key == key).cloned())
    }

    fn is_fav(&self, key: &str) -> bool {
        self.state.borrow().favourites.iter().any(|k| k == key)
    }

    fn alive(&self) -> Vec<Channel> {
        let h = self.health.borrow();
        self.channels.borrow().iter().filter(|c| h.alive(&c.sources)).cloned().collect()
    }

    fn list(&self, cat: &str) -> Vec<Channel> {
        self.alive()
            .into_iter()
            .filter(|c| match cat {
                "All" => true,
                "Favourites" => self.is_fav(&c.key),
                _ => c.category == cat,
            })
            .collect()
    }

    /// Favourites first (when there are any), All, then categories by size.
    fn categories(&self) -> Vec<String> {
        let alive = self.alive();
        let mut counts: HashMap<String, usize> = HashMap::new();
        for c in &alive {
            *counts.entry(c.category.clone()).or_default() += 1;
        }
        let mut cats: Vec<(String, usize)> = counts.into_iter().collect();
        cats.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        let mut out = vec![];
        if alive.iter().any(|c| self.is_fav(&c.key)) {
            out.push("Favourites".to_string());
        }
        out.push("All".to_string());
        out.extend(cats.into_iter().map(|(c, _)| c));
        out
    }

    // ---- the glance and the sheet ------------------------------------------

    /// What the fade shows about a channel; `status` in place of the
    /// programme ("Connecting…", "No source answers").
    fn info_data(&self, c: &Channel, status: Option<&str>) -> info::InfoData {
        let h = self.health.borrow();
        let order = h.order(&c.sources);
        let playing = if self.cur.borrow().as_deref() == Some(c.key.as_str()) { self.cur_src.get() } else { None };
        let sources = order
            .iter()
            .map(|&i| {
                let s = &c.sources[i];
                let p = h.probes.get(&s.url);
                info::SourceLine {
                    origin: s.origin.clone(),
                    quality: s.quality.clone(),
                    ms: p.filter(|p| p.ok).map(|p| p.ms),
                    playing: playing == Some(i) && self.started.get(),
                    dead: p.is_some_and(|p| !p.ok),
                }
            })
            .collect();
        drop(h);
        let lists = {
            let mut o: Vec<&str> = c.sources.iter().map(|s| s.origin.as_str()).collect();
            o.sort();
            o.dedup();
            o.len()
        };
        let mut facts = vec![c.category.clone()];
        facts.extend(c.quality().map(str::to_string));
        if !c.country.is_empty() {
            facts.push(catalog::country_name(&c.country));
        }
        facts.push(if lists == 1 { "1 list".to_string() } else { format!("{lists} lists") });
        let now = store::now() as i64;
        let epg = self.epg.borrow();
        let mut on = epg.at(&c.key, now).map(|p| (p.title.clone(), format!("{} – {}", epg::hm(p.start), epg::hm(p.stop)), (now - p.start) as f64 / (p.stop - p.start).max(1) as f64));
        let mut next: Vec<(String, String)> = epg.of(&c.key).iter().filter(|p| p.start > now).take(3).map(|p| (epg::hm(p.start), p.title.clone())).collect();
        drop(epg);
        // a recording playing: where it is, and for an episode what follows
        let playback = self.cur.borrow().as_deref() == Some(c.key.as_str()) && self.recording();
        if playback {
            let title = match self.playing_ep.get().and_then(|at| self.episode(at).map(|e| (at, e))) {
                Some((at, e)) => format!("{} · {}", self.ep_label(at), e.title),
                None => c.name.clone(),
            };
            let (pos, dur) = self.player.position().unwrap_or((0.0, 0.0));
            let clock = |t: f64| {
                let t = t.max(0.0) as u64;
                if t >= 3600 { format!("{}:{:02}:{:02}", t / 3600, t / 60 % 60, t % 60) } else { format!("{}:{:02}", t / 60, t % 60) }
            };
            let time = if dur > 0.0 { format!("{} / {}{}", clock(pos), clock(dur), if self.paused.get() { "   ·   Paused" } else { "" }) } else { String::new() };
            on = Some((title, time, if dur > 0.0 { pos / dur } else { 0.0 }));
            next = self.playing_ep.get().and_then(|at| self.after(at)).and_then(|n| self.episode(n).map(|e| (self.ep_label(n), e.title))).into_iter().collect();
        }
        info::InfoData {
            number: c.number,
            name: c.name.clone(),
            logo: self.playing_ep.get().filter(|_| c.key.starts_with("ep:")).and_then(|at| self.episode(at)).and_then(|e| self.thumb(&e.thumb).map(|t| (t, false))).or_else(|| self.guide.logo(&c.key)),
            facts,
            now: on,
            next,
            sources,
            favourite: self.is_fav(&c.key),
            status: status.map(str::to_string),
            playback,
            paused: self.paused.get(),
            episode: playback && self.playing_ep.get().is_some(),
        }
    }

    /// The glance, for `ms`; with the sheet open, the sheet follows instead.
    fn show_osd(self: &Rc<Self>, c: &Channel, status: Option<&str>, ms: u64) {
        if self.guide_open.get() {
            return;
        }
        let full = self.info.level() == 2;
        self.info.fill(&self.info_data(c, status), full);
        if full {
            return;
        }
        self.info.set_level(1);
        let g = self.osd_gen.get() + 1;
        self.osd_gen.set(g);
        self.tick_playback(g);
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_millis(ms), move || {
            if let Some(me) = me.upgrade() {
                if me.osd_gen.get() == g && me.info.level() == 1 && !(me.paused.get() && me.recording()) {
                    me.info.set_level(0);
                }
            }
        });
    }

    /// A recording's time, kept current while the glance or the sheet shows it.
    fn tick_playback(self: &Rc<Self>, g: u64) {
        if !self.recording() {
            return;
        }
        let me = Rc::downgrade(self);
        glib::timeout_add_local(Duration::from_millis(500), move || {
            let Some(me) = me.upgrade() else { return glib::ControlFlow::Break };
            if me.osd_gen.get() != g || me.info.level() == 0 || !me.recording() || me.guide_open.get() {
                return glib::ControlFlow::Break;
            }
            match me.playback_now() {
                Some((time, frac)) if me.info.has_playback() => me.info.update_playback(&time, frac, me.paused.get()),
                _ => me.refresh_info(),
            }
            glib::ControlFlow::Continue
        });
    }

    /// "12:34 / 22:10", and how far, for the recording playing.
    fn playback_now(&self) -> Option<(String, f64)> {
        let (pos, dur) = self.player.position()?;
        let clock = |t: f64| {
            let t = t.max(0.0) as u64;
            if t >= 3600 { format!("{}:{:02}:{:02}", t / 3600, t / 60 % 60, t % 60) } else { format!("{}:{:02}", t / 60, t % 60) }
        };
        Some((format!("{} / {}{}", clock(pos), clock(dur), if self.paused.get() { "   ·   Paused" } else { "" }), pos / dur))
    }

    /// A click on the glance's controls.
    fn control(self: &Rc<Self>, c: info::Control) {
        use info::Control::*;
        match c {
            Back => self.player.seek(-10.0),
            Forward => self.player.seek(10.0),
            SeekTo(f) => self.player.seek_to(f),
            Toggle => return self.command(mpris::Command::PlayPause),
            Previous | Next => {
                if let Some(at) = self.playing_ep.get() {
                    if let Some(n) = if matches!(c, Next) { self.after(at) } else { self.before(at) } {
                        self.play_episode(n);
                    }
                }
                return;
            }
        }
        self.show_current(4000);
    }

    /// What plays is a recording (an episode, a video, a page), not a channel.
    fn recording(&self) -> bool {
        let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) else { return false };
        self.started.get() && self.cur_src.get().and_then(|i| c.sources.get(i)).is_some_and(|s| catalog::is_recording(&s.url))
    }

    fn show_current(self: &Rc<Self>, ms: u64) {
        let key = self.cur.borrow().clone();
        if let Some(c) = key.and_then(|k| self.find(&k)) {
            self.show_osd(&c, None, ms);
        }
    }

    fn set_tuning(&self, on: bool) {
        if on {
            self.shade.add_css_class("on");
        } else {
            self.shade.remove_css_class("on");
        }
    }

    // ---- playing: race the fastest sources, fall back silently ---------

    fn play(self: &Rc<Self>, key: &str) {
        let Some(c) = self.find(key) else { return };
        if !key.starts_with("ep:") {
            self.playing_ep.set(None);
            self.start_at.set(None);
        }
        self.pending_next.set(None);
        // Esc on a failure goes back to what played last, and played
        let before = self.cur.borrow().clone();
        if before.as_deref() != Some(key) && self.started.get() {
            *self.prev_key.borrow_mut() = before;
        }
        self.last_error.borrow_mut().take();
        self.stalled.set(false);
        self.next_card.hide();
        self.next_cancel.set(false);
        let title = self.ep_line.borrow().get(key).and_then(|l| l.split_once(" · ").map(|(_, t)| t.to_string())).filter(|_| key.starts_with("ep:")).unwrap_or_else(|| c.name.clone());
        self.loading.loading(&title, "Connecting…");
        *self.cur.borrow_mut() = Some(key.to_string());
        {
            let mut st = self.state.borrow_mut();
            st.last = Some(key.to_string());
            store::save(&store::state_path(), &*st);
        }
        let gen = self.gen.get() + 1;
        self.gen.set(gen);
        let order = self.health.borrow().order(&c.sources);
        *self.order.borrow_mut() = order.clone();
        self.tried.borrow_mut().clear();
        self.cur_src.set(None);
        self.started.set(false);
        self.set_tuning(true);
        if self.info.level() == 1 {
            self.info.set_level(0);
        }
        self.guide.set_playing(Some(key));
        self.guide.set_watching(&format!("Connecting   {}", c.name));
        if self.paused.replace(false) {
            self.player.set_pause(false, true);
        }
        self.fade_volume(0.0, 120);
        self.stalls.borrow_mut().clear();
        self.weak_gen.set(self.weak_gen.get() + 1);
        self.weak.remove_css_class("show");
        if self.low_quality.replace(false) {
            self.player.set_low_quality(false);
        }
        let artist = self.mpris_artist(&c);
        *self.mpris_now.borrow_mut() = artist.clone();
        self.mpris.set_track(&c.name, &artist, logo_art(key));
        self.mpris.set_playing(false);
        self.ensure_logo(&c);

        let cand: Vec<usize> = order.iter().take(3).copied().collect();
        let sources: Vec<catalog::Source> = cand.iter().map(|&i| c.sources[i].clone()).collect();
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let w = health::race(sources, Duration::from_secs(4));
            let _ = tx.send_blocking(Msg::Race { gen, winner: w.map(|(j, p)| (cand[j], p)) });
        });
    }

    fn on_race(self: &Rc<Self>, gen: u64, winner: Option<(usize, Probe)>) {
        if gen != self.gen.get() {
            return;
        }
        let idx = match winner {
            Some((i, p)) => {
                if let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) {
                    self.health.borrow_mut().probes.insert(c.sources[i].url.clone(), p);
                }
                i
            }
            None => match self.order.borrow().first() {
                Some(&i) => i,
                None => return,
            },
        };
        self.load_source(idx);
    }

    fn load_source(self: &Rc<Self>, i: usize) {
        let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) else { return };
        let Some(s) = c.sources.get(i) else { return };
        self.tried.borrow_mut().push(i);
        self.cur_src.set(Some(i));
        let n = self.tried.borrow().len();
        if n > 1 && !self.started.get() {
            let title = self.loading_title(&c);
            self.loading.loading(&title, &format!("Source {n} of {}", self.order.borrow().len()));
        }
        self.player.load_at(&s.url, s.user_agent.as_deref().unwrap_or(catalog::BROWSER_UA), s.referrer.as_deref(), self.start_at.take());
        // A source that has not shown a frame after 12 s counts as dead.
        let gen = self.gen.get();
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_secs(12), move || {
            if let Some(me) = me.upgrade() {
                if me.gen.get() == gen && !me.started.get() && me.cur_src.get() == Some(i) {
                    me.fail_source();
                }
            }
        });
    }

    /// The current source died (or never started): mark it, and go on to
    /// the next one without a word. Only when none is left does the card
    /// say so.
    fn fail_source(self: &Rc<Self>) {
        let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) else { return };
        if let Some(i) = self.cur_src.get() {
            self.health.borrow_mut().probes.insert(c.sources[i].url.clone(), Probe { ok: false, ms: 0, at: store::now() });
        }
        self.started.set(false);
        let next = {
            let tried = self.tried.borrow();
            self.order.borrow().iter().copied().find(|i| !tried.contains(i))
        };
        match next {
            Some(i) => self.load_source(i),
            None => {
                self.cur_src.set(None);
                self.mpris.set_playing(false);
                self.guide.set_watching(&format!("Not answering   {}", c.name));
                self.show_failure(&c);
            }
        }
    }

    fn on_mpv(self: &Rc<Self>) {
        let evs: Vec<MpvEv> = self
            .player
            .drain()
            .into_iter()
            .map(|e| match e {
                player::MpvEvent::Restart => MpvEv::Restart,
                player::MpvEvent::Failed => MpvEv::Failed,
                player::MpvEvent::Ended => MpvEv::Ended,
                player::MpvEvent::Reconfig => MpvEv::Reconfig,
                player::MpvEvent::Stall(b) => MpvEv::Stall(b),
                player::MpvEvent::Error(e) => MpvEv::Error(e),
            })
            .collect();
        for ev in evs {
            debug(&format!(
                "mpv {} (started {})",
                match &ev {
                    MpvEv::Restart => "restart".to_string(),
                    MpvEv::Failed => "failed".to_string(),
                    MpvEv::Ended => "ended".to_string(),
                    MpvEv::Reconfig => "reconfig".to_string(),
                    MpvEv::Stall(b) => format!("stall {b}"),
                    MpvEv::Error(e) => format!("error {e}"),
                },
                self.started.get()
            ));
            match ev {
                MpvEv::Restart if self.started.get() => self.fade_volume(100.0, 600),
                MpvEv::Restart if !self.started.get() && self.cur_src.get().is_some() => {
                    self.started.set(true);
                    self.fade_volume(100.0, 600);
                    self.mpris.set_playing(!self.paused.get());
                    if let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) {
                        self.guide.set_watching(&format!("Watching   {}", c.name));
                    }
                    self.set_tuning(false);
                    self.loading.hide();
                    self.show_current(4000);
                }
                MpvEv::Failed if self.cur_src.get().is_some() => self.fail_source(),
                // a recording that played to its end: mpv goes on to the next
                // one of a playlist, or stops; a live stream cut is a failure
                MpvEv::Ended if self.cur_src.get().is_some() => {
                    let rec = self.started.get() && self.cur.borrow().clone().and_then(|k| self.find(&k)).zip(self.cur_src.get()).and_then(|(c, i)| c.sources.get(i).map(|s| catalog::is_recording(&s.url))).unwrap_or(false);
                    if !rec {
                        self.fail_source();
                    } else {
                        self.episode_ended();
                    }
                }
                MpvEv::Error(e) => *self.last_error.borrow_mut() = Some(e),
                MpvEv::Stall(true) if self.started.get() => {
                    self.on_stall();
                    self.waiting(true);
                }
                MpvEv::Stall(false) if self.started.get() && !self.paused.get() => {
                    self.waiting(false);
                    self.stall_gen.set(self.stall_gen.get() + 1);
                    self.fade_volume(100.0, 150);
                }
                MpvEv::Reconfig => {
                    let a = self.player.mpv.borrow().get_property::<f64>("video-params/aspect").unwrap_or(0.0);
                    if a > 0.3 && a < 4.0 && (a - self.video_aspect.get()).abs() > 0.01 {
                        self.video_aspect.set(a);
                        self.apply_insets();
                    }
                }
                _ => {}
            }
        }
    }

    // ---- zapping, digits, favourites -----------------------------------

    fn zap(self: &Rc<Self>, d: i32) {
        let cur = self.cur.borrow().clone();
        let mut list = self.list(&self.cat.borrow());
        if !list.iter().any(|c| Some(&c.key) == cur.as_ref()) {
            list = self.alive();
        }
        if list.is_empty() {
            return;
        }
        let i = cur.and_then(|k| list.iter().position(|c| c.key == k)).map(|i| i as i32).unwrap_or(-d.signum());
        let n = list.len() as i32;
        let next = (((i + d) % n) + n) % n;
        let key = list[next as usize].key.clone();
        self.play(&key);
    }

    fn digit(self: &Rc<Self>, ch: char) {
        let buf = {
            let mut b = self.digit_buf.borrow_mut();
            b.push(ch);
            b.clone()
        };
        self.digits.set_text(&if buf.len() < 3 { format!("{buf}_") } else { buf.clone() });
        self.digits.add_css_class("show");
        let g = self.digit_gen.get() + 1;
        self.digit_gen.set(g);
        let me = Rc::downgrade(self);
        let wait = if buf.len() >= 3 { 200 } else { 1200 };
        glib::timeout_add_local_once(Duration::from_millis(wait), move || {
            let Some(me) = me.upgrade() else { return };
            if me.digit_gen.get() != g {
                return;
            }
            let n: u32 = me.digit_buf.borrow().parse().unwrap_or(0);
            me.digit_buf.borrow_mut().clear();
            me.digits.remove_css_class("show");
            let key = me.alive().into_iter().find(|c| c.number == n).map(|c| c.key);
            if let Some(k) = key {
                me.play(&k);
            }
        });
    }

    fn toggle_fav(self: &Rc<Self>, key: &str) {
        {
            let mut st = self.state.borrow_mut();
            if let Some(i) = st.favourites.iter().position(|k| k == key) {
                st.favourites.remove(i);
            } else {
                st.favourites.push(key.to_string());
            }
            store::save(&store::state_path(), &*st);
        }
        if self.guide_open.get() {
            self.fill_guide(Some(key), true);
        } else if let Some(c) = self.find(key) {
            self.show_osd(&c, None, 2000);
        }
    }

    // ---- the guide --------------------------------------------------------

    fn fill_guide(self: &Rc<Self>, select: Option<&str>, keep_time: bool) {
        let cats = self.categories();
        if !cats.contains(&self.cat.borrow()) {
            *self.cat.borrow_mut() = cats.first().cloned().unwrap_or_else(|| "All".into());
        }
        let cat = self.cat.borrow().clone();
        let tabs: Vec<(String, usize)> = cats.iter().map(|c| (c.clone(), self.list(c).len())).collect();
        self.guide.set_categories(tabs, &cat);
        self.guide.set_reminders(self.reminder_set());
        let cur = self.cur.borrow().clone();
        let want = select.map(str::to_string).or(cur.clone());
        let rows: Vec<guide::RowData> = {
            let epg = self.epg.borrow();
            self.list(&cat)
                .into_iter()
                .map(|c| guide::RowData { progs: epg.of(&c.key).to_vec(), key: c.key, number: c.number, name: c.name })
                .collect()
        };
        self.guide.set_rows(rows, want.as_deref(), cur.as_deref(), keep_time);
    }

    fn open_guide(self: &Rc<Self>, open: bool) {
        if open {
            self.open_page(Page::Guide, false);
        } else {
            self.close_guide();
        }
    }

    fn close_guide(self: &Rc<Self>) {
        if !self.guide_open.replace(false) {
            return;
        }
        let (pw, ph) = self.guide.split(self.win.width(), self.win.height());
        self.player_to_pip(false, pw, ph);
        self.guide.root.remove_css_class("show");
        self.guide.root.set_can_target(false);
        self.guide.set_nav_focus(false);
        self.release_keyboard();
        self.refresh_help();
        self.apply_insets();
    }

    /// The guide open on `page`, the keyboard in the column (`column`) or
    /// in the page: the grid on the channel playing, the search field, or
    /// a setting's first control.
    fn open_page(self: &Rc<Self>, page: Page, column: bool) {
        let was = self.guide_open.replace(true);
        self.info.set_level(0);
        if self.loading.state() == loading::State::Buffering {
            self.loading.hide();
        }
        if !was {
            let (pw, ph) = self.guide.split(self.win.width(), self.win.height());
            self.player_to_pip(true, pw, ph);
            self.guide.root.add_css_class("show");
            self.guide.root.set_can_target(true);
        }
        self.guide.set_cats_focus(false);
        self.guide.set_page(page);
        self.guide.set_nav_focus(column);
        self.show_page(page);
        if !column {
            self.enter_page();
        } else {
            self.release_keyboard();
        }
        self.refresh_summaries();
        if !was {
            self.focus_current_tab();
            // after the shrink has been laid out, so the rows centre on the
            // real height; fresh: the selection on the channel playing and
            // the programme on now, whatever was picked last time
            let me = Rc::downgrade(self);
            self.guide.root.add_tick_callback(move |_, _| {
                if let Some(me) = me.upgrade() {
                    me.fill_guide(None, false);
                }
                glib::ControlFlow::Break
            });
        }
        self.refresh_help();
        self.apply_insets();
    }

    /// What a page shows, when its entry is picked.
    fn show_page(self: &Rc<Self>, page: Page) {
        if !page.is_library() {
            self.guide.set_custom_head(None);
        }
        match page {
            Page::Guide => {}
            Page::Continue | Page::Shows => {
                self.library_view.set_adding(false);
                if page == Page::Shows {
                    self.refresh_stale_shows();
                }
                self.render_library(false);
            }
            Page::Search => {
                let q = self.search.query();
                self.run_search(&q);
                self.load_world();
            }
            p => {
                self.last_setting.set(p);
                if p == Page::Countries {
                    self.load_world();
                }
                self.render_settings();
            }
        }
    }

    /// The keyboard from the column to the page picked.
    fn enter_page(self: &Rc<Self>) {
        self.guide.set_nav_focus(false);
        match self.guide.page() {
            Page::Guide | Page::Continue | Page::Shows => self.release_keyboard(),
            Page::Search => self.search.focus(),
            _ => self.settings_view.focus_first(),
        }
        self.refresh_help();
    }

    /// The keyboard back to the column.
    fn to_column(&self) {
        self.guide.set_cats_focus(false);
        self.guide.set_nav_focus(true);
        self.release_keyboard();
        self.refresh_help();
    }

    fn move_nav(self: &Rc<Self>, d: i32) {
        let before = self.guide.page();
        let p = self.guide.move_nav(d);
        if p != before {
            self.show_page(p);
        }
    }

    /// No widget keeps the keyboard: left in a field, h j k l would go on
    /// typing instead of moving.
    fn release_keyboard(&self) {
        GtkWindowExt::set_focus(&self.win, None::<&gtk::Widget>);
    }

    /// What each entry of the column says under its name.
    fn refresh_summaries(&self) {
        let s = self.settings.borrow();
        let alive = self.alive().len();
        let q = self.search.query();
        let mine = catalog::my_sources_path().display().to_string();
        let lists = self.lists.borrow().iter().filter(|l| l.spec != mine).count().max(s.playlists.len()) + catalog::my_sources().len();
        let every = match s.check_every_hours {
            1 => "Every hour".to_string(),
            24 => "Once a day".to_string(),
            h => format!("Every {h} hours"),
        };
        let fr = s.countries.iter().any(|c| c.eq_ignore_ascii_case("fr"));
        let on = [s.open_last, s.logos, s.lower_on_weak, s.autonext].iter().filter(|b| **b).count();
        let started = self.continue_list().len();
        let shows = self.lib.borrow().shows.len();
        let sums = vec![
            if q.is_empty() { "Channels and programmes".to_string() } else { format!("“{q}”") },
            format!("{alive} channels"),
            match started {
                0 => "Nothing started".to_string(),
                1 => "1 episode".to_string(),
                n => format!("{n} episodes"),
            },
            match (self.lib_open.get().and_then(|si| self.lib.borrow().shows.get(si).map(|s| (s.name.clone(), if s.groups.len() > 1 { s.group_name(self.lib_group.get()) } else { String::new() }))), shows) {
                (Some((name, g)), _) if g.is_empty() => name,
                (Some((name, g)), _) => format!("{name} · {g}"),
                (None, 0) => "None yet".to_string(),
                (None, 1) => "1 show".to_string(),
                (None, n) => format!("{n} shows"),
            },
            if s.countries.is_empty() { "None".to_string() } else { s.countries.iter().map(|c| catalog::country_name(c)).collect::<Vec<_>>().join(", ") },
            match lists {
                0 => "None".to_string(),
                1 => "1 source".to_string(),
                n => format!("{n} sources"),
            },
            if self.checking.get() {
                "Checking…".to_string()
            } else if self.health.borrow().last_check > 0 {
                format!("Checked {}", epg::day_at(self.health.borrow().last_check as i64))
            } else {
                every
            },
            if fr { "xmltvfr.fr".to_string() } else { "None".to_string() },
            match on {
                4 => "All on".to_string(),
                0 => "All off".to_string(),
                n => format!("{n} of 4 on"),
            },
        ];
        drop(s);
        self.guide.set_summaries(sums);
    }

    /// iptv-org's whole list, for the search's "Elsewhere" and the
    /// countries one can add; read once, in the background.
    fn load_world(&self) {
        if self.world.borrow().is_none() && !self.world_loading.replace(true) {
            let tx = self.tx.clone();
            std::thread::spawn(move || {
                let _ = tx.send_blocking(Msg::World(catalog::load_world()));
            });
        }
    }

    fn settings_shown(&self) -> bool {
        self.guide_open.get() && self.guide.page().is_settings()
    }

    fn search_shown(&self) -> bool {
        self.guide_open.get() && self.guide.page() == Page::Search
    }

    /// The tab shown must hold the channel playing, or opening the guide
    /// could not select it: keep the tab when it does, else take the
    /// channel's own category (All when even that is missing).
    fn focus_current_tab(&self) {
        let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) else { return };
        let cat = self.cat.borrow().clone();
        if self.list(&cat).iter().any(|x| x.key == c.key) {
            return;
        }
        let tab = if self.categories().contains(&c.category) { c.category.clone() } else { "All".to_string() };
        *self.cat.borrow_mut() = tab;
    }

    /// While the guide is open the picture takes the top right of the upper
    /// half: nothing is covered, nothing has to be drawn twice.
    fn player_to_pip(&self, on: bool, pw: i32, ph: i32) {
        let (a, u) = (&self.player.area, self.u);
        if on {
            a.set_hexpand(false);
            a.set_vexpand(false);
            a.set_halign(gtk::Align::End);
            a.set_valign(gtk::Align::Start);
            a.set_size_request(pw, ph);
            a.set_margin_top((1.6 * u).round() as i32);
            a.set_margin_end((2.0 * u).round() as i32);
            self.loading.fit(Some((pw, ph, (1.6 * u).round() as i32, (2.0 * u).round() as i32)));
        } else {
            a.set_hexpand(true);
            a.set_vexpand(true);
            a.set_halign(gtk::Align::Fill);
            a.set_valign(gtk::Align::Fill);
            a.set_size_request(-1, -1);
            a.set_margin_top(0);
            a.set_margin_end(0);
            self.loading.fit(None);
        }
    }

    fn toggle_help(&self) {
        self.help.hint.remove_css_class("show");
        self.help.set_open(!self.help.is_open());
        self.refresh_help();
    }

    /// What floats over the picture sits inside it, never astride the edge
    /// of the black bars: a 16:9 channel on a 16:10 screen leaves 60 px top
    /// and bottom, and a card at a fixed margin from the window straddled
    /// that line. The bars are worked out as mpv draws them; with the guide
    /// open the picture is small and the margins go back to the window's.
    fn apply_insets(&self) {
        let (w, h) = (self.win.width() as f64, self.win.height() as f64);
        let (side, top) = if self.guide_open.get() || w < 1.0 || h < 1.0 {
            (0, 0)
        } else {
            let a = self.video_aspect.get();
            if w / h > a {
                (((w - h * a) / 2.0).round() as i32, 0)
            } else {
                (0, ((h - w / a) / 2.0).round() as i32)
            }
        };
        self.digits.set_margin_top(top);
        self.digits.set_margin_end(side);
        self.alarm.set_margin_top(top);
        self.alarm.set_margin_end(side);
        self.info.set_insets(side, top);
        self.next_card.set_insets(side, top);
        self.help.hint.set_margin_bottom(top);
        self.help.hint.set_margin_end(side);
        self.toast.set_margin_bottom(top);
        self.weak.set_margin_top(top);
        self.weak.set_margin_end(side);
        self.weak.set_visible(!self.guide_open.get());
    }

    /// The list's block that matches what is on screen.
    fn refresh_help(&self) {
        let ctx = if self.alarm.has_css_class("show") {
            help::Context::Reminder
        } else if !self.guide_open.get() && self.recording() {
            help::Context::Streaming
        } else if !self.guide_open.get() {
            help::Context::Watching
        } else if !self.guide.nav_focus() && self.guide.page().is_library() {
            help::Context::Shows
        } else if self.guide.nav_focus() || self.guide.page() != Page::Guide {
            help::Context::Column
        } else if self.guide.cats_focus() {
            help::Context::Tabs
        } else {
            help::Context::Guide
        };
        self.help.set_context(ctx);
    }

    /// A key that does nothing: say which key lists them, for 2.5 s.
    fn key_hint(self: &Rc<Self>) {
        self.help.hint.add_css_class("show");
        let g = self.hint_gen.get() + 1;
        self.hint_gen.set(g);
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_millis(2500), move || {
            if let Some(me) = me.upgrade() {
                if me.hint_gen.get() == g {
                    me.help.hint.remove_css_class("show");
                }
            }
        });
    }

    fn move_category(self: &Rc<Self>, d: i32) {
        let cats = self.categories();
        let i = cats.iter().position(|c| *c == *self.cat.borrow()).unwrap_or(0) as i32;
        let n = cats.len() as i32;
        *self.cat.borrow_mut() = cats[(((i + d) % n + n) % n) as usize].clone();
        self.fill_guide(None, true);
    }

    /// Logos, read from the cache or downloaded once, then decoded and
    /// scaled on four worker threads. Called for every channel as soon as
    /// the list is known, so the guide never shows a placeholder; and for
    /// the rows in view, for any straggler. A logo that failed is
    /// not retried before the next launch.
    fn fetch_logos(self: &Rc<Self>, keys: Vec<String>) {
        if !self.settings.borrow().logos {
            return;
        }
        let mut todo = vec![];
        for k in keys {
            if self.guide.has_logo(&k) || self.logo_pending.borrow().contains(&k) {
                continue;
            }
            let path = logos::path_for(&k);
            let url = self.find(&k).and_then(|c| c.logo);
            if url.is_none() && !logos::fresh(&path) {
                continue;
            }
            self.logo_pending.borrow_mut().insert(k.clone());
            todo.push((k, url, path));
        }
        if todo.is_empty() {
            return;
        }
        let (bw, bh) = self.guide.logo_box();
        let queue = Arc::new(Mutex::new(todo));
        for _ in 0..4 {
            let (tx, queue) = (self.tx.clone(), queue.clone());
            std::thread::spawn(move || loop {
                let Some((key, url, path)) = queue.lock().ok().and_then(|mut q| q.pop()) else { break };
                let ok = logos::fresh(&path) || url.is_some_and(|u| logos::fetch(&u, &path));
                let small = if ok { logos::decode(&path, bw, bh) } else { None };
                let _ = tx.send_blocking(Msg::Logo { key, small });
            });
        }
    }

    // ---- sound and a weak connection -------------------------------------

    /// Eases mpv's volume to `to` (0-100) over `ms`: out on a zap or a
    /// stall, in when the picture comes back. A later fade replaces it.
    fn fade_volume(self: &Rc<Self>, to: f64, ms: u64) {
        let g = self.volume_gen.get() + 1;
        self.volume_gen.set(g);
        let from = self.volume.get();
        debug(&format!("fade {from:.0} -> {to:.0} in {ms} ms"));
        if (from - to).abs() < 0.5 {
            return;
        }
        let started = std::time::Instant::now();
        let me = Rc::downgrade(self);
        glib::timeout_add_local(Duration::from_millis(16), move || {
            let Some(me) = me.upgrade() else { return glib::ControlFlow::Break };
            if me.volume_gen.get() != g {
                return glib::ControlFlow::Break;
            }
            let k = (started.elapsed().as_millis() as f64 / ms.max(1) as f64).min(1.0);
            let eased = k * k * (3.0 - 2.0 * k);
            let v = from + (to - from) * eased;
            me.volume.set(v);
            me.player.set_volume(v);
            if k >= 1.0 { glib::ControlFlow::Break } else { glib::ControlFlow::Continue }
        });
    }

    /// mpv is waiting for the network: the sound drops out softly. Three
    /// stalls within a minute, or one longer than 3 s, is a weak connection.
    fn on_stall(self: &Rc<Self>) {
        self.fade_volume(0.0, 40);
        let now = store::now() as i64;
        let count = {
            let mut s = self.stalls.borrow_mut();
            s.retain(|t| now - t < 60);
            s.push(now);
            s.len()
        };
        if count >= 3 {
            self.weak_connection();
            return;
        }
        let g = self.stall_gen.get() + 1;
        self.stall_gen.set(g);
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_secs(3), move || {
            if let Some(me) = me.upgrade() {
                if me.stall_gen.get() == g {
                    me.weak_connection();
                }
            }
        });
    }

    /// A quiet cue, top right inside the picture, which shrinks to its
    /// bars after 5 s; and, unless turned off, the lowest quality from now
    /// on this channel (a reload of the same source, without a word).
    fn weak_connection(self: &Rc<Self>) {
        if !self.weak.has_css_class("show") {
            self.weak.remove_css_class("compact");
            self.weak_text.set_visible(true);
            self.weak.add_css_class("show");
            let g = self.weak_gen.get() + 1;
            self.weak_gen.set(g);
            let me = Rc::downgrade(self);
            glib::timeout_add_local_once(Duration::from_secs(5), move || {
                if let Some(me) = me.upgrade() {
                    if me.weak_gen.get() == g {
                        me.weak.add_css_class("compact");
                        me.weak_text.set_visible(false);
                    }
                }
            });
        }
        if self.settings.borrow().lower_on_weak && !self.low_quality.get() {
            self.low_quality.set(true);
            self.weak_text.set_text("Weak connection   ·   lower quality");
            self.player.set_low_quality(true);
            let src = self.cur.borrow().clone().and_then(|k| self.find(&k)).zip(self.cur_src.get());
            if let Some((c, i)) = src {
                if let Some(s) = c.sources.get(i) {
                    self.player.load(&s.url, s.user_agent.as_deref().unwrap_or(catalog::BROWSER_UA), s.referrer.as_deref());
                }
            }
        } else if !self.low_quality.get() {
            self.weak_text.set_text("Weak connection");
        }
    }

    /// Three quiet minutes: the cue goes. The lower quality stays until
    /// the next channel.
    fn check_connection(&self) {
        let now = store::now() as i64;
        let last = self.stalls.borrow().last().copied();
        if self.weak.has_css_class("show") && last.is_none_or(|t| now - t > 180) {
            self.weak.remove_css_class("show");
        }
    }

    // ---- the actions menu (m) -------------------------------------------------------

    /// m on a card or an episode: what can be done with it.
    fn open_menu(self: &Rc<Self>) {
        let page = self.guide.page();
        let sel = self.library_view.selected();
        let ep_acts = |at: (usize, usize, usize), cont: bool| -> Vec<(library::Act, String)> {
            let done = self.episode(at).and_then(|e| self.progress_of(&e.url)).is_some_and(|p| p.done);
            let mut v = vec![(library::Act::Watched(!done), if done { "Mark as unwatched" } else { "Mark as watched" }.to_string()), (library::Act::Restart, "Play from the beginning".to_string())];
            if cont {
                v.push((library::Act::RemoveFromContinue, "Remove from Continue watching".to_string()));
            }
            v
        };
        let (target, title, acts) = match (page, self.lib_open.get()) {
            (Page::Continue, _) => match self.lib_cont.borrow().get(sel).copied() {
                Some(at) => (at, self.episode(at).map(|e| e.title).unwrap_or_default(), ep_acts(at, true)),
                None => return,
            },
            (Page::Shows, Some(si)) => {
                let at = (si, self.lib_group.get(), sel);
                (at, self.episode(at).map(|e| e.title).unwrap_or_default(), ep_acts(at, false))
            }
            (Page::Shows, None) => {
                let Some(name) = self.lib.borrow().shows.get(sel).map(|s| s.name.clone()) else { return };
                ((sel, usize::MAX, 0), name, vec![(library::Act::Refresh, "Look for new episodes".to_string()), (library::Act::RemoveShow, "Remove show".to_string())])
            }
            _ => return,
        };
        self.menu_target.set(Some(target));
        self.menu_confirm.set(false);
        self.library_view.menu.open(&title, acts);
    }

    fn menu_act(self: &Rc<Self>, act: library::Act) {
        let Some(at) = self.menu_target.get() else { return };
        let menu = &self.library_view.menu;
        match act {
            library::Act::Watched(on) => {
                if let Some(e) = self.episode(at) {
                    let mut st = self.state.borrow_mut();
                    if on {
                        let d = e.duration as f64;
                        st.progress.insert(e.url, store::Progress { pos: d, dur: d, done: true, at: store::now() });
                    } else {
                        st.progress.remove(&e.url);
                    }
                    store::save(&store::state_path(), &*st);
                }
            }
            library::Act::Restart => {
                menu.close();
                return self.play_episode_at(at, true);
            }
            library::Act::RemoveFromContinue => {
                if let Some(url) = self.lib.borrow().shows.get(at.0).map(|s| s.url.clone()) {
                    let mut st = self.state.borrow_mut();
                    if !st.hidden_continue.contains(&url) {
                        st.hidden_continue.push(url);
                    }
                    store::save(&store::state_path(), &*st);
                }
            }
            library::Act::Refresh => {
                if let Some(url) = self.lib.borrow().shows.get(at.0).map(|s| s.url.clone()) {
                    self.show_toast("Looking for new episodes…");
                    let tx = self.tx.clone();
                    std::thread::spawn(move || {
                        let r = library::fetch(&url);
                        let _ = tx.send_blocking(Msg::Show(r, url));
                    });
                }
            }
            library::Act::RemoveShow => {
                // asked once more, in place
                if !self.menu_confirm.replace(true) {
                    let name = self.lib.borrow().shows.get(at.0).map(|s| s.name.clone()).unwrap_or_default();
                    menu.relabel(&format!("Remove {name}? Press again"));
                    return;
                }
                let name = {
                    let mut lib = self.lib.borrow_mut();
                    if at.0 >= lib.shows.len() {
                        return;
                    }
                    lib.shows.remove(at.0).name
                };
                self.lib.borrow().save();
                self.lib_open.set(None);
                self.show_toast(&format!("{name} removed"));
            }
        }
        menu.close();
        self.render_library(true);
    }

    // ---- loading, waiting, failing --------------------------------------------

    /// What the loading view names: the episode's title, or the channel's.
    fn loading_title(&self, c: &Channel) -> String {
        self.ep_line.borrow().get(&c.key).and_then(|l| l.split_once(" · ").map(|(_, t)| t.to_string())).filter(|_| c.key.starts_with("ep:")).unwrap_or_else(|| c.name.clone())
    }

    /// The network is late: a small ring, after half a second (a short
    /// wait does not blink).
    fn waiting(self: &Rc<Self>, on: bool) {
        self.stalled.set(on);
        let g = self.buffer_gen.get() + 1;
        self.buffer_gen.set(g);
        if !on {
            if self.loading.state() == loading::State::Buffering {
                self.loading.hide();
            }
            return;
        }
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_millis(500), move || {
            if let Some(me) = me.upgrade() {
                // over the guide, the small picture says enough
                if me.buffer_gen.get() == g && me.stalled.get() && !me.guide_open.get() && me.loading.state() == loading::State::Hidden {
                    me.loading.buffering();
                }
            }
        });
    }

    /// Nothing could be played: why, and the ways out, in the middle.
    fn show_failure(self: &Rc<Self>, c: &Channel) {
        self.set_tuning(true);
        let rec = c.sources.first().is_some_and(|s| catalog::is_recording(&s.url));
        let prev = self.prev_key.borrow().clone().filter(|k| *k != c.key).and_then(|k| self.find(&k));
        let back = prev.map(|p| (loading::Choice::Back, format!("Back to {}", p.name), keys::Action::Back));
        let mut choices = vec![(loading::Choice::Retry, "Try again".to_string(), keys::Action::Ok)];
        let (title, reason) = if rec {
            let url = c.sources.first().map(|s| s.url.clone()).unwrap_or_default();
            let host = catalog::host_of(&url);
            let site = if host.contains("youtube") || host.contains("youtu.be") { "YouTube".to_string() } else { host };
            let reason = match self.last_error.borrow().as_deref() {
                Some(e) => loading::reason(e, &site),
                None => format!("{site} didn't send the video."),
            };
            if self.playing_ep.get().and_then(|at| self.after(at)).is_some() {
                choices.push((loading::Choice::Third, "Next episode".into(), keys::Action::Step));
            }
            choices.extend(back);
            (format!("“{}” can't be played", self.loading_title(c)), reason)
        } else {
            let n = c.sources.len();
            choices.extend(back);
            choices.push((loading::Choice::Third, "Guide".into(), keys::Action::Step));
            let _ = n;
            let reason = "It may be back later.".to_string();
            (format!("{} isn't answering", c.name), reason)
        };
        let choices: Vec<(loading::Choice, String, keys::Action)> = choices;
        self.loading.failed(&title, &reason, &choices);
    }

    /// A way out of a failure.
    fn load_choice(self: &Rc<Self>, ch: loading::Choice) {
        if let Some(n) = self.asking.take() {
            self.loading.hide();
            self.set_tuning(false);
            match ch {
                loading::Choice::Retry => {
                    self.autoplay_run.set(0);
                    self.play_episode(n);
                }
                _ => self.open_episode(n),
            }
            return;
        }
        let cur = self.cur.borrow().clone();
        let rec = cur.as_ref().and_then(|k| self.find(k)).and_then(|c| c.sources.first().map(|s| catalog::is_recording(&s.url))).unwrap_or(false);
        match ch {
            loading::Choice::Retry => {
                if let Some(k) = cur {
                    if let Some(at) = self.playing_ep.get().filter(|_| k.starts_with("ep:")) {
                        self.play_episode(at);
                    } else {
                        self.play(&k);
                    }
                }
            }
            loading::Choice::Back => match self.prev_key.borrow().clone() {
                Some(p) => {
                    self.prev_key.borrow_mut().take();
                    self.play(&p);
                }
                None => {
                    self.loading.hide();
                    self.set_tuning(false);
                }
            },
            loading::Choice::Third if rec => {
                if let Some(n) = self.playing_ep.get().and_then(|at| self.after(at)) {
                    self.play_episode(n);
                }
            }
            loading::Choice::Third => self.open_guide(true),
        }
    }

    // ---- the gamepad ------------------------------------------------------------

    /// The pads for Antenne while it is in front (the bar's popup still
    /// takes them when Guide is pressed, and gives them back).
    fn pad_grab(&self, on: bool) {
        use std::io::Write;
        let line = if on { "{\"cmd\":\"app-grab\"}\n" } else { "{\"cmd\":\"app-release\"}\n" };
        let failed = self.pad.borrow_mut().as_mut().is_some_and(|s| s.write_all(line.as_bytes()).is_err());
        if failed {
            self.pad.borrow_mut().take();
        }
    }

    // ---- streaming ------------------------------------------------------------

    fn episode(&self, (si, g, i): (usize, usize, usize)) -> Option<library::Episode> {
        self.lib.borrow().shows.get(si)?.groups.get(g)?.episodes.get(i).cloned()
    }

    fn progress_of(&self, url: &str) -> Option<store::Progress> {
        self.state.borrow().progress.get(url).cloned()
    }

    /// The episode after (show, group, episode): the next in its group,
    /// else the first of the next group.
    fn after(&self, (si, g, i): (usize, usize, usize)) -> Option<(usize, usize, usize)> {
        let lib = self.lib.borrow();
        let show = lib.shows.get(si)?;
        if i + 1 < show.groups.get(g)?.episodes.len() {
            Some((si, g, i + 1))
        } else {
            (g + 1..show.groups.len()).find(|&n| !show.groups[n].episodes.is_empty()).map(|n| (si, n, 0))
        }
    }

    /// The episode before: the previous in its group, else the last of the
    /// group before.
    fn before(&self, (si, g, i): (usize, usize, usize)) -> Option<(usize, usize, usize)> {
        if i > 0 {
            return Some((si, g, i - 1));
        }
        let lib = self.lib.borrow();
        let show = lib.shows.get(si)?;
        (0..g).rev().find(|&n| !show.groups[n].episodes.is_empty()).map(|n| (si, n, show.groups[n].episodes.len() - 1))
    }

    /// Where a show stands: the episode to resume (with how far it went),
    /// or the next one, or its first (never started: `true`).
    fn next_of(&self, si: usize) -> ((usize, usize, usize), Option<f64>, bool) {
        let mut last: Option<((usize, usize, usize), store::Progress)> = None;
        if let Some(show) = self.lib.borrow().shows.get(si) {
            let st = self.state.borrow();
            for (g, grp) in show.groups.iter().enumerate() {
                for (i, e) in grp.episodes.iter().enumerate() {
                    if let Some(p) = st.progress.get(&e.url) {
                        if last.as_ref().is_none_or(|(_, q)| p.at > q.at) {
                            last = Some(((si, g, i), p.clone()));
                        }
                    }
                }
            }
        }
        match last {
            Some((at, p)) if !p.done => (at, Some(p.pos / p.dur.max(1.0)), false),
            Some((at, _)) => (self.after(at).unwrap_or(at), None, false),
            None => ((si, 0, 0), None, true),
        }
    }

    /// The episodes started (or whose next is waiting), the latest first.
    fn continue_list(&self) -> Vec<((usize, usize, usize), Option<f64>, u64)> {
        let n = self.lib.borrow().shows.len();
        let mut out = vec![];
        for si in 0..n {
            let (at, f, fresh) = self.next_of(si);
            let hidden = self.lib.borrow().shows.get(si).is_some_and(|s| self.state.borrow().hidden_continue.contains(&s.url));
            if fresh || hidden {
                continue;
            }
            let when = {
                let lib = self.lib.borrow();
                let st = self.state.borrow();
                lib.shows[si].groups.iter().flat_map(|g| g.episodes.iter()).filter_map(|e| st.progress.get(&e.url).map(|p| p.at)).max().unwrap_or(0)
            };
            if f.is_some() || self.episode(at).is_some_and(|e| !self.progress_of(&e.url).is_some_and(|p| p.done)) {
                out.push((at, f, when));
            }
        }
        out.sort_by(|a, b| b.2.cmp(&a.2));
        out
    }

    /// "Îles Orange · E7" (the group's name only when there are several).
    fn ep_label(&self, (si, g, i): (usize, usize, usize)) -> String {
        let lib = self.lib.borrow();
        let Some(show) = lib.shows.get(si) else { return String::new() };
        if show.groups.len() > 1 {
            format!("{} · E{}", show.group_name(g), i + 1)
        } else {
            format!("E{}", i + 1)
        }
    }

    fn minutes(secs: f64) -> String {
        format!("{} min", (secs / 60.0).round().max(1.0) as u32)
    }

    fn thumb(&self, url: &Option<String>) -> Option<gdk::Texture> {
        url.as_ref().and_then(|u| self.thumbs.borrow().get(u).cloned())
    }

    /// Covers, fetched once and cached like the logos, cropped to 16:9.
    fn fetch_thumbs(&self, urls: Vec<String>) {
        let mut todo = vec![];
        for u in urls {
            if self.thumbs.borrow().contains_key(&u) || !self.thumb_pending.borrow_mut().insert(u.clone()) {
                continue;
            }
            todo.push(u);
        }
        if todo.is_empty() {
            return;
        }
        let scale = self.win.scale_factor().max(1) as f64;
        let (w, h) = ((10.5 * self.u * scale).round() as u32, (10.5 * self.u * scale * 9.0 / 16.0).round() as u32);
        let queue = Arc::new(Mutex::new(todo));
        for _ in 0..4 {
            let (tx, queue) = (self.tx.clone(), queue.clone());
            std::thread::spawn(move || loop {
                let Some(url) = queue.lock().ok().and_then(|mut q| q.pop()) else { break };
                let path = logos::path_for(&format!("thumb:{url}"));
                let ok = logos::fresh(&path) || logos::fetch(&url, &path);
                let small = if ok { logos::decode_cover(&path, w, h) } else { None };
                let _ = tx.send_blocking(Msg::Thumb { key: url, small });
            });
        }
    }

    /// Continue watching, the shows, or a show's episodes.
    fn render_library(self: &Rc<Self>, keep: bool) {
        let page = self.guide.page();
        let sel = if keep { self.library_view.selected() } else { 0 };
        let mut want = vec![];
        if page == Page::Continue {
            let list = self.continue_list();
            *self.lib_cont.borrow_mut() = list.iter().map(|c| c.0).collect();
            let cards = list
                .iter()
                .filter_map(|&(at, f, _)| {
                    let e = self.episode(at)?;
                    want.extend(e.thumb.clone());
                    let left = f.map(|f| format!(" · {} left", Self::minutes(e.duration as f64 * (1.0 - f)))).unwrap_or_else(|| " · Next".into());
                    let name = self.lib.borrow().shows[at.0].name.clone();
                    Some(library::Card { title: name.clone(), sub: format!("{}{}", self.ep_label(at), left), progress: f.or(Some(0.0)).filter(|_| f.is_some()), thumb: self.thumb(&e.thumb), initials: catalog::initials(&name) })
                })
                .collect();
            self.library_view.set_cards(cards, sel, "Nothing started yet", keep);
        } else if let Some(si) = self.lib_open.get().filter(|&si| si < self.lib.borrow().shows.len()) {
            let g = self.lib_group.get();
            let (tabs, eps) = {
                let lib = self.lib.borrow();
                let show = &lib.shows[si];
                let tabs: Vec<(String, usize)> = (0..show.groups.len()).map(|i| (show.group_name(i), show.groups[i].episodes.len())).collect();
                (tabs, show.groups.get(g).map(|x| x.episodes.clone()).unwrap_or_default())
            };
            let tabs = if tabs.len() <= 1 { vec![("Episodes".to_string(), eps.len())] } else { tabs };
            let rows = eps
                .iter()
                .enumerate()
                .map(|(i, e)| {
                    want.extend(e.thumb.clone());
                    let p = self.progress_of(&e.url);
                    let done = p.as_ref().is_some_and(|p| p.done);
                    let f = p.as_ref().filter(|p| !p.done && p.pos > 30.0).map(|p| p.pos / p.dur.max(1.0));
                    let dur = if e.duration > 0 { Self::minutes(e.duration as f64) } else { String::new() };
                    let sub = match (f, done) {
                        (Some(f), _) => format!("{dur} · {} left", Self::minutes(e.duration as f64 * (1.0 - f))),
                        (None, true) => format!("{dur} · Watched"),
                        _ => dur,
                    };
                    library::EpRow { n: i + 1, title: e.title.clone(), sub: sub.trim_start_matches(" · ").to_string(), progress: f, done, thumb: self.thumb(&e.thumb) }
                })
                .collect();
            self.library_view.set_episodes(tabs, g, rows, sel, keep);
        } else {
            let pending = self.lib_pending.borrow().clone();
            let mut cards: Vec<library::Card> = vec![];
            let n = self.lib.borrow().shows.len();
            for si in 0..n {
                let (at, f, fresh) = self.next_of(si);
                let (name, size, origin, first_thumb) = {
                    let lib = self.lib.borrow();
                    let s = &lib.shows[si];
                    (s.name.clone(), s.size(), s.origin.clone(), s.groups.first().and_then(|g| g.episodes.first()).and_then(|e| e.thumb.clone()))
                };
                want.extend(first_thumb.clone());
                let sub = if fresh { format!("{size} · {origin}") } else { format!("Next: {}", self.ep_label(at)) };
                cards.push(library::Card { title: name.clone(), sub, progress: if fresh { None } else { Some(f.unwrap_or(0.0)) }, thumb: self.thumb(&first_thumb), initials: catalog::initials(&name) });
            }
            for p in &pending {
                cards.push(library::Card { title: catalog::host_of(p), sub: "Loading the episodes…".into(), progress: None, thumb: None, initials: "…".into() });
            }
            cards.push(library::Card { title: "Add a show".into(), sub: "A link or a folder".into(), progress: None, thumb: None, initials: "+".into() });
            self.library_view.set_cards(cards, sel, "", keep);
        }
        self.fetch_thumbs(want);
        self.lib_head();
        self.refresh_summaries();
    }

    /// The header: the show or episode picked.
    fn lib_head(&self) {
        let page = self.guide.page();
        let sel = self.library_view.selected();
        let ep_head = |at: (usize, usize, usize)| -> Option<guide::Head> {
            let e = self.episode(at)?;
            let show = self.lib.borrow().shows[at.0].name.clone();
            let p = self.progress_of(&e.url);
            let f = p.as_ref().filter(|p| !p.done && p.pos > 30.0).map(|p| p.pos / p.dur.max(1.0));
            let dur = if e.duration > 0 { Self::minutes(e.duration as f64) } else { String::new() };
            let time = match (f, p.as_ref().is_some_and(|p| p.done)) {
                (Some(f), _) => format!("{dur}   ·   {} left", Self::minutes(e.duration as f64 * (1.0 - f))),
                (None, true) => format!("{dur}   ·   Watched"),
                _ => dur,
            };
            let what = self.ep_label(at).replace("E", "Episode ");
            let (action, action2) = match f {
                Some(f) => (format!("▶   Resume · {} left", Self::minutes(e.duration as f64 * (1.0 - f))), "↺   From the beginning".to_string()),
                None => ("▶   Play".to_string(), String::new()),
            };
            Some(guide::Head { logo: self.thumb(&e.thumb), initials: catalog::initials(&show), line: format!("{show}   ·   {what}"), title: e.title.clone(), time, bar: f, action, action_key: true, action2, more: true, desc: String::new() })
        };
        let head = match page {
            Page::Continue => self.lib_cont.borrow().get(sel).copied().and_then(ep_head),
            Page::Shows => match self.lib_open.get() {
                Some(si) => ep_head((si, self.lib_group.get(), sel)),
                None => {
                    let n = self.lib.borrow().shows.len();
                    if sel < n {
                        let (at, f, fresh) = self.next_of(sel);
                        let e = self.episode(at);
                        let label = self.ep_label(at);
                        let lib = self.lib.borrow();
                        let s = &lib.shows[sel];
                        let left = match (f, &e) {
                            (Some(f), Some(e)) => format!(" · {} left", Self::minutes(e.duration as f64 * (1.0 - f))),
                            _ => String::new(),
                        };
                        Some(guide::Head {
                            logo: self.thumb(&s.groups.first().and_then(|g| g.episodes.first()).and_then(|e| e.thumb.clone())),
                            initials: catalog::initials(&s.name),
                            line: if s.groups.len() > 1 { format!("{}   ·   {}   ·   {} episodes", s.origin, s.size(), s.episodes()) } else { format!("{}   ·   {}", s.origin, s.size()) },
                            title: s.name.clone(),
                            time: String::new(),
                            bar: None,
                            action: format!("▶   {} · {label}{left}", if fresh { "Play" } else { "Resume" }),
                            action_key: false,
                            action2: String::new(),
                            more: true,
                            desc: String::new(),
                        })
                    } else {
                        Some(guide::Head {
                            logo: None,
                            initials: "+".into(),
                            line: "Streaming".into(),
                            title: "Add a show".into(),
                            time: "A YouTube channel or playlist, an M3U playlist, or a folder of videos.".into(),
                            bar: None,
                            action: String::new(),
                            action_key: false,
                            action2: String::new(),
                            more: false,
                            desc: "<span fgalpha=\"55%\">The docs explain how each one is split into seasons.</span>".into(),
                        })
                    }
                }
            },
            _ => None,
        };
        if head.is_some() {
            self.guide.set_custom_head(head);
        }
    }

    /// The guide on Shows, the show open on that episode.
    fn open_episode(self: &Rc<Self>, (si, g, i): (usize, usize, usize)) {
        self.lib_open.set(Some(si));
        self.lib_group.set(g);
        self.open_page(Page::Shows, false);
        self.library_view.select(i);
        self.lib_head();
    }

    /// Enter on a card or an episode.
    fn lib_activate(self: &Rc<Self>, i: usize) {
        match self.guide.page() {
            Page::Continue => {
                if let Some(at) = self.lib_cont.borrow().get(i).copied() {
                    self.play_episode(at);
                }
            }
            Page::Shows => match self.lib_open.get() {
                Some(si) => self.play_episode((si, self.lib_group.get(), i)),
                None => {
                    let n = self.lib.borrow().shows.len();
                    let pending = self.lib_pending.borrow().len();
                    if i < n {
                        let (at, _, _) = self.next_of(i);
                        self.lib_open.set(Some(i));
                        self.lib_group.set(at.1);
                        self.render_library(false);
                        self.library_view.select(at.2);
                        self.lib_head();
                    } else if i >= n + pending {
                        self.library_view.set_adding(true);
                    }
                }
            },
            _ => {}
        }
    }

    /// From a show's episodes back to all the shows, on the one that was open.
    fn lib_back(self: &Rc<Self>) {
        let si = self.lib_open.take().unwrap_or(0);
        self.render_library(false);
        self.library_view.select(si);
        self.lib_head();
        self.refresh_summaries();
    }

    fn lib_tab(self: &Rc<Self>, d: i32) {
        let Some(si) = self.lib_open.get() else { return };
        let n = self.lib.borrow().shows.get(si).map(|s| s.groups.len()).unwrap_or(1) as i32;
        let g = (self.lib_group.get() as i32 + d).clamp(0, n - 1) as usize;
        if g != self.lib_group.get() {
            self.lib_group.set(g);
            self.render_library(false);
        }
    }

    /// A show's link, listed in the background.
    fn add_show(self: &Rc<Self>, url: String) {
        self.library_view.set_adding(false);
        self.release_keyboard();
        self.lib_pending.borrow_mut().push(url.clone());
        self.render_library(true);
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let r = library::fetch(&url);
            let _ = tx.send_blocking(Msg::Show(r, url));
        });
    }

    /// Once a day, each show is listed again for its new episodes.
    fn refresh_stale_shows(&self) {
        let stale: Vec<String> = self.lib.borrow().shows.iter().filter(|s| s.version < library::VERSION || store::now().saturating_sub(s.fetched) > 86_400).map(|s| s.url.clone()).collect();
        let pending = self.lib_pending.borrow().clone();
        for url in stale.into_iter().filter(|u| !pending.contains(u)) {
            let tx = self.tx.clone();
            std::thread::spawn(move || {
                if let Ok(s) = library::fetch(&url) {
                    let _ = tx.send_blocking(Msg::Show(Ok(s), url));
                }
            });
        }
    }

    fn play_episode(self: &Rc<Self>, at: (usize, usize, usize)) {
        self.play_episode_at(at, false);
    }

    /// `from_start`: from its first second, even if it was started.
    fn play_episode_at(self: &Rc<Self>, at: (usize, usize, usize), from_start: bool) {
        let Some(e) = self.episode(at) else { return };
        let url = self.lib.borrow().shows.get(at.0).map(|s| s.url.clone()).unwrap_or_default();
        self.state.borrow_mut().hidden_continue.retain(|u| *u != url);
        let (show, origin) = {
            let lib = self.lib.borrow();
            (lib.shows[at.0].name.clone(), lib.shows[at.0].origin.clone())
        };
        let key = format!("ep:{}", e.url);
        if self.find(&key).is_none() {
            self.extra.borrow_mut().push(Channel {
                key: key.clone(),
                name: show,
                category: "Streaming".into(),
                sources: vec![catalog::Source { url: e.url.clone(), user_agent: None, referrer: None, quality: None, origin }],
                number: 0,
                logo: None,
                country: String::new(),
            });
        }
        self.ep_line.borrow_mut().insert(key.clone(), format!("{} · {}", self.ep_label(at), e.title));
        let resume = self.progress_of(&e.url).filter(|p| !from_start && !p.done && p.pos > 30.0 && p.pos < p.dur - 30.0).map(|p| p.pos);
        self.start_at.set(resume);
        self.pending_next.set(None);
        self.playing_ep.set(Some(at));
        self.play(&key);
        self.close_guide();
    }

    /// Every 5 s while an episode plays: where it is, kept.
    fn save_progress(self: &Rc<Self>) {
        let Some(at) = self.playing_ep.get() else { return };
        if !self.started.get() || !self.cur.borrow().as_deref().is_some_and(|k| k.starts_with("ep:")) {
            return;
        }
        let Some((pos, dur)) = self.player.position() else { return };
        let Some(e) = self.episode(at) else { return };
        {
            let mut st = self.state.borrow_mut();
            st.progress.insert(e.url, store::Progress { pos, dur, done: pos > dur - 30.0, at: store::now() });
            store::save(&store::state_path(), &*st);
        }
        if !self.paused.get() {
            self.check_credits(pos, dur);
        }
    }

    /// The last 25 s of an episode: the next one shows, bottom right,
    /// counting down; seeking back takes it away.
    fn check_credits(self: &Rc<Self>, pos: f64, dur: f64) {
        let Some(at) = self.playing_ep.get() else { return };
        let left = dur - pos;
        if self.next_card.shown() {
            if left > 30.0 {
                self.next_card.hide();
            }
            return;
        }
        if self.next_cancel.get() || !self.settings.borrow().autonext || dur < 120.0 || left > 25.0 {
            return;
        }
        let Some(n) = self.after(at) else { return };
        let Some(e) = self.episode(n) else { return };
        let show = self.lib.borrow().shows.get(n.0).map(|s| s.name.clone()).unwrap_or_default();
        self.next_card.show(self.thumb(&e.thumb), &catalog::initials(&show), &format!("{} · {}", self.ep_label(n), e.title));
        self.next_card.set_when(&format!("Starts in {} s", left.ceil() as u64));
        let me = Rc::downgrade(self);
        glib::timeout_add_local(Duration::from_millis(500), move || {
            let Some(me) = me.upgrade() else { return glib::ControlFlow::Break };
            if !me.next_card.shown() {
                return glib::ControlFlow::Break;
            }
            if let Some((pos, dur)) = me.player.position() {
                me.next_card.set_when(&format!("Starts in {} s", (dur - pos).max(0.0).ceil() as u64));
                if dur - pos > 30.0 {
                    me.next_card.hide();
                }
            }
            glib::ControlFlow::Continue
        });
    }

    /// The next episode on its own: after three in a row with no key
    /// pressed, asked first.
    fn autoplay(self: &Rc<Self>, next: (usize, usize, usize)) {
        if self.autoplay_run.get() >= 3 {
            let show = self.lib.borrow().shows.get(next.0).map(|s| s.name.clone()).unwrap_or_default();
            self.asking.set(Some(next));
            self.set_tuning(true);
            self.loading.ask(
                &format!("Still watching {show}?"),
                "Paused after three episodes in a row.",
                &[(loading::Choice::Retry, "Continue watching".into(), keys::Action::Ok), (loading::Choice::Back, "Back to the show".into(), keys::Action::Back)],
            );
            return;
        }
        self.autoplay_run.set(self.autoplay_run.get() + 1);
        self.play_episode(next);
    }

    /// The end of an episode: watched; the next one in 5 s unless Esc.
    fn episode_ended(self: &Rc<Self>) {
        let Some(at) = self.playing_ep.get() else { return };
        if let Some(e) = self.episode(at) {
            let mut st = self.state.borrow_mut();
            let dur = e.duration as f64;
            st.progress.insert(e.url, store::Progress { pos: dur, dur, done: true, at: store::now() });
            store::save(&store::state_path(), &*st);
        }
        let Some(next) = self.after(at) else { return };
        if !self.settings.borrow().autonext {
            return;
        }
        // the credits card was on screen: straight on, or nothing if Esc
        if self.next_card.shown() || self.next_cancel.get() {
            let go = self.next_card.shown() && !self.next_cancel.get();
            self.next_card.hide();
            if go {
                self.autoplay(next);
            }
            return;
        }
        let Some(ne) = self.episode(next) else { return };
        self.pending_next.set(Some(next));
        let g = self.next_gen.get() + 1;
        self.next_gen.set(g);
        if let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) {
            self.show_osd(&c, Some(&format!("Next: {} · {}   ·   in 5 s, Esc to stay", self.ep_label(next), ne.title)), 5500);
        }
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_secs(5), move || {
            if let Some(me) = me.upgrade() {
                if me.next_gen.get() == g {
                    if let Some(n) = me.pending_next.take() {
                        me.autoplay(n);
                    }
                }
            }
        });
    }

    // ---- search, info, settings ----------------------------------------------

    /// `/`: the guide on Search, the keyboard in the field.
    fn open_search(self: &Rc<Self>) {
        self.open_page(Page::Search, false);
    }

    /// Yours first: matched on the cleaned name, the number or the
    /// category, then on a programme still to come; then, from iptv-org's
    /// whole list, the channels you do not have. With nothing typed: the
    /// favourites.
    fn run_search(self: &Rc<Self>, q: &str) {
        let q = q.trim();
        let nq = epg::norm(q);
        let now = store::now() as i64;
        let matches = |c: &Channel| {
            !nq.is_empty() && (epg::norm(&c.name).contains(&nq) || c.number.to_string() == q || epg::norm(&c.category).starts_with(&nq))
        };
        let h = self.health.borrow();
        let epg = self.epg.borrow();
        let channels = self.channels.borrow();
        let hit = |c: &Channel, prog: Option<&epg::Prog>, group: &'static str| {
            let dead = !h.alive(&c.sources);
            let on = epg.at(&c.key, now);
            let (sub, progress) = match (prog, on) {
                (Some(p), _) => (format!("{} · {}", p.title, if p.start <= now { "now".to_string() } else { epg::hm(p.start) }), None),
                _ if dead => ("Not answering".to_string(), None),
                (None, Some(p)) => (format!("{} · until {}", p.title, epg::hm(p.stop)), Some((now - p.start) as f64 / (p.stop - p.start).max(1) as f64)),
                (None, None) => (c.category.clone(), None),
            };
            search::Hit { key: c.key.clone(), tag: c.number.to_string(), name: c.name.clone(), sub, group, dead, progress, logo: self.guide.logo(&c.key), glyph: None }
        };
        let mut hits = vec![];
        if let Some(kind) = catalog::link_kind(q) {
            drop((h, epg, channels));
            let link = |key: &str, glyph, name: &str, sub: String| search::Hit { key: key.to_string(), tag: String::new(), name: name.to_string(), sub, group: "LINK", dead: false, progress: None, logo: None, glyph: Some(glyph) };
            let what = format!("{} · {}", settings::kind_word(q), catalog::host_of(q));
            if kind == catalog::LinkKind::Playlist {
                hits.push(link("link:list", "+", "Add this playlist", what));
            } else {
                hits.push(link("link:play", "▶", "Play this link", what));
                hits.push(link("link:add", "+", "Add to My sources", "Keep it in the guide".to_string()));
            }
            self.search.set_hits(hits, None);
            self.refresh_summaries();
            return;
        }
        if q.is_empty() {
            for c in channels.iter().filter(|c| self.is_fav(&c.key)) {
                hits.push(hit(c, None, "FAVOURITES"));
            }
        } else {
            let mut named: Vec<&Channel> = channels.iter().filter(|c| matches(c)).collect();
            // the ones that answer before those that do not
            named.sort_by_key(|c| !h.alive(&c.sources));
            for c in named.iter().take(60) {
                hits.push(hit(c, None, "CHANNELS"));
            }
            if nq.len() >= 3 {
                for c in channels.iter().filter(|c| !matches(c) && h.alive(&c.sources)).take(400) {
                    if let Some(p) = epg.of(&c.key).iter().find(|p| p.stop > now && epg::norm(&p.title).contains(&nq)) {
                        hits.push(hit(c, Some(p), "PROGRAMMES"));
                        if hits.len() > 90 {
                            break;
                        }
                    }
                }
            }
            if let Some(world) = self.world.borrow().as_ref() {
                let mine: HashSet<&str> = channels.iter().map(|c| c.key.as_str()).collect();
                for c in world.iter().filter(|c| !mine.contains(c.key.as_str()) && matches(c)).take(40) {
                    let country = if c.country.is_empty() { String::new() } else { catalog::country_name(&c.country) };
                    hits.push(search::Hit {
                        key: c.key.clone(),
                        tag: c.country.clone(),
                        name: c.name.clone(),
                        sub: [country, c.category.clone()].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" · "),
                        group: "OTHER COUNTRIES",
                        dead: false,
                        progress: None,
                        logo: None,
                        glyph: None,
                    });
                }
            }
        }
        drop((h, epg, channels));
        let empty = if q.is_empty() { Some("No favourites yet".to_string()) } else { Some(format!("Nothing matches “{q}”")) };
        self.search.set_hits(hits, empty);
        self.refresh_summaries();
    }

    /// A channel picked in the search: one from elsewhere is kept aside so
    /// it can be played (and found) like the others.
    fn pick_search(self: &Rc<Self>, key: &str) {
        let q = self.search.entry.text().trim().to_string();
        match key {
            // a link played once, kept aside like a channel from elsewhere
            "link:play" => {
                let k = format!("link:{q}");
                if self.find(&k).is_none() {
                    self.extra.borrow_mut().push(Channel {
                        key: k.clone(),
                        name: catalog::host_of(&q),
                        category: "My sources".into(),
                        sources: vec![catalog::Source { url: q.clone(), user_agent: None, referrer: None, quality: None, origin: "Link".into() }],
                        number: 0,
                        logo: None,
                        country: String::new(),
                    });
                }
                self.play(&k);
                self.close_guide();
                return;
            }
            "link:add" => {
                self.settings_view.start_naming(&q);
                self.search.entry.set_text("");
                self.open_page(Page::Playlists, false);
                self.settings_view.focus_name();
                return;
            }
            "link:list" => {
                self.search.entry.set_text("");
                self.settings_action(settings::Action::AddList(q));
                self.open_page(Page::Playlists, true);
                return;
            }
            _ => {}
        }
        if self.find(key).is_none() {
            let w = self.world.borrow().as_ref().and_then(|w| w.iter().find(|c| c.key == key).cloned());
            if let Some(c) = w {
                self.extra.borrow_mut().push(c);
            }
        }
        self.play(key);
        self.close_guide();
    }

    /// "i": the sheet, or closing it.
    fn toggle_info(self: &Rc<Self>) {
        if self.info.is_open() {
            self.info.set_level(0);
            return;
        }
        self.close_guide();
        self.refresh_info();
        self.info.set_level(2);
    }

    /// Space: the next level. The sheet, then the guide on the channel
    /// playing; from the guide, back to the picture.
    fn step(self: &Rc<Self>) {
        if self.guide_open.get() {
            self.close_guide();
        } else if self.info.is_open() {
            match self.playing_ep.get() {
                Some(at) => self.open_episode(at),
                None => self.open_page(Page::Guide, false),
            }
        } else {
            self.toggle_info();
        }
    }

    fn refresh_info(&self) {
        let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) else { return };
        let status = if self.cur_src.get().is_none() && self.tried.borrow().len() >= self.order.borrow().len() && !self.order.borrow().is_empty() {
            Some("Not answering")
        } else if !self.started.get() {
            Some("Connecting…")
        } else {
            None
        };
        self.info.fill(&self.info_data(&c, status), self.info.level() != 1);
    }

    /// `s`: the guide on the last settings page, the keyboard in the column.
    fn open_settings(self: &Rc<Self>) {
        self.open_page(self.last_setting.get(), true);
    }

    fn render_settings(self: &Rc<Self>) {
        let page = self.guide.page();
        if !page.is_settings() {
            return;
        }
        let s = self.settings.borrow().clone();
        let h = self.health.borrow();
        let channels = self.channels.borrow();
        let countries = s
            .countries
            .iter()
            .map(|cc| {
                let origin = format!("iptv-org {}", catalog::country_name(cc));
                let mine: Vec<&Channel> = channels.iter().filter(|c| c.sources.iter().any(|x| x.origin == origin)).collect();
                let detail = if mine.is_empty() {
                    "Loading channels…".to_string()
                } else {
                    format!("{} channels", mine.iter().filter(|c| h.alive(&c.sources)).count())
                };
                settings::CountryRow { cc: cc.clone(), name: catalog::country_name(cc), detail }
            })
            .collect();
        let all_countries = match self.world.borrow().as_ref() {
            Some(w) => {
                let mut n: HashMap<String, usize> = HashMap::new();
                for c in w.iter().filter(|c| c.country.len() == 2) {
                    *n.entry(c.country.to_lowercase()).or_default() += 1;
                }
                n.into_iter().map(|(cc, k)| (cc.clone(), catalog::country_name(&cc), k)).collect()
            }
            None => vec![],
        };
        let known = self.lists.borrow();
        let mine = catalog::my_sources_path().display().to_string();
        let mut lists: Vec<settings::ListRow> = known
            .iter()
            .filter(|l| l.spec != mine)
            .map(|l| settings::ListRow {
                spec: l.spec.clone(),
                name: l.name.clone(),
                detail: if l.from_folder {
                    format!("In the playlists folder · {} channels", l.channels)
                } else if l.merged > 0 {
                    format!("Playlist · {} channels · {} already in the guide", l.channels, l.merged)
                } else {
                    format!("Playlist · {} channels", l.channels)
                },
                from_folder: l.from_folder,
            })
            .collect();
        for p in &s.playlists {
            if !known.iter().any(|l| &l.spec == p) {
                lists.push(settings::ListRow { spec: p.clone(), name: p.rsplit('/').next().unwrap_or(p).to_string(), detail: "Loading…".into(), from_folder: false });
            }
        }
        let epg = self.epg.borrow();
        let mut guides = vec![];
        if s.countries.iter().any(|c| c.eq_ignore_ascii_case("fr")) {
            let when = if epg.fetched == 0 { "not downloaded yet".to_string() } else { format!("updated {}", epg::day_at(epg.fetched as i64)) };
            guides.push(("xmltvfr.fr".to_string(), format!("{} channels · {}", epg.progs.len(), when)));
        }
        let silent = channels.iter().filter(|c| !h.alive(&c.sources)).count();
        let last_check = if h.last_check == 0 {
            "Not checked yet".to_string()
        } else if silent == 1 {
            format!("{} · 1 channel not answering", epg::day_at_cap(h.last_check as i64))
        } else if silent > 0 {
            format!("{} · {silent} channels not answering", epg::day_at_cap(h.last_check as i64))
        } else {
            epg::day_at_cap(h.last_check as i64)
        };
        let data = settings::SettingsData {
            countries,
            all_countries,
            lists,
            sources: catalog::my_sources().into_iter().map(|m| (m.name, m.url)).collect(),
            guides,
            every: s.check_every_hours,
            last_check,
            checking: self.checking.get(),
            open_last: s.open_last,
            logos: s.logos,
            lower_on_weak: s.lower_on_weak,
            autonext: s.autonext,
        };
        drop((h, channels, known, epg));
        self.settings_view.render(page, &data);
    }

    fn save_settings(&self) {
        store::save(&store::settings_path(), &*self.settings.borrow());
    }

    /// The list again, from a background thread, after a country or a
    /// playlist changed; the sources never checked are checked next.
    fn reload_catalog(&self) {
        let (tx, settings) = (self.tx.clone(), self.settings.borrow().clone());
        let known: HashSet<String> = self.health.borrow().probes.keys().cloned().collect();
        std::thread::spawn(move || {
            let cat = catalog::load(&settings, false);
            let new: Vec<catalog::Source> = cat.channels.iter().flat_map(|c| c.sources.clone()).filter(|s| !known.contains(&s.url)).collect();
            let _ = tx.send_blocking(Msg::Catalog(cat));
            if !new.is_empty() {
                let _ = tx.send_blocking(Msg::Health(health::check(new, 24)));
            }
        });
    }

    fn settings_action(self: &Rc<Self>, a: settings::Action) {
        use settings::Action::*;
        // what changes the list renders the page again; a switch does not
        // (it would steal the keyboard from it)
        let mut again = true;
        match a {
            AddCountry(cc) => {
                {
                    let mut s = self.settings.borrow_mut();
                    if !s.countries.iter().any(|c| c.eq_ignore_ascii_case(&cc)) {
                        s.countries.push(cc);
                    }
                }
                self.save_settings();
                self.reload_catalog();
            }
            RemoveCountry(cc) => {
                self.settings.borrow_mut().countries.retain(|c| !c.eq_ignore_ascii_case(&cc));
                self.save_settings();
                self.reload_catalog();
            }
            AddList(spec) => {
                {
                    let mut s = self.settings.borrow_mut();
                    if !s.playlists.contains(&spec) {
                        s.playlists.push(spec);
                    }
                }
                self.save_settings();
                self.reload_catalog();
            }
            RemoveList(spec) => {
                self.settings.borrow_mut().playlists.retain(|p| *p != spec);
                self.save_settings();
                self.reload_catalog();
            }
            AddSource(name, url) => {
                let mut all = catalog::my_sources();
                all.retain(|m| m.url != url);
                all.push(catalog::MySource { name: name.clone(), url });
                catalog::save_my_sources(&all);
                self.show_toast(&format!("{name} added to My sources"));
                self.reload_catalog();
            }
            RemoveSource(url) => {
                let mut all = catalog::my_sources();
                all.retain(|m| m.url != url);
                catalog::save_my_sources(&all);
                self.reload_catalog();
            }
            Redraw => {}
            ChooseFile => {
                let filter = gtk::FileFilter::new();
                filter.set_name(Some("Playlists and videos"));
                for x in ["m3u", "m3u8", "mp4", "mkv", "webm", "ts", "mov", "avi", "m4v"] {
                    filter.add_suffix(x);
                }
                let filters = gio::ListStore::new::<gtk::FileFilter>();
                filters.append(&filter);
                let dialog = gtk::FileDialog::builder().title("Choose a playlist").filters(&filters).default_filter(&filter).build();
                let me = Rc::downgrade(self);
                dialog.open(Some(&self.win), gio::Cancellable::NONE, move |res| {
                    let (Some(me), Ok(file)) = (me.upgrade(), res) else { return };
                    if let Some(path) = file.path() {
                        let p = path.display().to_string();
                        if catalog::link_kind(&p) == Some(catalog::LinkKind::Playlist) {
                            me.settings_action(AddList(p));
                        } else {
                            me.settings_view.start_naming(&p);
                            me.render_settings();
                            me.settings_view.focus_name();
                        }
                    }
                });
                return;
            }
            OpenFolder => {
                let dir = catalog::folder();
                let _ = std::fs::create_dir_all(&dir);
                let uri = gio::File::for_path(&dir).uri();
                let _ = gio::AppInfo::launch_default_for_uri(&uri, None::<&gio::AppLaunchContext>);
                return;
            }
            Every(h) => {
                self.settings.borrow_mut().check_every_hours = h;
                self.save_settings();
                again = false;
            }
            CheckNow => {
                if !self.checking.replace(true) {
                    let tx = self.tx.clone();
                    let sources: Vec<catalog::Source> = self.channels.borrow().iter().flat_map(|c| c.sources.clone()).collect();
                    std::thread::spawn(move || {
                        let _ = tx.send_blocking(Msg::Checked(health::check(sources, 24)));
                    });
                }
            }
            OpenLast(v) => {
                self.settings.borrow_mut().open_last = v;
                self.save_settings();
                again = false;
            }
            Logos(v) => {
                self.settings.borrow_mut().logos = v;
                self.save_settings();
                again = false;
            }
            LowerOnWeak(v) => {
                self.settings.borrow_mut().lower_on_weak = v;
                self.save_settings();
                again = false;
            }
            AutoNext(v) => {
                self.settings.borrow_mut().autonext = v;
                self.save_settings();
                again = false;
            }
        }
        if again && self.settings_shown() {
            self.render_settings();
        }
        self.refresh_summaries();
    }

    // ---- reminders ---------------------------------------------------------

    fn reminder_set(&self) -> HashSet<(String, i64)> {
        self.state.borrow().reminders.iter().map(|r| (r.key.clone(), r.start)).collect()
    }

    /// Enter on a programme still to come: a reminder, set or removed.
    fn toggle_reminder(self: &Rc<Self>, key: &str, p: &epg::Prog) {
        let on = {
            let mut st = self.state.borrow_mut();
            let had = st.reminders.iter().position(|r| r.key == key && r.start == p.start);
            match had {
                Some(i) => {
                    st.reminders.remove(i);
                    false
                }
                None => {
                    st.reminders.push(store::Reminder { key: key.to_string(), start: p.start, stop: p.stop, title: p.title.clone() });
                    true
                }
            }
        };
        store::save(&store::state_path(), &*self.state.borrow());
        self.guide.set_reminders(self.reminder_set());
        if on {
            self.show_toast(&format!("Reminder set   ·   {}   {}", epg::hm(p.start), p.title));
        } else {
            self.show_toast("Reminder removed");
        }
    }

    fn show_toast(self: &Rc<Self>, text: &str) {
        self.toast.set_text(text);
        self.toast.add_css_class("show");
        let g = self.toast_gen.get() + 1;
        self.toast_gen.set(g);
        let me = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_millis(2200), move || {
            if let Some(me) = me.upgrade() {
                if me.toast_gen.get() == g {
                    me.toast.remove_css_class("show");
                }
            }
        });
    }

    /// Reminders whose programme starts within half a minute ring once;
    /// those already over are dropped.
    fn check_reminders(self: &Rc<Self>) {
        let now = store::now() as i64;
        let due: Vec<store::Reminder> = {
            let mut st = self.state.borrow_mut();
            let due = st.reminders.iter().filter(|r| r.start - 30 <= now && now < r.stop).cloned().collect::<Vec<_>>();
            let before = st.reminders.len();
            st.reminders.retain(|r| r.start - 30 > now);
            if st.reminders.len() != before {
                store::save(&store::state_path(), &*st);
            }
            due
        };
        if !due.is_empty() {
            self.guide.set_reminders(self.reminder_set());
        }
        for r in due {
            self.ring(&r);
        }
    }

    /// In front of you: a card offering to switch, 15 s. Elsewhere (another
    /// workspace, another window in front): a desktop notification whose
    /// Watch button brings the TV here on that channel.
    fn ring(self: &Rc<Self>, r: &store::Reminder) {
        let Some(c) = self.find(&r.key) else { return };
        if self.win.is_active() && self.video_on.get() {
            self.alarm_title.set_text(&r.title);
            self.alarm_ch.set_text(&format!("{}   {}", c.number, c.name));
            *self.alarm_key.borrow_mut() = Some(r.key.clone());
            self.alarm.add_css_class("show");
            self.refresh_help();
            let g = self.alarm_gen.get() + 1;
            self.alarm_gen.set(g);
            let started = std::time::Instant::now();
            let me = Rc::downgrade(self);
            glib::timeout_add_local(Duration::from_millis(100), move || {
                let Some(me) = me.upgrade() else { return glib::ControlFlow::Break };
                if me.alarm_gen.get() != g {
                    return glib::ControlFlow::Break;
                }
                let left = 1.0 - started.elapsed().as_secs_f64() / 15.0;
                if left <= 0.0 {
                    me.close_alarm();
                    return glib::ControlFlow::Break;
                }
                me.alarm_bar.set_fraction(left);
                glib::ControlFlow::Continue
            });
        } else {
            let (tx, key, title, name) = (self.tx.clone(), r.key.clone(), r.title.clone(), c.name.clone());
            let icon = logos::path_for(&r.key);
            std::thread::spawn(move || {
                let mut cmd = std::process::Command::new("notify-send");
                cmd.args(["-a", "Antenne", "-t", "60000", "--action=watch=Watch"]);
                if icon.exists() {
                    cmd.arg("-i").arg(&icon);
                }
                cmd.args(["Starting now", &format!("{title}   ·   {name}")]);
                if let Ok(out) = cmd.output() {
                    if String::from_utf8_lossy(&out.stdout).trim() == "watch" {
                        let _ = tx.send_blocking(Msg::Watch { key });
                    }
                }
            });
        }
    }

    fn close_alarm(&self) {
        self.alarm_gen.set(self.alarm_gen.get() + 1);
        self.alarm.remove_css_class("show");
        self.alarm_key.borrow_mut().take();
        self.refresh_help();
    }

    /// What the bar shows under the channel name: the programme when the
    /// guide knows it, else the number and category.
    fn mpris_artist(&self, c: &Channel) -> String {
        match self.epg.borrow().at(&c.key, store::now() as i64) {
            Some(p) => p.title.clone(),
            None => format!("{} · {}", c.number, c.category),
        }
    }

    /// Every half minute: the guide's now line and clock, and the bar's
    /// programme once the next one has begun.
    fn minute(self: &Rc<Self>) {
        if self.guide_open.get() {
            self.guide.tick();
        }
        self.check_reminders();
        self.check_connection();
        let Some(c) = self.cur.borrow().clone().and_then(|k| self.find(&k)) else { return };
        let artist = self.mpris_artist(&c);
        if *self.mpris_now.borrow() != artist {
            *self.mpris_now.borrow_mut() = artist.clone();
            self.mpris.set_track(&c.name, &artist, logo_art(&c.key));
        }
    }

    /// The playing channel's logo, for the bar's media module, even if it
    /// was never picked in the guide.
    fn ensure_logo(&self, c: &Channel) {
        let path = logos::path_for(&c.key);
        if logos::fresh(&path) || !self.settings.borrow().logos {
            return;
        }
        let Some(url) = c.logo.clone() else { return };
        let (tx, key) = (self.tx.clone(), c.key.clone());
        std::thread::spawn(move || {
            if logos::fetch(&url, &path) {
                let _ = tx.send_blocking(Msg::Art { key });
            }
        });
    }

    fn command(self: &Rc<Self>, cmd: mpris::Command) {
        use mpris::Command::*;
        let pause = match cmd {
            PlayPause => Some(!self.paused.get()),
            Play => Some(false),
            Pause => Some(true),
            Next => return self.zap(1),
            Previous => return self.zap(-1),
            Raise => return self.reactivate(),
            Quit => return self.win.close(),
        };
        if let Some(p) = pause {
            self.paused.set(p);
            self.player.set_pause(p, !self.recording());
            self.mpris.set_playing(!p && self.started.get());
            self.show_current(if p { 4000 } else { 2000 });
        }
    }

    // ---- Super+G: follow you, focus, or open the guide -----------------

    fn reactivate(self: &Rc<Self>) {
        let ours = hypr::our_window();
        let ws = hypr::active_workspace();
        let active = hypr::active_address();
        match (ours, ws) {
            (Some(o), Some(ws)) if o.workspace != ws && o.workspace > 0 => {
                hypr::move_to(&o.address, ws);
                hypr::focus(&o.address);
            }
            (Some(o), _) if active.as_deref() != Some(o.address.as_str()) => hypr::focus(&o.address),
            (Some(_), _) => self.open_guide(!self.guide_open.get()),
            _ => self.win.present(),
        }
    }

    // ---- nobody watching: no picture -------------------------------------

    fn check_visibility(&self) {
        let stale = glib::monotonic_time() - self.last_tick.get() > 1_500_000;
        let visible = !self.suspended.get() && !stale;
        if visible != self.video_on.get() {
            self.video_on.set(visible);
            self.player.set_video(visible);
        }
    }

    fn on_fullscreen(&self, full: bool) {
        let prev = self.dnd_prev.clone();
        std::thread::spawn(move || {
            let mut p = prev.lock().unwrap();
            if full {
                if p.is_none() {
                    *p = hypr::dnd();
                    if p.is_some() {
                        hypr::set_dnd(true);
                    }
                }
            } else if let Some(was) = p.take() {
                hypr::set_dnd(was);
            }
        });
    }
}

fn build(app: &gtk::Application) -> Rc<App> {
    let settings: store::Settings = store::load(&store::settings_path());
    if !store::settings_path().exists() {
        store::save(&store::settings_path(), &settings);
    }
    let state: store::State = store::load(&store::state_path());
    let health = Health::load();
    let first = catalog::load(&settings, true);
    let (channels, first_lists) = (first.channels, first.lists);

    let display = gdk::Display::default().expect("no display");
    let h = display
        .monitors()
        .item(0)
        .and_then(|m| m.downcast::<gdk::Monitor>().ok())
        .map(|m| m.geometry().height())
        .unwrap_or(1080);
    let u = h as f64 / 72.0;
    keys::set_unit(u);
    let provider = gtk::CssProvider::new();
    provider.load_from_string(&css(u));
    gtk::style_context_add_provider_for_display(&display, &provider, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);

    let player = player::Player::new(hypr::on_battery()).expect("libmpv failed to start");

    let win = gtk::ApplicationWindow::builder().application(app).title("Antenne").decorated(false).build();
    win.add_css_class("antenne");
    let overlay = gtk::Overlay::new();
    overlay.set_child(Some(&player.area));

    let shade = gtk::Box::new(gtk::Orientation::Vertical, 0);
    shade.add_css_class("shade");
    shade.set_can_target(false);
    overlay.add_overlay(&shade);
    let loading_view = loading::LoadingView::new(u);
    overlay.add_overlay(&loading_view.root);
    let loading_choices = loading_view.on_choice.clone();
    let next_card_view = info::NextCard::new(u);
    overlay.add_overlay(&next_card_view.root);
    let next_choices = next_card_view.on_choice.clone();

    let digits = gtk::Label::new(None);
    digits.add_css_class("digits");
    digits.set_halign(gtk::Align::End);
    digits.set_valign(gtk::Align::Start);
    digits.set_can_target(false);
    overlay.add_overlay(&digits);

    let guide = guide::GuideView::new(u);
    overlay.add_overlay(&guide.root);
    let info_view = info::InfoView::new(u);
    overlay.add_overlay(&info_view.root);
    overlay.add_overlay(&info_view.card);
    // Search and the settings are pages of the guide's column
    let info_view_controls = info_view.on_control.clone();
    let search_view = search::SearchView::new(u);
    guide.add_page("search", &search_view.root);
    let settings_view = settings::SettingsView::new();
    guide.add_page("settings", &settings_view.root);
    let library_view = library::LibraryView::new(u);
    guide.add_page("library", &library_view.root);

    // the reminder that rings, and the small confirmation line
    let alarm = gtk::Box::new(gtk::Orientation::Vertical, 0);
    alarm.add_css_class("alarm");
    alarm.add_css_class("glass");
    alarm.set_halign(gtk::Align::End);
    alarm.set_valign(gtk::Align::Start);
    alarm.set_can_target(false);
    let kicker = gtk::Label::new(Some("STARTING NOW"));
    kicker.add_css_class("akick");
    kicker.set_xalign(0.0);
    let alarm_title = gtk::Label::new(None);
    alarm_title.add_css_class("atitle");
    alarm_title.set_xalign(0.0);
    alarm_title.set_ellipsize(gtk::pango::EllipsizeMode::End);
    alarm_title.set_max_width_chars(30);
    let alarm_ch = gtk::Label::new(None);
    alarm_ch.add_css_class("ach");
    alarm_ch.set_xalign(0.0);
    let acts = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    acts.add_css_class("aacts");
    acts.append(&keys::hint(keys::Action::Ok, "Watch", "act"));
    acts.append(&keys::hint(keys::Action::Back, "Dismiss", "act"));
    let alarm_bar = gtk::ProgressBar::new();
    alarm_bar.add_css_class("abar");
    for w in [kicker.upcast_ref::<gtk::Widget>(), alarm_title.upcast_ref(), alarm_ch.upcast_ref(), acts.upcast_ref(), alarm_bar.upcast_ref()] {
        alarm.append(w);
    }
    overlay.add_overlay(&alarm);
    // the weak connection cue: three bars, one lit, and a word that goes
    let weak = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    weak.add_css_class("weak");
    weak.add_css_class("glass");
    weak.set_halign(gtk::Align::End);
    weak.set_valign(gtk::Align::Start);
    weak.set_can_target(false);
    let bars = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    bars.add_css_class("bars");
    bars.set_valign(gtk::Align::Center);
    for (i, class) in ["b1", "b2", "b3"].iter().enumerate() {
        let bar = gtk::Box::new(gtk::Orientation::Vertical, 0);
        bar.add_css_class("bar");
        bar.add_css_class(class);
        if i > 0 {
            bar.add_css_class("dim");
        }
        bar.set_valign(gtk::Align::End);
        bars.append(&bar);
    }
    let weak_text = gtk::Label::new(Some("Weak connection"));
    weak_text.add_css_class("wtext");
    weak.append(&bars);
    weak.append(&weak_text);
    overlay.add_overlay(&weak);
    let toast = gtk::Label::new(None);
    toast.add_css_class("toast");
    toast.add_css_class("glass");
    toast.set_halign(gtk::Align::Center);
    toast.set_valign(gtk::Align::End);
    toast.set_can_target(false);
    overlay.add_overlay(&toast);

    // The key for the list: ":" where it needs no Shift (AZERTY), "?"
    // otherwise. Both always work.
    let colon_plain = display
        .map_keyval(gdk::Key::colon)
        .is_some_and(|ks| ks.iter().any(|k| k.level() == 0 && k.group() == 0));
    let help = help::Help::new(if colon_plain { ":" } else { "?" });
    overlay.add_overlay(&help.root);
    overlay.add_overlay(&help.hint);
    win.set_child(Some(&overlay));

    let (tx, rx) = async_channel::unbounded::<Msg>();
    let first_cat = if state.favourites.is_empty() { "All" } else { "Favourites" };
    let app_state = Rc::new(App {
        win: win.clone(),
        player: player.clone(),
        guide: guide.clone(),
        epg: RefCell::new(epg::Guide::load()),
        u,
        logo_pending: RefCell::new(HashSet::new()),
        mpris_now: RefCell::new(String::new()),
        shade,
        digits,
        help,
        info: info_view,
        search: search_view.clone(),
        settings_view: settings_view.clone(),
        lists: RefCell::new(first_lists),
        world: RefCell::new(None),
        world_loading: Cell::new(false),
        extra: RefCell::new(vec![]),
        checking: Cell::new(false),
        last_setting: Cell::new(Page::Countries),
        library_view: library_view.clone(),
        lib: RefCell::new(library::Library::load()),
        lib_open: Cell::new(None),
        lib_group: Cell::new(0),
        lib_pending: RefCell::new(vec![]),
        lib_cont: RefCell::new(vec![]),
        thumbs: RefCell::new(HashMap::new()),
        thumb_pending: RefCell::new(HashSet::new()),
        thumb_gen: Cell::new(0),
        playing_ep: Cell::new(None),
        ep_line: RefCell::new(HashMap::new()),
        start_at: Cell::new(None),
        pending_next: Cell::new(None),
        next_gen: Cell::new(0),
        pad: RefCell::new(None),
        loading: loading_view,
        prev_key: RefCell::new(None),
        last_error: RefCell::new(None),
        stalled: Cell::new(false),
        buffer_gen: Cell::new(0),
        next_card: next_card_view,
        next_cancel: Cell::new(false),
        autoplay_run: Cell::new(0),
        asking: Cell::new(None),
        menu_target: Cell::new(None),
        menu_confirm: Cell::new(false),
        alarm,
        alarm_title,
        alarm_ch,
        alarm_bar,
        alarm_key: RefCell::new(None),
        alarm_gen: Cell::new(0),
        toast,
        toast_gen: Cell::new(0),
        mpris: mpris::Mpris::start(),
        paused: Cell::new(false),
        tx: tx.clone(),
        channels: RefCell::new(channels),
        health: RefCell::new(health),
        settings: RefCell::new(settings.clone()),
        state: RefCell::new(state),
        cur: RefCell::new(None),
        gen: Cell::new(0),
        order: RefCell::new(vec![]),
        tried: RefCell::new(vec![]),
        cur_src: Cell::new(None),
        started: Cell::new(false),
        guide_open: Cell::new(false),
        cat: RefCell::new(first_cat.into()),
        osd_gen: Cell::new(0),
        digit_buf: RefCell::new(String::new()),
        digit_gen: Cell::new(0),
        hint_gen: Cell::new(0),
        cursor_gen: Cell::new(0),
        last_tick: Cell::new(glib::monotonic_time()),
        win_size: Cell::new((0, 0)),
        video_aspect: Cell::new(16.0 / 9.0),
        volume: Cell::new(100.0),
        volume_gen: Cell::new(0),
        stalls: RefCell::new(vec![]),
        stall_gen: Cell::new(0),
        weak,
        weak_text,
        weak_gen: Cell::new(0),
        low_quality: Cell::new(false),
        suspended: Cell::new(false),
        video_on: Cell::new(true),
        dnd_prev: Arc::new(Mutex::new(None)),
    });

    // mpv wakes us from its own thread; one pending wakeup is enough.
    {
        let pending = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let p = pending.clone();
        let tx = tx.clone();
        player.mpv.borrow_mut().event_context_mut().set_wakeup_callback(move || {
            if !p.swap(true, std::sync::atomic::Ordering::AcqRel) {
                let _ = tx.send_blocking(Msg::MpvWake);
            }
        });
        let me = Rc::downgrade(&app_state);
        glib::spawn_future_local(async move {
            while let Ok(m) = rx.recv().await {
                let Some(me) = me.upgrade() else { break };
                match m {
                    Msg::MpvWake => {
                        pending.store(false, std::sync::atomic::Ordering::Release);
                        me.on_mpv();
                    }
                    Msg::Race { gen, winner } => me.on_race(gen, winner),
                    Msg::Logo { key, small } => {
                        if let Some(sm) = small {
                            me.logo_pending.borrow_mut().remove(&key);
                            let bytes = glib::Bytes::from_owned(sm.rgba);
                            let t = gdk::MemoryTexture::new(sm.width as i32, sm.height as i32, gdk::MemoryFormat::R8g8b8a8, &bytes, sm.width as usize * 4);
                            me.guide.set_logo(&key, t.upcast(), sm.light);
                            if me.cur.borrow().as_deref() == Some(key.as_str()) {
                                me.mpris.set_art(logo_art(&key));
                            }
                        }
                    }
                    Msg::Watch { key } => {
                        if me.guide_open.get() {
                            me.open_guide(false);
                        }
                        me.play(&key);
                        me.reactivate();
                    }
                    Msg::Art { key } => {
                        if me.cur.borrow().as_deref() == Some(key.as_str()) {
                            me.mpris.set_art(logo_art(&key));
                        }
                    }
                    Msg::Guide(g) => {
                        *me.epg.borrow_mut() = g;
                        if me.guide_open.get() {
                            me.fill_guide(None, true);
                        }
                    }
                    Msg::World(w) => {
                        *me.world.borrow_mut() = Some(w);
                        if me.search_shown() {
                            let q = me.search.query();
                            me.run_search(&q);
                        }
                        if me.settings_shown() {
                            me.render_settings();
                        }
                    }
                    Msg::Checked(map) => {
                        me.checking.set(false);
                        {
                            let mut h = me.health.borrow_mut();
                            h.probes.extend(map);
                            h.last_check = store::now();
                            h.save();
                        }
                        if me.settings_shown() {
                            me.render_settings();
                        }
                        if me.guide_open.get() {
                            me.fill_guide(None, true);
                            me.refresh_summaries();
                        }
                    }
                    Msg::Catalog(cat) => {
                        if !cat.channels.is_empty() || me.settings.borrow().countries.is_empty() {
                            *me.channels.borrow_mut() = cat.channels;
                        }
                        *me.lists.borrow_mut() = cat.lists;
                        if me.settings_shown() {
                            me.render_settings();
                        }
                        let keys = me.alive().into_iter().map(|c| c.key).collect();
                        me.fetch_logos(keys);
                        if me.cur.borrow().is_none() {
                            start_playing(&me);
                        }
                        if me.guide_open.get() {
                            me.fill_guide(None, true);
                            me.refresh_summaries();
                        }
                    }
                    Msg::Show(r, url) => {
                        me.lib_pending.borrow_mut().retain(|u| *u != url);
                        match r {
                            Ok(show) => {
                                let fresh = {
                                    let mut lib = me.lib.borrow_mut();
                                    let had = lib.shows.iter().position(|s| s.url == show.url);
                                    let msg = format!("{} added", show.name);
                                    match had {
                                        Some(i) => {
                                            lib.shows[i] = show;
                                            None
                                        }
                                        None => {
                                            lib.shows.push(show);
                                            Some(msg)
                                        }
                                    }
                                };
                                me.lib.borrow().save();
                                if let Some(m) = fresh {
                                    me.show_toast(&m);
                                }
                            }
                            Err(e) => me.show_toast(&e),
                        }
                        me.refresh_summaries();
                        if me.guide_open.get() && me.guide.page().is_library() {
                            me.render_library(true);
                        }
                    }
                    Msg::PadLink(s) => {
                        *me.pad.borrow_mut() = Some(s);
                        me.pad_grab(me.win.is_active());
                    }
                    Msg::Pad(b) => on_pad(&me, &b),
                    Msg::PadFamily(f) => keys::set_family(&f),
                    Msg::Thumb { key, small } => {
                        me.thumb_pending.borrow_mut().remove(&key);
                        if let Some(sm) = small {
                            let bytes = glib::Bytes::from_owned(sm.rgba);
                            let t = gdk::MemoryTexture::new(sm.width as i32, sm.height as i32, gdk::MemoryFormat::R8g8b8a8, &bytes, sm.width as usize * 4);
                            me.thumbs.borrow_mut().insert(key, t.upcast());
                            // many arrive at once: one redraw for a batch
                            let g = me.thumb_gen.get() + 1;
                            me.thumb_gen.set(g);
                            let w = Rc::downgrade(&me);
                            glib::timeout_add_local_once(Duration::from_millis(150), move || {
                                if let Some(me) = w.upgrade() {
                                    if me.thumb_gen.get() == g && me.guide_open.get() && me.guide.page().is_library() && !me.library_view.adding() {
                                        me.render_library(true);
                                    }
                                }
                            });
                        }
                    }
                    Msg::Health(map) => {
                        {
                            let mut h = me.health.borrow_mut();
                            h.probes.extend(map);
                            h.last_check = store::now();
                            h.save();
                        }
                        if me.guide_open.get() {
                            me.fill_guide(None, true);
                            me.refresh_summaries();
                        }
                        if me.settings_shown() {
                            me.render_settings();
                        }
                        if me.info.is_open() {
                            me.refresh_info();
                        }
                    }
                }
            }
        });
    }

    // The search and the settings.
    {
        let me = Rc::downgrade(&app_state);
        *search_view.on_change.borrow_mut() = Some(Box::new(move |q| {
            if let Some(me) = me.upgrade() {
                me.run_search(&q);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *search_view.on_pick.borrow_mut() = Some(Box::new(move |k| {
            if let Some(me) = me.upgrade() {
                me.pick_search(&k);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *next_choices.borrow_mut() = Some(Box::new(move |now| {
            if let Some(me) = me.upgrade() {
                me.autoplay_run.set(0);
                if now {
                    if let Some(n) = me.playing_ep.get().and_then(|at| me.after(at)) {
                        me.play_episode(n);
                    }
                } else {
                    me.next_cancel.set(true);
                    me.next_card.hide();
                }
            }
        }));
        let me = Rc::downgrade(&app_state);
        *library_view.menu.on_act.borrow_mut() = Some(Box::new(move |a| {
            if let Some(me) = me.upgrade() {
                me.menu_act(a);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *loading_choices.borrow_mut() = Some(Box::new(move |c| {
            if let Some(me) = me.upgrade() {
                me.load_choice(c);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *info_view_controls.borrow_mut() = Some(Box::new(move |c| {
            if let Some(me) = me.upgrade() {
                me.control(c);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *library_view.on_activate.borrow_mut() = Some(Box::new(move |i| {
            if let Some(me) = me.upgrade() {
                me.guide.set_nav_focus(false);
                me.lib_activate(i);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *library_view.on_back.borrow_mut() = Some(Box::new({
            let me = me.clone();
            move || {
                if let Some(me) = me.upgrade() {
                    me.lib_back();
                }
            }
        }));
        *library_view.on_tab.borrow_mut() = Some(Box::new(move |i| {
            if let Some(me) = me.upgrade() {
                let d = i as i32 - me.lib_group.get() as i32;
                me.lib_tab(d);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *library_view.on_add.borrow_mut() = Some(Box::new(move |url| {
            if let Some(me) = me.upgrade() {
                me.add_show(url);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *settings_view.on_action.borrow_mut() = Some(Box::new(move |a| {
            if let Some(me) = me.upgrade() {
                me.settings_action(a);
            }
        }));
    }

    // The bar's play/pause and next/previous.
    {
        let me = Rc::downgrade(&app_state);
        *app_state.mpris.on_command.borrow_mut() = Some(Box::new(move |cmd| {
            if let Some(me) = me.upgrade() {
                me.command(cmd);
            }
        }));
    }

    // Guide callbacks.
    {
        let me = Rc::downgrade(&app_state);
        *guide.on_play.borrow_mut() = Some(Box::new(move |k| {
            if let Some(me) = me.upgrade() {
                me.play(&k);
                me.open_guide(false);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *guide.on_category.borrow_mut() = Some(Box::new(move |c| {
            if let Some(me) = me.upgrade() {
                *me.cat.borrow_mut() = c;
                me.guide.set_cats_focus(true);
                me.fill_guide(None, true);
            }
        }));
        let me = Rc::downgrade(&app_state);
        *guide.on_visible.borrow_mut() = Some(Box::new(move |keys| {
            if let Some(me) = me.upgrade() {
                me.fetch_logos(keys);
            }
        }));
        // one side holds the contour: the page's selection fades while the
        // menu has the keyboard
        let roots: Vec<gtk::Widget> = vec![library_view.root.clone().upcast(), search_view.root.clone().upcast()];
        *guide.on_focus.borrow_mut() = Some(Box::new(move |menu| {
            for r in &roots {
                if menu {
                    r.remove_css_class("f");
                } else {
                    r.add_css_class("f");
                }
            }
        }));
        let me = Rc::downgrade(&app_state);
        *guide.on_nav.borrow_mut() = Some(Box::new(move |p| {
            if let Some(me) = me.upgrade() {
                me.guide.set_page(p);
                me.show_page(p);
                me.to_column();
            }
        }));
    }

    // The gamepad, through the Manette service: its buttons become keys.
    {
        let tx = tx.clone();
        std::thread::spawn(move || {
            use std::io::BufRead;
            let path = std::env::var_os("XDG_RUNTIME_DIR").map(std::path::PathBuf::from).unwrap_or_else(std::env::temp_dir).join("manette.sock");
            loop {
                if let Ok(s) = std::os::unix::net::UnixStream::connect(&path) {
                    if let Ok(w) = s.try_clone() {
                        let _ = tx.send_blocking(Msg::PadLink(w));
                    }
                    for line in std::io::BufReader::new(s).lines() {
                        let Ok(line) = line else { break };
                        let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) else { continue };
                        if v["event"] == "pads" {
                            if let Some(f) = v["pads"].get(0).and_then(|p| p["family"].as_str()) {
                                let _ = tx.send_blocking(Msg::PadFamily(f.to_string()));
                            }
                        }
                        if v["event"] == "nav" {
                            if let Some(b) = v["button"].as_str() {
                                let _ = tx.send_blocking(Msg::Pad(b.to_string()));
                            }
                        }
                    }
                }
                std::thread::sleep(Duration::from_secs(5));
            }
        });
        let me = Rc::downgrade(&app_state);
        win.connect_is_active_notify(move |w| {
            if let Some(me) = me.upgrade() {
                me.pad_grab(w.is_active());
            }
        });
    }

    // Keys.
    let keys = gtk::EventControllerKey::new();
    keys.set_propagation_phase(gtk::PropagationPhase::Capture);
    let me = Rc::downgrade(&app_state);
    keys.connect_key_pressed(move |_, key, code, mods| match me.upgrade() {
        Some(me) => {
            keys::set_mode(keys::Mode::Keyboard);
            handle_key(&me, key, code, mods)
        }
        None => glib::Propagation::Proceed,
    });
    win.add_controller(keys);

    // The pointer: shows the card, hides itself after a moment.
    let motion = gtk::EventControllerMotion::new();
    let me = Rc::downgrade(&app_state);
    let last_xy = Rc::new(Cell::new((0.0f64, 0.0f64)));
    motion.connect_motion(move |_, x, y| {
        let Some(me) = me.upgrade() else { return };
        let (lx, ly) = last_xy.replace((x, y));
        if (lx - x).abs() + (ly - y).abs() < 2.0 {
            return;
        }
        me.win.set_cursor(None);
        if !me.guide_open.get() && me.info.level() == 0 {
            me.show_current(4000);
        }
        let g = me.cursor_gen.get() + 1;
        me.cursor_gen.set(g);
        let w = Rc::downgrade(&me);
        glib::timeout_add_local_once(Duration::from_millis(1500), move || {
            if let Some(me) = w.upgrade() {
                if me.cursor_gen.get() == g {
                    me.win.set_cursor_from_name(Some("none"));
                }
            }
        });
    });
    win.add_controller(motion);

    let click = gtk::GestureClick::new();
    let me = Rc::downgrade(&app_state);
    click.connect_pressed(move |_, n, _, _| {
        let Some(me) = me.upgrade() else { return };
        if n == 2 {
            if me.win.is_fullscreen() {
                me.win.unfullscreen()
            } else {
                me.win.fullscreen()
            }
        } else if me.guide_open.get() {
            me.open_guide(false);
        } else if me.recording() {
            me.command(mpris::Command::PlayPause);
        }
    });
    player.area.add_controller(click);

    // Visibility: the frame clock stops on a hidden workspace; a
    // suspended toplevel says the same thing more directly.
    let me = Rc::downgrade(&app_state);
    win.add_tick_callback(move |w, _| {
        if let Some(me) = me.upgrade() {
            me.last_tick.set(glib::monotonic_time());
            // The window changed size with the guide open (fullscreen on or
            // off, a new tiling): split again, and move the picture with it.
            let size = (w.width(), w.height());
            if me.win_size.replace(size) != size {
                me.apply_insets();
                if me.guide_open.get() {
                    let (pw, ph) = me.guide.split(size.0, size.1);
                    me.player_to_pip(true, pw, ph);
                    me.player.area.queue_render();
                }
            }
        }
        glib::ControlFlow::Continue
    });
    let me = Rc::downgrade(&app_state);
    glib::timeout_add_local(Duration::from_millis(500), move || match me.upgrade() {
        Some(me) => {
            me.check_visibility();
            glib::ControlFlow::Continue
        }
        None => glib::ControlFlow::Break,
    });
    let me = Rc::downgrade(&app_state);
    win.connect_realize(move |w| {
        let Some(t) = w.surface().and_then(|s| s.downcast::<gdk::Toplevel>().ok()) else { return };
        let me = me.clone();
        t.connect_notify_local(Some("state"), move |t, _| {
            if let Some(me) = me.upgrade() {
                me.suspended.set(t.state().contains(gdk::ToplevelState::SUSPENDED));
                me.check_visibility();
            }
        });
    });

    if std::env::var_os("ANTENNE_DEBUG").is_some() {
        let me = Rc::downgrade(&app_state);
        glib::timeout_add_seconds_local(2, move || match me.upgrade() {
            Some(me) => {
                let mpv = me.player.mpv.borrow();
                let v = mpv.get_property::<f64>("volume").unwrap_or(-1.0);
                let mute = mpv.get_property::<bool>("mute").unwrap_or(false);
                let aid = mpv.get_property::<String>("aid").unwrap_or_default();
                drop(mpv);
                debug(&format!("volume {v:.0} (ours {:.0}) mute {mute} aid {aid}", me.volume.get()));
                glib::ControlFlow::Continue
            }
            None => glib::ControlFlow::Break,
        });
    }

    let me = Rc::downgrade(&app_state);
    glib::timeout_add_seconds_local(5, move || match me.upgrade() {
        Some(me) => {
            me.save_progress();
            glib::ControlFlow::Continue
        }
        None => glib::ControlFlow::Break,
    });
    let me = Rc::downgrade(&app_state);
    glib::timeout_add_seconds_local(30, move || match me.upgrade() {
        Some(me) => {
            me.minute();
            glib::ControlFlow::Continue
        }
        None => glib::ControlFlow::Break,
    });

    let me = Rc::downgrade(&app_state);
    win.connect_fullscreened_notify(move |w| {
        if let Some(me) = me.upgrade() {
            me.on_fullscreen(w.is_fullscreen());
        }
    });
    let me = Rc::downgrade(&app_state);
    win.connect_close_request(move |_| {
        if let Some(me) = me.upgrade() {
            me.health.borrow().save();
            if let Some(was) = me.dnd_prev.lock().unwrap().take() {
                hypr::set_dnd(was);
            }
        }
        glib::Propagation::Proceed
    });

    win.fullscreen();
    win.present();
    win.set_cursor_from_name(Some("none"));
    start_playing(&app_state);
    let keys = app_state.alive().into_iter().map(|c| c.key).collect();
    app_state.fetch_logos(keys);
    // the shows' new episodes, once the channel plays
    {
        let me = Rc::downgrade(&app_state);
        glib::timeout_add_local_once(Duration::from_secs(4), move || {
            if let Some(me) = me.upgrade() {
                me.refresh_stale_shows();
            }
        });
    }

    // Refresh the list, then the guide once a day, then check the channels
    // if it is time.
    let due = app_state.health.borrow().due(settings.check_every_hours);
    let guide_due = app_state.epg.borrow().due();
    std::thread::spawn(move || {
        let cat = catalog::load(&settings, false);
        let sources: Vec<catalog::Source> = cat.channels.iter().flat_map(|c| c.sources.clone()).collect();
        let names: Vec<(String, String)> = cat.channels.iter().map(|c| (c.key.clone(), c.name.clone())).collect();
        let guides = cat.guides.clone();
        let _ = tx.send_blocking(Msg::Catalog(cat));
        if guide_due {
            let mut urls = guides;
            if settings.countries.iter().any(|c| c.eq_ignore_ascii_case("fr")) {
                urls.insert(0, epg::XMLTVFR.to_string());
            }
            if let Some(g) = epg::Guide::fetch(&urls, &names) {
                g.save();
                let _ = tx.send_blocking(Msg::Guide(g));
            }
        }
        if due {
            let _ = tx.send_blocking(Msg::Health(health::check(sources, 24)));
        }
    });
    app_state
}

/// A gamepad button. A: choose (pause a video), B: back, X: the next level
/// (as Space), Y: search, Select: the list of keys, Start: settings; the
/// shoulders: 10 s back or on in a video, the tabs or seasons in the guide;
/// the triggers: a minute in a video, a page in a list.
fn on_pad(me: &Rc<App>, b: &str) {
    keys::set_mode(keys::Mode::Pad);
    me.win.set_cursor_from_name(Some("none"));
    let open = me.guide_open.get();
    let rec = !open && me.recording();
    let page = me.guide.page();
    // a settings page: GTK's controls take the arrows and A themselves
    if open && !me.guide.nav_focus() && page.is_settings() {
        let dir = match b {
            "up" => Some(gtk::DirectionType::Up),
            "down" => Some(gtk::DirectionType::Down),
            "left" => Some(gtk::DirectionType::Left),
            "right" => Some(gtk::DirectionType::Right),
            _ => None,
        };
        match (b, dir) {
            (_, Some(d)) => {
                if GtkWindowExt::focus(&me.win).is_none() {
                    me.settings_view.focus_first();
                } else if !me.win.child_focus(d) && d == gtk::DirectionType::Left {
                    me.to_column();
                }
                return;
            }
            ("a", _) => {
                if let Some(w) = GtkWindowExt::focus(&me.win) {
                    w.activate();
                }
                return;
            }
            ("x", _) => return me.step(),
            _ => {}
        }
    }
    let seek = |s: f64| {
        me.player.seek(s);
        me.show_current(3000);
    };
    let key = match b {
        "up" => gdk::Key::Up,
        "down" => gdk::Key::Down,
        "left" => gdk::Key::Left,
        "right" => gdk::Key::Right,
        "a" => gdk::Key::Return,
        "b" => gdk::Key::Escape,
        "x" => gdk::Key::space,
        "y" => gdk::Key::slash,
        "select" => gdk::Key::colon,
        "start" if open && page.is_library() && !me.guide.nav_focus() => gdk::Key::m,
        "start" => gdk::Key::s,
        "lb" if rec => return seek(-10.0),
        "rb" if rec => return seek(10.0),
        "lt" if rec => return seek(-60.0),
        "rt" if rec => return seek(60.0),
        "lb" if open => gdk::Key::ISO_Left_Tab,
        "rb" if open => gdk::Key::Tab,
        "lt" if open => gdk::Key::Page_Up,
        "rt" if open => gdk::Key::Page_Down,
        "lb" => gdk::Key::Up,
        "rb" => gdk::Key::Down,
        _ => return,
    };
    handle_key(me, key, 0, gdk::ModifierType::empty());
}

/// A key, from the keyboard or the gamepad (`on_pad`).
fn handle_key(me: &Rc<App>, key: gdk::Key, code: u32, mods: gdk::ModifierType) -> glib::Propagation {
    if mods.intersects(gdk::ModifierType::CONTROL_MASK | gdk::ModifierType::ALT_MASK | gdk::ModifierType::SUPER_MASK) {
        return glib::Propagation::Proceed;
    }
    me.autoplay_run.set(0);
    // the next episode's card, during the credits
    if !me.guide_open.get() && me.next_card.shown() {
        match key {
            gdk::Key::Return | gdk::Key::KP_Enter => {
                if let Some(n) = me.playing_ep.get().and_then(|at| me.after(at)) {
                    me.play_episode(n);
                }
                return glib::Propagation::Stop;
            }
            gdk::Key::Escape => {
                me.next_cancel.set(true);
                me.next_card.hide();
                return glib::Propagation::Stop;
            }
            _ => {}
        }
    }
    // a failure or a question on screen: its ways out
    if !me.guide_open.get() && matches!(me.loading.state(), loading::State::Failed | loading::State::Asking) {
        let ch = match key {
            gdk::Key::Return | gdk::Key::KP_Enter => Some(loading::Choice::Retry),
            gdk::Key::Escape => Some(loading::Choice::Back),
            gdk::Key::space => Some(loading::Choice::Third),
            _ => None,
        };
        if let Some(ch) = ch {
            me.load_choice(ch);
            return glib::Propagation::Stop;
        }
    }
    let typing = GtkWindowExt::focus(&me.win).is_some_and(|w| w.is::<gtk::Text>());
    let page = me.guide.page();
    // a click in a page gives it the keyboard
    if me.guide_open.get() && me.guide.nav_focus() {
        let f = GtkWindowExt::focus(&me.win);
        let root = if page == Page::Search { me.search.root.clone() } else { me.settings_view.root.clone() };
        if page != Page::Guide && f.is_some_and(|w| w.is_ancestor(&root)) {
            me.guide.set_nav_focus(false);
        }
    }
    let in_page = me.guide_open.get() && !me.guide.nav_focus();
    // A settings page: GTK's own keys (Tab, arrows, Space) move and act;
    // h j k l move too, Esc (or ← with nowhere left to go) is the column.
    if in_page && page.is_settings() {
        let dir = |d| GtkWindowExt::focus(&me.win).is_some() && me.win.child_focus(d);
        match key {
            gdk::Key::Escape => me.to_column(),
            gdk::Key::Left | gdk::Key::h if !typing => {
                if !dir(gtk::DirectionType::Left) {
                    me.to_column();
                }
            }
            gdk::Key::j if !typing => {
                if !dir(gtk::DirectionType::Down) {
                    me.settings_view.focus_first();
                }
            }
            gdk::Key::k if !typing => {
                dir(gtk::DirectionType::Up);
            }
            gdk::Key::l if !typing => {
                dir(gtk::DirectionType::Right);
            }
            _ => {
                if GtkWindowExt::focus(&me.win).is_none() && matches!(key, gdk::Key::Down | gdk::Key::Up | gdk::Key::Tab) {
                    me.settings_view.focus_first();
                    return glib::Propagation::Stop;
                }
                return glib::Propagation::Proceed;
            }
        }
        return glib::Propagation::Stop;
    }
    // Streaming: the grid of cards, or a show's episodes; h j k l move too.
    if in_page && page.is_library() {
        let lv = me.library_view.clone();
        if lv.adding() {
            if key == gdk::Key::Escape {
                lv.set_adding(false);
                me.release_keyboard();
                return glib::Propagation::Stop;
            }
            return glib::Propagation::Proceed;
        }
            if lv.menu.is_open() {
            match key {
                gdk::Key::Up | gdk::Key::k => lv.menu.move_sel(-1),
                gdk::Key::Down | gdk::Key::j => lv.menu.move_sel(1),
                gdk::Key::Return | gdk::Key::KP_Enter => {
                    if let Some(a) = lv.menu.selected() {
                        me.menu_act(a);
                    }
                }
                gdk::Key::Escape | gdk::Key::m | gdk::Key::Menu => lv.menu.close(),
                _ => {}
            }
            return glib::Propagation::Stop;
        }
        if matches!(key, gdk::Key::m | gdk::Key::Menu) {
            me.open_menu();
            return glib::Propagation::Stop;
        }
        if key == gdk::Key::Home {
            let at = match (page, me.lib_open.get()) {
                (Page::Continue, _) => me.lib_cont.borrow().get(lv.selected()).copied(),
                (Page::Shows, Some(si)) => Some((si, me.lib_group.get(), lv.selected())),
                _ => None,
            };
            if let Some(at) = at {
                me.play_episode_at(at, true);
            }
            return glib::Propagation::Stop;
        }
        let episodes = lv.mode() == library::Mode::Episodes;
        let moved = match key {
            gdk::Key::Left | gdk::Key::h if episodes => {
                me.lib_tab(-1);
                false
            }
            gdk::Key::Right | gdk::Key::l if episodes => {
                me.lib_tab(1);
                false
            }
            gdk::Key::Tab if episodes => {
                me.lib_tab(1);
                false
            }
            gdk::Key::ISO_Left_Tab if episodes => {
                me.lib_tab(-1);
                false
            }
            gdk::Key::Left | gdk::Key::h => {
                if !lv.move_sel(-1, 0) {
                    me.to_column();
                }
                true
            }
            gdk::Key::Right | gdk::Key::l => lv.move_sel(1, 0),
            gdk::Key::Up | gdk::Key::k => lv.move_sel(0, -1),
            gdk::Key::Down | gdk::Key::j => lv.move_sel(0, 1),
            gdk::Key::Page_Up => lv.move_sel(0, -4),
            gdk::Key::Page_Down => lv.move_sel(0, 4),
            gdk::Key::Return | gdk::Key::KP_Enter => {
                lv.activate();
                false
            }
            gdk::Key::Escape if episodes => {
                me.lib_back();
                false
            }
            gdk::Key::Escape => {
                me.to_column();
                false
            }
            _ => return glib::Propagation::Proceed,
        };
        if moved {
            me.lib_head();
        }
        me.refresh_help();
        return glib::Propagation::Stop;
    }
    // Search: typing goes to the field; ↑ ↓ and Enter to the list.
    if in_page && page == Page::Search {
        match key {
            gdk::Key::Escape => me.to_column(),
            gdk::Key::Up => me.search.move_sel(-1),
            gdk::Key::Down => me.search.move_sel(1),
            gdk::Key::Page_Up => me.search.move_sel(-6),
            gdk::Key::Page_Down => me.search.move_sel(6),
            gdk::Key::Return | gdk::Key::KP_Enter => me.search.pick(),
            _ => {
                if !typing {
                    me.search.focus();
                }
                return glib::Propagation::Proceed;
            }
        }
        return glib::Propagation::Stop;
    }
    // hjkl are the arrows and Space is Enter, as in Prisme and Neovim --
    // except while a text field has the keyboard, where they are letters
    // and a space.
    let key = if typing {
        key
    } else {
        match key {
            gdk::Key::h | gdk::Key::H => gdk::Key::Left,
            gdk::Key::j | gdk::Key::J => gdk::Key::Down,
            gdk::Key::k | gdk::Key::K => gdk::Key::Up,
            gdk::Key::l | gdk::Key::L => gdk::Key::Right,
            other => other,
        }
    };
    if me.alarm.has_css_class("show") && (enter_key(key) || key == gdk::Key::Escape) {
        let k = me.alarm_key.borrow().clone();
        me.close_alarm();
        if enter_key(key) {
            if let Some(k) = k {
                if me.guide_open.get() {
                    me.open_guide(false);
                }
                me.play(&k);
            }
        }
        return glib::Propagation::Stop;
    }
    let open = me.guide_open.get();
    let column = open && me.guide.nav_focus();
    let cats = open && !column && me.guide.cats_focus();
    let enter = key == gdk::Key::Return || key == gdk::Key::KP_Enter;
    // The digit row by position: on AZERTY it types & é " ' ... without
    // Shift (evdev keycodes 2-11, +8 here). The keypad gives digits anyway.
    let digit = match code {
        10..=18 => char::from_digit(code - 9, 10),
        19 => Some('0'),
        _ => key.to_unicode().filter(char::is_ascii_digit),
    };
    match key {
        gdk::Key::colon | gdk::Key::question => me.toggle_help(),
        // Space: the glance unfolds into the sheet, the sheet into the
        // guide, the guide closes
        gdk::Key::space => me.step(),
        gdk::Key::slash => me.open_search(),
        gdk::Key::i | gdk::Key::I => me.toggle_info(),
        gdk::Key::s | gdk::Key::S => me.open_settings(),
        gdk::Key::Escape if me.pending_next.get().is_some() => {
            me.pending_next.set(None);
            me.info.set_level(0);
        }
        gdk::Key::Escape if me.info.level() > 0 => me.info.set_level(0),
        gdk::Key::Escape if me.help.is_open() => me.toggle_help(),
        gdk::Key::F11 => {
            if me.win.is_fullscreen() {
                me.win.unfullscreen()
            } else {
                me.win.fullscreen()
            }
        }
        gdk::Key::Escape if open => me.open_guide(false),
        gdk::Key::g if open => me.open_guide(false),
        // the column of pages: the page follows the entry picked
        gdk::Key::Up if column => me.move_nav(-1),
        gdk::Key::Down if column => me.move_nav(1),
        gdk::Key::Right if column => me.enter_page(),
        _ if column && enter => me.enter_page(),
        gdk::Key::Left if column => {}
        gdk::Key::Tab | gdk::Key::ISO_Left_Tab if column => {}
        // Tab / Shift+Tab: next / previous tab, from anywhere in the guide
        gdk::Key::Tab if open => me.move_category(1),
        gdk::Key::ISO_Left_Tab if open => me.move_category(-1),
        // the tabs, a row above the grid
        gdk::Key::Left if cats => me.move_category(-1),
        gdk::Key::Right if cats => me.move_category(1),
        gdk::Key::Down if cats => me.guide.set_cats_focus(false),
        gdk::Key::Up if cats => {}
        _ if cats && enter => me.guide.set_cats_focus(false),
        gdk::Key::Up if open && me.guide.at_first_row() => me.guide.set_cats_focus(true),
        gdk::Key::Up if open => me.guide.move_row(-1),
        gdk::Key::Down if open => me.guide.move_row(1),
        gdk::Key::Page_Up if open => me.guide.move_row(-6),
        gdk::Key::Page_Down if open => me.guide.move_row(6),
        gdk::Key::Home if open => me.guide.home(),
        gdk::Key::Right if open => {
            me.guide.move_prog(1);
        }
        gdk::Key::Left if open => {
            if !me.guide.move_prog(-1) {
                me.to_column();
            }
        }
        _ if open && enter => match me.guide.selected_prog() {
            Some((k, p)) if p.start > store::now() as i64 => me.toggle_reminder(&k, &p),
            _ => {
                if let Some(k) = me.guide.selected_key() {
                    me.play(&k);
                }
                me.open_guide(false);
            }
        },
        gdk::Key::f => {
            let key = if open && page == Page::Guide { me.guide.selected_key() } else { me.cur.borrow().clone() };
            if let Some(k) = key {
                me.toggle_fav(&k);
            }
            if me.info.is_open() {
                me.refresh_info();
            }
        }
        // a recording: back and forward, pause, the episode before or after
        gdk::Key::Left | gdk::Key::Right if !open && me.recording() => {
            let step = if mods.contains(gdk::ModifierType::SHIFT_MASK) { 60.0 } else { 10.0 };
            me.player.seek(if key == gdk::Key::Left { -step } else { step });
            me.show_current(3000);
        }
        _ if !open && enter && me.recording() => me.command(mpris::Command::PlayPause),
        gdk::Key::Home if !open && me.recording() => {
            me.player.seek_to(0.0);
            me.show_current(3000);
        }
        // the channel before, as a remote's "Last" button
        gdk::Key::BackSpace if !open => {
            if let Some(p) = me.prev_key.borrow().clone() {
                me.play(&p);
            }
        }
        gdk::Key::Up | gdk::Key::Down if !open && me.playing_ep.get().is_some() => {
            let at = me.playing_ep.get().unwrap_or((0, 0, 0));
            let to = if key == gdk::Key::Down { me.after(at) } else { me.before(at) };
            if let Some(n) = to {
                me.play_episode(n);
            }
        }
        gdk::Key::Up => me.zap(-1),
        gdk::Key::Down => me.zap(1),
        gdk::Key::g => me.open_guide(true),
        // nothing to choose while watching: a glance
        _ if enter => me.show_current(4000),
        _ => match digit {
            Some(c) if !open => me.digit(c),
            _ => {
                let modifier = matches!(
                    key,
                    gdk::Key::Shift_L | gdk::Key::Shift_R | gdk::Key::Control_L | gdk::Key::Control_R
                        | gdk::Key::Alt_L | gdk::Key::Alt_R | gdk::Key::Super_L | gdk::Key::Super_R
                        | gdk::Key::ISO_Level3_Shift | gdk::Key::Caps_Lock | gdk::Key::Tab
                );
                if !modifier {
                    me.key_hint();
                    if !open {
                        me.show_current(3000);
                    }
                }
                return glib::Propagation::Proceed;
            }
        },
    }
    me.refresh_help();
    glib::Propagation::Stop
}

/// ANTENNE_DEBUG=1: what happens, on stderr.
fn debug(msg: &str) {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    if *ON.get_or_init(|| std::env::var_os("ANTENNE_DEBUG").is_some()) {
        eprintln!("antenne: {msg}");
    }
}

fn enter_key(k: gdk::Key) -> bool {
    k == gdk::Key::Return || k == gdk::Key::KP_Enter
}

fn logo_art(key: &str) -> Option<String> {
    let p = logos::path_for(key);
    logos::fresh(&p).then(|| format!("file://{}", p.display()))
}

fn start_playing(me: &Rc<App>) {
    let last = if me.settings.borrow().open_last { me.state.borrow().last.clone() } else { None };
    let alive = me.alive();
    let key = last.filter(|k| alive.iter().any(|c| &c.key == k)).or_else(|| alive.first().map(|c| c.key.clone()));
    if let Some(k) = key {
        me.play(&k);
    }
}

#[cfg(test)]
mod tests {
    /// The style sheet parses without a warning (needs a display, so run
    /// by hand: cargo test css -- --ignored).
    #[test]
    #[ignore]
    fn css_parses() {
        use gtk4 as gtk;
        gtk::init().unwrap();
        let p = gtk::CssProvider::new();
        let errors = std::rc::Rc::new(std::cell::RefCell::new(vec![]));
        let e = errors.clone();
        p.connect_parsing_error(move |_, section, err| e.borrow_mut().push(format!("{}: {}", section.to_str(), err)));
        p.load_from_string(&super::css(16.67));
        assert!(errors.borrow().is_empty(), "{:#?}", errors.borrow());
    }
}

fn main() -> glib::ExitCode {
    let app = gtk::Application::new(Some(APP_ID), gio::ApplicationFlags::empty());
    let slot: Rc<RefCell<Option<Rc<App>>>> = Rc::new(RefCell::new(None));
    app.connect_activate(move |app| {
        let existing = slot.borrow().clone();
        match existing {
            Some(a) => a.reactivate(),
            None => *slot.borrow_mut() = Some(build(app)),
        }
    });
    app.run()
}
