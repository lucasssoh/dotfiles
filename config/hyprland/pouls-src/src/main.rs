//! Pouls: the system figures behind the bar.
//!
//! One thread, blocked in poll(2) on:
//!   - the kernel's uevent socket, for the charger and the battery;
//!   - the socket at $XDG_RUNTIME_DIR/pouls.sock and its clients.
//! poll only gets a timeout while a client is watching and the screen is on:
//! that is the 3 s sample of the figures that have no event (stats.rs). With
//! the screen off or the bar in zen mode, only a uevent wakes it.
//!
//! The socket speaks JSON lines, like Balise's and Manette's.
//!   pushed:   {"event":"stats",…}         on watch and when what the bar shows changes
//!             {"event":"power",…}         on connect and on any change
//!             {"event":"adapterDropped"}  the charger latched off (power.rs)
//!   accepted: {"cmd":"watch","on":bool}   the client shows the figures, or not
//!             {"cmd":"iface","name":"…"}  whose download rate to show
//!             {"cmd":"screen","on":bool}  from `pouls screen on|off` (idle-action.sh)
//!             {"cmd":"conservation","on":bool}
//!             {"cmd":"fastCharge","on":bool}

mod attr;
mod power;
mod stats;

use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use power::{Power, PowerState};
use stats::Sampler;

const TICK: Duration = Duration::from_secs(3);
const ADAPTER_SETTLE: Duration = Duration::from_secs(2);
/// How late the kernel may fire our timeout to batch it with other wakeups.
/// A figure shown 250 ms late is invisible; a wakeup shared is one saved.
const TIMER_SLACK_NS: libc::c_ulong = 250_000_000;

struct Client {
    id: u64,
    stream: UnixStream,
    inbox: Vec<u8>,
    watch: bool,
}

struct Daemon {
    uevent: RawFd,
    listener: UnixListener,
    clients: Vec<Client>,
    next_client: u64,
    screen_on: bool,
    sampler: Sampler,
    power: Power,
    power_state: PowerState,
    /// What the clients were last sent, as stats::Figures::shown().
    shown: String,
    next_tick: Option<Instant>,
    adapter_check: Option<Instant>,
}

fn socket_path() -> PathBuf {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    dir.join("pouls.sock")
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        [] => {
            if let Err(e) = run() {
                eprintln!("pouls: {e}");
                std::process::exit(1);
            }
        }
        ["--version" | "-V"] => println!("pouls {}", env!("CARGO_PKG_VERSION")),
        // Never fails: the idle ladder must not stall on a daemon that is
        // not running.
        ["screen", state @ ("on" | "off")] => {
            if let Ok(mut s) = UnixStream::connect(socket_path()) {
                let _ = writeln!(s, "{}", json!({ "cmd": "screen", "on": *state == "on" }));
                // Wait for the greeting every client gets: hanging up before
                // it is sent would make that send fail, and the daemon would
                // drop us with the line unread.
                let _ = s.set_read_timeout(Some(Duration::from_secs(1)));
                let _ = s.read(&mut [0u8; 512]);
            }
        }
        _ => eprintln!("usage: pouls                 runs the daemon (see pouls.service)\n       pouls screen on|off   tells it the screen went on or off"),
    }
}

fn run() -> io::Result<()> {
    let path = socket_path();
    if UnixStream::connect(&path).is_ok() {
        return Err(io::Error::new(ErrorKind::AddrInUse, "already running"));
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;
    listener.set_nonblocking(true)?;

    // SAFETY: plain syscalls with constant arguments.
    unsafe { libc::prctl(libc::PR_SET_TIMERSLACK, TIMER_SLACK_NS) };

    let mut d = Daemon {
        uevent: open_uevent()?,
        listener,
        clients: Vec::new(),
        next_client: 1,
        screen_on: true,
        sampler: Sampler::open(),
        power: Power::open(),
        power_state: PowerState::default(),
        shown: String::new(),
        next_tick: None,
        adapter_check: None,
    };
    d.power_state = d.power.read();
    d.run()
}

/// The kernel's own uevent broadcast, the one udev listens to. Joining group
/// 1 needs no privilege.
fn open_uevent() -> io::Result<RawFd> {
    // SAFETY: socket/bind with a zeroed, correctly sized sockaddr_nl.
    unsafe {
        let fd = libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_DGRAM | libc::SOCK_NONBLOCK | libc::SOCK_CLOEXEC,
            libc::NETLINK_KOBJECT_UEVENT,
        );
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let mut addr: libc::sockaddr_nl = std::mem::zeroed();
        addr.nl_family = libc::AF_NETLINK as libc::sa_family_t;
        addr.nl_groups = 1;
        let len = std::mem::size_of::<libc::sockaddr_nl>() as libc::socklen_t;
        if libc::bind(fd, (&addr as *const libc::sockaddr_nl).cast(), len) < 0 {
            let e = io::Error::last_os_error();
            libc::close(fd);
            return Err(e);
        }
        Ok(fd)
    }
}

