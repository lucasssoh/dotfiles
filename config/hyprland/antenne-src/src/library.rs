//! Streaming: shows followed from a link (a YouTube channel or playlist,
//! an Internet Archive collection, an arte collection…), each with its
//! seasons, arcs or parts and their episodes, as yt-dlp lists them without
//! downloading anything. The pages are "Continue watching" (the episodes
//! started, the next ones) and "Shows" (a grid; a show opened: its seasons
//! in tabs over its episodes). Keys are handled by main.rs; the view keeps
//! the selection in view with a row to spare.

use crate::store;
use gtk4 as gtk;
use gtk::prelude::*;
use gtk::{gdk, glib, pango};
use serde::{Deserialize, Serialize};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct Episode {
    pub title: String,
    pub url: String,
    /// Seconds; 0 when unknown.
    pub duration: u32,
    pub thumb: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct Group {
    pub name: String,
    pub episodes: Vec<Episode>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct Show {
    pub name: String,
    /// The link it was added from.
    pub url: String,
    /// "YouTube", "arte.tv"…
    pub origin: String,
    /// What a group is called: "Seasons", "Arcs", "Parts", or "Episodes"
    /// when there is a single one.
    pub level: String,
    pub groups: Vec<Group>,
    pub fetched: u64,
    /// How it was listed: an older listing is redone (tidier groups and titles).
    pub version: u32,
}

/// An attribute of an #EXTINF line: `group-title="Season 1"`.
fn attr(line: &str, name: &str) -> Option<String> {
    let k = format!("{name}=\"");
    let i = line.find(&k)? + k.len();
    let j = line[i..].find('"')? + i;
    Some(line[i..j].to_string()).filter(|v| !v.is_empty())
}

/// A show from an M3U playlist: its group-titles are the seasons, in the
/// order they come; each entry an episode (its name, its link, its
/// tvg-logo as the picture, its length when given).
pub fn from_m3u(text: &str, name: &str, url: &str, origin: &str) -> Result<Show, String> {
    let mut groups: Vec<Group> = vec![];
    let mut title = name.to_string();
    let mut pending: Option<(String, Option<String>, u32, Option<String>)> = None;
    for line in text.lines().map(str::trim) {
        if let Some(t) = line.strip_prefix("#PLAYLIST:") {
            title = t.trim().to_string();
        } else if let Some(info) = line.strip_prefix("#EXTINF:") {
            let dur = info.split([' ', ',']).next().and_then(|d| d.parse::<f64>().ok()).filter(|d| *d > 0.0).unwrap_or(0.0) as u32;
            let ep = info.rsplit_once(',').map(|(_, n)| n.trim().to_string()).unwrap_or_default();
            pending = Some((ep, attr(info, "group-title"), dur, attr(info, "tvg-logo")));
        } else if !line.is_empty() && !line.starts_with('#') {
            let (ep, group, duration, thumb) = pending.take().unwrap_or_default();
            let gname = group.unwrap_or_default();
            let i = match groups.iter().position(|g| g.name == gname) {
                Some(i) => i,
                None => {
                    groups.push(Group { name: gname, episodes: vec![] });
                    groups.len() - 1
                }
            };
            let ep = if ep.is_empty() { crate::catalog::host_of(line) } else { ep };
            groups[i].episodes.push(Episode { title: ep, url: line.to_string(), duration, thumb });
        }
    }
    groups.retain(|g| !g.episodes.is_empty());
    if groups.is_empty() {
        return Err("This playlist holds no episodes".into());
    }
    let level = if groups.len() == 1 { "Episodes" } else { "Seasons" }.to_string();
    Ok(Show { name: title, url: url.to_string(), origin: origin.into(), level, groups, fetched: store::now(), version: VERSION })
}

const VIDEOS: [&str; 9] = ["mp4", "mkv", "webm", "avi", "mov", "m4v", "ts", "flv", "mpg"];

/// "Episode 2" before "Episode 10".
fn natural(a: &str, b: &str) -> std::cmp::Ordering {
    match (number_in(a), number_in(b)) {
        (Some(x), Some(y)) if x != y => x.cmp(&y),
        _ => a.to_lowercase().cmp(&b.to_lowercase()),
    }
}

fn videos_in(dir: &std::path::Path) -> Vec<Episode> {
    let mut v: Vec<std::path::PathBuf> = std::fs::read_dir(dir)
        .map(|d| d.flatten().map(|e| e.path()).filter(|p| p.is_file() && p.extension().and_then(|x| x.to_str()).is_some_and(|x| VIDEOS.contains(&x.to_lowercase().as_str()))).collect())
        .unwrap_or_default();
    v.sort_by(|a, b| natural(&a.file_name().unwrap_or_default().to_string_lossy(), &b.file_name().unwrap_or_default().to_string_lossy()));
    v.into_iter()
        .map(|p| Episode { title: p.file_stem().map(|s| s.to_string_lossy().replace(['_', '.'], " ")).unwrap_or_default(), url: p.display().to_string(), duration: 0, thumb: None })
        .collect()
}

/// A show from a folder: its sub-folders are the seasons, the videos in
/// them the episodes (or the folder's own videos, as one season).
pub fn from_folder(dir: &std::path::Path) -> Result<Show, String> {
    let mut subs: Vec<std::path::PathBuf> = std::fs::read_dir(dir).map_err(|_| "This folder can't be read".to_string())?.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
    subs.sort_by(|a, b| natural(&a.file_name().unwrap_or_default().to_string_lossy(), &b.file_name().unwrap_or_default().to_string_lossy()));
    let mut groups: Vec<Group> = subs.iter().map(|s| Group { name: s.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(), episodes: videos_in(s) }).filter(|g| !g.episodes.is_empty()).collect();
    if groups.is_empty() {
        groups.push(Group { name: String::new(), episodes: videos_in(dir) });
    }
    groups.retain(|g| !g.episodes.is_empty());
    if groups.is_empty() {
        return Err("No videos in this folder".into());
    }
    let level = if groups.len() == 1 { "Episodes" } else { "Seasons" }.to_string();
    let name = dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "Show".into());
    Ok(Show { name, url: dir.display().to_string(), origin: "Folder".into(), level, groups, fetched: store::now(), version: VERSION })
}

/// The listing's version: shows listed before it are listed again.
pub const VERSION: u32 = 2;

impl Show {
    pub fn episodes(&self) -> usize {
        self.groups.iter().map(|g| g.episodes.len()).sum()
    }

    /// "4 arcs", "1 season", "26 episodes".
    pub fn size(&self) -> String {
        if self.groups.len() <= 1 {
            let n = self.episodes();
            return format!("{n} episode{}", if n == 1 { "" } else { "s" });
        }
        let n = self.groups.len();
        let w = self.level.to_lowercase();
        if n == 1 {
            format!("1 {}", w.trim_end_matches('s'))
        } else {
            format!("{n} {w}")
        }
    }

    /// The group's name, or "Season 3" when the source gives none.
    pub fn group_name(&self, i: usize) -> String {
        self.groups.get(i).map(|g| g.name.clone()).filter(|n| !n.is_empty()).unwrap_or_else(|| format!("Season {}", i + 1))
    }
}

#[derive(Serialize, Deserialize, Default)]
#[serde(default)]
pub struct Library {
    pub shows: Vec<Show>,
}

pub fn path() -> std::path::PathBuf {
    store::config_dir().join("library.json")
}

impl Library {
    pub fn load() -> Self {
        store::load(&path())
    }
    pub fn save(&self) {
        store::save(&path(), self)
    }
}

/// yt-dlp's flat listing of a link, as JSON.
fn listing(url: &str) -> Result<serde_json::Value, String> {
    let out = std::process::Command::new("yt-dlp")
        .args(["--flat-playlist", "-J", "--no-warnings", "--ignore-errors", url])
        .output()
        .map_err(|_| "yt-dlp is not installed".to_string())?;
    serde_json::from_slice(&out.stdout).map_err(|_| "Nothing to watch at this link".to_string())
}

fn episodes_of(v: &serde_json::Value) -> Vec<Episode> {
    v["entries"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|e| {
                    let title = e["title"].as_str()?.to_string();
                    if title.starts_with('[') && (title.contains("Private") || title.contains("Deleted")) {
                        return None;
                    }
                    let url = e["url"].as_str().or_else(|| e["webpage_url"].as_str())?.to_string();
                    let thumb = e["thumbnails"].as_array().and_then(|t| t.last()).and_then(|t| t["url"].as_str()).map(str::to_string).or_else(|| e["thumbnail"].as_str().map(str::to_string));
                    Some(Episode { title, url, duration: e["duration"].as_f64().unwrap_or(0.0) as u32, thumb })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// (season, episode) from "S01E87" in a title.
fn se_of(t: &str) -> Option<(u32, u32)> {
    let up = t.to_uppercase();
    let b = up.as_bytes();
    (0..b.len().saturating_sub(3)).find_map(|i| {
        if b[i] != b'S' || !b[i + 1].is_ascii_digit() {
            return None;
        }
        let s: String = up[i + 1..].chars().take_while(|c| c.is_ascii_digit()).collect();
        let rest = &up[i + 1 + s.len()..];
        let e: String = rest.strip_prefix('E')?.chars().take_while(|c| c.is_ascii_digit()).collect();
        Some((s.parse().ok()?, e.parse().ok()?))
    })
}

/// Episodes in their order when the titles number them, and without the
/// short extracts a playlist of full episodes sometimes holds.
fn tidy(eps: &mut Vec<Episode>) {
    let long = eps.iter().filter(|e| e.duration >= 180).count();
    if long * 2 > eps.len() {
        eps.retain(|e| e.duration == 0 || e.duration >= 60);
    }
    if eps.iter().filter(|e| se_of(&e.title).is_some()).count() * 3 > eps.len() * 2 {
        eps.sort_by_key(|e| se_of(&e.title).unwrap_or((u32::MAX, u32::MAX)));
    }
}

/// "Ultra-héros 🦸 Doraemon (S01E06) | Anime Culte" is "Ultra-héros",
/// "Oggy and the Cockroaches - Shoplifting  Full Episode in HD" is
/// "Shoplifting": the episode code, the emoji, the show's name and the
/// channel's catch phrases go, and the longest piece left is the title.
/// The title as it was when nothing is left.
fn clean_title(t: &str, show: &str) -> String {
    const NOISE: [&str; 15] = [
        "full episodes in hd", "full episode in hd", "new episodes in hd", "new episode in hd", "best cartoon collection",
        "cartoon compilation for kids", "cartoon for kids", "full episodes", "full episode", "anime culte", "nouvelle saison",
        "épisodes complets", "épisode complet", "new episodes", "in hd",
    ];
    let mut x = t.to_string();
    if let Some((s, e)) = se_of(&x) {
        for pat in [format!("(S{s:02}E{e:02})"), format!("S{s:02}E{e:02}"), format!("(S{s}E{e})"), format!("S{s}E{e}")] {
            x = x.replace(&pat, " ");
        }
    }
    // "(Season 3)", "(SEASON 4)", "(Saison 2)"
    while let Some(a) = x.find('(') {
        let Some(b) = x[a..].find(')').map(|b| a + b) else { break };
        let inner = x[a + 1..b].to_lowercase();
        if inner.starts_with("season") || inner.starts_with("saison") {
            x.replace_range(a..=b, " ");
        } else {
            break;
        }
    }
    let show_l = show.to_lowercase();
    let mut pieces: Vec<String> = vec![];
    for p in x.split(|c: char| c == '|' || !(c.is_alphanumeric() || c.is_whitespace() || "'’,.!?&:-()".contains(c))) {
        let mut p = p.trim().to_string();
        // the show's name: keep what follows it after a " - "
        if !show_l.is_empty() && p.to_lowercase().contains(&show_l) {
            let rest: Vec<&str> = p.split(" - ").filter(|seg| !seg.to_lowercase().contains(&show_l)).collect();
            p = rest.join(" - ");
        }
        for n in NOISE {
            while let Some(k) = p.to_lowercase().find(n) {
                if k + n.len() <= p.len() && p.is_char_boundary(k) && p.is_char_boundary(k + n.len()) {
                    p.replace_range(k..k + n.len(), " ");
                } else {
                    break;
                }
            }
        }
        // a shouted run of words after a title in lower case goes
        let words: Vec<&str> = p.split_whitespace().collect();
        let has_lower = words.iter().any(|w| w.chars().any(|c| c.is_lowercase()));
        let p: String = if has_lower { words.into_iter().filter(|w| !(w.chars().count() > 1 && w.chars().all(|c| !c.is_lowercase()) && w.chars().any(|c| c.is_alphabetic()))).collect::<Vec<_>>().join(" ") } else { words.join(" ") };
        let p = p.trim_matches(|c: char| c.is_whitespace() || "-–:|,".contains(c)).to_string();
        if p.chars().count() >= 3 {
            pieces.push(p);
        }
    }
    let Some(best) = pieces.into_iter().max_by_key(|p| p.chars().count()) else { return t.trim().to_string() };
    // all in capitals: written as a title
    if best.chars().any(|c| c.is_alphabetic()) && !best.chars().any(|c| c.is_lowercase()) {
        return best.split_whitespace().map(|w| {
            let mut c = w.chars();
            c.next().map(|f| f.to_string() + &c.as_str().to_lowercase()).unwrap_or_default()
        }).collect::<Vec<_>>().join(" ");
    }
    best
}

/// The first number in a name, to put "Season 2" before "Season 10".
fn number_in(s: &str) -> Option<u32> {
    let d: String = s.chars().skip_while(|c| !c.is_ascii_digit()).take_while(|c| c.is_ascii_digit()).collect();
    d.parse().ok()
}

/// A show from a link: a channel's playlists become its groups; a
/// playlist is a single group. Run on a worker thread.
pub fn fetch(url: &str) -> Result<Show, String> {
    let raw = url.trim();
    // a folder, or an M3U playlist (a file or a link): no yt-dlp
    let local = raw.strip_prefix("file://").unwrap_or(raw);
    let path = std::path::Path::new(local);
    if local.starts_with('/') && path.is_dir() {
        return from_folder(path);
    }
    let lower = local.to_lowercase();
    let stem = |s: &str| s.split(['?', '#']).next().unwrap_or(s).rsplit('/').next().unwrap_or(s).trim_end_matches(".m3u").to_string();
    if local.starts_with('/') && lower.ends_with(".m3u") {
        let text = std::fs::read_to_string(path).map_err(|_| "This file can't be read".to_string())?;
        return from_m3u(&text, &stem(local), raw, "Playlist");
    }
    if raw.starts_with("http") && crate::catalog::link_kind(raw) == Some(crate::catalog::LinkKind::Playlist) {
        let text = ureq::get(raw).timeout(std::time::Duration::from_secs(15)).call().ok().and_then(|r| r.into_string().ok()).ok_or_else(|| "This playlist didn't answer".to_string())?;
        return from_m3u(&text, &stem(raw), raw, "Playlist");
    }
    let mut link = raw.to_string();
    let lower = link.to_lowercase();
    let yt = lower.contains("youtube.com/");
    // a channel's own page lists its tabs; its playlists are the seasons
    if yt && (lower.contains("/@") || lower.contains("/channel/") || lower.contains("/c/")) && !lower.contains("/playlists") && !lower.contains("list=") {
        link = format!("{}/playlists", link.trim_end_matches('/').trim_end_matches("/videos").trim_end_matches("/featured"));
    }
    let v = listing(&link)?;
    let entries = v["entries"].as_array().cloned().unwrap_or_default();
    let nested = !entries.is_empty()
        && entries.iter().all(|e| e["_type"].as_str() == Some("playlist") || e["ie_key"].as_str().is_some_and(|k| k.ends_with("Tab") || k.ends_with("Playlist")));
    let mut groups = vec![];
    if nested {
        // six playlists at a time: a channel with twenty seasons lists in seconds
        let todo: Vec<(String, String)> = entries.iter().take(40).filter_map(|e| Some((e["url"].as_str()?.to_string(), e["title"].as_str().unwrap_or("").to_string()))).collect();
        for chunk in todo.chunks(6) {
            let got: Vec<Option<Group>> = std::thread::scope(|sc| {
                let hs: Vec<_> = chunk
                    .iter()
                    .map(|(u, t)| {
                        sc.spawn(move || {
                            let g = listing(u).ok()?;
                            let mut eps = episodes_of(&g);
                            tidy(&mut eps);
                            (!eps.is_empty()).then(|| Group { name: if t.is_empty() { g["title"].as_str().unwrap_or("").to_string() } else { t.clone() }, episodes: eps })
                        })
                    })
                    .collect();
                hs.into_iter().map(|h| h.join().ok().flatten()).collect()
            });
            groups.extend(got.into_iter().flatten());
        }
        // a channel's playlists hold more than episodes: trailers, shorts,
        // clips go; when some say they are full episodes, only those stay
        let low = |g: &Group| g.name.to_lowercase();
        groups.retain(|g| !["short", "bande annonce", "bande-annonce", "trailer", "teaser", "live", "clip"].iter().any(|w| low(g).contains(w)));
        if groups.iter().any(|g| ["épisodes complets", "episodes complets", "full episode", "épisode complet", "episode complet"].iter().any(|w| low(g).contains(w))) {
            groups.retain(|g| ["épisode", "episode"].iter().any(|w| low(g).contains(w)));
        }
        if groups.iter().all(|g| number_in(&g.name).is_some()) {
            groups.sort_by_key(|g| number_in(&g.name));
        }
    } else {
        let mut eps = episodes_of(&v);
        tidy(&mut eps);
        if !eps.is_empty() {
            groups.push(Group { name: String::new(), episodes: eps });
        }
    }
    if groups.is_empty() {
        return Err("Nothing to watch at this link".into());
    }
    let names: Vec<String> = groups.iter().map(|g| g.name.to_lowercase()).collect();
    let level = if groups.len() == 1 {
        "Episodes"
    } else if names.iter().any(|n| n.contains("arc")) {
        "Arcs"
    } else if names.iter().any(|n| n.contains("part") || n.contains("partie")) {
        "Parts"
    } else {
        "Seasons"
    }
    .to_string();
    let name = v["channel"].as_str().or(v["uploader"].as_str()).or(v["title"].as_str()).unwrap_or("Show").trim_end_matches(" - Playlists").trim_end_matches(" - Videos").to_string();
    // "Doraemon - Épisodes Complets - Saison 1" is "Saison 1" here
    let short = name.split([' ', '-']).next().unwrap_or("").to_lowercase();
    for g in groups.iter_mut() {
        let mut parts: Vec<&str> = g.name.split(" - ").map(str::trim).collect();
        parts.retain(|p| {
            let l = p.to_lowercase();
            !(l == short || l.starts_with(&format!("{short} ")) && l.len() < short.len() + 12 || l.contains("épisodes complets") || l.contains("episodes complets") || l.contains("full episodes"))
        });
        if !parts.is_empty() && parts.len() < g.name.split(" - ").count() {
            g.name = parts.join(" - ");
        }
    }
    let name = name.trim_end_matches(" - Chaîne officielle").trim_end_matches(" - Official Channel").to_string();
    let base = name.split(" - ").next().unwrap_or(&name).to_string();
    for g in groups.iter_mut() {
        for e in g.episodes.iter_mut() {
            e.title = clean_title(&e.title, &base);
        }
    }
    let origin = if yt { "YouTube".to_string() } else { crate::catalog::host_of(url) };
    Ok(Show { name, url: url.trim().to_string(), origin, level, groups, fetched: store::now(), version: VERSION })
}

// ---- the page ---------------------------------------------------------------

pub struct Card {
    pub title: String,
    pub sub: String,
    pub progress: Option<f64>,
    pub thumb: Option<gdk::Texture>,
    pub initials: String,
}

pub struct EpRow {
    pub n: usize,
    pub title: String,
    pub sub: String,
    pub progress: Option<f64>,
    pub done: bool,
    pub thumb: Option<gdk::Texture>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Cards,
    Episodes,
}

pub struct LibraryView {
    /// The page, and its actions menu over it.
    pub root: gtk::Overlay,
    pub menu: ActMenu,
    tabs: gtk::Box,
    tab_scroll: gtk::ScrolledWindow,
    panel: gtk::Box,
    scroller: gtk::ScrolledWindow,
    content: gtk::Box,
    pub field: gtk::Entry,
    field_row: gtk::Box,
    items: RefCell<Vec<gtk::Widget>>,
    sel: Cell<usize>,
    mode: Cell<Mode>,
    u: f64,
    pub on_activate: RefCell<Option<Box<dyn Fn(usize)>>>,
    pub on_tab: RefCell<Option<Box<dyn Fn(usize)>>>,
    pub on_add: RefCell<Option<Box<dyn Fn(String)>>>,
    /// "‹ All shows", from a show's episodes.
    pub on_back: RefCell<Option<Box<dyn Fn()>>>,
}

fn label(text: &str, class: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class(class);
    l.set_xalign(0.0);
    l.set_ellipsize(pango::EllipsizeMode::End);
    l
}

/// A 16:9 picture `w` wide, its progress along the bottom.
fn cover(thumb: &Option<gdk::Texture>, initials: &str, w: i32, progress: Option<f64>) -> gtk::Overlay {
    let h = w * 9 / 16;
    let o = gtk::Overlay::new();
    o.add_css_class("lcover");
    o.set_size_request(w, h);
    o.set_overflow(gtk::Overflow::Hidden);
    o.set_halign(gtk::Align::Start);
    o.set_valign(gtk::Align::Center);
    match thumb {
        Some(t) => {
            let p = gtk::Picture::for_paintable(t);
            p.set_content_fit(gtk::ContentFit::Cover);
            p.set_can_shrink(true);
            p.set_size_request(w, h);
            o.set_child(Some(&p));
        }
        None => {
            let l = gtk::Label::new(Some(initials));
            l.add_css_class("lini");
            l.set_size_request(w, h);
            o.set_child(Some(&l));
        }
    }
    if let Some(f) = progress {
        let bar = gtk::ProgressBar::new();
        bar.add_css_class("lbar");
        bar.set_valign(gtk::Align::End);
        bar.set_fraction(f.clamp(0.0, 1.0));
        o.add_overlay(&bar);
    }
    o
}

impl LibraryView {
    pub fn new(u: f64) -> Rc<Self> {
        let page = gtk::Box::new(gtk::Orientation::Vertical, 0);
        let root = gtk::Overlay::new();
        root.add_css_class("spage");
        root.set_child(Some(&page));
        let menu = ActMenu::new();
        root.add_overlay(&menu.root);
        let tabs = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        tabs.add_css_class("ptabs");
        let tab_scroll = gtk::ScrolledWindow::builder().hscrollbar_policy(gtk::PolicyType::External).vscrollbar_policy(gtk::PolicyType::Never).child(&tabs).build();
        tab_scroll.add_css_class("ptabs");
        let panel = gtk::Box::new(gtk::Orientation::Vertical, 0);
        panel.add_css_class("ppanel");
        panel.set_vexpand(true);
        let field_row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        field_row.add_css_class("lfield");
        let field = gtk::Entry::new();
        field.add_css_class("pfield");
        field.set_placeholder_text(Some("Paste a link or a path"));
        field.set_hexpand(true);
        let fbox = gtk::Box::new(gtk::Orientation::Vertical, 0);
        fbox.set_hexpand(true);
        fbox.append(&field);

        field_row.append(&fbox);
        field_row.set_visible(false);
        let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
        content.add_css_class("lcontent");
        let scroller = gtk::ScrolledWindow::builder().hscrollbar_policy(gtk::PolicyType::Never).vscrollbar_policy(gtk::PolicyType::External).vexpand(true).child(&content).build();
        panel.append(&field_row);
        panel.append(&scroller);
        page.append(&tab_scroll);
        page.append(&panel);
        let me = Rc::new(LibraryView {
            root,
            menu,
            tabs,
            tab_scroll,
            panel,
            scroller,
            content,
            field: field.clone(),
            field_row,
            items: RefCell::new(vec![]),
            sel: Cell::new(0),
            mode: Cell::new(Mode::Cards),
            u,
            on_activate: RefCell::new(None),
            on_tab: RefCell::new(None),
            on_add: RefCell::new(None),
            on_back: RefCell::new(None),
        });
        let w = Rc::downgrade(&me);
        field.connect_activate(move |e| {
            if let Some(me) = w.upgrade() {
                let t = e.text().trim().to_string();
                if !t.is_empty() {
                    e.set_text("");
                    if let Some(f) = me.on_add.borrow().as_ref() {
                        f(t);
                    }
                }
            }
        });
        me
    }

    pub fn mode(&self) -> Mode {
        self.mode.get()
    }

    pub fn selected(&self) -> usize {
        self.sel.get()
    }

    /// The field to paste a show's link, shown and given the keyboard, or hidden.
    pub fn set_adding(&self, on: bool) {
        self.field_row.set_visible(on);
        if on {
            self.field.grab_focus_without_selecting();
        }
    }

    pub fn adding(&self) -> bool {
        self.field_row.is_visible()
    }

    fn clear(&self) {
        while let Some(c) = self.content.first_child() {
            self.content.remove(&c);
        }
        while let Some(c) = self.tabs.first_child() {
            self.tabs.remove(&c);
        }
    }

    /// A grid of cards (Continue watching, Shows); `last_is_add`: the last
    /// card adds a show.
    pub fn set_cards(self: &Rc<Self>, cards: Vec<Card>, sel: usize, empty: &str, keep_scroll: bool) {
        let v = self.scroller.vadjustment().value();
        self.clear();
        self.mode.set(Mode::Cards);
        self.tab_scroll.set_visible(true);
        self.panel.remove_css_class("flush");
        let flow = gtk::FlowBox::new();
        flow.add_css_class("lgrid");
        flow.set_selection_mode(gtk::SelectionMode::None);
        flow.set_homogeneous(true);
        flow.set_max_children_per_line(12);
        flow.set_min_children_per_line(1);
        flow.set_valign(gtk::Align::Start);
        let w = (10.5 * self.u).round() as i32;
        let mut items = vec![];
        for (i, c) in cards.into_iter().enumerate() {
            let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
            card.add_css_class("lcard");
            card.append(&cover(&c.thumb, &c.initials, w, c.progress));
            let t = label(&c.title, "ltitle");
            t.set_max_width_chars(1);
            card.append(&t);
            let s = label(&c.sub, "lsub");
            s.set_max_width_chars(1);
            card.append(&s);
            card.set_size_request(w, -1);
            let click = gtk::GestureClick::new();
            let wk = Rc::downgrade(self);
            click.connect_released(move |_, _, _, _| {
                if let Some(me) = wk.upgrade() {
                    me.select(i);
                    me.activate();
                }
            });
            card.add_controller(click);
            flow.insert(&card, -1);
            if let Some(ch) = flow.child_at_index(i as i32) {
                ch.set_focusable(false);
            }
            items.push(card.upcast::<gtk::Widget>());
        }
        if items.is_empty() {
            self.content.append(&label(empty, "sempty"));
        } else {
            self.content.append(&flow);
        }
        *self.items.borrow_mut() = items;
        self.sel.set(usize::MAX);
        if keep_scroll {
            self.scroller.vadjustment().set_value(v);
        } else {
            self.scroller.vadjustment().set_value(0.0);
        }
        self.select(sel);
    }

    /// A show opened: its groups as tabs (`tab` picked), its episodes below.
    pub fn set_episodes(self: &Rc<Self>, tabs: Vec<(String, usize)>, tab: usize, rows: Vec<EpRow>, sel: usize, keep_scroll: bool) {
        let v = self.scroller.vadjustment().value();
        self.clear();
        self.mode.set(Mode::Episodes);
        self.tab_scroll.set_visible(true);
        self.field_row.set_visible(false);
        // the way back to the other shows, before this one's seasons
        let back = gtk::Button::new();
        back.add_css_class("lback");
        back.set_focusable(false);
        let bx = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        bx.append(&label("‹   All shows", "lbackname"));
        let cap = crate::keys::KeyCap::new(crate::keys::Action::Back);
        cap.set_margin_start((0.6 * self.u) as i32);
        bx.append(&cap);
        back.set_child(Some(&bx));
        let wk = Rc::downgrade(self);
        back.connect_clicked(move |_| {
            if let Some(me) = wk.upgrade() {
                if let Some(f) = me.on_back.borrow().as_ref() {
                    f();
                }
            }
        });
        self.tabs.append(&back);
        let mut active: Option<gtk::Button> = None;
        for (i, (name, n)) in tabs.iter().enumerate() {
            let on = i == tab;
            if on {
                let f = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                f.add_css_class("lfoot");
                f.set_valign(gtk::Align::End);
                self.tabs.append(&f);
            }
            let b = gtk::Button::new();
            b.add_css_class("ltab");
            if on {
                b.add_css_class("on");
            }
            let bx = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            bx.append(&label(name, "ltabname"));
            bx.append(&label(&n.to_string(), "ltabn"));
            b.set_child(Some(&bx));
            b.set_focusable(false);
            let wk = Rc::downgrade(self);
            b.connect_clicked(move |_| {
                if let Some(me) = wk.upgrade() {
                    if let Some(f) = me.on_tab.borrow().as_ref() {
                        f(i);
                    }
                }
            });
            self.tabs.append(&b);
            if on {
                let f = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                f.add_css_class("tfoot");
                f.set_valign(gtk::Align::End);
                self.tabs.append(&f);
                active = Some(b);
            }
        }
        self.panel.remove_css_class("flush");
        // the tab picked kept in view
        if let Some(b) = active {
            let sc = self.tab_scroll.clone();
            let tabs = self.tabs.clone();
            self.tabs.add_tick_callback(move |_, _| {
                if let Some(r) = b.compute_bounds(&tabs) {
                    let adj = sc.hadjustment();
                    let (x, w) = (r.x() as f64, r.width() as f64);
                    if x - 40.0 < adj.value() {
                        adj.set_value((x - 40.0).max(0.0));
                    } else if x + w + 40.0 > adj.value() + adj.page_size() {
                        adj.set_value(x + w + 40.0 - adj.page_size());
                    }
                }
                glib::ControlFlow::Break
            });
        }
        let tw = (6.0 * self.u).round() as i32;
        let mut items = vec![];
        let list = gtk::Box::new(gtk::Orientation::Vertical, 0);
        list.add_css_class("lrows");
        for (i, r) in rows.into_iter().enumerate() {
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            row.add_css_class("lrow");
            if r.done {
                row.add_css_class("done");
            }
            row.append(&cover(&r.thumb, &r.n.to_string(), tw, if r.done { Some(1.0) } else { r.progress }));
            let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
            text.set_hexpand(true);
            text.set_valign(gtk::Align::Center);
            let line = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            line.append(&label(&r.n.to_string(), "lnum"));
            let t = label(&r.title, "ltitle");
            t.set_hexpand(true);
            line.append(&t);
            text.append(&line);
            text.append(&label(&r.sub, "lsub"));
            row.append(&text);
            if r.done {
                row.append(&label("✓", "lok"));
            }
            let click = gtk::GestureClick::new();
            let wk = Rc::downgrade(self);
            click.connect_released(move |_, _, _, _| {
                if let Some(me) = wk.upgrade() {
                    me.select(i);
                    me.activate();
                }
            });
            row.add_controller(click);
            list.append(&row);
            items.push(row.upcast::<gtk::Widget>());
        }
        self.content.append(&list);
        *self.items.borrow_mut() = items;
        self.sel.set(usize::MAX);
        if keep_scroll {
            self.scroller.vadjustment().set_value(v);
        } else {
            self.scroller.vadjustment().set_value(0.0);
        }
        self.select(sel);
    }

    /// Cards on the grid's first line: the number of columns.
    fn columns(&self) -> usize {
        let items = self.items.borrow();
        let first = items.first().and_then(|w| w.compute_bounds(&self.content)).map(|r| r.y());
        items.iter().take_while(|w| w.compute_bounds(&self.content).map(|r| r.y()) == first).count().max(1)
    }

    /// Moves the selection; false when ← is pressed on the first column
    /// (the menu takes the keyboard back).
    pub fn move_sel(&self, dx: i32, dy: i32) -> bool {
        let n = self.items.borrow().len() as i32;
        if n == 0 {
            return dx >= 0;
        }
        let cur = self.sel.get().min(n as usize - 1) as i32;
        let cols = if self.mode.get() == Mode::Cards { self.columns() as i32 } else { 1 };
        if dx < 0 && cur % cols == 0 {
            return false;
        }
        let next = (cur + dx + dy * cols).clamp(0, n - 1);
        self.select(next as usize);
        true
    }

    pub fn select(&self, i: usize) {
        let items = self.items.borrow();
        if items.is_empty() {
            return;
        }
        let i = i.min(items.len() - 1);
        if let Some(w) = items.get(self.sel.get()) {
            w.remove_css_class("sel");
        }
        self.sel.set(i);
        let item = items[i].clone();
        item.add_css_class("sel");
        drop(items);
        let sc = self.scroller.clone();
        let content = self.content.clone();
        self.content.add_tick_callback(move |_, _| {
            if let Some(r) = item.compute_bounds(&content) {
                let adj = sc.vadjustment();
                let (y, h) = (r.y() as f64, r.height() as f64);
                let pad = h * 0.5;
                let v = adj.value();
                if y - pad < v {
                    adj.set_value((y - pad).max(0.0));
                } else if y + h + pad > v + adj.page_size() {
                    adj.set_value((y + h + pad - adj.page_size()).min(adj.upper() - adj.page_size()));
                }
            }
            glib::ControlFlow::Break
        });
    }

    pub fn activate(&self) {
        let i = self.sel.get();
        if i == usize::MAX {
            return;
        }
        if let Some(f) = self.on_activate.borrow().as_ref() {
            f(i);
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn m3u_seasons() {
        let t = "#EXTM3U\n#EXTINF:-1 group-title=\"Season 1\" tvg-logo=\"https://e.org/1.jpg\",Pilot\nhttps://e.org/s1e1.mp4\n#EXTINF:1320 group-title=\"Season 1\",Second\nhttps://e.org/s1e2.mp4\n#EXTINF:-1 group-title=\"Season 2\",Third\nhttps://e.org/s2e1.mp4\n";
        let s = super::from_m3u(t, "My show", "x", "Playlist").unwrap();
        assert_eq!(s.groups.len(), 2);
        assert_eq!(s.groups[0].name, "Season 1");
        assert_eq!(s.groups[0].episodes[1].duration, 1320);
        assert_eq!(s.groups[0].episodes[0].thumb.as_deref(), Some("https://e.org/1.jpg"));
        assert_eq!(s.level, "Seasons");
    }

    #[test]
    fn titles() {
        use super::clean_title as c;
        assert_eq!(c("Ultra-héros 🦸 Doraemon (S01E06) | Anime Culte", "Doraemon"), "Ultra-héros");
        assert_eq!(c("NOUVELLE SAISON ✨ La future femme de Nobita ✨ Doraemon (S02E02)", "Doraemon"), "La future femme de Nobita");
        assert_eq!(c("Le bouton du dictateur - Part 1 | Doraemon  (S02E03)", "Doraemon"), "Le bouton du dictateur - Part 1");
        assert_eq!(c("Oggy and the Cockroaches - Shoplifting   Full Episode in HD", "Oggy"), "Shoplifting");
        assert_eq!(c("PANIC ROOM | Oggy and the Cockroaches (S04E08) BEST CARTOON COLLECTION | New Episodes in HD", "Oggy"), "Panic Room");
        assert_eq!(c("Zig & Sharko | Nurse Marina! (Season 3) BEST CARTOON COLLECTION | New Episodes in HD", "Zig & Sharko"), "Nurse Marina!");
        assert_eq!(c("Full Episode in HD", "Zig & Sharko"), "Full Episode in HD");
    }
}

#[cfg(test)]
mod live {
    /// cargo test --release library_live -- --ignored --nocapture
    #[test]
    #[ignore]
    fn library_live() {
        let t = std::time::Instant::now();
        let s = super::fetch(&std::env::var("SHOW").unwrap_or("https://www.youtube.com/@NASA".into())).expect("a show");
        println!("{} · {} · {} · {:?}", s.name, s.origin, s.size(), t.elapsed());
        for g in s.groups.iter().take(5) {
            println!("  {} ({}): {:?}", g.name, g.episodes.len(), g.episodes.iter().take(3).map(|e| (&e.title, e.duration)).collect::<Vec<_>>());
        }
    }
}

/// What can be done with a show or an episode, from its little menu.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Act {
    Watched(bool),
    Restart,
    RemoveFromContinue,
    Refresh,
    RemoveShow,
}

/// A short list of actions over the page, like a long press on a TV:
/// ↑ ↓ choose, Enter does it, Esc closes.
pub struct ActMenu {
    pub root: gtk::Box,
    title: gtk::Label,
    list: gtk::Box,
    items: RefCell<Vec<(Act, gtk::Button)>>,
    sel: Cell<usize>,
    pub on_act: Rc<RefCell<Option<Box<dyn Fn(Act)>>>>,
}

impl ActMenu {
    pub fn new() -> Self {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("lmenu");
        root.set_halign(gtk::Align::Center);
        root.set_valign(gtk::Align::Center);
        root.set_visible(false);
        let title = label("", "lmtitle");
        let list = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.append(&title);
        root.append(&list);
        ActMenu { root, title, list, items: RefCell::new(vec![]), sel: Cell::new(0), on_act: Rc::default() }
    }

    pub fn is_open(&self) -> bool {
        self.root.is_visible()
    }

    pub fn open(&self, title: &str, acts: Vec<(Act, String)>) {
        while let Some(c) = self.list.first_child() {
            self.list.remove(&c);
        }
        self.title.set_text(title);
        let mut items = vec![];
        for (act, text) in acts {
            let b = gtk::Button::with_label(&text);
            b.add_css_class("lmitem");
            b.set_focusable(false);
            let cb = self.on_act.clone();
            b.connect_clicked(move |_| {
                if let Some(f) = cb.borrow().as_ref() {
                    f(act);
                }
            });
            self.list.append(&b);
            items.push((act, b));
        }
        *self.items.borrow_mut() = items;
        self.root.set_visible(true);
        self.select(0);
    }

    pub fn close(&self) {
        self.root.set_visible(false);
    }

    pub fn move_sel(&self, d: i32) {
        let n = self.items.borrow().len() as i32;
        if n > 0 {
            self.select((self.sel.get() as i32 + d).clamp(0, n - 1) as usize);
        }
    }

    fn select(&self, i: usize) {
        for (k, (_, b)) in self.items.borrow().iter().enumerate() {
            if k == i {
                b.add_css_class("sel");
            } else {
                b.remove_css_class("sel");
            }
        }
        self.sel.set(i);
    }

    pub fn selected(&self) -> Option<Act> {
        self.items.borrow().get(self.sel.get()).map(|(a, _)| *a)
    }

    /// The selected action's text changed in place (a confirmation).
    pub fn relabel(&self, text: &str) {
        if let Some((_, b)) = self.items.borrow().get(self.sel.get()) {
            b.set_label(text);
        }
    }
}
