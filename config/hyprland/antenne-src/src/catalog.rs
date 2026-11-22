//! The channel list: iptv-org's per-country M3U playlists plus the user's
//! own, merged into channels that each carry every source known for them.
//!
//! The per-country playlists rather than iptv-org's JSON API: France is a
//! 60 KB file against 12 MB of JSON for the whole world, it already carries
//! the headers some servers demand (user agent, referrer), and the same
//! parser then reads the user's own playlists.

use crate::store;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::time::Duration;

pub const BROWSER_UA: &str = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0";

#[derive(Clone, Debug)]
pub struct Source {
    pub url: String,
    pub user_agent: Option<String>,
    pub referrer: Option<String>,
    pub quality: Option<String>,
    /// Where it came from, for the info sheet: "iptv-org France", "ma-liste.m3u".
    pub origin: String,
}

impl Source {
    /// 1080 for "1080p"; 0 when unknown.
    pub fn lines(&self) -> u32 {
        self.quality.as_deref().map(|q| q.trim_end_matches(['p', 'i']).parse().unwrap_or(0)).unwrap_or(0)
    }
}

#[derive(Clone, Debug)]
pub struct Channel {
    /// tvg-id without its feed ("tf1.fr"), or "name:<name>" when there is none.
    pub key: String,
    pub name: String,
    pub category: String,
    pub sources: Vec<Source>,
    pub number: u32,
    /// The channel's logo (tvg-logo), when the playlist gives one.
    pub logo: Option<String>,
    /// Two-letter country, from the iptv-org id ("tf1.fr" -> "FR"); empty
    /// for the user's own lists without ids.
    pub country: String,
}

impl Channel {
    pub fn quality(&self) -> Option<&str> {
        self.sources.iter().filter_map(|s| s.quality.as_deref()).max_by_key(|q| q.trim_end_matches(['p', 'i']).parse::<u32>().unwrap_or(0))
    }
}

/// French DTT numbers, so 1 is TF1 and 15 is BFM TV as on any TV.
/// Everything else is numbered from 30 in name order.
const TNT: &[(&str, u32)] = &[
    ("tf1.fr", 1), ("france2.fr", 2), ("france3.fr", 3), ("canalplus.fr", 4), ("france5.fr", 5),
    ("m6.fr", 6), ("arte.fr", 7), ("c8.fr", 8), ("w9.fr", 9), ("tmc.fr", 10), ("tfx.fr", 11),
    ("nrj12.fr", 12), ("lcp.fr", 13), ("france4.fr", 14), ("bfmtv.fr", 15), ("cnews.fr", 16),
    ("cstar.fr", 17), ("gulli.fr", 18), ("tf1seriesfilms.fr", 20), ("lequipe.fr", 21), ("6ter.fr", 22),
    ("rmcstory.fr", 23), ("rmcdecouverte.fr", 24), ("cherie25.fr", 25), ("lci.fr", 26), ("franceinfo.fr", 27),
];

/// One `key="value"` attribute out of an #EXTINF line.
fn attr<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let pat = format!("{key}=\"");
    let i = line.find(&pat)? + pat.len();
    let j = line[i..].find('"')? + i;
    Some(&line[i..j]).filter(|v| !v.is_empty())
}

/// The display name: what follows the first comma outside quotes.
fn extinf_name(line: &str) -> &str {
    let mut quoted = false;
    for (i, c) in line.char_indices() {
        match c {
            '"' => quoted = !quoted,
            ',' if !quoted => return line[i + 1..].trim(),
            _ => {}
        }
    }
    ""
}

/// "TF1 (1080p) [Geo-blocked]" -> ("TF1", Some("1080p")).
fn split_name(raw: &str) -> (String, Option<String>) {
    let mut name = raw.trim().to_string();
    let mut quality = None;
    loop {
        let t = name.trim_end().to_string();
        if t.ends_with(']') {
            if let Some(i) = t.rfind('[') {
                name = t[..i].to_string();
                continue;
            }
        }
        if t.ends_with(')') {
            if let Some(i) = t.rfind('(') {
                let inner = &t[i + 1..t.len() - 1];
                let digits = inner.trim_end_matches(['p', 'i']);
                if inner.len() > digits.len() && digits.chars().all(|c| c.is_ascii_digit()) && !digits.is_empty() {
                    quality = Some(inner.to_string());
                    name = t[..i].to_string();
                    continue;
                }
            }
        }
        return (t, quality);
    }
}

