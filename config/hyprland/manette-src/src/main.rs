//! Manette: the gamepad daemon behind the bar's controller popup.
//!
//! One thread, blocked in poll(2) on three kinds of descriptor:
//!   - inotify on /dev/input, for pads plugged in or paired;
//!   - each pad's event node, masked to the Guide button (see pad.rs);
//!   - the socket at $XDG_RUNTIME_DIR/manette.sock and its clients.
//! poll only gets a timeout while Guide is held or a direction repeats in the
//! popup, so a quiet machine never wakes it.
//!
//! The socket speaks JSON lines, like Balise's.
//!   pushed:   {"event":"pads","pads":[…]}         on connect and on any change
//!             {"event":"connected","pad":{…}}     a pad arrived (not at start-up)
//!             {"event":"disconnected","pad":{…}}
//!             {"event":"guide","long":false|true}
//!             {"event":"nav","button":"up|down|left|right|a|b|x|y|lb|rb|lt|rt|select|start|guide"}
//!             {"event":"library","games":[…]}   in answer to "library"
//!   accepted: {"cmd":"grab"}     the popup is open: pads navigate it, games see nothing
//!             {"cmd":"release"}  (also implied when the grabbing client goes away)
//!             {"cmd":"refresh"}  push "pads" again, batteries re-read
//!             {"cmd":"library"}  the installed Steam and Lutris games (library.rs)

mod library;
mod pad;

use std::collections::HashSet;
use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::Instant;

use serde_json::{json, Value};

use pad::{Out, Pad};

struct Client {
    id: u64,
    stream: UnixStream,
    inbox: Vec<u8>,
}

struct Daemon {
    inotify: RawFd,
    listener: UnixListener,
    clients: Vec<Client>,
    next_client: u64,
    pads: Vec<Pad>,
    /// Readable nodes that turned out not to be pads, so an ACL change on a
    /// keyboard does not get it reopened. Forgotten when the node is recreated.
    not_pads: HashSet<String>,
    grab_owner: Option<u64>,
}

fn socket_path() -> PathBuf {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    dir.join("manette.sock")
}

fn main() {
    if let Some(arg) = std::env::args().nth(1) {
        match arg.as_str() {
            "--version" | "-V" => println!("manette {}", env!("CARGO_PKG_VERSION")),
            _ => eprintln!("usage: manette        runs the daemon (see manette.service)"),
        }
        return;
    }
    if let Err(e) = run() {
        eprintln!("manette: {e}");
        std::process::exit(1);
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

    // SAFETY: plain syscalls on a path we own.
    let inotify = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
    if inotify < 0 {
        return Err(io::Error::last_os_error());
    }
    // IN_ATTRIB: udev sets the seat's ACL on a node after creating it, and a
    // node we could not open at IN_CREATE becomes readable then.
    let watch = unsafe {
        libc::inotify_add_watch(inotify, c"/dev/input".as_ptr(), libc::IN_CREATE | libc::IN_ATTRIB)
    };
    if watch < 0 {
        return Err(io::Error::last_os_error());
    }

    let mut d = Daemon {
        inotify,
        listener,
        clients: Vec::new(),
        next_client: 1,
        pads: Vec::new(),
        not_pads: HashSet::new(),
        grab_owner: None,
    };
    for entry in std::fs::read_dir("/dev/input")?.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        d.try_pad(&name, false);
    }
    d.run()
}

