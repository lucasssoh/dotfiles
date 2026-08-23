//! `config.toml` -- position/margins/transitions. Adapted from
//! orbit-vendor/src/config.rs; same field shape (kept `stack_transition*`
//! even though Phase 1 only has a single WiFi tab, for forward-compat with
//! the later Ethernet/Bluetooth tabs -- see the project plan's roadmap).

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    #[serde(default = "default_position")]
    pub position: String,

    #[serde(default = "default_window_transition")]
    pub window_transition: String,

    #[serde(default = "default_transition_duration")]
    pub window_transition_duration: u32,

    #[serde(default = "default_stack_transition")]
    pub stack_transition: String,

    #[serde(default = "default_stack_transition_duration")]
    pub stack_transition_duration: u32,

    #[serde(default = "default_margin")]
    pub margin_top: i32,

    #[serde(default = "default_margin")]
    pub margin_right: i32,

    #[serde(default = "default_margin")]
    pub margin_bottom: i32,

    #[serde(default = "default_margin")]
    pub margin_left: i32,
}

fn default_position() -> String {
    "top-right".to_string()
}
fn default_window_transition() -> String {
    "slidedown".to_string()
}
fn default_stack_transition() -> String {
    "crossfade".to_string()
}
fn default_transition_duration() -> u32 {
    150
}

/// Deliberately shorter than the window's: the tab crossfade is only
/// there to avoid a hard cut, not to be noticed. Separate from
/// `default_transition_duration` so shortening one doesn't silently
/// shorten the panel's own open/close animation too -- they shared a
/// default until this split.
fn default_stack_transition_duration() -> u32 {
    120
}
fn default_margin() -> i32 {
    8
}

impl Default for Config {
    fn default() -> Self {
        Self {
            position: default_position(),
            window_transition: default_window_transition(),
            window_transition_duration: default_transition_duration(),
            stack_transition: default_stack_transition(),
            stack_transition_duration: default_stack_transition_duration(),
            margin_top: default_margin(),
            margin_right: default_margin(),
            margin_bottom: default_margin(),
            margin_left: default_margin(),
        }
    }
}

impl Config {
    pub fn load() -> Self {
        let path = crate::paths::config_file();

        if path.exists() {
            match std::fs::read_to_string(&path) {
                Ok(content) => match toml::from_str(&content) {
                    Ok(config) => return config,
                    Err(e) => eprintln!("Failed to parse config: {}", e),
                },
                Err(e) => eprintln!("Failed to read config: {}", e),
            }
        }

        Self::default()
    }
}