struct Entry {
    key: String,
    name: String,
    category: String,
    logo: Option<String>,
    source: Source,
}

/// The entries, and the guides the playlist names on its first line
/// (url-tvg / x-tvg-url, possibly several, comma-separated).
fn parse_m3u(text: &str, origin: &str) -> (Vec<Entry>, Vec<String>) {
    let mut out = Vec::new();
    let mut guides = Vec::new();
    let (mut info, mut ua, mut referrer): (Option<String>, Option<String>, Option<String>) = (None, None, None);
    for line in text.lines() {
        let line = line.trim_end_matches('\r').trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with("#EXTM3U") {
            for key in ["url-tvg", "x-tvg-url"] {
                if let Some(v) = attr(line, key) {
                    guides.extend(v.split(',').map(str::trim).filter(|u| u.starts_with("http")).map(str::to_string));
                }
            }
        } else if line.starts_with("#EXTINF") {
            ua = attr(line, "http-user-agent").map(str::to_string);
            referrer = attr(line, "http-referrer").map(str::to_string);
            info = Some(line.to_string());
        } else if let Some(opt) = line.strip_prefix("#EXTVLCOPT:") {
            if let Some(v) = opt.strip_prefix("http-user-agent=") {
                ua = Some(v.to_string());
            } else if let Some(v) = opt.strip_prefix("http-referrer=") {
                referrer = Some(v.to_string());
            }
        } else if !line.starts_with('#') {
            let Some(inf) = info.take() else { continue };
            let (name, quality) = split_name(extinf_name(&inf));
            if name.is_empty() {
                continue;
            }
            let key = match attr(&inf, "tvg-id") {
                Some(id) => id.split('@').next().unwrap_or(id).to_lowercase(),
                None => format!("name:{}", name.to_lowercase()),
            };
            let category = attr(&inf, "group-title")
                .and_then(|g| g.split(';').next())
                .filter(|g| *g != "Undefined")
                .unwrap_or("Other")
                .to_string();
            out.push(Entry {
                key,
                name,
                category,
                logo: attr(&inf, "tvg-logo").filter(|u| u.starts_with("http")).map(str::to_string),
                source: Source { url: line.to_string(), user_agent: ua.take(), referrer: referrer.take(), quality, origin: origin.to_string() },
            });
        }
    }
    (out, guides)
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(6))
        .timeout_read(Duration::from_secs(15))
        .user_agent(BROWSER_UA)
        .build()
}

fn cache_file(name: &str) -> PathBuf {
    store::cache_dir().join("playlists").join(name)
}

fn age(path: &PathBuf) -> Option<Duration> {
    std::fs::metadata(path).ok()?.modified().ok()?.elapsed().ok()
}

/// A playlist's text: from the cache when it is under a day old (or when
/// the network is down), downloaded otherwise.
fn fetch(url: &str, cache: &PathBuf, refresh: bool) -> Option<String> {
    let fresh = age(cache).is_some_and(|a| a < Duration::from_secs(24 * 3600));
    if fresh && !refresh {
        if let Ok(t) = std::fs::read_to_string(cache) {
            return Some(t);
        }
    }
    if refresh || !fresh {
        if let Ok(resp) = agent().get(url).call() {
            if let Ok(t) = resp.into_string() {
                if let Some(d) = cache.parent() {
                    let _ = std::fs::create_dir_all(d);
                }
                let _ = std::fs::write(cache, &t);
                return Some(t);
            }
        }
    }
    std::fs::read_to_string(cache).ok()
}

