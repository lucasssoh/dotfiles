use clap::{Parser, Subcommand};

mod app;
mod config;
mod ipc;
mod paths;
mod theme;
mod ui;

use config::Config;
use ipc::{DaemonClient, DaemonCommand};

#[derive(Parser)]
#[command(name = "balise")]
#[command(about = "Native Wayland WiFi/Bluetooth/Ethernet manager panel")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Run as background daemon
    Daemon,
    /// Show the window
    Show,
    /// Hide the window
    Hide,
    /// Toggle daemon window visibility
    Toggle {
        /// Optional position override (top-left, top-center, top-right,
        /// center-left, center, center-right, bottom-left, bottom-center,
        /// bottom-right)
        position: Option<String>,
        /// Optional tab to switch to (only "wifi" exists today)
        #[arg(long, short)]
        tab: Option<String>,
    },
    /// Reload theme from configuration
    ReloadTheme,
    /// Reload config (position, margins) from config.toml
    ReloadConfig,
}

fn main() {
    // Unlike Prisme (a carousel of high-res photos, forced to "opengl"):
    // Balise's UI is flat lists/toggles/labels, the same category as Roue,
    // which measured ~68 MB stabilized RSS on "cairo" vs ~182 MB on
    // "opengl" for that kind of content with no perceptible smoothness
    // difference. Respects a value already set by the environment.
    if std::env::var_os("GSK_RENDERER").is_none() {
        std::env::set_var("GSK_RENDERER", "cairo");
    }

    let cli = Cli::parse();
    let config = Config::load();

    match cli.command {
        Some(Commands::Daemon) => run_daemon(config),
        Some(Commands::Show) => show(),
        Some(Commands::Hide) => hide(),
        Some(Commands::Toggle { position, tab }) => toggle_daemon(position, tab),
        Some(Commands::ReloadTheme) => reload_theme(),
        Some(Commands::ReloadConfig) => reload_config(),
        None => run_gui(config),
    }
}

fn run_gui(config: Config) {
    let app = app::BaliseApp::new(config).expect("Failed to create application");
    app.run();
}

fn run_daemon(config: Config) {
    if DaemonClient::is_daemon_running() {
        eprintln!("Daemon is already running");
        std::process::exit(1);
    }

    let app = app::BaliseApp::new_daemon(config).expect("Failed to create daemon");
    app.run();
}

fn toggle_daemon(position: Option<String>, tab: Option<String>) {
    if !DaemonClient::is_daemon_running() {
        eprintln!("Daemon is not running. Start it with: balise daemon");
        std::process::exit(1);
    }

    match DaemonClient::send_command(DaemonCommand::Toggle(position, tab)) {
        Ok(response) => println!("Daemon response: {}", response),
        Err(e) => {
            eprintln!("Failed to send command: {}", e);
            std::process::exit(1);
        }
    }
}

fn show() {
    if !DaemonClient::is_daemon_running() {
        println!("Daemon not running, nothing to show.");
        return;
    }

    match DaemonClient::send_command(DaemonCommand::Show) {
        Ok(response) => println!("Show triggered: {}", response),
        Err(e) => {
            eprintln!("Failed to show window: {}", e);
            std::process::exit(1);
        }
    }
}

fn hide() {
    if !DaemonClient::is_daemon_running() {
        println!("Daemon not running, nothing to hide.");
        return;
    }

    match DaemonClient::send_command(DaemonCommand::Hide) {
        Ok(response) => println!("Hide triggered: {}", response),
        Err(e) => {
            eprintln!("Failed to hide window: {}", e);
            std::process::exit(1);
        }
    }
}

fn reload_theme() {
    if !DaemonClient::is_daemon_running() {
        println!("Daemon not running, nothing to reload.");
        return;
    }

    match DaemonClient::send_command(DaemonCommand::ReloadTheme) {
        Ok(response) => println!("Theme reload triggered: {}", response),
        Err(e) => {
            eprintln!("Failed to trigger theme reload: {}", e);
            std::process::exit(1);
        }
    }
}

fn reload_config() {
    if !DaemonClient::is_daemon_running() {
        println!("Daemon not running, nothing to reload.");
        return;
    }

    match DaemonClient::send_command(DaemonCommand::ReloadConfig) {
        Ok(response) => println!("Config reload triggered: {}", response),
        Err(e) => {
            eprintln!("Failed to trigger config reload: {}", e);
            std::process::exit(1);
        }
    }
}
