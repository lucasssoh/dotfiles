//! The daemon: one thread in poll(2) on the socket, its clients and a wake
//! pipe the polkit agent writes to when it has something to ask.
//!
//! Asks queue up; the bar shows the first one. Each is answered once, to
//! whoever asked (an askpass or pinentry connection, or the polkit session
//! waiting on a channel), and forgotten. With no bar connected an ask is
//! cancelled at once rather than left hanging a git push forever.

use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::{chain, polkit, wire};

pub enum FromAgent {
    Ask {
        token: String,
        title: String,
        message: String,
        echo: bool,
        error: String,
        chain: Vec<String>,
        reply: async_channel::Sender<Option<String>>,
    },
    /// polkit cancelled the request (the caller went away, or timed out).
    Drop { token: String },
}

/// What the polkit thread holds to reach the loop.
#[derive(Clone)]
pub struct Waker {
    tx: mpsc::Sender<FromAgent>,
    fd: RawFd,
}

impl Waker {
    pub fn send(&self, msg: FromAgent) {
        if self.tx.send(msg).is_ok() {
            // SAFETY: one byte to our own pipe; a full pipe already wakes the loop.
            unsafe { libc::write(self.fd, [1u8].as_ptr().cast(), 1) };
        }
    }
}

#[derive(PartialEq)]
enum Role {
    New,
    Bar,
    Asker,
}

struct Client {
    id: u64,
    pid: u32,
    stream: UnixStream,
    inbox: Vec<u8>,
    role: Role,
}

enum Reply {
    Client(u64),
    Agent(String, async_channel::Sender<Option<String>>),
}

struct Pending {
    id: u64,
    kind: String,
    title: String,
    message: String,
    echo: bool,
    confirm: bool,
    error: String,
    chain: Vec<String>,
    reply: Reply,
    /// For an askpass ask: who asked and what, to tell a second try.
    retry_key: Option<(u32, String)>,
}

struct Daemon {
    listener: UnixListener,
    wake_read: RawFd,
    from_agent: mpsc::Receiver<FromAgent>,
    clients: Vec<Client>,
    next_client: u64,
    pending: Vec<Pending>,
    next_ask: u64,
    /// The last askpass answer: ssh asking again, the same thing, from the
    /// same process, means the passphrase was wrong.
    last_answered: Option<(u32, String, Instant)>,
}

pub fn run() -> io::Result<()> {
    let path = wire::socket_path();
    if UnixStream::connect(&path).is_ok() {
        return Err(io::Error::new(ErrorKind::AddrInUse, "already running"));
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    listener.set_nonblocking(true)?;

    let mut fds = [0 as RawFd; 2];
    // SAFETY: pipe2 fills the two-element array.
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_NONBLOCK | libc::O_CLOEXEC) } < 0 {
        return Err(io::Error::last_os_error());
    }
    let (tx, rx) = mpsc::channel();
    let waker = Waker { tx, fd: fds[1] };

    // Without polkit (no system bus, another agent already registered) the
    // SSH and GPG prompts still work.
    let _agent = match polkit::start(waker) {
        Ok(conn) => Some(conn),
        Err(e) => {
            eprintln!("sesame: no polkit agent: {e}");
            None
        }
    };

    let mut d = Daemon {
        listener,
        wake_read: fds[0],
        from_agent: rx,
        clients: Vec::new(),
        next_client: 1,
        pending: Vec::new(),
        next_ask: 1,
        last_answered: None,
    };
    d.run()
}

fn peer(stream: &UnixStream) -> Option<(u32, u32)> {
    let mut cred = libc::ucred { pid: 0, uid: 0, gid: 0 };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: SO_PEERCRED fills a ucred of the given size.
    let r = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&mut cred as *mut libc::ucred).cast(),
            &mut len,
        )
    };
    (r == 0).then_some((cred.pid as u32, cred.uid))
}

/// Only the shell may see the asks and answer them.
fn is_shell(pid: u32) -> bool {
    std::fs::read_link(format!("/proc/{pid}/exe"))
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .is_some_and(|n| n == "quickshell" || n == "qs")
}