fn read_playlist(spec: &str, refresh: bool) -> Option<String> {
    if spec.starts_with("http://") || spec.starts_with("https://") {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        spec.hash(&mut h);
        fetch(spec, &cache_file(&format!("own-{:016x}.m3u", h.finish())), refresh)
    } else {
        let path = spec.strip_prefix("~/").map(|p| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(p)).unwrap_or_else(|| spec.into());
        std::fs::read_to_string(path).ok()
    }
}

/// Country names for the origins shown in the info sheet and settings.
/// Country codes and names, as iptv-org names its per-country lists
/// ("uk" for the United Kingdom, as well as "gb").
const COUNTRIES: &str = "ad Andorra;ae United Arab Emirates;af Afghanistan;ag Antigua and Barbuda;ai Anguilla;al Albania;am Armenia;ao Angola;ar Argentina;as American Samoa;at Austria;au Australia;aw Aruba;ax Åland;az Azerbaijan;ba Bosnia and Herzegovina;bb Barbados;bd Bangladesh;be Belgium;bf Burkina Faso;bg Bulgaria;bh Bahrain;bi Burundi;bj Benin;bl Saint Barthélemy;bm Bermuda;bn Brunei;bo Bolivia;bq Caribbean Netherlands;br Brazil;bs Bahamas;bt Bhutan;bw Botswana;by Belarus;bz Belize;ca Canada;cd DR Congo;cf Central African Republic;cg Congo;ch Switzerland;ci Ivory Coast;ck Cook Islands;cl Chile;cm Cameroon;cn China;co Colombia;cr Costa Rica;cu Cuba;cv Cape Verde;cw Curaçao;cy Cyprus;cz Czechia;de Germany;dj Djibouti;dk Denmark;dm Dominica;do Dominican Republic;dz Algeria;ec Ecuador;ee Estonia;eg Egypt;eh Western Sahara;er Eritrea;es Spain;et Ethiopia;fi Finland;fj Fiji;fk Falkland Islands;fm Micronesia;fo Faroe Islands;fr France;ga Gabon;gb United Kingdom;uk United Kingdom;gd Grenada;ge Georgia;gf French Guiana;gg Guernsey;gh Ghana;gi Gibraltar;gl Greenland;gm Gambia;gn Guinea;gp Guadeloupe;gq Equatorial Guinea;gr Greece;gt Guatemala;gu Guam;gw Guinea-Bissau;gy Guyana;hk Hong Kong;hn Honduras;hr Croatia;ht Haiti;hu Hungary;id Indonesia;ie Ireland;il Israel;im Isle of Man;in India;iq Iraq;ir Iran;is Iceland;it Italy;je Jersey;jm Jamaica;jo Jordan;jp Japan;ke Kenya;kg Kyrgyzstan;kh Cambodia;ki Kiribati;km Comoros;kn Saint Kitts and Nevis;kp North Korea;kr South Korea;kw Kuwait;ky Cayman Islands;kz Kazakhstan;la Laos;lb Lebanon;lc Saint Lucia;li Liechtenstein;lk Sri Lanka;lr Liberia;ls Lesotho;lt Lithuania;lu Luxembourg;lv Latvia;ly Libya;ma Morocco;mc Monaco;md Moldova;me Montenegro;mf Saint Martin;mg Madagascar;mh Marshall Islands;mk North Macedonia;ml Mali;mm Myanmar;mn Mongolia;mo Macao;mp Northern Mariana Islands;mq Martinique;mr Mauritania;ms Montserrat;mt Malta;mu Mauritius;mv Maldives;mw Malawi;mx Mexico;my Malaysia;mz Mozambique;na Namibia;nc New Caledonia;ne Niger;ng Nigeria;ni Nicaragua;nl Netherlands;no Norway;np Nepal;nr Nauru;nz New Zealand;om Oman;pa Panama;pe Peru;pf French Polynesia;pg Papua New Guinea;ph Philippines;pk Pakistan;pl Poland;pm Saint Pierre and Miquelon;pr Puerto Rico;ps Palestine;pt Portugal;pw Palau;py Paraguay;qa Qatar;re Réunion;ro Romania;rs Serbia;ru Russia;rw Rwanda;sa Saudi Arabia;sb Solomon Islands;sc Seychelles;sd Sudan;se Sweden;sg Singapore;si Slovenia;sk Slovakia;sl Sierra Leone;sm San Marino;sn Senegal;so Somalia;sr Suriname;ss South Sudan;st São Tomé and Príncipe;sv El Salvador;sx Sint Maarten;sy Syria;sz Eswatini;tc Turks and Caicos Islands;td Chad;tg Togo;th Thailand;tj Tajikistan;tl Timor-Leste;tm Turkmenistan;tn Tunisia;to Tonga;tr Turkey;tt Trinidad and Tobago;tv Tuvalu;tw Taiwan;tz Tanzania;ua Ukraine;ug Uganda;us United States;uy Uruguay;uz Uzbekistan;va Vatican City;vc Saint Vincent and the Grenadines;ve Venezuela;vg British Virgin Islands;vi US Virgin Islands;vn Vietnam;vu Vanuatu;wf Wallis and Futuna;ws Samoa;xk Kosovo;ye Yemen;yt Mayotte;za South Africa;zm Zambia;zw Zimbabwe";

