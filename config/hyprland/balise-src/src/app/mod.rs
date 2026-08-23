//! App orchestration: GTK Application, the daemon-command event loop.
//! Adapted from orbit-vendor/src/app/mod.rs, trimmed to Phase 0/1 scope --
//! no NetworkManager/tokio runtime wiring yet (that lands with Phase 1b's
//! WiFi UI); today this just makes `balise daemon` + `show`/`hide`/`toggle`
//! actually control a real window.

use gtk4::gio::ApplicationFlags;
use gtk4::prelude::*;
use gtk4::{glib, Application};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

use crate::config::Config;
use crate::ipc::{DaemonCommand, DaemonServer};
use crate::ui::BaliseWindow;

pub enum AppEvent {
    DaemonCommand(DaemonCommand),
    DaemonStarted(DaemonServer),
}

pub struct BaliseApp {
    app: Application,
    config: Config,
    is_daemon: bool,
}

impl BaliseApp {
    pub fn new(config: Config) -> Result<Self, glib::Error> {
        Self::new_with_mode(config, false)
    }

    pub fn new_daemon(config: Config) -> Result<Self, glib::Error> {
        Self::new_with_mode(config, true)
    }

    fn new_with_mode(config: Config, is_daemon: bool) -> Result<Self, glib::Error> {
        let app = Application::new(Some("com.balise.app"), ApplicationFlags::empty());
        Ok(Self { app, config, is_daemon })
    }

    pub fn run(&self) -> glib::ExitCode {
        let config = self.config.clone();
        let is_daemon = self.is_daemon;

        self.app.connect_activate(move |app| {
            // SIGTERM/SIGINT -> clean quit, needed for `systemctl --user
            // stop balise` once Phase 5 wires up the systemd unit.
            let app_term = app.clone();
            glib::unix_signal_add_local(15, move || {
                app_term.quit();
                glib::ControlFlow::Break
            });
            let app_int = app.clone();
            glib::unix_signal_add_local(2, move || {
                app_int.quit();
                glib::ControlFlow::Break
            });

            let win = BaliseWindow::new(app, config.clone());
            let (tx, rx) = async_channel::unbounded::<AppEvent>();
            let is_visible = Rc::new(RefCell::new(!is_daemon));

            // One-shot GUI mode (no subcommand, `balise` alone): show
            // immediately, matching Orbit's run_gui behavior -- there's no
            // daemon command to trigger it otherwise.
            if !is_daemon {
                win.show();
            }

            // Shared multi-threaded runtime, kept alive for the whole
            // process (see the `_rt_keepalive` binding below) -- this is
            // also where the NetworkManager D-Bus calls will run once
            // Phase 1b lands (see the project plan), so it's created here
            // unconditionally rather than only for the daemon's IPC.
            //
            // DaemonServer::new() uses tokio::net::UnixListener, which
            // needs an active tokio reactor at creation time -- glib's own
            // executor (spawn_future_local) doesn't provide one, hence the
            // background OS thread driving this runtime's block_on. The
            // runtime must then stay alive for as long as the listener is
            // used: dropping it shuts its reactor down, which orphans the
            // listener even though DaemonServer::run() polls it from a
            // SEPARATE dedicated thread/runtime of its own -- confirmed
            // live (a throwaway per-init-thread runtime produced an
            // infinite "Tokio 1.x context ... being shutdown" error loop
            // the moment that thread's runtime dropped).
            let rt = Arc::new(tokio::runtime::Runtime::new().expect("failed to create tokio runtime"));

            if is_daemon {
                let rt_init = rt.clone();
                let tx_init = tx.clone();
                std::thread::spawn(move || match rt_init.block_on(async { DaemonServer::new().await }) {
                    Ok(server) => {
                        let _ = tx_init.send_blocking(AppEvent::DaemonStarted(server));
                    }
                    Err(e) => {
                        eprintln!("balise: failed to start daemon: {}", e);
                        std::process::exit(1);
                    }
                });
            }

            glib::spawn_future_local(async move {
                // Keeps `rt` (and therefore the daemon socket's reactor)
                // alive for as long as this event loop runs -- i.e. the
                // whole process lifetime.
                let _rt_keepalive = rt;
                while let Ok(event) = rx.recv().await {
                    match event {
                        AppEvent::DaemonCommand(cmd) => match cmd {
                            DaemonCommand::Show => {
                                win.show();
                                *is_visible.borrow_mut() = true;
                            }
                            DaemonCommand::Hide => {
                                win.hide();
                                *is_visible.borrow_mut() = false;
                            }
                            DaemonCommand::Toggle(position, _tab) => {
                                if *is_visible.borrow() {
                                    win.hide();
                                    *is_visible.borrow_mut() = false;
                                } else {
                                    if let Some(pos) = position {
                                        win.set_position(&pos);
                                    }
                                    win.show();
                                    *is_visible.borrow_mut() = true;
                                }
                            }
                            DaemonCommand::ReloadTheme => {
                                win.apply_theme();
                            }
                            DaemonCommand::ReloadConfig => {
                                win.reload_config();
                            }
                            DaemonCommand::Quit => {
                                std::process::exit(0);
                            }
                        },
                        AppEvent::DaemonStarted(server) => {
                            let tx_cmd = tx.clone();
                            server.run(move |cmd| {
                                let _ = tx_cmd.send_blocking(AppEvent::DaemonCommand(cmd));
                            });
                        }
                    }
                }
            });
        });

        self.app.run_with_args(&[] as &[&str])
    }
}
