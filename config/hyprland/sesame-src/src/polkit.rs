//! The session's polkit agent. polkitd calls BeginAuthentication on the
//! system bus; the password is checked by polkit's own setuid helper
//! (PAM), never by us: we pass it the cookie, it asks, the bar answers.
//!
//! The call returns once the helper says SUCCESS or the user cancels,
//! which is how polkitd learns the outcome. Three tries, like GNOME's.

use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

use zbus::blocking;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

use crate::chain;
use crate::daemon::{FromAgent, Waker};

const HELPER: &str = "/usr/lib/polkit-1/polkit-agent-helper-1";
const OBJECT: &str = "/org/coucou/Sesame/PolkitAgent";
const TRIES: usize = 3;

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.PolicyKit1.Error")]
enum PkError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Failed(String),
    Cancelled(String),
}

enum Outcome {
    Authorized,
    Cancelled,
    Failed,
}

#[derive(Default)]
struct Running {
    /// cookie -> the helper's pid, to stop it on CancelAuthentication.
    helpers: HashMap<String, u32>,
    cancelled: HashSet<String>,
}

struct Agent {
    waker: Waker,
    running: Arc<Mutex<Running>>,
}

#[zbus::interface(name = "org.freedesktop.PolicyKit1.AuthenticationAgent")]
impl Agent {
    async fn begin_authentication(
        &self,
        _action_id: String,
        message: String,
        _icon_name: String,
        details: HashMap<String, String>,
        cookie: String,
        identities: Vec<(String, HashMap<String, OwnedValue>)>,
    ) -> Result<(), PkError> {
        let user = pick_user(&identities).ok_or_else(|| PkError::Failed("no user to authenticate as".into()))?;
        let steps = chain_for(&details);
        let (tx, rx) = async_channel::bounded(1);
        let waker = self.waker.clone();
        let running = self.running.clone();
        let c = cookie.clone();
        std::thread::spawn(move || {
            let r = session(&user, &c, &message, steps, &waker, &running);
            let _ = tx.send_blocking(r);
        });
        let outcome = rx.recv().await.unwrap_or(Outcome::Failed);
        self.running.lock().unwrap().cancelled.remove(&cookie);
        match outcome {
            Outcome::Authorized => Ok(()),
            Outcome::Cancelled => Err(PkError::Cancelled("cancelled".into())),
            Outcome::Failed => Err(PkError::Failed("authentication failed".into())),
        }
    }

    async fn cancel_authentication(&self, cookie: String) -> Result<(), PkError> {
        {
            let mut r = self.running.lock().unwrap();
            r.cancelled.insert(cookie.clone());
            if let Some(&pid) = r.helpers.get(&cookie) {
                // SAFETY: a signal to the helper we spawned and still track.
                unsafe { libc::kill(pid as i32, libc::SIGTERM) };
            }
        }
        self.waker.send(FromAgent::Drop { token: cookie });
        Ok(())
    }
}

pub fn start(waker: Waker) -> zbus::Result<blocking::Connection> {
    let agent = Agent { waker, running: Arc::default() };
    let conn = blocking::connection::Builder::system()?.serve_at(OBJECT, agent)?.build()?;

    let session = session_id(&conn)?;
    let subject: (&str, HashMap<&str, Value>) =
        ("unix-session", HashMap::from([("session-id", Value::from(session.as_str()))]));
    let locale = std::env::var("LANG").unwrap_or_else(|_| "C.UTF-8".into());
    conn.call_method(
        Some("org.freedesktop.PolicyKit1"),
        "/org/freedesktop/PolicyKit1/Authority",
        Some("org.freedesktop.PolicyKit1.Authority"),
        "RegisterAuthenticationAgent",
        &(subject, locale, OBJECT),
    )?;
    Ok(conn)
}

/// The user's graphical session, from logind: this daemon runs under
/// systemd --user, outside the session, so XDG_SESSION_ID is only a fallback.
fn session_id(conn: &blocking::Connection) -> zbus::Result<String> {
    // SAFETY: getuid cannot fail.
    let uid = unsafe { libc::getuid() };
    let manager = blocking::Proxy::new(
        conn,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )?;
    let user: OwnedObjectPath = manager.call("GetUser", &(uid,))?;
    let user = blocking::Proxy::new(conn, "org.freedesktop.login1", user, "org.freedesktop.login1.User")?;
    let (id, _): (String, OwnedObjectPath) = user.get_property("Display")?;
    if !id.is_empty() {
        return Ok(id);
    }
    std::env::var("XDG_SESSION_ID").map_err(|_| zbus::Error::Failure("no graphical session".into()))
}