pub fn country_name(cc: &str) -> String {
    let cc = cc.to_lowercase();
    COUNTRIES
        .split(';')
        .find_map(|e| e.split_once(' ').filter(|(c, _)| *c == cc).map(|(_, n)| n.to_string()))
        .unwrap_or_else(|| cc.to_uppercase())
}

/// A playlist of the user's, as the settings show it.
#[derive(Clone, Debug)]
pub struct ListStats {
    /// As written in settings.json (URL or path), or the file in the folder.
    pub spec: String,
    pub name: String,
    pub channels: usize,
    /// Of those, how many were already known from another list.
    pub merged: usize,
    /// Read from ~/.config/antenne/playlists, not from settings.json.
    pub from_folder: bool,
}

/// `offline`: only what is already cached, so the window fills at once
/// on launch; the refreshed list follows from a background thread.
pub struct Catalog {
    pub channels: Vec<Channel>,
    /// Guides named by the playlists themselves.
    pub guides: Vec<String>,
    pub lists: Vec<ListStats>,
}

/// The folder whose playlists are read without being added anywhere.
pub fn folder() -> PathBuf {
    store::config_dir().join("playlists")
}

/// What a pasted link is. Antenne knows no site in particular: a page is
/// handed to mpv, which asks yt-dlp for the video when it cannot open the
/// page itself.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LinkKind {
    Playlist,
    Stream,
    Page,
    Video,
}

const MEDIA: [&str; 14] = ["m3u8", "mpd", "mp4", "mkv", "webm", "ts", "mov", "avi", "m4v", "flv", "mp3", "aac", "ogg", "opus"];

pub fn link_kind(s: &str) -> Option<LinkKind> {
    let s = s.trim();
    let lower = s.to_lowercase();
    let path = lower.split(['?', '#']).next().unwrap_or(&lower);
    let ext = path.rsplit_once('.').map(|(_, e)| e).unwrap_or("");
    if ["rtsp://", "rtsps://", "rtmp://", "rtmps://", "udp://", "rtp://", "srt://"].iter().any(|p| lower.starts_with(p)) {
        return Some(LinkKind::Stream);
    }
    if s.starts_with('/') || lower.starts_with("file://") {
        return if ext == "m3u" {
            Some(LinkKind::Playlist)
        } else if MEDIA.contains(&ext) {
            Some(LinkKind::Video)
        } else {
            None
        };
    }
    let rest = lower.strip_prefix("https://").or_else(|| lower.strip_prefix("http://"))?;
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    if !host.contains('.') || s.contains(char::is_whitespace) {
        return None;
    }
    Some(if is_playlist(s) {
        LinkKind::Playlist
    } else if MEDIA.contains(&ext) {
        LinkKind::Stream
    } else {
        LinkKind::Page
    })
}

