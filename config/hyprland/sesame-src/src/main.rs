//! Sésame: every password the session asks for outside a terminal, on one
//! card in the bar, with the command that asks for it.
//!
//!   sesame            the daemon (sesame.service): the socket, the polkit agent
//!   sesame askpass    SSH_ASKPASS for ssh and git (config/hyprland/sesame/askpass)
//!   sesame pinentry   gpg-agent's pinentry-program (config/hyprland/sesame/pinentry)
//!
//! The socket at $XDG_RUNTIME_DIR/sesame.sock speaks JSON lines.
//!   asker -> daemon   {"cmd":"ask","kind","title","message","echo","confirm","origin":pid|null}
//!   daemon -> asker   {"event":"answer","secret":"…"} | {"event":"cancel"}
//!   bar -> daemon     {"cmd":"hello"}                     only the shell's own process is taken as the bar
//!                     {"cmd":"answer","id":N,"secret":"…"} | {"cmd":"cancel","id":N}
//!   daemon -> bar     {"event":"asks","asks":[{id,kind,title,message,echo,confirm,error,chain:[…]}]}
//!
//! No answer is kept: each ask is answered once, to the process that asked.

mod askpass;
mod chain;
mod daemon;
mod pinentry;
mod polkit;
mod wire;

fn main() {
    let mut args = std::env::args().skip(1);
    let code = match args.next().as_deref() {
        None => match daemon::run() {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("sesame: {e}");
                1
            }
        },
        Some("askpass") => askpass::run(args.collect()),
        Some("pinentry") => pinentry::run(args.collect()),
        Some("--version" | "-V") => {
            println!("sesame {}", env!("CARGO_PKG_VERSION"));
            0
        }
        Some(_) => {
            eprintln!("usage: sesame              runs the daemon (see sesame.service)");
            eprintln!("       sesame askpass PROMPT   SSH_ASKPASS");
            eprintln!("       sesame pinentry         gpg-agent's pinentry");
            2
        }
    };
    std::process::exit(code);
}
