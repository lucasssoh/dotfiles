//! gpg-agent's pinentry: the Assuan protocol on stdin/stdout, the part of
//! it gpg-agent uses. Without the daemon (a text console, the shell not
//! started), it hands over to the system's pinentry before saying a word.

use std::io::{self, BufRead, Write};
use std::os::unix::process::CommandExt;

use crate::wire::{Ask, Conn};

// GPG_ERR_SOURCE_PINENTRY (5) << 24 | the code.
const ERR_CANCELED: &str = "ERR 83886179 Operation cancelled <Pinentry>";
const ERR_NOT_CONFIRMED: &str = "ERR 83886194 Not confirmed <Pinentry>";

#[derive(Default)]
struct State {
    title: String,
    desc: String,
    prompt: String,
    error: String,
    owner: Option<u32>,
}

pub fn run(args: Vec<String>) -> i32 {
    let mut conn = match Conn::open() {
        Ok(c) => c,
        Err(_) => {
            let e = std::process::Command::new("/usr/bin/pinentry").args(&args).exec();
            eprintln!("sesame: no daemon and no /usr/bin/pinentry: {e}");
            return 1;
        }
    };

    let stdin = io::stdin();
    let mut out = io::stdout().lock();
    let mut st = State::default();
    let _ = writeln!(out, "OK Pleased to meet you");
    let _ = out.flush();

    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let (cmd, arg) = line.split_once(' ').unwrap_or((line.as_str(), ""));
        let reply: Vec<String> = match cmd.to_ascii_uppercase().as_str() {
            "SETTITLE" => set(&mut st.title, arg),
            "SETDESC" => set(&mut st.desc, arg),
            "SETPROMPT" => set(&mut st.prompt, arg),
            "SETERROR" => set(&mut st.error, arg),
            "OPTION" => {
                // owner=PID/HOST or owner=PID/UID HOST, depending on the version.
                if let Some(v) = arg.strip_prefix("owner=") {
                    let digits: String = v.chars().take_while(char::is_ascii_digit).collect();
                    st.owner = digits.parse().ok();
                }
                vec!["OK".into()]
            }
            "GETINFO" => match arg {
                "pid" => vec![format!("D {}", std::process::id()), "OK".into()],
                "version" => vec![format!("D {}", env!("CARGO_PKG_VERSION")), "OK".into()],
                "flavor" => vec!["D sesame".into(), "OK".into()],
                _ => vec!["OK".into()],
            },
            "GETPIN" => {
                let r = ask(&mut conn, &mut st, false);
                match r {
                    Some(pin) if !pin.is_empty() => vec![format!("D {}", escape(&pin)), "OK".into()],
                    Some(_) => vec!["OK".into()],
                    None => vec![ERR_CANCELED.into()],
                }
            }
            "CONFIRM" => {
                if arg.contains("--one-button") {
                    vec!["OK".into()]
                } else {
                    match ask(&mut conn, &mut st, true) {
                        Some(_) => vec!["OK".into()],
                        None => vec![ERR_NOT_CONFIRMED.into()],
                    }
                }
            }
            "RESET" => {
                st = State { owner: st.owner, ..State::default() };
                vec!["OK".into()]
            }
            "BYE" => {
                let _ = writeln!(out, "OK closing connection");
                let _ = out.flush();
                return 0;
            }
            _ => vec!["OK".into()],
        };
        for r in reply {
            let _ = writeln!(out, "{r}");
        }
        let _ = out.flush();
    }
    0
}

fn set(field: &mut String, arg: &str) -> Vec<String> {
    *field = unescape(arg);
    vec!["OK".into()]
}

fn ask(conn: &mut Conn, st: &mut State, confirm: bool) -> Option<String> {
    let mut message = st.desc.trim().to_string();
    if !st.error.is_empty() {
        message = format!("{}\n\n{}", st.error.trim(), message);
    }
    let title = if !st.title.is_empty() {
        st.title.clone()
    } else if confirm {
        "GPG".to_string()
    } else {
        "Unlock GPG key".to_string()
    };
    let a = Ask { kind: "gpg", title: &title, message: &message, echo: false, confirm, origin: st.owner };
    // gpg-agent sends SETERROR again before the next try, if there is one.
    st.error.clear();
    conn.ask(&a).ok().flatten()
}

fn unescape(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            let hex = std::str::from_utf8(&b[i + 1..i + 3]).unwrap_or("");
            if let Ok(v) = u8::from_str_radix(hex, 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn escape(s: &str) -> String {
    s.replace('%', "%25").replace('\r', "%0D").replace('\n', "%0A")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assuan_escapes() {
        assert_eq!(unescape("Please enter%0Athe passphrase 100%25"), "Please enter\nthe passphrase 100%");
        assert_eq!(unescape("trailing %4"), "trailing %4");
        assert_eq!(escape("a%b\nc"), "a%25b%0Ac");
    }
}
