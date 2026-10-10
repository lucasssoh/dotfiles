//! SSH_ASKPASS: ssh (and git, for its own prompts) runs this with the
//! prompt as its only argument and reads the answer on stdout. ssh says
//! what kind of prompt it is in SSH_ASKPASS_PROMPT: unset for a secret,
//! "confirm" for yes/no, "none" for a notice it kills us to dismiss.

use crate::wire::{Ask, Conn};

pub fn run(args: Vec<String>) -> i32 {
    let prompt = args.join(" ");
    let mode = std::env::var("SSH_ASKPASS_PROMPT").unwrap_or_default();
    let message = tidy(&prompt);

    let lower = prompt.to_lowercase();
    let git = lower.starts_with("username for ") || lower.starts_with("password for ");
    let (kind, title) = if git {
        ("git", "Git sign-in")
    } else if mode == "confirm" {
        ("ssh", "Allow SSH key")
    } else if mode == "none" {
        ("ssh", "SSH key")
    } else if lower.contains("(yes/no") {
        ("ssh", "Unknown host")
    } else if lower.contains("passphrase") {
        ("ssh", "Unlock SSH key")
    } else {
        ("ssh", "SSH")
    };
    // A user name, or the yes/no of an unknown host key, is typed in clear.
    let echo = lower.starts_with("username for ") || lower.contains("(yes/no");
    let confirm = mode == "confirm" || mode == "none";

    let mut conn = match Conn::open() {
        Ok(c) => c,
        Err(_) => {
            eprintln!("sesame: the shell's password prompt is not running (sesame.service)");
            return 1;
        }
    };
    let ask = Ask { kind, title, message: &message, echo, confirm, origin: None };
    match conn.ask(&ask) {
        Ok(Some(secret)) => {
            if !confirm {
                println!("{secret}");
            }
            0
        }
        _ => 1,
    }
}

/// "Enter passphrase for key '/home/u/.ssh/id_ed25519': " reads better as
/// "Enter passphrase for key '~/.ssh/id_ed25519'".
fn tidy(prompt: &str) -> String {
    let mut s = prompt.trim().trim_end_matches(':').trim_end().to_string();
    if let Ok(home) = std::env::var("HOME") {
        if !home.is_empty() {
            s = s.replace(&home, "~");
        }
    }
    s
}