impl Daemon {
    fn sampling(&self) -> bool {
        self.screen_on && self.clients.iter().any(|c| c.watch)
    }

    fn run(&mut self) -> io::Result<()> {
        let mut fds: Vec<libc::pollfd> = Vec::new();
        loop {
            self.arm_tick();

            fds.clear();
            let pfd = |fd: RawFd| libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
            fds.push(pfd(self.uevent));
            fds.push(pfd(self.listener.as_raw_fd()));
            fds.extend(self.clients.iter().map(|c| pfd(c.stream.as_raw_fd())));

            let now = Instant::now();
            let timeout = match [self.next_tick, self.adapter_check].into_iter().flatten().min() {
                Some(t) => t.saturating_duration_since(now).as_millis().min(i32::MAX as u128) as i32,
                None => -1,
            };
            // SAFETY: fds is a live, correctly sized array of pollfd.
            let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) };
            if n < 0 {
                let e = io::Error::last_os_error();
                if e.kind() == ErrorKind::Interrupted {
                    continue;
                }
                return Err(e);
            }
            let now = Instant::now();

            // By identity rather than by index: a send can drop a client.
            let ready: Vec<u64> = (0..self.clients.len())
                .filter(|&i| fds[2 + i].revents != 0)
                .map(|i| self.clients[i].id)
                .collect();
            for id in ready {
                let Some(i) = self.clients.iter().position(|c| c.id == id) else { continue };
                if !self.read_client(i) {
                    self.clients.retain(|c| c.id != id);
                }
            }
            if fds[1].revents != 0 {
                self.accept();
            }
            if fds[0].revents != 0 && self.read_uevents() {
                self.refresh_power(now);
            }