/// A recording (a page's video, a file, an .mp4 link) rather than a live
/// stream: its end is an end, not a source that died.
pub fn is_recording(url: &str) -> bool {
    match link_kind(url) {
        Some(LinkKind::Page) | Some(LinkKind::Video) => true,
        Some(LinkKind::Stream) => {
            let lower = url.to_lowercase();
            let path = lower.split(['?', '#']).next().unwrap_or(&lower);
            let ext = path.rsplit_once('.').map(|(_, e)| e).unwrap_or("");
            !matches!(ext, "m3u8" | "mpd" | "ts") && (lower.starts_with("http") || lower.starts_with('/'))
        }
        _ => false,
    }
}

/// "arte.tv" for https://www.arte.tv/fr/…, "192.168.1.20" for rtsp://…,
/// the file's name for a video on disk.
pub fn host_of(s: &str) -> String {
    let s = s.trim();
    if s.starts_with('/') || s.starts_with("file://") {
        return s.rsplit('/').next().unwrap_or(s).to_string();
    }
    let rest = s.split_once("://").map(|(_, r)| r).unwrap_or(s);
    let host = rest.split(['/', '?', '#']).next().unwrap_or(rest);
    let host = host.rsplit_once('@').map(|(_, h)| h).unwrap_or(host);
    let host = host.split(':').next().unwrap_or(host);
    host.trim_start_matches("www.").to_string()
}

/// A stream, a page or a video the user added, kept as a channel of its
/// own in the playlists folder ("My sources" in the guide).
#[derive(Clone, Debug, PartialEq)]
pub struct MySource {
    pub name: String,
    pub url: String,
}

pub fn my_sources_path() -> PathBuf {
    folder().join("my-sources.m3u")
}

pub fn my_sources() -> Vec<MySource> {
    let Ok(t) = std::fs::read_to_string(my_sources_path()) else { return vec![] };
    let mut out = vec![];
    let mut name: Option<String> = None;
    for line in t.lines().map(str::trim) {
        if let Some(info) = line.strip_prefix("#EXTINF") {
            name = info.rsplit_once(',').map(|(_, n)| n.trim().to_string());
        } else if !line.is_empty() && !line.starts_with('#') {
            out.push(MySource { name: name.take().unwrap_or_else(|| host_of(line)), url: line.to_string() });
        }
    }
    out
}

pub fn save_my_sources(list: &[MySource]) {
    let mut t = String::from("#EXTM3U\n");
    for (i, s) in list.iter().enumerate() {
        let mut id = crate::epg::norm(&s.name);
        if id.is_empty() {
            id = format!("source{i}");
        }
        let name = s.name.replace(',', " ");
        t.push_str(&format!("#EXTINF:-1 tvg-id=\"my.{id}\" group-title=\"My sources\",{name}\n{}\n", s.url.trim()));
    }
    let _ = std::fs::create_dir_all(folder());
    let _ = std::fs::write(my_sources_path(), t);
}

fn spec_name(spec: &str) -> String {
    let base = spec.split(['?', '#']).next().unwrap_or(spec).trim_end_matches('/');
    base.rsplit('/').next().filter(|n| !n.is_empty()).unwrap_or(spec).to_string()
}

/// A line of a playlist that is itself a playlist (.m3u, not an HLS
/// stream's .m3u8): opened and merged too.
fn is_playlist(url: &str) -> bool {
    let path = url.split(['?', '#']).next().unwrap_or(url).to_lowercase();
    path.ends_with(".m3u") || url.contains("type=m3u")
}

/// One playlist and the playlists it names, two levels deep, each read
/// once: two lists that name each other do not loop.
fn read_tree(spec: &str, origin: &str, offline: bool, depth: u8, seen: &mut HashSet<String>, entries: &mut Vec<Entry>, guides: &mut Vec<String>) -> usize {
    if !seen.insert(spec.to_string()) {
        return 0;
    }
    let text = if offline && spec.starts_with("http") { None } else { read_playlist(spec, false) };
    let Some(t) = text else { return 0 };
    let (e, g) = parse_m3u(&t, origin);
    guides.extend(g);
    let mut n = 0;
    for entry in e {
        if depth < 2 && is_playlist(&entry.source.url) {
            n += read_tree(&entry.source.url.clone(), origin, offline, depth + 1, seen, entries, guides);
        } else {
            entries.push(entry);
            n += 1;
        }
    }
    n
}