/// The user to authenticate as: ourselves when allowed, else the first
/// administrator polkit offers.
fn pick_user(identities: &[(String, HashMap<String, OwnedValue>)]) -> Option<String> {
    // SAFETY: getuid cannot fail.
    let me = unsafe { libc::getuid() };
    let uids: Vec<u32> = identities
        .iter()
        .filter(|(kind, _)| kind == "unix-user")
        .filter_map(|(_, d)| d.get("uid").and_then(|v| u32::try_from(v).ok()))
        .collect();
    let uid = if uids.contains(&me) { me } else { *uids.first()? };
    user_name(uid)
}

fn user_name(uid: u32) -> Option<String> {
    let mut pw: libc::passwd = unsafe { std::mem::zeroed() };
    let mut buf = vec![0 as libc::c_char; 4096];
    let mut out: *mut libc::passwd = std::ptr::null_mut();
    // SAFETY: getpwuid_r writes into pw and buf, of the sizes given.
    let r = unsafe { libc::getpwuid_r(uid, &mut pw, buf.as_mut_ptr(), buf.len(), &mut out) };
    if r != 0 || out.is_null() {
        return None;
    }
    // SAFETY: pw_name points into buf, NUL-terminated.
    Some(unsafe { std::ffi::CStr::from_ptr(pw.pw_name) }.to_string_lossy().into_owned())
}

/// Who asked. polkit names the subject (whose rights are checked) and the
/// caller (who asked polkit). pkexec is the caller, run by the subject:
/// start from it, so the card shows the command it is about to run. A
/// service checking on someone's behalf (systemd, NetworkManager) is not
/// below the subject, and the subject tells more.
fn chain_for(details: &HashMap<String, String>) -> Vec<String> {
    let pid = |k: &str| details.get(k).and_then(|p| p.parse::<u32>().ok());
    let (Some(subject), caller) = (pid("polkit.subject-pid"), pid("polkit.caller-pid")) else {
        return Vec::new();
    };
    let below = |mut p: u32| {
        for _ in 0..16 {
            if p == subject {
                return true;
            }
            match chain::ppid(p) {
                Some(up) if up > 1 => p = up,
                _ => return false,
            }
        }
        false
    };
    match caller {
        Some(c) if below(c) => chain::from(c),
        _ => chain::from(subject),
    }
}

fn session(user: &str, cookie: &str, message: &str, steps: Vec<String>, waker: &Waker, running: &Mutex<Running>) -> Outcome {
    let mut error = String::new();
    for _ in 0..TRIES {
        let Ok(mut child) = Command::new(HELPER)
            .arg(user)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        else {
            return Outcome::Failed;
        };
        running.lock().unwrap().helpers.insert(cookie.to_string(), child.id());
        let mut stdin = child.stdin.take().unwrap();
        let mut out = BufReader::new(child.stdout.take().unwrap());
        let _ = writeln!(stdin, "{cookie}");

        let mut line = String::new();
        let result = loop {
            line.clear();
            if out.read_line(&mut line).unwrap_or(0) == 0 {
                break Outcome::Failed;
            }
            let l = line.trim_end_matches('\n');
            let prompt = l
                .strip_prefix("PAM_PROMPT_ECHO_OFF ")
                .map(|_| false)
                .or_else(|| l.strip_prefix("PAM_PROMPT_ECHO_ON ").map(|_| true));
            if let Some(echo) = prompt {
                let (tx, rx) = async_channel::bounded(1);
                waker.send(FromAgent::Ask {
                    token: cookie.to_string(),
                    title: "Authentication required".into(),
                    message: message.to_string(),
                    echo,
                    error: std::mem::take(&mut error),
                    chain: steps.clone(),
                    reply: tx,
                });
                match rx.recv_blocking() {
                    Ok(Some(secret)) => {
                        let _ = writeln!(stdin, "{secret}");
                    }
                    _ => {
                        let _ = child.kill();
                        break Outcome::Cancelled;
                    }
                }
            } else if let Some(m) = l.strip_prefix("PAM_ERROR_MSG ") {
                error = m.to_string();
            } else if l == "SUCCESS" {
                break Outcome::Authorized;
            } else if l == "FAILURE" {
                break Outcome::Failed;
            }
        };
        let _ = child.wait();
        let cancelled = {
            let mut r = running.lock().unwrap();
            r.helpers.remove(cookie);
            r.cancelled.contains(cookie)
        };
        match result {
            Outcome::Authorized => return Outcome::Authorized,
            _ if cancelled => return Outcome::Cancelled,
            Outcome::Cancelled => return Outcome::Cancelled,
            Outcome::Failed => {
                if error.is_empty() {
                    error = "Wrong password. Try again.".into();
                }
            }
        }
    }
    Outcome::Failed
}