impl Daemon {
    fn run(&mut self) -> io::Result<()> {
        let mut fds: Vec<libc::pollfd> = Vec::new();
        loop {
            fds.clear();
            let pfd = |fd: RawFd| libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
            fds.push(pfd(self.wake_read));
            fds.push(pfd(self.listener.as_raw_fd()));
            fds.extend(self.clients.iter().map(|c| pfd(c.stream.as_raw_fd())));
            // SAFETY: fds is a live, correctly sized array of pollfd.
            let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
            if n < 0 {
                let e = io::Error::last_os_error();
                if e.kind() == ErrorKind::Interrupted {
                    continue;
                }
                return Err(e);
            }
            let ready: Vec<u64> =
                (0..self.clients.len()).filter(|&i| fds[2 + i].revents != 0).map(|i| self.clients[i].id).collect();
            for id in ready {
                let Some(i) = self.clients.iter().position(|c| c.id == id) else { continue };
                if !self.read_client(i) {
                    self.drop_client(id);
                }
            }
            if fds[1].revents != 0 {
                self.accept();
            }
            if fds[0].revents != 0 {
                let mut buf = [0u8; 64];
                // SAFETY: draining our own non-blocking pipe into a local buffer.
                while unsafe { libc::read(self.wake_read, buf.as_mut_ptr().cast(), buf.len()) } > 0 {}
                while let Ok(msg) = self.from_agent.try_recv() {
                    self.from_agent(msg);
                }
            }
        }
    }

    fn has_bar(&self) -> bool {
        self.clients.iter().any(|c| c.role == Role::Bar)
    }

    fn from_agent(&mut self, msg: FromAgent) {
        match msg {
            FromAgent::Ask { token, title, message, echo, error, chain, reply } => {
                if !self.has_bar() {
                    let _ = reply.send_blocking(None);
                    return;
                }
                let id = self.next_ask;
                self.next_ask += 1;
                self.pending.push(Pending {
                    id,
                    kind: "polkit".into(),
                    title,
                    message,
                    echo,
                    confirm: false,
                    error,
                    chain,
                    reply: Reply::Agent(token, reply),
                    retry_key: None,
                });
                self.push();
            }
            FromAgent::Drop { token } => {
                let before = self.pending.len();
                self.pending.retain(|p| {
                    let gone = matches!(&p.reply, Reply::Agent(t, _) if *t == token);
                    if gone {
                        if let Reply::Agent(_, tx) = &p.reply {
                            let _ = tx.send_blocking(None);
                        }
                    }
                    !gone
                });
                if self.pending.len() != before {
                    self.push();
                }
            }
        }
    }

    fn accept(&mut self) {
        while let Ok((stream, _)) = self.listener.accept() {
            let Some((pid, uid)) = peer(&stream) else { continue };
            // SAFETY: getuid cannot fail.
            if uid != unsafe { libc::getuid() } || stream.set_nonblocking(true).is_err() {
                continue;
            }
            let id = self.next_client;
            self.next_client += 1;
            self.clients.push(Client { id, pid, stream, inbox: Vec::new(), role: Role::New });
        }
    }

