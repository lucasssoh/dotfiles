//! The client side of the socket, shared by askpass and pinentry: one
//! connection, one ask at a time, blocking until the card is answered.

use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

use serde_json::{json, Value};

pub fn socket_path() -> PathBuf {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    dir.join("sesame.sock")
}

pub struct Ask<'a> {
    pub kind: &'a str,
    pub title: &'a str,
    pub message: &'a str,
    pub echo: bool,
    pub confirm: bool,
    /// Where the "asked by" chain starts. None: the asker's parent.
    pub origin: Option<u32>,
}

pub struct Conn {
    write: UnixStream,
    read: BufReader<UnixStream>,
}

impl Conn {
    pub fn open() -> io::Result<Conn> {
        let write = UnixStream::connect(socket_path())?;
        let read = BufReader::new(write.try_clone()?);
        Ok(Conn { write, read })
    }

    /// Some(secret) when answered (empty for a confirmation), None when
    /// cancelled, or when the daemon went away.
    pub fn ask(&mut self, a: &Ask) -> io::Result<Option<String>> {
        let msg = json!({
            "cmd": "ask", "kind": a.kind, "title": a.title, "message": a.message,
            "echo": a.echo, "confirm": a.confirm, "origin": a.origin,
        });
        let mut line = msg.to_string();
        line.push('\n');
        self.write.write_all(line.as_bytes())?;
        let mut reply = String::new();
        if self.read.read_line(&mut reply)? == 0 {
            return Ok(None);
        }
        let v: Value = serde_json::from_str(&reply).unwrap_or(Value::Null);
        Ok(match v.get("event").and_then(Value::as_str) {
            Some("answer") => Some(v.get("secret").and_then(Value::as_str).unwrap_or("").to_string()),
            _ => None,
        })
    }
}