            if self.next_tick.is_some_and(|t| now >= t) {
                self.next_tick = Some(now + TICK);
                self.sampler.sample(now);
                self.push_stats(false);
                // No power read here. conservation_mode and charge_types
                // are answered by the embedded controller, 6.7 ms each with
                // the process put to sleep for it (measured), and the
                // charger has its uevent: every 3 s that would be paying
                // twice for nothing.
            }
            if self.adapter_check.is_some_and(|t| now >= t) {
                self.adapter_check = None;
                if self.power_state.mains == Some(false) && power::adapter_dropped() {
                    self.broadcast(&json!({ "event": "adapterDropped" }));
                }
            }
        }
    }

    /// Start or stop the sample to match whether anyone is looking. Starting
    /// samples at once, so a bar coming back shows fresh figures, not those
    /// from before the screen went off.
    fn arm_tick(&mut self) {
        match (self.sampling(), self.next_tick.is_some()) {
            (true, false) => {
                let now = Instant::now();
                self.sampler.sample(now);
                self.push_stats(true);
                self.next_tick = Some(now + TICK);
            }
            (false, true) => {
                self.next_tick = None;
                self.sampler.forget();
            }
            _ => {}
        }
    }

    /// True when a power_supply or typec device changed.
    fn read_uevents(&mut self) -> bool {
        let mut buf = [0u8; 8192];
        let mut relevant = false;
        loop {
            // SAFETY: reading into a local buffer of the given length.
            let n = unsafe { libc::recv(self.uevent, buf.as_mut_ptr().cast(), buf.len(), 0) };
            if n <= 0 {
                return relevant;
            }
            relevant |= buf[..n as usize]
                .split(|&b| b == 0)
                .any(|kv| kv == b"SUBSYSTEM=power_supply" || kv == b"SUBSYSTEM=typec");
        }
    }

    fn refresh_power(&mut self, now: Instant) {
        let s = self.power.read();
        if s == self.power_state {
            return;
        }
        match (self.power_state.mains, s.mains) {
            (Some(true), Some(false)) => self.adapter_check = Some(now + ADAPTER_SETTLE),
            (_, Some(true)) => self.adapter_check = None,
            _ => {}
        }
        self.power_state = s;
        let msg = self.power_state.to_json();
        self.broadcast(&msg);
    }

    fn stats_msg(&self) -> Value {
        self.sampler.now.to_json(self.sampler.has_temp(), self.sampler.has_fan())
    }

    fn push_stats(&mut self, force: bool) {
        let shown = self.sampler.now.shown();
        if !force && shown == self.shown {
            return;
        }
        self.shown = shown;
        let msg = self.stats_msg();
        let ids: Vec<u64> = self.clients.iter().filter(|c| c.watch).map(|c| c.id).collect();
        for id in ids {
            self.send_to(id, &msg);
        }
    }

    fn accept(&mut self) {
        while let Ok((stream, _)) = self.listener.accept() {
            if stream.set_nonblocking(true).is_err() {
                continue;
            }
            let id = self.next_client;
            self.next_client += 1;
            self.clients.push(Client { id, stream, inbox: Vec::new(), watch: false });
            let msg = self.power_state.to_json();
            self.send_to(id, &msg);
        }
    }

    /// False when the client has gone.
    fn read_client(&mut self, i: usize) -> bool {
        let mut buf = [0u8; 1024];
        // `pouls screen off` writes its line and hangs up: the line and the
        // end arrive together, and the line still has to be obeyed.
        let mut open = true;
        loop {
            match self.clients[i].stream.read(&mut buf) {
                Ok(0) => {
                    open = false;
                    break;
                }
                Ok(n) => self.clients[i].inbox.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => {
                    open = false;
                    break;
                }
            }
        }
        let id = self.clients[i].id;
        while let Some(nl) = self.clients[i].inbox.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.clients[i].inbox.drain(..=nl).collect();
            let Ok(cmd) = serde_json::from_slice::<Value>(&line) else { continue };
            let on = cmd.get("on").and_then(Value::as_bool).unwrap_or(false);
            match cmd.get("cmd").and_then(Value::as_str) {
                Some("watch") => {
                    let was = self.clients[i].watch;
                    self.clients[i].watch = on;
                    // A watcher joining while the sample already runs gets
                    // the current figures now rather than at the next change.
                    if on && !was && self.next_tick.is_some() {
                        let msg = self.stats_msg();
                        self.send_to(id, &msg);
                    }
                }
                Some("iface") => {
                    let name = cmd.get("name").and_then(Value::as_str).unwrap_or("");
                    self.sampler.set_iface(name);
                }
                Some("screen") => {
                    self.screen_on = on;
                    // Back from idle or from sleep, when the EC may have put
                    // fast charge back to Standard without a uevent.
                    if on {
                        self.refresh_power(Instant::now());
                    }
                }
                Some("conservation") => {
                    self.power.set_conservation(on);
                    self.refresh_power(Instant::now());
                }
                Some("fastCharge") => {
                    self.power.set_fast_charge(on);
                    self.refresh_power(Instant::now());
                }
                _ => {}
            }
            // send_to above may have dropped this very client.
            if self.clients.get(i).map(|c| c.id) != Some(id) {
                return true;
            }
        }
        // A client that never ends its line does not get to grow forever.
        open && self.clients[i].inbox.len() <= 64 * 1024
    }

    fn send_to(&mut self, id: u64, msg: &Value) {
        let mut line = msg.to_string();
        line.push('\n');
        let failed = self
            .clients
            .iter_mut()
            .find(|c| c.id == id)
            .is_some_and(|c| c.stream.write_all(line.as_bytes()).is_err());
        if failed {
            self.clients.retain(|c| c.id != id);
        }
    }

    fn broadcast(&mut self, msg: &Value) {
        let ids: Vec<u64> = self.clients.iter().map(|c| c.id).collect();
        for id in ids {
            self.send_to(id, msg);
        }
    }
}
