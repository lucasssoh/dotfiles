//! The games installed through Steam and Lutris, for the popup's library.
//!
//! Read on demand, when the popup opens, never kept: the files are small and
//! a fresh read is the only way to never show a game that was uninstalled
//! since. Everything here is read-only. Launchers that keep no readable
//! library (Heroic, Bottles, itch…) reach the popup through their desktop
//! entries instead, which the bar reads itself.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

pub fn read() -> Value {
    let mut games = Vec::new();
    steam(&mut games);
    lutris(&mut games);
    json!({ "event": "library", "games": games })
}

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

fn first_existing(paths: &[PathBuf]) -> Option<PathBuf> {
    paths.iter().find(|p| p.exists()).cloned()
}

fn path_str(p: Option<PathBuf>) -> Value {
    p.map_or(Value::Null, |p| Value::from(p.to_string_lossy().into_owned()))
}

// ---- Steam ---------------------------------------------------------------

/// `"key"		"value"` on one line of a VDF/ACF file.
fn vdf_value<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let mut parts = line.trim().splitn(2, |c: char| c.is_whitespace());
    let k = parts.next()?.trim_matches('"');
    if k != key {
        return None;
    }
    Some(parts.next()?.trim().trim_matches('"'))
}

/// Runtimes and compatibility tools Steam installs as apps.
fn steam_tool(name: &str) -> bool {
    ["Proton", "Steam Linux Runtime", "Steamworks Common", "SteamVR"]
        .iter()
        .any(|p| name.starts_with(p))
}

/// A file named `name` in the app's artwork cache, which Steam spreads over
/// hashed sub-folders.
fn steam_art(cache: &Path, name: &str) -> Option<PathBuf> {
    let direct = cache.join(name);
    if direct.exists() {
        return Some(direct);
    }
    std::fs::read_dir(cache).ok()?.flatten().map(|e| e.path().join(name)).find(|p| p.exists())
}

fn steam(games: &mut Vec<Value>) {
    let h = home();
    let (root, command): (PathBuf, Vec<&str>) = if let Some(r) = first_existing(&[h.join(".local/share/Steam")]) {
        (r, vec!["steam"])
    } else if let Some(r) = first_existing(&[h.join(".var/app/com.valvesoftware.Steam/.local/share/Steam")]) {
        (r, vec!["flatpak", "run", "com.valvesoftware.Steam"])
    } else {
        return;
    };

    let mut libraries = vec![root.clone()];
    if let Ok(vdf) = std::fs::read_to_string(root.join("steamapps/libraryfolders.vdf")) {
        for line in vdf.lines() {
            if let Some(p) = vdf_value(line, "path") {
                let p = PathBuf::from(p);
                if !libraries.contains(&p) {
                    libraries.push(p);
                }
            }
        }
    }

    for lib in libraries {
        let Ok(dir) = std::fs::read_dir(lib.join("steamapps")) else { continue };
        for entry in dir.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if !name.starts_with("appmanifest_") || !name.ends_with(".acf") {
                continue;
            }
            let Ok(acf) = std::fs::read_to_string(entry.path()) else { continue };
            let (mut id, mut title, mut last, mut flags) = (None, None, 0i64, 0i64);
            for line in acf.lines() {
                if id.is_none() { id = vdf_value(line, "appid").map(str::to_string); }
                if title.is_none() { title = vdf_value(line, "name").map(str::to_string); }
                if let Some(v) = vdf_value(line, "LastPlayed") { last = v.parse().unwrap_or(0); }
                if let Some(v) = vdf_value(line, "StateFlags") { flags = v.parse().unwrap_or(0); }
            }
            let (Some(id), Some(title)) = (id, title) else { continue };
            // StateFlags 4: fully installed.
            if steam_tool(&title) || flags & 4 == 0 {
                continue;
            }
            let cache = root.join("appcache/librarycache").join(&id);
            let mut launch: Vec<String> = command.iter().map(|s| s.to_string()).collect();
            launch.push("-silent".into());
            launch.push(format!("steam://rungameid/{id}"));
            games.push(json!({
                "id": format!("steam:{id}"),
                "title": title,
                "source": "Steam",
                "last": last,
                "cover": path_str(steam_art(&cache, "library_capsule.jpg").or_else(|| steam_art(&cache, "library_600x900.jpg"))),
                "hero": path_str(steam_art(&cache, "library_hero.jpg").or_else(|| steam_art(&cache, "header.jpg"))),
                "launch": launch,
            }));
        }
    }
}

// ---- Lutris --------------------------------------------------------------

