//! The shell's themes, read from ~/.config/hypr/themes/*.json (the same
//! files Quickshell and shell-theme.py read), and the selection in
//! ~/.config/hypr/shell-theme.json: the look ("cartoon" is Ink, anything
//! else Glass) and the theme. Prisme writes both back on Enter;
//! Quickshell watches the file and recolours the shell.

use serde_json::Value;
use std::path::PathBuf;

/// One mode's colours, as #rrggbb.
#[derive(Clone, Debug, Default)]
pub struct Colors {
    pub panel: String,
    pub card: String,
    pub primary: String,
    pub on_accent: String,
    pub accent: String,
    pub highlight: String,
    pub success: String,
    pub info: String,
    pub warning: String,
    pub danger: String,
    pub extra: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct Theme {
    pub id: String,
    pub name: String,
    pub folder: Option<String>,
    pub dark: Colors,
    pub light: Colors,
}

impl Theme {
    pub fn colors(&self, dark: bool) -> &Colors {
        if dark { &self.dark } else { &self.light }
    }
}

fn hypr_dir() -> Option<PathBuf> {
    Some(PathBuf::from(std::env::var("HOME").ok()?).join(".config/hypr"))
}

fn is_hex(v: &str) -> bool {
    v.len() == 7 && v.starts_with('#') && v[1..].chars().all(|c| c.is_ascii_hexdigit())
}

fn colors(mode: &Value) -> Option<Colors> {
    let get = |group: &str, key: &str| -> Option<String> {
        let v = mode.get(group)?.get(key)?.as_str()?;
        is_hex(v).then(|| v.to_lowercase())
    };
    let opt = |group: &str, key: &str| get(group, key);
    Some(Colors {
        panel: get("surfaces", "panel")?,
        card: get("surfaces", "card")?,
        primary: get("text", "primary")?,
        on_accent: get("text", "on-accent")?,
        accent: get("accents", "active")?,
        highlight: get("accents", "highlight")?,
        success: get("accents", "success")?,
        info: get("accents", "info")?,
        warning: get("accents", "warning")?,
        danger: get("accents", "danger")?,
        extra: ["blue", "magenta", "cyan"].iter().filter_map(|k| opt("accents", k)).collect(),
    })
}

fn parse(id: &str, text: &str) -> Option<Theme> {
    let v: Value = serde_json::from_str(text).ok()?;
    if v.get("schema")?.as_str()? != "coucou-theme/1" {
        return None;
    }
    let modes = v.get("modes")?;
    Some(Theme {
        id: id.to_string(),
        name: v.get("name").and_then(Value::as_str).unwrap_or(id).to_string(),
        folder: v.get("folder").and_then(Value::as_str).filter(|f| is_hex(f)).map(str::to_lowercase),
        dark: colors(modes.get("dark")?)?,
        light: colors(modes.get("light")?)?,
    })
}

/// Every valid theme, by name.
pub fn load_all() -> Vec<Theme> {
    let Some(dir) = hypr_dir().map(|d| d.join("themes")) else {
        return Vec::new();
    };
    let mut out: Vec<Theme> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let path = e.path();
            if path.extension()? != "json" {
                return None;
            }
            let id = path.file_stem()?.to_string_lossy().into_owned();
            parse(&id, &std::fs::read_to_string(&path).ok()?)
        })
        .collect();
    out.sort_by_key(|t| t.name.to_lowercase());
    out
}

fn selection_path() -> Option<PathBuf> {
    Some(hypr_dir()?.join("shell-theme.json"))
}

/// The look (true: Ink) and the theme id in use.
pub fn selection() -> (bool, Option<String>) {
    let v: Value = selection_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Value::Null);
    let ink = v.get("style").and_then(Value::as_str) == Some("cartoon");
    (ink, v.get("theme").and_then(Value::as_str).map(str::to_string))
}

/// Writes the band chosen on Enter: an Ink theme (`Some(id)`, the
/// "cartoon" style with that theme), or Glass (`None`: the "default" style,
/// keeping the theme it had, as the shell's theme picker does, so going
/// back to Ink finds it again). Anything else in the file stays; written in
/// one step, so Quickshell's watcher never reads half of it.
pub fn select(theme: Option<&str>) {
    let Some(path) = selection_path() else {
        return;
    };
    let mut v: Value = std::fs::read_to_string(&path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .filter(Value::is_object)
        .unwrap_or_else(|| serde_json::json!({ "style": "default" }));
    let style = if theme.is_some() { "cartoon" } else { "default" };
    let same_theme = theme.is_none_or(|id| v.get("theme").and_then(Value::as_str) == Some(id));
    if v.get("style").and_then(Value::as_str) == Some(style) && same_theme {
        return;
    }
    v["style"] = Value::String(style.to_string());
    if let Some(id) = theme {
        v["theme"] = Value::String(id.to_string());
    }
    let tmp = path.with_extension("json.prisme");
    let text = serde_json::to_string_pretty(&v).unwrap_or_default() + "\n";
    if std::fs::write(&tmp, text).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

/// #rrggbb as (r, g, b) in 0..1.
pub fn rgb(hex: &str) -> (f64, f64, f64) {
    let c = |i: usize| u8::from_str_radix(hex.get(i..i + 2).unwrap_or("00"), 16).unwrap_or(0) as f64 / 255.0;
    (c(1), c(3), c(5))
}

/// `a` taken `t` of the way toward `b`, as #rrggbb.
pub fn mix(a: &str, b: &str, t: f64) -> String {
    let (x, y) = (rgb(a), rgb(b));
    let m = |p: f64, q: f64| ((p + (q - p) * t) * 255.0).round().clamp(0.0, 255.0) as u8;
    format!("#{:02x}{:02x}{:02x}", m(x.0, y.0), m(x.1, y.1), m(x.2, y.2))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_theme() {
        let t = parse("x", r##"{"schema":"coucou-theme/1","name":"X","modes":{
            "dark":{"surfaces":{"panel":"#111111","card":"#222222","card-hover":"#333333"},
                    "text":{"primary":"#ffffff","secondary":"#cccccc","muted":"#999999","on-accent":"#000000"},
                    "accents":{"active":"#ff0000","highlight":"#00ff00","success":"#0000ff","info":"#00ffff","warning":"#ffff00","danger":"#ff00ff","magenta":"#aa00aa"}},
            "light":{"surfaces":{"panel":"#eeeeee","card":"#dddddd","card-hover":"#cccccc"},
                    "text":{"primary":"#000000","secondary":"#333333","muted":"#666666","on-accent":"#ffffff"},
                    "accents":{"active":"#ff0000","highlight":"#00ff00","success":"#0000ff","info":"#00ffff","warning":"#ffff00","danger":"#ff00ff"}}}}"##).unwrap();
        assert_eq!(t.name, "X");
        assert_eq!(t.dark.extra, vec!["#aa00aa"]);
        assert!(parse("x", r#"{"schema":"other"}"#).is_none());
    }

    #[test]
    fn mixes() {
        assert_eq!(mix("#000000", "#ffffff", 0.5), "#808080");
    }
}