pub fn load(settings: &store::Settings, offline: bool) -> Catalog {
    let mut entries = Vec::new();
    let mut guides: Vec<String> = Vec::new();
    for cc in &settings.countries {
        let cc = cc.to_lowercase();
        let cache = cache_file(&format!("{cc}.m3u"));
        let text = if offline {
            std::fs::read_to_string(&cache).ok()
        } else {
            fetch(&format!("https://iptv-org.github.io/iptv/countries/{cc}.m3u"), &cache, false)
        };
        if let Some(t) = text {
            let (e, g) = parse_m3u(&t, &format!("iptv-org {}", country_name(&cc)));
            entries.extend(e);
            guides.extend(g);
        }
    }
    // the user's lists: those in settings.json, then the folder's
    let mut specs: Vec<(String, bool)> = settings.playlists.iter().map(|p| (p.clone(), false)).collect();
    if let Ok(dir) = std::fs::read_dir(folder()) {
        let mut files: Vec<String> = dir
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x.eq_ignore_ascii_case("m3u") || x.eq_ignore_ascii_case("m3u8")))
            .map(|p| p.display().to_string())
            .collect();
        files.sort();
        specs.extend(files.into_iter().map(|f| (f, true)));
    }
    // videos put in the folder are channels of their own
    if let Ok(dir) = std::fs::read_dir(folder()) {
        let mut vids: Vec<PathBuf> = dir.flatten().map(|e| e.path()).filter(|p| p.extension().and_then(|x| x.to_str()).is_some_and(|x| MEDIA.contains(&x.to_lowercase().as_str()) && x != "m3u8")).collect();
        vids.sort();
        for p in vids {
            let path = p.display().to_string();
            let name = p.file_stem().and_then(|s| s.to_str()).unwrap_or("Video").to_string();
            entries.push(Entry {
                key: format!("file:{path}"),
                name,
                category: "My sources".into(),
                logo: None,
                source: Source { url: path, user_agent: None, referrer: None, quality: None, origin: "Playlists folder".into() },
            });
        }
    }
    let mut seen = HashSet::new();
    let mut spans: Vec<(String, String, bool, usize, usize)> = vec![];
    for (spec, from_folder) in &specs {
        let name = spec_name(spec);
        let start = entries.len();
        read_tree(spec, &name, offline, 0, &mut seen, &mut entries, &mut guides);
        spans.push((spec.clone(), name, *from_folder, start, entries.len()));
    }
    guides.dedup();
    let channels = merge(entries.iter().map(clone_entry).collect());
    // how many of each list's channels another list already had
    let lists = spans
        .into_iter()
        .map(|(spec, name, from_folder, a, b)| {
            let keys: HashSet<String> = entries[a..b].iter().map(|e| e.key.clone()).collect();
            let merged = channels
                .iter()
                .filter(|c| c.sources.iter().any(|s| s.origin == name) && c.sources.iter().any(|s| s.origin != name))
                .count();
            ListStats { spec, name, channels: keys.len(), merged, from_folder }
        })
        .collect();
    Catalog { channels, guides, lists }
}

fn clone_entry(e: &Entry) -> Entry {
    Entry { key: e.key.clone(), name: e.name.clone(), category: e.category.clone(), logo: e.logo.clone(), source: e.source.clone() }
}

/// Every channel iptv-org lists, for "Elsewhere" in the search: 2.6 MB,
/// downloaded the first time the search opens, kept a day.
pub fn load_world() -> Vec<Channel> {
    let cache = cache_file("world.m3u");
    let Some(t) = fetch("https://iptv-org.github.io/iptv/index.m3u", &cache, false) else { return vec![] };
    let (e, _) = parse_m3u(&t, "iptv-org");
    merge(e)
}