fn lutris(games: &mut Vec<Value>) {
    let h = home();
    let (data, command): (PathBuf, Vec<&str>) = if h.join(".local/share/lutris/pga.db").exists() {
        (h.join(".local/share/lutris"), vec!["lutris"])
    } else if h.join(".var/app/net.lutris.Lutris/data/lutris/pga.db").exists() {
        (h.join(".var/app/net.lutris.Lutris/data/lutris"), vec!["flatpak", "run", "net.lutris.Lutris"])
    } else {
        return;
    };
    let Some(rows) = sqlite::query(
        &data.join("pga.db"),
        "SELECT id, name, slug, COALESCE(lastplayed, 0) FROM games WHERE installed = 1",
    ) else {
        return;
    };
    for row in rows {
        let [id, name, slug, last] = &row[..] else { continue };
        let art = |dir: &str| {
            first_existing(&[
                data.join(dir).join(format!("{slug}.jpg")),
                data.join(dir).join(format!("{slug}.png")),
            ])
        };
        let mut launch: Vec<String> = command.iter().map(|s| s.to_string()).collect();
        launch.push(format!("lutris:rungameid/{id}"));
        games.push(json!({
            "id": format!("lutris:{id}"),
            "title": name,
            "source": "Lutris",
            "last": last.parse::<i64>().unwrap_or(0),
            "cover": path_str(art("coverart")),
            "hero": path_str(art("banners")),
            "launch": launch,
        }));
    }
}

/// Just enough SQLite to read Lutris' database, through the system's
/// libsqlite3 loaded when it is needed and let go right after: no build
/// dependency, and nothing resident while the popup is closed.
mod sqlite {
    use super::*;

    type Open = unsafe extern "C" fn(*const c_char, *mut *mut c_void, c_int, *const c_char) -> c_int;
    type Prepare = unsafe extern "C" fn(*mut c_void, *const c_char, c_int, *mut *mut c_void, *mut *const c_char) -> c_int;
    type Step = unsafe extern "C" fn(*mut c_void) -> c_int;
    type Count = unsafe extern "C" fn(*mut c_void) -> c_int;
    type Text = unsafe extern "C" fn(*mut c_void, c_int) -> *const c_char;
    type Finish = unsafe extern "C" fn(*mut c_void) -> c_int;

    const SQLITE_OPEN_READONLY: c_int = 0x01;
    const SQLITE_OPEN_URI: c_int = 0x40;
    const SQLITE_ROW: c_int = 100;

    unsafe fn sym<T>(lib: *mut c_void, name: &CStr) -> Option<T> {
        let p = libc::dlsym(lib, name.as_ptr());
        // SAFETY: T is the function pointer type of the named symbol.
        (!p.is_null()).then(|| std::mem::transmute_copy(&p))
    }

    pub fn query(db: &Path, sql: &str) -> Option<Vec<Vec<String>>> {
        // SAFETY: dlopen/dlsym with valid C strings; every handle obtained
        // below is released before returning.
        unsafe {
            let lib = libc::dlopen(c"libsqlite3.so.0".as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL);
            if lib.is_null() {
                return None;
            }
            let out = run(lib, db, sql);
            libc::dlclose(lib);
            out
        }
    }

    unsafe fn run(lib: *mut c_void, db: &Path, sql: &str) -> Option<Vec<Vec<String>>> {
        let open: Open = sym(lib, c"sqlite3_open_v2")?;
        let prepare: Prepare = sym(lib, c"sqlite3_prepare_v2")?;
        let step: Step = sym(lib, c"sqlite3_step")?;
        let count: Count = sym(lib, c"sqlite3_column_count")?;
        let text: Text = sym(lib, c"sqlite3_column_text")?;
        let finalize: Finish = sym(lib, c"sqlite3_finalize")?;
        let close: Finish = sym(lib, c"sqlite3_close")?;

        // immutable=1: no locking and no journal, so Lutris writing at the
        // same moment can never be blocked by this read.
        let uri = CString::new(format!("file:{}?mode=ro&immutable=1", db.display())).ok()?;
        let sql = CString::new(sql).ok()?;
        let mut conn = std::ptr::null_mut();
        if open(uri.as_ptr(), &mut conn, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, std::ptr::null()) != 0 {
            close(conn);
            return None;
        }
        let mut stmt = std::ptr::null_mut();
        if prepare(conn, sql.as_ptr(), -1, &mut stmt, std::ptr::null_mut()) != 0 {
            close(conn);
            return None;
        }
        let mut rows = Vec::new();
        while step(stmt) == SQLITE_ROW {
            let n = count(stmt);
            rows.push((0..n).map(|i| {
                let p = text(stmt, i);
                if p.is_null() { String::new() } else { CStr::from_ptr(p).to_string_lossy().into_owned() }
            }).collect());
        }
        finalize(stmt);
        close(conn);
        Some(rows)
    }
}
