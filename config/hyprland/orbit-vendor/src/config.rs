use serde::Deserialize;
use std::path::PathBuf;

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
    
    #[serde(default = "default_transition_duration")]
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

fn default_position() -> String { "center".to_string() }
fn default_window_transition() -> String { "slidedown".to_string() }
fn default_stack_transition() -> String { "slidehorizontal".to_string() }
fn default_transition_duration() -> u32 { 200 }
fn default_margin() -> i32 { 10 }

impl Default for Config {
    fn default() -> Self {
        Self {
            position: default_position(),
            window_transition: default_window_transition(),
            window_transition_duration: default_transition_duration(),
            stack_transition: default_stack_transition(),
            stack_transition_duration: default_transition_duration(),
            margin_top: default_margin(),
            margin_right: default_margin(),
            margin_bottom: default_margin(),
            margin_left: default_margin(),
        }
    }
}

impl Config {
    pub fn load() -> Self {
        let config_path = match Self::config_path() {
            Some(p) => p,
            None => return Self::default(),
        };
        
        if config_path.exists() {
            match std::fs::read_to_string(&config_path) {
                Ok(content) => {
                    match toml::from_str(&content) {
                        Ok(config) => {
                            return config;
                        }
                        Err(e) => {
                            eprintln!("Failed to parse config: {}", e);
                        }
                    }
                }
                Err(e) => {
                    eprintln!("Failed to read config: {}", e);
                }
            }
        }
        
        Self::default()
    }
    
    pub fn config_path() -> Option<PathBuf> {
        let home = std::env::var("HOME").ok()?;
        Some(PathBuf::from(home)
            .join(".config")
            .join("orbit")
            .join("config.toml"))
    }
}