fn merge(entries: Vec<Entry>) -> Vec<Channel> {
    let mut order: Vec<String> = Vec::new();
    let mut by: HashMap<String, Channel> = HashMap::new();
    for e in entries {
        let ch = by.entry(e.key.clone()).or_insert_with(|| {
            order.push(e.key.clone());
            let cc = e.key.rsplit('.').next().unwrap_or("");
            let country = if e.key.starts_with("name:") || cc.len() != 2 || !cc.chars().all(|c| c.is_ascii_alphabetic()) { String::new() } else { cc.to_uppercase() };
            Channel { key: e.key.clone(), name: e.name.clone(), category: e.category.clone(), sources: vec![], number: 0, logo: None, country }
        });
        if ch.logo.is_none() {
            ch.logo = e.logo.clone();
        }
        if !ch.sources.iter().any(|s| s.url == e.source.url) {
            ch.sources.push(e.source);
        }
    }
    // A channel without an id joins the one with an id whose cleaned name
    // is the same: "TF1 HD" and "FR: TF1" in a list are TF1, not new channels.
    let mut by_norm: HashMap<String, String> = HashMap::new();
    for k in &order {
        if !k.starts_with("name:") {
            if let Some(c) = by.get(k) {
                by_norm.entry(crate::epg::norm(&c.name)).or_insert_with(|| k.clone());
            }
        }
    }
    for k in order.iter().filter(|k| k.starts_with("name:")) {
        let Some(name) = by.get(k).map(|c| c.name.clone()) else { continue };
        if let Some(target) = by_norm.get(&crate::epg::norm(&name)).cloned() {
            if let Some(c) = by.remove(k) {
                let t = by.get_mut(&target).expect("target channel");
                for s in c.sources {
                    if !t.sources.iter().any(|x| x.url == s.url) {
                        t.sources.push(s);
                    }
                }
                if t.logo.is_none() {
                    t.logo = c.logo;
                }
            }
        }
    }
    let tnt: HashMap<&str, u32> = TNT.iter().copied().collect();
    let mut chans: Vec<Channel> = order.into_iter().filter_map(|k| by.remove(&k)).collect();
    for c in chans.iter_mut() {
        c.number = tnt.get(c.key.as_str()).copied().unwrap_or(0);
    }
    chans.sort_by(|a, b| match (a.number, b.number) {
        (0, 0) => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        (0, _) => std::cmp::Ordering::Greater,
        (_, 0) => std::cmp::Ordering::Less,
        (x, y) => x.cmp(&y),
    });
    let mut next = 30;
    for c in chans.iter_mut().filter(|c| c.number == 0) {
        c.number = next;
        next += 1;
    }
    chans
}

