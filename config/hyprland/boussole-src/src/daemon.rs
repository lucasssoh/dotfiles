//! The service: one thread blocked in poll(2), like Manette's.
//!
//! Watched all the time:
//!   - the socket at $XDG_RUNTIME_DIR/boussole.sock and its clients (JSON
//!     lines, the same for the bar and the command line);
//!   - one alarm clock, a timerfd on the real time (absolute, cancelled when
//!     the clock is set): the next alert, the next timetable download or
//!     midnight, whichever comes first. A time that passed during sleep
//!     fires on waking;
//!   - inotify on the course folder and on the personal calendars;
//!   - the pipes of its children: curl (timetable), khal (personal events),
//!     notify-send (an alert waiting for its button).
//! poll only gets a timeout while a rescan waits for a burst of file events
//! to settle.
//!
//!   pushed:   {"event":"status",…}  on connect and on every change
//!             {"event":"plan"}      the plan changed: ask for it
//!   accepted: {"cmd":"…", …}        see `Service::command`; every command
//!             gets {"reply":"…","ok":true|false,"text":"…","data":…}

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::ade::{self, Snapshot};
use crate::ajout::{self, Action};
use crate::alertes::{self, Kind};
use crate::catalogue::{Catalogue, Inclusion};
use crate::i18n;
use crate::journee::{self, Place};
use crate::khal;
use crate::model::*;
use crate::plan::{self, Input, Pin, Plan, Session, Work};
use crate::store::{self, Event, Outcome, PartReport, Paths, Store};
use crate::time::{Date, Hm, Local, Tz};

pub(crate) enum Job {
    Ade,
    Khal,
    /// An alert with buttons, waiting for one.
    Notify { session: Option<String> },
    /// Fire and forget (poking the bar, opening a file).
    Quiet,
    /// `busctl monitor` on zathura, resident: read line by line.
    Bus,
}

pub(crate) struct Running {
    pub(crate) child: Child,
    pub(crate) job: Job,
    pub(crate) out: Vec<u8>,
    pub(crate) started: Instant,
}

pub(crate) struct Client {
    id: u64,
    stream: UnixStream,
    inbox: Vec<u8>,
}

pub struct Service {
    pub(crate) store: Store,
    pub(crate) tz: Tz,
    pub(crate) catalogue: Catalogue,
    pub(crate) ade: Option<Snapshot>,
    pub(crate) ade_error: Option<String>,
    pub(crate) personal: Vec<Busy>,
    pub(crate) plan: Plan,
    /// Alerts sent, with the day they belong to (pruned after two days).
    pub(crate) sent: BTreeMap<String, Date>,
    /// notify-send ids per session, so a reminder replaces the first alert.
    pub(crate) notifications: HashMap<String, u32>,
    pub(crate) listener: UnixListener,
    pub(crate) clients: Vec<Client>,
    pub(crate) next_client: u64,
    pub(crate) timer: RawFd,
    pub(crate) inotify: RawFd,
    /// inotify watch → (folder, is the personal calendar).
    pub(crate) watches: HashMap<i32, (PathBuf, bool)>,
    pub(crate) children: Vec<Running>,
    pub(crate) rescan_at: Option<Instant>,
    pub(crate) khal_at: Option<Instant>,
    /// Instant of the next timetable download.
    pub(crate) next_fetch: Option<i64>,
    /// BOOTTIME − MONOTONIC: grows across a suspend.
    pub(crate) slept: i64,
    pub(crate) suivi: crate::suivi::Suivi,
}

fn clock(id: libc::clockid_t) -> i64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: a valid clock id and a live timespec.
    unsafe { libc::clock_gettime(id, &mut ts) };
    ts.tv_sec as i64
}

pub(crate) fn now_secs() -> i64 {
    clock(libc::CLOCK_REALTIME)
}

pub(crate) fn set_nonblocking(fd: RawFd) {
    // SAFETY: fcntl on a descriptor we own.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
    }
}

pub(crate) fn which(cmd: &str) -> Option<PathBuf> {
    std::env::var_os("PATH")?.to_str()?.split(':').map(|d| Path::new(d).join(cmd)).find(|p| p.is_file())
}

pub fn run(paths: Paths) -> io::Result<()> {
    let socket = paths.socket();
    if UnixStream::connect(&socket).is_ok() {
        return Err(io::Error::new(ErrorKind::AddrInUse, "already running"));
    }
    let _ = std::fs::remove_file(&socket);
    std::fs::create_dir_all(&paths.runtime)?;
    let listener = UnixListener::bind(&socket)?;
    listener.set_nonblocking(true)?;

    // SAFETY: plain syscalls creating descriptors we own.
    let timer = unsafe { libc::timerfd_create(libc::CLOCK_REALTIME, libc::TFD_NONBLOCK | libc::TFD_CLOEXEC) };
    let inotify = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
    if timer < 0 || inotify < 0 {
        return Err(io::Error::last_os_error());
    }

    let store = Store::open(paths)?;
    let ade = store::read_json(&store.paths.data.join("ade.json"));
    let sent = store::read_json(&store.paths.data.join("alerts.json")).unwrap_or_default();
    let plan = store::read_json(&store.paths.data.join("plan.json")).unwrap_or_default();
    let mut s = Service {
        store,
        tz: Tz::local(),
        catalogue: Catalogue::default(),
        ade,
        ade_error: None,
        personal: Vec::new(),
        plan,
        sent,
        notifications: HashMap::new(),
        listener,
        clients: Vec::new(),
        next_client: 1,
        timer,
        inotify,
        watches: HashMap::new(),
        children: Vec::new(),
        rescan_at: None,
        khal_at: None,
        next_fetch: None,
        slept: clock(libc::CLOCK_BOOTTIME) - clock(libc::CLOCK_MONOTONIC),
        suivi: crate::suivi::Suivi::default(),
    };
    s.rescan();
    s.suivi_start();
    s.watch_khal();
    s.spawn_khal();
    s.fetch_if_stale(0);
    s.replan();
    s.run()
}

impl Service {
    pub(crate) fn now(&self) -> Local {
        self.tz.to_local(now_secs())
    }

    pub(crate) fn lang(&self) -> Lang {
        self.store.settings.lang
    }

    pub(crate) fn fr(&self) -> bool {
        self.lang() == Lang::Fr
    }

    // ─── Loop ────────────────────────────────────────────────────────────

    fn run(&mut self) -> io::Result<()> {
        let mut fds: Vec<libc::pollfd> = Vec::new();
        loop {
            fds.clear();
            let pfd = |fd: RawFd| libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
            fds.push(pfd(self.timer));
            fds.push(pfd(self.inotify));
            fds.push(pfd(self.listener.as_raw_fd()));
            fds.extend(self.clients.iter().map(|c| pfd(c.stream.as_raw_fd())));
            fds.extend(self.children.iter().map(|c| pfd(c.child.stdout.as_ref().map_or(-1, |o| o.as_raw_fd()))));
            let hypr_at = fds.len();
            fds.push(pfd(self.suivi.hypr.as_ref().map_or(-1, |h| h.as_raw_fd())));

            let now = Instant::now();
            let timeout = [self.rescan_at, self.khal_at]
                .into_iter()
                .flatten()
                .min()
                .map_or(-1, |t| t.saturating_duration_since(now).as_millis().min(i32::MAX as u128) as i32 + 1);
            // SAFETY: fds is a live, correctly sized array of pollfd.
            let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) };
            if n < 0 {
                let e = io::Error::last_os_error();
                if e.kind() == ErrorKind::Interrupted {
                    continue;
                }
                return Err(e);
            }

            let client_base = 3;
            let child_base = client_base + self.clients.len();
            let ready_clients: Vec<u64> =
                (0..self.clients.len()).filter(|&i| fds[client_base + i].revents != 0).map(|i| self.clients[i].id).collect();
            let ready_children: Vec<u32> =
                (0..self.children.len()).filter(|&i| fds[child_base + i].revents != 0).map(|i| self.children[i].child.id()).collect();