    /// False when the client has gone.
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
        if self.clients[i].inbox.len() > 64 * 1024 {
            return false;
        }
        let id = self.clients[i].id;
        let mut lines = Vec::new();
        {
            let inbox = &mut self.clients[i].inbox;
            while let Some(nl) = inbox.iter().position(|&b| b == b'\n') {
                lines.push(inbox.drain(..=nl).collect::<Vec<u8>>());
            }
        }
        for line in lines {
            let Ok(msg) = serde_json::from_slice::<Value>(&line) else { continue };
            self.command(id, &msg);
        }
        // A command may have dropped this very client.
        self.clients.iter().any(|c| c.id == id)
    }

    fn command(&mut self, id: u64, msg: &Value) {
        let Some(i) = self.clients.iter().position(|c| c.id == id) else { return };
        let str_of = |k: &str| msg.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        match (msg.get("cmd").and_then(Value::as_str), &self.clients[i].role) {
            (Some("hello"), Role::New) => {
                if is_shell(self.clients[i].pid) {
                    self.clients[i].role = Role::Bar;
                    let m = self.asks_msg();
                    self.send_to(id, &m);
                } else {
                    self.drop_client(id);
                }
            }
            (Some("ask"), Role::New) => {
                self.clients[i].role = Role::Asker;
                if !self.has_bar() {
                    self.send_to(id, &json!({ "event": "cancel" }));
                    return;
                }
                let pid = self.clients[i].pid;
                let origin = msg
                    .get("origin")
                    .and_then(Value::as_u64)
                    .map(|p| p as u32)
                    .or_else(|| chain::ppid(pid))
                    .unwrap_or(pid);
                let message = str_of("message");
                let kind = str_of("kind");
                let mut error = String::new();
                let retry_key = (kind != "gpg").then(|| (origin, message.clone()));
                if let (Some((o, m, at)), Some((ro, rm))) = (&self.last_answered, &retry_key) {
                    if o == ro && m == rm && at.elapsed() < Duration::from_secs(120) {
                        error = if kind == "git" { "Wrong password. Try again." } else { "Wrong passphrase. Try again." }.into();
                    }
                }
                let ask_id = self.next_ask;
                self.next_ask += 1;
                self.pending.push(Pending {
                    id: ask_id,
                    kind,
                    title: str_of("title"),
                    message,
                    echo: msg.get("echo").and_then(Value::as_bool).unwrap_or(false),
                    confirm: msg.get("confirm").and_then(Value::as_bool).unwrap_or(false),
                    error,
                    chain: chain::from(origin),
                    reply: Reply::Client(id),
                    retry_key,
                });
                self.push();
            }
            // A pinentry asks again on the same connection.
            (Some("ask"), Role::Asker) => {
                let mut m = msg.clone();
                self.clients[i].role = Role::New;
                if let Some(o) = m.as_object_mut() {
                    o.entry("origin").or_insert(Value::Null);
                }
                self.command(id, &m);
            }
            (Some("answer"), Role::Bar) => {
                let ask = msg.get("id").and_then(Value::as_u64).unwrap_or(0);
                let secret = str_of("secret");
                self.resolve(ask, Some(secret));
            }
            (Some("cancel"), Role::Bar) => {
                let ask = msg.get("id").and_then(Value::as_u64).unwrap_or(0);
                self.resolve(ask, None);
            }
            _ => {}
        }
    }

    fn resolve(&mut self, ask: u64, secret: Option<String>) {
        let Some(i) = self.pending.iter().position(|p| p.id == ask) else { return };
        let p = self.pending.remove(i);
        if secret.is_some() {
            if let Some((o, m)) = p.retry_key {
                self.last_answered = Some((o, m, Instant::now()));
            }
        }
        match p.reply {
            Reply::Client(cid) => {
                let m = match &secret {
                    Some(s) => json!({ "event": "answer", "secret": s }),
                    None => json!({ "event": "cancel" }),
                };
                self.send_to(cid, &m);
            }
            Reply::Agent(_, tx) => {
                let _ = tx.send_blocking(secret);
            }
        }
        self.push();
    }

    fn drop_client(&mut self, id: u64) {
        let Some(i) = self.clients.iter().position(|c| c.id == id) else { return };
        let gone = self.clients.remove(i);
        let before = self.pending.len();
        // ssh killed (Ctrl+C, or done with a notice): its card goes.
        self.pending.retain(|p| !matches!(p.reply, Reply::Client(c) if c == id));
        if gone.role == Role::Bar && !self.has_bar() {
            // The shell went away: nobody can answer what is waiting.
            let ids: Vec<u64> = self.pending.iter().map(|p| p.id).collect();
            for ask in ids {
                self.resolve(ask, None);
            }
        }
        if self.pending.len() != before {
            self.push();
        }
    }

    fn asks_msg(&self) -> Value {
        let asks: Vec<Value> = self
            .pending
            .iter()
            .map(|p| {
                json!({
                    "id": p.id, "kind": p.kind, "title": p.title, "message": p.message,
                    "echo": p.echo, "confirm": p.confirm, "error": p.error, "chain": p.chain,
                })
            })
            .collect();
        json!({ "event": "asks", "asks": asks })
    }

    fn push(&mut self) {
        let m = self.asks_msg();
        let bars: Vec<u64> = self.clients.iter().filter(|c| c.role == Role::Bar).map(|c| c.id).collect();
        for id in bars {
            self.send_to(id, &m);
        }
    }

    fn send_to(&mut self, id: u64, msg: &Value) {
        let mut line = msg.to_string();
        line.push('\n');
        let failed = self
            .clients
            .iter_mut()
            .find(|c| c.id == id)
            .is_some_and(|c| write_all_blocking(&mut c.stream, line.as_bytes()).is_err());
        if failed {
            self.drop_client(id);
        }
    }
}

/// The stream is non-blocking for reads; a reply is a few hundred bytes,
/// but a full buffer must not lose half a line.
fn write_all_blocking(s: &mut UnixStream, mut buf: &[u8]) -> io::Result<()> {
    let deadline = Instant::now() + Duration::from_secs(2);
    while !buf.is_empty() {
        match s.write(buf) {
            Ok(0) => return Err(ErrorKind::WriteZero.into()),
            Ok(n) => buf = &buf[n..],
            Err(e) if e.kind() == ErrorKind::WouldBlock && Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(5));
            }
            Err(e) if e.kind() == ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    Ok(())
}