/// Two-letter initials for a card without a picture yet.
pub fn initials(name: &str) -> String {
    let words: Vec<&str> = name.split(|c: char| c.is_whitespace() || c == '\'' || c == '-').filter(|w| !w.is_empty()).collect();
    let mut s = String::new();
    for w in words.iter().take(2) {
        if w.chars().next().is_some_and(|c| c.is_ascii_digit()) {
            s.extend(w.chars().take(2));
        } else if let Some(c) = w.chars().next() {
            s.extend(c.to_uppercase());
        }
    }
    s.chars().take(3).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn links() {
        use LinkKind::*;
        assert_eq!(link_kind("https://example.org/list.m3u"), Some(Playlist));
        assert_eq!(link_kind("https://cdn.example.org/live/index.m3u8?token=1"), Some(Stream));
        assert_eq!(link_kind("rtsp://192.168.1.20:554/stream"), Some(Stream));
        assert_eq!(link_kind("https://www.arte.tv/fr/videos/123/"), Some(Page));
        assert_eq!(link_kind("/home/me/Videos/film.mkv"), Some(Video));
        assert_eq!(link_kind("tf1"), None);
        assert_eq!(link_kind("https://localhost/x"), None);
        assert_eq!(host_of("https://www.arte.tv/fr/videos/"), "arte.tv");
        assert_eq!(host_of("rtsp://user:pw@192.168.1.20:554/s"), "192.168.1.20");
    }

    #[test]
    fn merges_by_cleaned_name_and_follows_nothing_twice() {
        let m3u = "#EXTM3U\n#EXTINF:-1 tvg-id=\"TF1.fr\",TF1\nhttps://a/1.m3u8\n#EXTINF:-1,FR: TF1 HD\nhttps://b/2.m3u8\n#EXTINF:-1,Other\nhttps://c/3.m3u8\n";
        let ch = merge(parse_m3u(m3u, "x").0);
        assert_eq!(ch.len(), 2);
        assert_eq!(ch[0].key, "tf1.fr");
        assert_eq!(ch[0].sources.len(), 2);
        assert_eq!(ch[0].country, "FR");
        assert!(is_playlist("https://x/list.m3u?t=1"));
        assert!(!is_playlist("https://x/live.m3u8"));
        assert_eq!(spec_name("https://x/a/ma-liste.m3u?x=1"), "ma-liste.m3u");
    }

    #[test]
    fn names_and_qualities() {
        assert_eq!(split_name("TF1 (1080p)"), ("TF1".into(), Some("1080p".into())));
        assert_eq!(split_name("Arte (720p) [Geo-blocked]"), ("Arte".into(), Some("720p".into())));
        assert_eq!(split_name("13eme Rue"), ("13eme Rue".into(), None));
        assert_eq!(split_name("TV (Paris)"), ("TV (Paris)".into(), None));
    }

    #[test]
    fn parses_headers_and_merges() {
        let m3u = "#EXTM3U url-tvg=\"https://g/a.xml.gz,https://g/b.xml\"\n#EXTINF:-1 tvg-id=\"TF1.fr@SD\" tvg-logo=\"https://l/tf1.png\" group-title=\"General\",TF1 (1080p)\nhttps://a/tf1.m3u8\n\
#EXTINF:-1 tvg-id=\"TF1.fr@HD\" http-referrer=\"https://r/\" group-title=\"General\",TF1 (720p)\n#EXTVLCOPT:http-user-agent=UA\nhttps://b/tf1.m3u8\n\
#EXTINF:-1 group-title=\"Undefined\",Some, Channel\nhttps://c/x.m3u8\n";
        let (entries, guides) = parse_m3u(m3u, "test");
        assert_eq!(guides, vec!["https://g/a.xml.gz".to_string(), "https://g/b.xml".to_string()]);
        let ch = merge(entries);
        assert_eq!(ch.len(), 2);
        assert_eq!(ch[0].key, "tf1.fr");
        assert_eq!(ch[0].number, 1);
        assert_eq!(ch[0].sources.len(), 2);
        assert_eq!(ch[0].logo.as_deref(), Some("https://l/tf1.png"));
        assert_eq!(ch[1].logo, None);
        assert_eq!(ch[0].sources[1].user_agent.as_deref(), Some("UA"));
        assert_eq!(ch[0].sources[1].referrer.as_deref(), Some("https://r/"));
        assert_eq!(ch[1].name, "Some, Channel");
        assert_eq!(ch[1].category, "Other");
        assert_eq!(ch[1].number, 30);
    }
}

#[cfg(test)]
mod live {
    /// cargo test --release catalog_live -- --ignored --nocapture
    #[test]
    #[ignore]
    fn catalog_live() {
        let s = crate::store::load::<crate::store::Settings>(&crate::store::settings_path());
        let t = std::time::Instant::now();
        let cat = super::load(&s, false);
        let multi = cat.channels.iter().filter(|c| c.sources.len() > 1).count();
        let origins: std::collections::BTreeSet<String> = cat.channels.iter().flat_map(|c| c.sources.iter().map(|s| s.origin.clone())).collect();
        println!("{} channels ({} with several sources), origins {:?}, {} own lists, {:.1} s", cat.channels.len(), multi, origins, cat.lists.len(), t.elapsed().as_secs_f64());
        let t = std::time::Instant::now();
        let w = super::load_world();
        let fr = w.iter().filter(|c| c.country == "FR").count();
        println!("world: {} channels ({} FR), {:.1} s", w.len(), fr, t.elapsed().as_secs_f64());
        let nhk: Vec<&str> = w.iter().filter(|c| crate::epg::norm(&c.name).contains("nhk")).map(|c| c.name.as_str()).take(4).collect();
        println!("search 'nhk' elsewhere: {nhk:?}");
    }
}