impl Daemon {
    fn run(&mut self) -> io::Result<()> {
        let mut fds: Vec<libc::pollfd> = Vec::new();
        let mut outs = Vec::new();
        loop {
            fds.clear();
            let pfd = |fd: RawFd| libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
            fds.push(pfd(self.inotify));
            fds.push(pfd(self.listener.as_raw_fd()));
            fds.extend(self.clients.iter().map(|c| pfd(c.stream.as_raw_fd())));
            fds.extend(self.pads.iter().map(|p| pfd(p.as_raw_fd())));

            let now = Instant::now();
            let timeout = match self.pads.iter().filter_map(Pad::deadline).min() {
                Some(t) => t.saturating_duration_since(now).as_millis().min(i32::MAX as u128) as i32 + 1,
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
            // Who is ready, by identity rather than by index: sending can
            // drop a client and a read can drop a pad, shifting both lists.
            let client_base = 2;
            let pad_base = client_base + self.clients.len();
            let ready_clients: Vec<u64> = (0..self.clients.len())
                .filter(|&i| fds[client_base + i].revents != 0)
                .map(|i| self.clients[i].id)
                .collect();
            let ready_pads: Vec<String> = (0..self.pads.len())
                .filter(|&i| fds[pad_base + i].revents != 0)
                .map(|i| self.pads[i].id.clone())
                .collect();

            for id in ready_pads {
                let Some(i) = self.pads.iter().position(|p| p.id == id) else { continue };
                outs.clear();
                if self.pads[i].read(now, &mut outs).is_err() {
                    let gone = self.pads.remove(i);
                    let desc = gone.describe();
                    self.broadcast(&json!({ "event": "disconnected", "pad": desc }));
                    self.push_pads();
                    continue;
                }
                self.emit(&outs);
            }
            for p in 0..self.pads.len() {
                outs.clear();
                self.pads[p].tick(now, &mut outs);
                self.emit(&outs);
            }

            for id in ready_clients {
                let Some(i) = self.clients.iter().position(|c| c.id == id) else { continue };
                if !self.read_client(i) {
                    self.drop_client(id);
                }
            }

            if fds[1].revents != 0 {
                self.accept();
            }
            if fds[0].revents != 0 {
                self.read_inotify();
            }
        }
    }

    fn try_pad(&mut self, name: &str, announce: bool) {
        if !name.starts_with("event") || self.not_pads.contains(name) || self.pads.iter().any(|p| p.id == name) {
            return;
        }
        match Pad::open(name) {
            Ok(Some(mut pad)) => {
                if announce {
                    pad.arrived(Instant::now());
                }
                if self.grab_owner.is_some() {
                    let _ = pad.set_grab(true);
                }
                let desc = pad.describe();
                self.pads.push(pad);
                if announce {
                    self.broadcast(&json!({ "event": "connected", "pad": desc }));
                    self.push_pads();
                }
            }
            Ok(None) => {
                self.not_pads.insert(name.to_string());
            }
            // Not readable yet: the ACL comes with a later IN_ATTRIB.
            Err(_) => {}
        }
    }

    fn read_inotify(&mut self) {
        let mut buf = [0u8; 4096];
        loop {
            // SAFETY: reading into a local buffer of the given length.
            let n = unsafe { libc::read(self.inotify, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                return;
            }
            let mut off = 0usize;
            let header = std::mem::size_of::<libc::inotify_event>();
            while off + header <= n as usize {
                // SAFETY: the kernel wrote a whole inotify_event at `off`.
                let ev = unsafe { std::ptr::read_unaligned(buf.as_ptr().add(off) as *const libc::inotify_event) };
                let raw = &buf[off + header..off + header + ev.len as usize];
                let name = String::from_utf8_lossy(&raw[..raw.iter().position(|&b| b == 0).unwrap_or(raw.len())]).into_owned();
                if ev.mask & libc::IN_CREATE != 0 {
                    self.not_pads.remove(&name);
                }
                self.try_pad(&name, true);
                off += header + ev.len as usize;
            }
        }
    }

    fn emit(&mut self, outs: &[Out]) {
        for o in outs {
            let msg = match o {
                Out::GuideShort => json!({ "event": "guide", "long": false }),
                Out::GuideLong => json!({ "event": "guide", "long": true }),
                Out::Nav(b) => json!({ "event": "nav", "button": b }),
            };
            match o {
                // Navigation belongs to whoever opened the popup.
                Out::Nav(_) => {
                    if let Some(owner) = self.grab_owner {
                        self.send_to(owner, &msg);
                    }
                }
                _ => self.broadcast(&msg),
            }
        }
    }

    fn set_grab(&mut self, owner: Option<u64>) {
        self.grab_owner = owner;
        let on = owner.is_some();
        for p in &mut self.pads {
            let _ = p.set_grab(on);
        }
    }

    fn pads_msg(&self) -> Value {
        json!({ "event": "pads", "pads": self.pads.iter().map(Pad::describe).collect::<Vec<_>>() })
    }

    fn push_pads(&mut self) {
        let msg = self.pads_msg();
        self.broadcast(&msg);
    }

    fn accept(&mut self) {
        while let Ok((stream, _)) = self.listener.accept() {
            if stream.set_nonblocking(true).is_err() {
                continue;
            }
            let id = self.next_client;
            self.next_client += 1;
            self.clients.push(Client { id, stream, inbox: Vec::new() });
            let msg = self.pads_msg();
            self.send_to(id, &msg);
        }
    }

    /// False when the client has gone.
    fn read_client(&mut self, i: usize) -> bool {
        let mut buf = [0u8; 1024];
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
        while let Some(nl) = self.clients[i].inbox.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.clients[i].inbox.drain(..=nl).collect();
            let Ok(cmd) = serde_json::from_slice::<Value>(&line) else { continue };
            match cmd.get("cmd").and_then(Value::as_str) {
                Some("grab") => self.set_grab(Some(id)),
                Some("release") if self.grab_owner == Some(id) => self.set_grab(None),
                Some("refresh") => {
                    let msg = self.pads_msg();
                    self.send_to(id, &msg);
                }
                Some("library") => {
                    let msg = library::read();
                    self.send_to(id, &msg);
                }
                _ => {}
            }
        }
        // A client that never ends its line does not get to grow forever.
        if self.clients[i].inbox.len() > 64 * 1024 {
            return false;
        }
        true
    }

    fn drop_client(&mut self, id: u64) {
        self.clients.retain(|c| c.id != id);
        // The bar crashed or restarted with the popup open: never leave the
        // pads grabbed with nobody to give them back.
        if self.grab_owner == Some(id) {
            self.set_grab(None);
        }
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
            self.drop_client(id);
        }
    }

    fn broadcast(&mut self, msg: &Value) {
        let ids: Vec<u64> = self.clients.iter().map(|c| c.id).collect();
        for id in ids {
            self.send_to(id, msg);
        }
    }
}