            let hypr_ready = fds[hypr_at].revents != 0;
            for pid in ready_children {
                self.read_child(pid);
            }
            if hypr_ready {
                self.read_hypr();
            }
            for id in ready_clients {
                if let Some(i) = self.clients.iter().position(|c| c.id == id) {
                    if !self.read_client(i) {
                        self.clients.retain(|c| c.id != id);
                    }
                }
            }
            if fds[2].revents != 0 {
                self.accept();
            }
            if fds[1].revents != 0 {
                self.read_inotify();
            }
            let now = Instant::now();
            if self.rescan_at.is_some_and(|t| t <= now) {
                self.rescan_at = None;
                self.rescan();
                self.replan();
            }
            if self.khal_at.is_some_and(|t| t <= now) {
                self.khal_at = None;
                self.spawn_khal();
            }
            if fds[0].revents != 0 {
                self.on_timer();
            }
            self.reap_stale();
        }
    }

    fn on_timer(&mut self) {
        let mut buf = [0u8; 8];
        // SAFETY: reading the expiration count into a local buffer.
        let n = unsafe { libc::read(self.timer, buf.as_mut_ptr().cast(), 8) };
        let clock_set = n < 0 && io::Error::last_os_error().raw_os_error() == Some(libc::ECANCELED);
        let slept = clock(libc::CLOCK_BOOTTIME) - clock(libc::CLOCK_MONOTONIC);
        let resumed = slept - self.slept > 60;
        self.slept = slept;
        if clock_set || resumed {
            // Back from sleep: a fresh timetable and a fresh agenda.
            self.fetch_if_stale(30 * 60);
            self.spawn_khal();
        }
        if self.next_fetch.is_some_and(|t| t <= now_secs()) {
            self.fetch();
        }
        self.suivi_tick();
        self.replan();
    }

    /// Arms the alarm clock on the next thing to do.
    pub(crate) fn arm(&mut self) {
        let now = self.now();
        let sent: BTreeSet<String> = self.sent.keys().cloned().collect();
        let mut next = vec![Local::new(now.date.add(1), Hm(0))];
        next.extend(alertes::next(&self.plan, &self.store.state, &self.store.settings, &sent, now));
        let mut t = next.into_iter().map(|l| self.tz.to_utc(l)).min().unwrap();
        if let Some(f) = self.next_fetch {
            t = t.min(f);
        }
        if let Some(q) = self.suivi_deadline() {
            t = t.min(q);
        }
        let spec = libc::itimerspec {
            it_interval: libc::timespec { tv_sec: 0, tv_nsec: 0 },
            it_value: libc::timespec { tv_sec: t.max(now_secs() + 1) as libc::time_t, tv_nsec: 0 },
        };
        // SAFETY: arming our own timerfd with a valid itimerspec.
        unsafe {
            libc::timerfd_settime(
                self.timer,
                libc::TFD_TIMER_ABSTIME | libc::TFD_TIMER_CANCEL_ON_SET,
                &spec,
                std::ptr::null_mut(),
            )
        };
    }

    // ─── Course folder ───────────────────────────────────────────────────

    fn rescan(&mut self) {
        let Some(root) = self.store.settings.courses.clone() else { return };
        self.catalogue = Catalogue::scan(&root, &self.store.settings.ignore);
        // Watch every folder, new ones included (adding a watch twice is harmless).
        let mut dirs = vec![root.clone()];
        while let Some(d) = dirs.pop() {
            let Ok(c) = std::ffi::CString::new(d.as_os_str().as_encoded_bytes()) else { continue };
            let mask = libc::IN_CREATE | libc::IN_DELETE | libc::IN_MOVED_FROM | libc::IN_MOVED_TO | libc::IN_CLOSE_WRITE;
            // SAFETY: a valid C string and our inotify descriptor.
            let wd = unsafe { libc::inotify_add_watch(self.inotify, c.as_ptr(), mask) };
            if wd >= 0 {
                self.watches.insert(wd, (d.clone(), false));
            }
            if let Ok(rd) = std::fs::read_dir(&d) {
                for e in rd.flatten() {
                    let name = e.file_name();
                    if e.file_type().is_ok_and(|t| t.is_dir()) && !name.to_string_lossy().starts_with('.') {
                        dirs.push(e.path());
                    }
                }
            }
        }
    }

    fn read_inotify(&mut self) {
        let mut buf = [0u8; 8192];
        loop {
            // SAFETY: reading into a local buffer of the given length.
            let n = unsafe { libc::read(self.inotify, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                return;
            }
            let header = std::mem::size_of::<libc::inotify_event>();
            let mut off = 0usize;
            while off + header <= n as usize {
                // SAFETY: the kernel wrote a whole inotify_event at `off`.
                let ev = unsafe { std::ptr::read_unaligned(buf.as_ptr().add(off) as *const libc::inotify_event) };
                let raw = &buf[off + header..off + header + ev.len as usize];
                let name = String::from_utf8_lossy(&raw[..raw.iter().position(|&b| b == 0).unwrap_or(raw.len())]).into_owned();
                let personal = self.watches.get(&ev.wd).is_some_and(|w| w.1);
                // Editors' swap and temporary files are noise.
                let noise = name.starts_with('.') || name.ends_with('~') || name.ends_with(".swp") || name.ends_with(".tmp");
                if personal {
                    self.khal_at = Some(Instant::now() + Duration::from_millis(500));
                } else if !noise {
                    self.rescan_at = Some(Instant::now() + Duration::from_millis(800));
                }
                off += header + ev.len as usize;
            }
        }
    }

    // ─── khal ────────────────────────────────────────────────────────────

    fn khal_config(&self) -> (khal::Config, Vec<PathBuf>) {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let path = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or(home.join(".config")).join("khal/config");
        let text = std::fs::read_to_string(path).unwrap_or_default();
        let cfg = khal::read_config(&text);
        let dirs = text
            .lines()
            .filter_map(|l| l.trim().strip_prefix("path").and_then(|r| r.trim().strip_prefix('=')))
            .map(|p| {
                let p = p.trim();
                p.strip_prefix("~/").map_or(PathBuf::from(p), |r| home.join(r))
            })
            .filter(|p| p.extension().is_none_or(|e| e != "db"))
            .filter(|p| !p.ends_with(khal::STUDY) && !p.ends_with(khal::COURSES))
            .collect();
        (cfg, dirs)
    }

    fn watch_khal(&mut self) {
        for d in self.khal_config().1 {
            let Ok(c) = std::ffi::CString::new(d.as_os_str().as_encoded_bytes()) else { continue };
            let mask = libc::IN_CREATE | libc::IN_DELETE | libc::IN_MOVED_TO | libc::IN_CLOSE_WRITE;
            // SAFETY: a valid C string and our inotify descriptor.
            let wd = unsafe { libc::inotify_add_watch(self.inotify, c.as_ptr(), mask) };
            if wd >= 0 {
                self.watches.insert(wd, (d, true));
            }
        }
    }

    fn spawn_khal(&mut self) {
        if which("khal").is_none() || self.children.iter().any(|c| matches!(c.job, Job::Khal)) {
            return;
        }
        let (cfg, _) = self.khal_config();
        let args = khal::list_args(&cfg, self.now().date, 120);
        self.spawn(Command::new("khal").args(args), Job::Khal);
    }

    fn sync_khal(&mut self, courses: &[Course]) {
        let khal_dir = self.store.paths.khal.clone();
        let study = khal::study_files(&self.plan.sessions, &self.tz, self.lang());
        let cours = khal::course_files(courses, &self.tz);
        let a = khal::sync(&khal_dir.join(khal::STUDY), &study).unwrap_or(false);
        let b = khal::sync(&khal_dir.join(khal::COURSES), &cours).unwrap_or(false);
        if (a || b) && which("qs").is_some() {
            self.spawn(Command::new("qs").args(["-c", "bar", "ipc", "call", "bar", "reloadEvents"]), Job::Quiet);
        }
    }

    // ─── Timetable ───────────────────────────────────────────────────────

    fn fetch_if_stale(&mut self, max_age: i64) {
        let age = self.ade.as_ref().map_or(i64::MAX, |s| now_secs() - s.fetched);
        if age > max_age {
            self.fetch();
        }
    }

    fn fetch(&mut self) {
        self.next_fetch = None;
        let Some(url) = self.store.settings.calendar_url.clone() else { return };
        if self.children.iter().any(|c| matches!(c.job, Job::Ade)) {
            return;
        }
        let url = ade::window_url(&url, self.now().date);
        self.spawn(Command::new("curl").args(["-sSfL", "--max-time", "60", &url]), Job::Ade);
    }

    /// Every hour from 6:00 to 20:00.
    fn schedule_fetch(&mut self) {
        if self.store.settings.calendar_url.is_none() {
            self.next_fetch = None;
            return;
        }
        let now = self.now();
        let mut t = Local::new(now.date, Hm::new(now.time.h() + 1, 0));
        if t.time.h() > 20 || t.time.0 >= 1440 {
            t = Local::new(now.date.add(1), Hm::new(6, 0));
        } else if t.time.h() < 6 {
            t = Local::new(now.date, Hm::new(6, 0));
        }
        self.next_fetch = Some(self.tz.to_utc(t));
    }

    fn timetable(&self) -> (Vec<Course>, Vec<Deadline>) {
        let Some(snap) = &self.ade else { return (Vec::new(), Vec::new()) };
        let s = &self.store.settings;
        ade::timetable(&snap.events, &s.groups, &s.domains, &self.tz)
    }

    fn ade_done(&mut self, out: Result<String, String>) {
        let now = now_secs();
        let parsed = out.and_then(|text| ade::parse(&text, &self.tz));
        match ade::reconcile(self.ade.as_ref(), parsed, now) {
            ade::Outcome::Kept { reason } => self.ade_error = Some(reason),
            ade::Outcome::Updated { snapshot, changes } => {
                self.ade_error = None;
                let today = self.now().date;
                let tell: Vec<String> = ade::worth_telling(&changes, &self.store.settings.groups, &self.tz, today)
                    .into_iter()
                    .map(|c| self.describe_change(c))
                    .collect();
                let _ = store::write_json(&self.store.paths.data.join("ade.json"), &snapshot);
                self.ade = Some(snapshot);
                if !tell.is_empty() {
                    let title = if self.fr() { "Boussole · emploi du temps" } else { "Boussole · timetable" };
                    self.notify(title, &tell.join("\n"), &[], None);
                }
            }
        }
        self.schedule_fetch();
        self.replan();
    }

    fn describe_change(&self, c: &ade::Change) -> String {
        let lang = self.lang();
        let fr = self.fr();
        let at = |t: i64| i18n::local(self.tz.to_local(t), lang);
        match c {
            ade::Change::Cancelled { event } => {
                format!("{}, {} : {}", event.summary, at(event.start), if fr { "annulé" } else { "cancelled" })
            }
            ade::Change::Added { event } => format!("{}, {} : {}", event.summary, at(event.start), if fr { "ajouté" } else { "added" }),
            ade::Change::Moved { event, from_start, .. } => {
                if fr {
                    format!("{} : déplacé de {} à {}", event.summary, at(*from_start), at(event.start))
                } else {
                    format!("{}: moved from {} to {}", event.summary, at(*from_start), at(event.start))
                }
            }
        }
    }

    // ─── Children ────────────────────────────────────────────────────────

    pub(crate) fn spawn(&mut self, cmd: &mut Command, job: Job) {
        let quiet = matches!(job, Job::Quiet);
        cmd.stdin(Stdio::null()).stderr(Stdio::null()).stdout(if quiet { Stdio::null() } else { Stdio::piped() });
        let Ok(child) = cmd.spawn() else {
            if matches!(job, Job::Ade) {
                self.ade_error = Some("curl".into());
            }
            return;
        };
        if let Some(out) = &child.stdout {
            set_nonblocking(out.as_raw_fd());
        }
        self.children.push(Running { child, job, out: Vec::new(), started: Instant::now() });
    }

    fn read_child(&mut self, pid: u32) {
        let Some(i) = self.children.iter().position(|c| c.child.id() == pid) else { return };
        let mut buf = [0u8; 16384];
        let mut eof = false;
        let running = &mut self.children[i];
        if let Some(out) = running.child.stdout.as_mut() {
            loop {
                match out.read(&mut buf) {
                    Ok(0) => {
                        eof = true;
                        break;
                    }
                    Ok(n) => running.out.extend_from_slice(&buf[..n]),
                    Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                    Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                    Err(_) => {
                        eof = true;
                        break;
                    }
                }
            }
        } else {
            eof = true;
        }
        if matches!(self.children[i].job, Job::Bus) {
            let mut lines = Vec::new();
            while let Some(nl) = self.children[i].out.iter().position(|&b| b == b'\n') {
                let line: Vec<u8> = self.children[i].out.drain(..=nl).collect();
                lines.push(String::from_utf8_lossy(&line).into_owned());
            }
            for l in lines {
                self.bus_line(&l);
            }
            if eof {
                let mut r = self.children.remove(i);
                let _ = r.child.wait();
                // Restarted at the next wake.
                self.suivi.bus_alive = false;
            }
            return;
        }
        if !eof {
            return;
        }
        let mut r = self.children.remove(i);
        let ok = r.child.wait().is_ok_and(|s| s.success());
        let text = String::from_utf8_lossy(&r.out).into_owned();
        match r.job {
            Job::Ade => self.ade_done(if ok { Ok(text) } else { Err("download".into()) }),
            Job::Khal => {
                if ok {
                    let (cfg, _) = self.khal_config();
                    self.personal = khal::parse_list(&text, &cfg);
                    self.replan();
                }
            }
            Job::Notify { session } => {
                let mut lines = text.lines();
                let id = lines.next().and_then(|l| l.trim().parse::<u32>().ok());
                if let (Some(s), Some(id)) = (&session, id) {
                    self.notifications.insert(s.clone(), id);
                }
                if let (Some(s), Some(action)) = (session, lines.next().map(str::trim)) {
                    self.on_action(&s, action);
                }
            }
            Job::Quiet | Job::Bus => {}
        }
    }

    /// Quiet children are reaped as they end; an alert nobody answered for
    /// hours is let go.
    fn reap_stale(&mut self) {
        let mut i = 0;
        while i < self.children.len() {
            let c = &mut self.children[i];
            let done = matches!(c.job, Job::Quiet) && matches!(c.child.try_wait(), Ok(Some(_)));
            let stale = matches!(c.job, Job::Notify { .. }) && c.started.elapsed() > Duration::from_secs(4 * 3600);
            if stale {
                let _ = c.child.kill();
                let _ = c.child.wait();
            }
            if done || stale {
                self.children.remove(i);
            } else {
                i += 1;
            }
        }
    }

    // ─── Planning ────────────────────────────────────────────────────────

    fn deadlines(&self, from_calendar: Vec<Deadline>) -> Vec<Deadline> {
        let mut all = from_calendar;
        for d in &self.store.state.deadlines {
            all.retain(|c| c.id != d.id);
            all.push(d.clone());
        }
        all
    }

    /// Sessions under way keep their work where it is.
    fn pins(&self, today: Date) -> Vec<Pin> {
        let mut pins = self.store.state.pins.clone();
        for s in self.plan.sessions.iter().filter(|s| s.date == today) {
            if matches!(self.store.state.outcomes.get(&s.id), Some(Outcome::Started { .. } | Outcome::Paused { .. })) {
                for p in &s.parts {
                    pins.retain(|x| x.task != p.task);
                    pins.push(Pin { task: p.task.clone(), date: s.date, start: s.start, minutes: p.minutes, work: Some(p.work.clone()), domain: p.domain.clone() });
                }
            }
        }
        pins
    }

    fn compute(&self, st: &store::State, extra_pins: &[Pin], removed: &[String], previous: Option<&Plan>) -> Plan {
        let now = self.now();
        let (courses, cal) = self.timetable();
        let mut deadlines = cal;
        for d in &st.deadlines {
            deadlines.retain(|c| c.id != d.id);
            deadlines.push(d.clone());
        }
        let mut busy = self.personal.clone();
        busy.extend(st.busy.iter().cloned());
        let mut pins = self.pins(now.date);
        pins.retain(|p| !removed.contains(&p.task) && !extra_pins.iter().any(|e| e.task == p.task));
        pins.extend(extra_pins.iter().cloned());
        let learned: [Option<Hm>; 7] = std::array::from_fn(|wd| journee::learn_start(&st.starts, wd as u32));
        let spent: Vec<String> = st
            .outcomes
            .iter()
            .filter(|(_, o)| matches!(o, Outcome::Closed { .. } | Outcome::Skipped | Outcome::Missed))
            .map(|(id, _)| id.clone())
            .collect();
        // The measured pace, per subject, unless set by hand.
        let mut settings = self.store.settings.clone();
        for d in &settings.domains {
            if let (false, Some(f)) = (settings.pace.domain_factor.contains_key(&d.id), st.factor(&d.id)) {
                settings.pace.domain_factor.insert(d.id.clone(), f);
            }
        }
        let input = Input {
            now,
            settings: &settings,
            domains: &self.store.settings.domains,
            catalogue: &self.catalogue,
            progress: &st.progress,
            courses: &courses,
            calendar: self.ade.is_some(),
            busy: &busy,
            deadlines: &deadlines,
            projects: &st.projects,
            campaigns: &st.campaigns,
            chores: &st.chores,
            pinned: &pins,
            learned,
            missed_streak: st.missed_streak,
            spent: &spent,
            previous,
        };
        plan::plan(&input)
    }

    pub(crate) fn replan(&mut self) {
        let now = self.now();
        // Sessions whose time went by without a start.
        let missed: Vec<String> = self
            .plan
            .sessions
            .iter()
            .filter(|s| s.counted && !s.parts.is_empty() && Local::new(s.date, s.end) <= now)
            .filter(|s| !self.store.state.outcomes.contains_key(&s.id))
            .map(|s| s.id.clone())
            .collect();
        for session in missed {
            let _ = self.store.record(Event::Missed { session }, now);
        }
        let previous = self.plan.clone();
        let fresh = self.compute(&self.store.state, &[], &[], (previous.made.is_some()).then_some(&previous));
        let changed = fresh.sessions != previous.sessions || fresh.offers != previous.offers;
        self.plan = fresh;
        let _ = store::write_json(&self.store.paths.data.join("plan.json"), &self.plan);
        let (courses, _) = self.timetable();
        self.sync_khal(&courses);
        self.send_alerts();
        if self.next_fetch.is_none() {
            self.schedule_fetch();
        }
        self.arm();
        self.push_status();
        if changed {
            self.broadcast(&json!({ "event": "plan" }));
        }
    }

    // ─── Alerts ──────────────────────────────────────────────────────────

    pub(crate) fn notify(&mut self, title: &str, body: &str, actions: &[(String, String)], session: Option<String>) {
        if which("notify-send").is_none() {
            return;
        }
        let mut cmd = Command::new("notify-send");
        cmd.args(["-a", "Boussole"]);
        if actions.is_empty() {
            cmd.arg(title).arg(body);
            self.spawn(&mut cmd, Job::Quiet);
            return;
        }
        cmd.arg("-p");
        if let Some(id) = session.as_ref().and_then(|s| self.notifications.get(s)) {
            cmd.arg(format!("--replace-id={id}"));
        }
        for (name, label) in actions {
            cmd.arg(format!("--action={name}={label}"));
        }
        cmd.arg(title).arg(body);
        // A newer alert for the same session replaces the waiting one.
        if let Some(s) = &session {
            for c in self.children.iter_mut() {
                if matches!(&c.job, Job::Notify { session: Some(x) } if x == s) {
                    let _ = c.child.kill();
                }
            }
        }
        self.spawn(&mut cmd, Job::Notify { session });
    }

    fn session_body(&self, s: &Session) -> String {
        let lang = self.lang();
        s.parts
            .iter()
            .map(|p| {
                let d = p.domain.as_deref().map(|d| format!("{d} · ")).unwrap_or_default();
                format!("{d}{} ({} min)", i18n::work(&p.work, lang), p.minutes)
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn session_actions(&self, s: &Session, from: Hm) -> Vec<(String, String)> {
        let fr = self.fr();
        let r = &self.store.settings.rhythm;
        let len = s.end.0 - s.start.0;
        let slot = journee::Slot {
            date: s.date,
            start: s.start,
            end: s.end,
            kind: s.kind,
            counted: true,
            place: s.place,
            shortened: s.shortened,
            limit: if s.kind == journee::SlotKind::Block { r.block_range.1 } else { r.latest_end },
        };
        let mut a = vec![("start".to_string(), (if fr { "Commencer" } else { "Start" }).to_string())];
        for (t, _) in journee::later_options(&slot, from, len, r.min_session).into_iter().take(2) {
            a.push((format!("later:{t}"), if fr { format!("À {t}") } else { format!("At {t}") }));
        }
        a.push(("skip".into(), (if fr { "Pas ce soir" } else { "Not tonight" }).into()));
        a
    }

    fn send_alerts(&mut self) {
        let now = self.now();
        let sent: BTreeSet<String> = self.sent.keys().cloned().collect();
        let (st, settings) = (&self.store.state, &self.store.settings);
        let due = alertes::due(&self.plan, st, settings, &sent, now);
        let expired = alertes::expired(&self.plan, st, settings, &sent, now);
        for k in expired {
            self.sent.insert(k, now.date);
        }
        let fr = self.fr();
        let lang = self.lang();
        for a in due {
            self.sent.insert(a.key.clone(), now.date);
            match a.kind {
                Kind::Start | Kind::Reminder => {
                    let Some(s) = a.session.as_ref().and_then(|id| self.plan.sessions.iter().find(|s| s.id == *id)).cloned() else { continue };
                    let span = format!("{}–{}", a.at.time.max(s.start), s.end);
                    let title = match (a.kind, fr) {
                        (Kind::Start, true) => format!("Séance · {span}"),
                        (Kind::Start, false) => format!("Session · {span}"),
                        (_, true) => format!("Toujours partant ? Séance de {}", a.at.time.plus(-15)),
                        (_, false) => format!("Still on? The {} session", a.at.time.plus(-15)),
                    };
                    let body = self.session_body(&s);
                    let actions = self.session_actions(&s, now.time);
                    self.notify(&title, &body, &actions, Some(s.id.clone()));
                }
                Kind::Recap => {
                    let Some(day) = a.day else { continue };
                    let (courses, _) = self.timetable();
                    let mut lines: Vec<String> = Vec::new();
                    let first = courses.iter().filter(|c| c.start.date == day).map(|c| c.start.time).min();
                    if let Some(t) = first {
                        lines.push(if fr { format!("Premier cours à {t}.") } else { format!("First course at {t}.") });
                    }
                    for s in self.plan.sessions.iter().filter(|s| s.date == day && !s.parts.is_empty()) {
                        let what = s.parts.iter().map(|p| i18n::work(&p.work, lang)).collect::<Vec<_>>().join(" + ");
                        let short = if s.shortened {
                            if fr {
                                " (raccourcie)"
                            } else {
                                " (shortened)"
                            }
                        } else {
                            ""
                        };
                        lines.push(format!("{}–{}{short} · {what}", s.start, s.end));
                    }
                    for o in self.plan.offers.iter().filter(|o| o.date == day && o.kind == journee::SlotKind::Gap) {
                        let what = o.parts.first().map(|p| i18n::work(&p.work, lang)).unwrap_or_default();
                        lines.push(if fr {
                            format!("Heure creuse {}–{} : {what} ?", o.start, o.end)
                        } else {
                            format!("Free period {}–{}: {what}?", o.start, o.end)
                        });
                    }
                    let title = if fr {
                        format!("Demain · {}", i18n::date(day, lang))
                    } else {
                        format!("Tomorrow · {}", i18n::date(day, lang))
                    };
                    self.notify(&title, &lines.join("\n"), &[], None);
                }
            }
        }
        let cutoff = now.date.add(-2);
        self.sent.retain(|_, d| *d >= cutoff);
        let _ = store::write_json(&self.store.paths.data.join("alerts.json"), &self.sent);
    }

    fn on_action(&mut self, session: &str, action: &str) {
        let now = self.now();
        let result = if action == "start" {
            self.start(session)
        } else if action == "skip" {
            self.store.record(Event::Skipped { session: session.into() }, now).map(|_| ())
        } else if action == "still:yes" || action == "still:no" {
            self.still_working(action == "still:yes");
            Ok(())
        } else if action == "close" {
            self.close(session, None, None).map(|_| ())
        } else if let Some(t) = action.strip_prefix("later:").and_then(Hm::parse) {
            self.store.record(Event::Postponed { session: session.into(), to: Local::new(now.date, t) }, now).map(|_| ())
        } else {
            Ok(())
        };
        if result.is_ok() {
            self.replan();
        }
    }

    /// Starts a session and opens its first file in Liseuse.
    pub(crate) fn start(&mut self, session: &str) -> io::Result<()> {
        let now = self.now();
        self.store.record(Event::Started { session: session.into(), at: now }, now)?;
        self.session_started(session);
        let item = self.plan.sessions.iter().find(|s| s.id == session).and_then(|s| {
            s.parts.iter().find_map(|p| match &p.work {
                Work::Study { item, .. } | Work::Read { item } | Work::Review { item, .. } | Work::Redo { item, .. } | Work::ExamSubject { item, .. } => {
                    Some(item.clone())
                }
                _ => None,
            })
        });
        if let (Some(item), Some(root)) = (item, self.store.settings.courses.clone()) {
            let path = root.join(item);
            let opener = if which("liseuse").is_some() { "liseuse" } else { "xdg-open" };
            self.spawn(Command::new(opener).arg(path), Job::Quiet);
        }
        Ok(())
    }

    // ─── Socket ──────────────────────────────────────────────────────────

    fn status(&self) -> Value {
        let now = self.now();
        let st = &self.store.state;
        let open = |s: &&Session| {
            !matches!(st.outcomes.get(&s.id), Some(Outcome::Closed { .. } | Outcome::Skipped | Outcome::Missed))
        };
        let active = self.plan.sessions.iter().find(|s| matches!(st.outcomes.get(&s.id), Some(Outcome::Started { .. } | Outcome::Paused { .. })));
        let next = self
            .plan
            .sessions
            .iter()
            .filter(|s| s.counted && !s.parts.is_empty() && Local::new(s.date, s.end) > now)
            .find(open);
        // Started and never closed: to declare.
        let declare: Vec<&String> = st
            .outcomes
            .iter()
            .filter(|(id, o)| matches!(o, Outcome::Started { .. } | Outcome::Paused { .. }) && !self.plan.sessions.iter().any(|s| s.id == **id && Local::new(s.date, s.end).plus(15) > now))
            .map(|(id, _)| id)
            .collect();
        let gap = self
            .plan
            .offers
            .iter()
            .find(|o| o.kind == journee::SlotKind::Gap && o.date == now.date && o.start <= now.time && now.time < o.end);
        json!({
            "event": "status",
            "lang": self.lang(),
            "paused": self.plan.paused,
            "next": next,
            "active": active.map(|s| json!({ "session": s, "outcome": st.outcomes.get(&s.id) })),
            "declare": declare,
            "gap": gap,
            "missed_streak": st.missed_streak,
            "calendar": {
                "set": self.store.settings.calendar_url.is_some(),
                "age_minutes": self.ade.as_ref().map(|s| (now_secs() - s.fetched) / 60),
                "error": self.ade_error,
            },
            "undecided": self.catalogue.undecided(&st.progress.files).len(),
            "suivi": self.suivi_status(),
        })
    }

    pub(crate) fn push_status(&mut self) {
        let msg = self.status();
        self.broadcast(&msg);
    }

    pub(crate) fn broadcast(&mut self, msg: &Value) {
        let mut line = msg.to_string();
        line.push('\n');
        self.clients.retain_mut(|c| c.stream.write_all(line.as_bytes()).is_ok());
    }

    fn send_to(&mut self, id: u64, msg: &Value) {
        let mut line = msg.to_string();
        line.push('\n');
        if let Some(i) = self.clients.iter().position(|c| c.id == id) {
            if self.clients[i].stream.write_all(line.as_bytes()).is_err() {
                self.clients.remove(i);
            }
        }
    }

    fn accept(&mut self) {
        while let Ok((stream, _)) = self.listener.accept() {
            if stream.set_nonblocking(true).is_err() {
                continue;
            }
            let id = self.next_client;
            self.next_client += 1;
            self.clients.push(Client { id, stream, inbox: Vec::new() });
            let msg = self.status();
            self.send_to(id, &msg);
        }
    }

    fn read_client(&mut self, i: usize) -> bool {
        let mut buf = [0u8; 4096];
        loop {
            match self.clients[i].stream.read(&mut buf) {
                Ok(0) => return false,
                Ok(n) => self.clients[i].inbox.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => return false,
            }
        }
        let id = self.clients[i].id;
        let mut lines = Vec::new();
        while let Some(nl) = self.clients[i].inbox.iter().position(|&b| b == b'\n') {
            lines.push(self.clients[i].inbox.drain(..=nl).collect::<Vec<u8>>());
        }
        let too_long = self.clients[i].inbox.len() > 256 * 1024;
        for line in lines {
            let Ok(cmd) = serde_json::from_slice::<Value>(&line) else { continue };
            let name = cmd.get("cmd").and_then(Value::as_str).unwrap_or("").to_string();
            let reply = match self.command(&name, &cmd) {
                Ok((text, data)) => json!({ "reply": name, "ok": true, "text": text, "data": data }),
                Err(text) => json!({ "reply": name, "ok": false, "text": text }),
            };
            self.send_to(id, &reply);
        }
        !too_long
    }

    // ─── Commands ────────────────────────────────────────────────────────

    fn command(&mut self, name: &str, cmd: &Value) -> Result<(String, Value), String> {
        let now = self.now();
        let fr = self.fr();
        let lang = self.lang();
        let s = |k: &str| cmd.get(k).and_then(Value::as_str).map(String::from);
        let apply = cmd.get("apply").and_then(Value::as_bool).unwrap_or(false);
        let io = |e: io::Error| e.to_string();
        let session_arg = |me: &Self| -> Result<Session, String> {
            match s("session") {
                Some(id) => me.plan.session(&id).cloned().ok_or_else(|| format!("{id}?")),
                None => me
                    .plan
                    .sessions
                    .iter()
                    .find(|x| x.counted && !x.parts.is_empty() && Local::new(x.date, x.end) > now)
                    .cloned()
                    .ok_or_else(|| (if fr { "Aucune séance à venir." } else { "No session ahead." }).to_string()),
            }
        };
        let out = match name {
            "status" => (self.status_text(), self.status()),
            "plan" => {
                let days = cmd.get("days").and_then(Value::as_i64).unwrap_or(7) as i32;
                (self.days_text(now.date, days), serde_json::to_value(&self.plan).unwrap())
            }
            "start" => {
                let x = session_arg(self)?;
                self.start(&x.id).map_err(io)?;
                self.replan();
                (if fr { format!("Séance {} commencée.", x.id) } else { format!("Session {} started.", x.id) }, Value::Null)
            }
            "later" => {
                let x = session_arg(self)?;
                let t = s("at").and_then(|t| Hm::parse(&t)).ok_or("HH:MM")?;
                let r = &self.store.settings.rhythm;
                if t.plus(r.min_session) > r.latest_end || t < now.time {
                    return Err(if fr { format!("{t} : plus de place avant {}.", r.latest_end) } else { format!("{t}: no room before {}.", r.latest_end) });
                }
                self.store.record(Event::Postponed { session: x.id.clone(), to: Local::new(now.date, t) }, now).map_err(io)?;
                self.replan();
                (if fr { format!("Reportée à {t}.") } else { format!("Moved to {t}.") }, Value::Null)
            }
            "skip" => {
                let x = session_arg(self)?;
                self.store.record(Event::Skipped { session: x.id.clone() }, now).map_err(io)?;
                self.replan();
                (self.changes_text(), Value::Null)
            }
            "pause-session" => {
                let x = session_arg(self)?;
                self.store.record(Event::Paused { session: x.id.clone(), at: now }, now).map_err(io)?;
                self.session_paused(true);
                self.replan();
                (String::new(), Value::Null)
            }
            "resume-session" => {
                let x = session_arg(self)?;
                self.store.record(Event::Resumed { session: x.id.clone(), at: now }, now).map_err(io)?;
                self.session_paused(false);
                self.replan();
                (String::new(), Value::Null)
            }
            "activity" => {
                self.set_activity(cmd.get("idle").and_then(Value::as_bool), cmd.get("media").and_then(Value::as_bool));
                (String::new(), Value::Null)
            }
            "still" => {
                self.still_working(cmd.get("yes").and_then(Value::as_bool).unwrap_or(true));
                (String::new(), Value::Null)
            }
            "draft" => {
                let x = session_arg(self)?;
                let d = self.draft(&x.id).ok_or("draft")?;
                (draft_text(&d, &x, lang), serde_json::to_value(&d).unwrap())
            }
            "close" => {
                let x = session_arg(self)?;
                let parts = match cmd.get("parts") {
                    Some(p) => Some(serde_json::from_value(p.clone()).map_err(|e| e.to_string())?),
                    None => None,
                };
                let media = cmd.get("media_for_course").and_then(Value::as_bool);
                self.close(&x.id, parts, media).map_err(io)?;
                (self.changes_text(), Value::Null)
            }
            "done" => {
                let x = session_arg(self)?;
                let parts: Vec<PartReport> = match cmd.get("parts") {
                    Some(p) => serde_json::from_value(p.clone()).map_err(|e| e.to_string())?,
                    // Everything as planned.
                    None => x
                        .parts
                        .iter()
                        .map(|p| PartReport {
                            task: p.task.clone(),
                            minutes: p.minutes,
                            planned: p.minutes,
                            done: true,
                            read_upto: study_upto(&p.work),
                            exercises: study_exercises(&p.work),
                            assessment: Some(Assessment::Understood),
                            note: None,
                        })
                        .collect(),
                };
                let minutes = parts.iter().map(|p| p.minutes).sum();
                let tracking = self.session_closed(None);
                self.store.record(Event::Closed { session: x.id.clone(), at: now, minutes, parts, tracking }, now).map_err(io)?;
                self.replan();
                (self.changes_text(), Value::Null)
            }
            "add" => {
                let line = s("line").unwrap_or_default();
                let domains: Vec<String> = self.store.settings.domains.iter().map(|d| d.id.clone()).collect();
                let projects: Vec<(String, String, Option<String>)> =
                    self.store.state.projects.iter().map(|p| (p.id.clone(), p.name.clone(), p.domain.clone())).collect();
                let cx = ajout::Context { today: now.date, lang, domains: &domains, projects: &projects, campaigns: &self.store.state.campaigns };
                let u = ajout::parse(&line, &cx).map_err(|e| ajout::explain(&e, lang))?;
                if let Action::Free { minutes, place } = u.action {
                    return Ok((format!("{}\n{}", u.sentence, self.free_time(minutes, place)), Value::Null));
                }
                let ev = match u.action {
                    Action::Deadline(d) => Event::Deadline { deadline: d },
                    Action::Busy(b) => Event::Busy { busy: b },
                    Action::Chore(c) => Event::Chore { chore: c },
                    Action::Apply { campaign, company } => {
                        let mut c = self.store.state.campaigns.iter().find(|c| c.id == campaign).cloned().ok_or("campaign")?;
                        c.rows.push(Row { name: company, status: RowStatus::ToSend, sent: None, interview: None });
                        Event::Campaign { campaign: c }
                    }
                    Action::Free { .. } => unreachable!(),
                };
                if !apply {
                    // Its effect, on a copy of the journal.
                    let mut entries = self.store.entries.clone();
                    entries.push(store::Entry { seq: self.store.state.seq + 1, at: now, event: ev });
                    let preview = self.compute(&store::reduce(&entries), &[], &[], Some(&self.plan));
                    let effect = i18n::changes(&preview.changes, now.date, lang);
                    let text = if effect.is_empty() { u.sentence } else { format!("{}\n{effect}", u.sentence) };
                    return Ok((text, json!({ "understood": true })));
                }
                self.store.record(ev, now).map_err(io)?;
                self.replan();
                (format!("{}\n{}", u.sentence, self.changes_text()).trim().to_string(), Value::Null)
            }
            "undo" => {
                let e = self.store.undo(now).map_err(io)?;
                self.replan();
                match e {
                    Some(e) => (if fr { format!("Annulé : {}.", event_label(&e.event)) } else { format!("Undone: {}.", event_label(&e.event)) }, Value::Null),
                    None => ((if fr { "Rien à annuler." } else { "Nothing to undo." }).into(), Value::Null),
                }
            }
            "history" => {
                let lines: Vec<String> = self.store.history(20).iter().map(|e| format!("{}  {}", i18n::local(e.at, lang), event_label(&e.event))).collect();
                (lines.join("\n"), Value::Null)
            }
            "move" | "pin" => {
                let x = session_arg(self)?;
                let part = match s("task") {
                    Some(t) => x.parts.iter().find(|p| p.task == t).cloned(),
                    None => x.parts.first().cloned(),
                }
                .ok_or("task?")?;
                let (date, start) = if name == "pin" {
                    (x.date, x.start)
                } else {
                    let date = s("date").and_then(|d| ajout_date(&d, now.date)).ok_or(if fr { "date ?" } else { "date?" })?;
                    let start = s("at").and_then(|t| Hm::parse(&t)).ok_or("HH:MM")?;
                    (date, start)
                };
                let pin = Pin { task: part.task.clone(), date, start, minutes: part.minutes, work: Some(part.work.clone()), domain: part.domain.clone() };
                let preview = self.compute(&self.store.state, std::slice::from_ref(&pin), &[], Some(&self.plan));
                let placed = preview.sessions.iter().any(|s| s.date == date && s.parts.iter().any(|p| p.task == part.task));
                if !placed {
                    return Err(if fr { format!("Pas de séance possible {} à {start}.", i18n::date(date, lang)) } else { format!("No session possible on {} at {start}.", i18n::date(date, lang)) });
                }
                let effect = i18n::changes(&preview.changes, now.date, lang);
                if !apply {
                    return Ok((effect, Value::Null));
                }
                self.store.record(Event::Pin { pin }, now).map_err(io)?;
                self.replan();
                (effect, Value::Null)
            }
            "unpin" => {
                let task = s("task").ok_or("task")?;
                self.store.record(Event::Unpin { task }, now).map_err(io)?;
                self.replan();
                (self.changes_text(), Value::Null)
            }
            "files" => {
                if let (Some(items), Some(inc)) = (cmd.get("items"), s("inclusion")) {
                    let items: Vec<String> = serde_json::from_value(items.clone()).map_err(|e| e.to_string())?;
                    if let Some(bad) = items.iter().find(|i| self.catalogue.get(i).is_none()) {
                        return Err(if fr { format!("« {bad} » n'est pas dans le dossier de cours.") } else { format!("“{bad}” is not in the course folder.") });
                    }
                    let inclusion = if inc == "planned" { Inclusion::Planned } else { Inclusion::Ignored };
                    self.store.record(Event::Files { items, inclusion }, now).map_err(io)?;
                    self.replan();
                }
                let new: Vec<String> = self.catalogue.undecided(&self.store.state.progress.files).iter().map(|i| i.id.clone()).collect();
                (new.join("\n"), json!(new))
            }
            "deadlines" => {
                let (_, cal) = self.timetable();
                let all = self.deadlines(cal);
                let lines: Vec<String> = all.iter().map(|d| format!("{}  {}  {}", d.id, i18n::local(d.at, lang), d.title)).collect();
                (lines.join("\n"), serde_json::to_value(&all).unwrap())
            }
            "deadline-remove" => {
                let id = s("id").ok_or("id")?;
                self.store.record(Event::DeadlineRemoved { id }, now).map_err(io)?;
                self.replan();
                (self.changes_text(), Value::Null)
            }
            "project" => {
                let p: Project = serde_json::from_value(cmd.get("project").cloned().ok_or("project")?).map_err(|e| e.to_string())?;
                self.store.record(Event::Project { project: p }, now).map_err(io)?;
                self.replan();
                (self.changes_text(), Value::Null)
            }
            "project-remove" => {
                self.store.record(Event::ProjectRemoved { id: s("id").ok_or("id")? }, now).map_err(io)?;
                self.replan();
                (String::new(), Value::Null)
            }
            "projects" => {
                let lines: Vec<String> = self
                    .store
                    .state
                    .projects
                    .iter()
                    .map(|p| {
                        let left: f32 = p.steps.iter().filter(|s| !s.done).map(|s| s.hours).sum();
                        format!("{}  {}  {}  {left} h", p.id, i18n::local(p.due, lang), p.steps.len())
                    })
                    .collect();
                (lines.join("\n"), serde_json::to_value(&self.store.state.projects).unwrap())
            }
            "campaign" => {
                let c: Campaign = serde_json::from_value(cmd.get("campaign").cloned().ok_or("campaign")?).map_err(|e| e.to_string())?;
                self.store.record(Event::Campaign { campaign: c }, now).map_err(io)?;
                self.replan();
                (String::new(), Value::Null)
            }
            "campaigns" => {
                let lines: Vec<String> = self
                    .store
                    .state
                    .campaigns
                    .iter()
                    .flat_map(|c| {
                        std::iter::once(format!("{}  {} → {}", c.name, i18n::date(c.start, lang), i18n::date(c.end, lang)))
                            .chain(c.rows.iter().map(|r| format!("  {}  {:?}", r.name, r.status)))
                    })
                    .collect();
                (lines.join("\n"), serde_json::to_value(&self.store.state.campaigns).unwrap())
            }
            "settings" => (String::new(), serde_json::to_value(&self.store.settings).unwrap()),
            "set" => {
                // A JSON merge patch over the settings, checked before it is kept.
                let patch = cmd.get("patch").cloned().ok_or("patch")?;
                let mut v = serde_json::to_value(&self.store.settings).unwrap();
                merge(&mut v, &patch);
                let settings: Settings = serde_json::from_value(v).map_err(|e| e.to_string())?;
                let url_changed = settings.calendar_url != self.store.settings.calendar_url;
                let courses_changed = settings.courses != self.store.settings.courses || settings.ignore != self.store.settings.ignore;
                self.store.settings = settings;
                self.store.save_settings().map_err(io)?;
                if courses_changed {
                    self.rescan();
                }
                if url_changed {
                    self.ade = None;
                    self.fetch();
                }
                self.replan();
                (self.changes_text(), Value::Null)
            }
            "groups" => {
                let fams = self.ade.as_ref().map(|s| ade::families(&s.events)).unwrap_or_default();
                let lines: Vec<String> = fams
                    .iter()
                    .map(|f| {
                        let chosen = self.store.settings.groups.get(&f.name);
                        let vals: Vec<String> = f
                            .values
                            .iter()
                            .map(|(v, n)| if chosen.is_some_and(|c| c.contains(v)) { format!("[{v}]×{n}") } else { format!("{v}×{n}") })
                            .collect();
                        format!("{}: {}", f.name, vals.join("  "))
                    })
                    .collect();
                (lines.join("\n"), serde_json::to_value(&fams).unwrap())
            }
            "refresh" => {
                self.fetch();
                self.spawn_khal();
                self.rescan();
                self.replan();
                (String::new(), Value::Null)
            }
            "gate" => {
                let active = self.plan.sessions.iter().find(|x| {
                    matches!(self.store.state.outcomes.get(&x.id), Some(Outcome::Started { .. }))
                        && x.date == now.date
                        && x.end > now.time
                });
                match (self.store.settings.gate, active) {
                    (true, Some(x)) => {
                        let what = x.parts.first().map(|p| format!("{}{}", p.domain.as_deref().map(|d| format!("{d} ")).unwrap_or_default(), i18n::work(&p.work, lang))).unwrap_or_default();
                        let text = if fr { format!("Séance {what} jusqu'à {}", x.end) } else { format!("Session {what} until {}", x.end) };
                        (text, json!({ "locked": true, "session": x.id, "match": self.store.settings.gate_match }))
                    }
                    _ => (String::new(), json!({ "locked": false })),
                }
            }
            _ => return Err(format!("{name}?")),
        };
        Ok(out)
    }

    fn changes_text(&self) -> String {
        i18n::changes(&self.plan.changes, self.now().date, self.lang())
    }

    fn status_text(&self) -> String {
        let fr = self.fr();
        let lang = self.lang();
        let v = self.status();
        let mut lines = Vec::new();
        if self.plan.paused {
            lines.push((if fr { "En pause." } else { "Paused." }).to_string());
        }
        if let Some(s) = v.get("next").and_then(|n| serde_json::from_value::<Session>(n.clone()).ok()) {
            lines.push(format!("{} {}–{}  {}", i18n::date(s.date, lang), s.start, s.end, s.id));
            lines.push(self.session_body(&s));
        }
        if let Some(age) = v["calendar"]["age_minutes"].as_i64() {
            lines.push(if fr { format!("ADE vu il y a {age} min.") } else { format!("ADE seen {age} min ago.") });
        }
        if let Some(e) = v["calendar"]["error"].as_str() {
            lines.push(if fr { format!("Dernière récupération ADE en échec ({e}) : l'emploi du temps gardé est le précédent.") } else { format!("Last ADE download failed ({e}): the previous timetable is kept.") });
        }
        lines.extend(crate::suivi::status_lines(&v["suivi"], fr));
        let n = v["undecided"].as_u64().unwrap_or(0);
        if n > 0 {
            lines.push(if fr { format!("{n} fichiers à planifier (boussole files).") } else { format!("{n} files to plan (boussole files).") });
        }
        lines.join("\n")
    }

    fn days_text(&self, from: Date, days: i32) -> String {
        let lang = self.lang();
        let (courses, _) = self.timetable();
        let mut out = Vec::new();
        for day in (0..days).map(|i| from.add(i)) {
            let mut lines: Vec<(Hm, String)> = Vec::new();
            for c in courses.iter().filter(|c| c.start.date == day) {
                lines.push((c.start.time, format!("  {}–{}    {}", c.start.time, c.end.time, c.title)));
            }
            for s in self.plan.sessions.iter().chain(&self.plan.offers).filter(|s| s.date == day && !s.parts.is_empty()) {
                let tag = if s.counted { "●" } else { "○" };
                let what: Vec<String> = s
                    .parts
                    .iter()
                    .map(|p| format!("{}{} ({}′)", p.domain.as_deref().map(|d| format!("{d} ")).unwrap_or_default(), i18n::work(&p.work, lang), p.minutes))
                    .collect();
                let state = match self.store.state.outcomes.get(&s.id) {
                    Some(Outcome::Closed { .. }) => " ✓",
                    Some(Outcome::Skipped | Outcome::Missed) => " ✗",
                    _ => "",
                };
                lines.push((s.start, format!("{tag} {}–{}  {}{state}  [{}]", s.start, s.end, what.join(" + "), s.id)));
            }
            lines.sort_by_key(|l| l.0);
            out.push(i18n::date(day, lang));
            out.extend(lines.into_iter().map(|l| l.1));
        }
        if !self.plan.margins.is_empty() {
            out.push(String::new());
            for m in &self.plan.margins {
                out.push(if self.fr() {
                    format!("Marge avant {} ({}) : {} séances", m.title, i18n::date(m.date, lang), m.sessions)
                } else {
                    format!("Margin before {} ({}): {} sessions", m.title, i18n::date(m.date, lang), m.sessions)
                });
            }
        }
        out.join("\n")
    }

    /// "I have time": the most useful work that fits, from what is planned next.
    fn free_time(&self, minutes: i32, place: Place) -> String {
        let fr = self.fr();
        let lang = self.lang();
        let now = self.now();
        let found = self
            .plan
            .sessions
            .iter()
            .filter(|s| Local::new(s.date, s.start) >= now)
            .flat_map(|s| s.parts.iter().map(move |p| (s, p)))
            .find(|(_, p)| p.minutes <= minutes && (place == Place::Home || !p.timed) && !matches!(p.work, Work::Campaign { .. } | Work::Recall { .. }));
        match found {
            Some((s, p)) => {
                let what = format!("{}{}", p.domain.as_deref().map(|d| format!("{d} ")).unwrap_or_default(), i18n::work(&p.work, lang));
                if fr {
                    format!("{what} ({} min), prévue {} à {}. La faire maintenant avance le programme.", p.minutes, i18n::date(s.date, lang), s.start)
                } else {
                    format!("{what} ({} min), planned {} at {}. Doing it now moves the plan forward.", p.minutes, i18n::date(s.date, lang), s.start)
                }
            }
            None => (if fr { "Rien de prévu ne tient dans ce temps." } else { "Nothing planned fits in that time." }).into(),
        }
    }
}

impl Service {
    /// "Close": the user's report, or else the pre-filled one, with what
    /// the tracking measured. Media time counts only if it was for the course.
    pub(crate) fn close(&mut self, session: &str, parts: Option<Vec<PartReport>>, media_for_course: Option<bool>) -> io::Result<()> {
        let now = self.now();
        let draft = self.draft(session);
        let mut parts = parts.or_else(|| draft.as_ref().map(|d| d.parts.clone())).unwrap_or_default();
        let effective = draft.as_ref().map_or(0, |d| d.effective_minutes - if media_for_course == Some(false) { d.media_minutes } else { 0 });
        let reported: i32 = parts.iter().map(|p| p.minutes).sum();
        if reported == 0 && effective > 0 {
            let planned: i32 = parts.iter().map(|p| p.planned).sum::<i32>().max(1);
            for p in &mut parts {
                p.minutes = effective * p.planned / planned;
            }
        }
        let minutes = parts.iter().map(|p| p.minutes).sum();
        let tracking = self.session_closed(media_for_course);
        self.store.record(Event::Closed { session: session.into(), at: now, minutes, parts, tracking }, now)?;
        self.replan();
        Ok(())
    }
}

fn draft_text(d: &crate::seance::Draft, s: &Session, lang: Lang) -> String {
    let fr = lang == Lang::Fr;
    let mut out = vec![if fr {
        format!("{} · {} min effectives", s.id, d.effective_minutes)
    } else {
        format!("{} · {} effective min", s.id, d.effective_minutes)
    }];
    for (p, r) in s.parts.iter().zip(&d.parts) {
        let upto = r.read_upto.map(|u| format!(" · lu jusqu'au §{u}")).unwrap_or_default();
        out.push(format!("  {} ({} min){upto}", i18n::work(&p.work, lang), r.minutes));
    }
    for f in &d.files {
        let name = i18n::item_name(&f.item);
        out.push(if fr {
            format!("  {name} : {} pages lues, {} survolées", f.read.len(), f.skimmed.len())
        } else {
            format!("  {name}: {} pages read, {} skimmed", f.read.len(), f.skimmed.len())
        });
        if let Some((day, upto)) = f.before {
            out.push(if fr { format!("    déjà lu jusqu'au §{upto} le {}, à confirmer", i18n::date(day, lang)) } else { format!("    read up to §{upto} on {}, to confirm", i18n::date(day, lang)) });
        }
    }
    if d.media_minutes > 0 {
        out.push(if fr { format!("Une vidéo a joué {} min : pour le cours ?", d.media_minutes) } else { format!("A video played for {} min: for the course?", d.media_minutes) });
    }
    out.join("\n")
}

fn study_upto(w: &Work) -> Option<u32> {
    match w {
        Work::Study { sections: Some((_, b)), .. } => Some(*b),
        _ => None,
    }
}

fn study_exercises(w: &Work) -> BTreeMap<u32, Exercise> {
    match w {
        Work::Study { exercises: Some((a, b)), .. } => (*a..=*b).map(|n| (n, Exercise::Solo)).collect(),
        _ => BTreeMap::new(),
    }
}

fn ajout_date(s: &str, today: Date) -> Option<Date> {
    Date::parse(s).or_else(|| {
        let cx = ajout::Context { today, lang: Lang::En, domains: &[], projects: &[], campaigns: &[] };
        match ajout::parse(&format!("indispo {s} 10h-11h"), &cx) {
            Ok(ajout::Understood { action: Action::Busy(b), .. }) => Some(b.start.date),
            _ => None,
        }
    })
}

fn event_label(e: &Event) -> String {
    match e {
        Event::Started { session, .. } => format!("start {session}"),
        Event::Postponed { session, to } => format!("later {session} → {}", to.time),
        Event::Skipped { session } => format!("skip {session}"),
        Event::Missed { session } => format!("missed {session}"),
        Event::Paused { session, .. } => format!("pause {session}"),
        Event::Closed { session, .. } => format!("close {session}"),
        Event::Files { items, inclusion } => format!("{} file(s) {inclusion:?}", items.len()),
        Event::Deadline { deadline } => deadline.title.clone(),
        Event::DeadlineRemoved { id } => format!("− {id}"),
        Event::Project { project } => project.name.clone(),
        Event::ProjectRemoved { id } => format!("− {id}"),
        Event::Campaign { campaign } => campaign.name.clone(),
        Event::Chore { chore } => chore.title.clone(),
        Event::Busy { busy } => format!("busy {} {}–{}", busy.start.date, busy.start.time, busy.end.time),
        Event::BusyRemoved { start } => format!("− busy {start}"),
        Event::Pin { pin } => format!("pin {} → {} {}", pin.task, pin.date, pin.start),
        Event::Unpin { task } => format!("unpin {task}"),
        Event::Undo { of } => format!("undo #{of}"),
        Event::Resumed { session, .. } => format!("resume {session}"),
        Event::FreeReading { item, upto, .. } => format!("{} §{upto}", i18n::item_name(item)),
    }
}

/// RFC 7386 merge patch.
fn merge(target: &mut Value, patch: &Value) {
    match (target, patch) {
        (Value::Object(t), Value::Object(p)) => {
            for (k, v) in p {
                if v.is_null() {
                    t.remove(k);
                } else {
                    merge(t.entry(k.clone()).or_insert(Value::Null), v);
                }
            }
        }
        (t, p) => *t = p.clone(),
    }
}
