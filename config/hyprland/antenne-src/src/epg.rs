//! The programme guide (XMLTV): what is on now, next, and tonight.
//!
//! For France, xmltvfr.fr publishes a free guide every day: 782 channels,
//! ten days, 18 MB gzipped, with iptv-org's channel ids (TF1.fr...). It is
//! read as it downloads (gzip, then XML, never whole in memory), and only
//! the channels Antenne knows and the next 36 hours are kept, in guide.json.
//! Playlists that name their own guide (url-tvg="..." on their first line)
//! add theirs.

use crate::store;
use quick_xml::events::Event;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};
use std::time::Duration;

pub const XMLTVFR: &str = "https://xmltvfr.fr/xmltv/xmltv.xml.gz";

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Prog {
    pub start: i64,
    pub stop: i64,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub desc: Option<String>,
}

#[derive(Serialize, Deserialize, Default, Clone)]
#[serde(default)]
pub struct Guide {
    pub fetched: u64,
    /// Channel key (as in the catalogue) -> its programmes, by start.
    pub progs: HashMap<String, Vec<Prog>>,
}

/// Lowercase, accents folded, letters and digits only, with the usual
/// quality and country decorations dropped: "TF1 HD", "FR: TF1" -> "tf1".
pub fn norm(name: &str) -> String {
    let mut s: String = name
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'à' | 'â' | 'ä' | 'á' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' | 'í' => 'i',
            'ô' | 'ö' | 'ó' => 'o',
            'ù' | 'û' | 'ü' | 'ú' => 'u',
            'ç' => 'c',
            '&' => 'e',
            c => c,
        })
        .collect();
    for p in ["fr:", "fr |", "|fr|", "fr-"] {
        if let Some(rest) = s.strip_prefix(p) {
            s = rest.to_string();
        }
    }
    let mut s: String = s.chars().filter(|c| c.is_ascii_alphanumeric()).collect();
    for suffix in ["fhd", "uhd", "hd", "4k", "sd"] {
        if s.len() > suffix.len() + 1 && s.ends_with(suffix) {
            s.truncate(s.len() - suffix.len());
            break;
        }
    }
    s
}

/// "20261121203000 +0100" -> Unix seconds.
fn xmltv_time(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() < 14 {
        return None;
    }
    let num = |r: std::ops::Range<usize>| s.get(r)?.parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (num(0..4)?, num(4..6)?, num(6..8)?, num(8..10)?, num(10..12)?, num(12..14)?);
    // days from civil (Howard Hinnant)
    let (y2, m2) = if mo <= 2 { (y - 1, mo + 9) } else { (y, mo - 3) };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * m2 + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    let mut t = days * 86400 + h * 3600 + mi * 60 + se;
    if let Some(off) = s[14..].trim().get(0..5) {
        let sign = if off.starts_with('-') { -1 } else { 1 };
        if let (Ok(oh), Ok(om)) = (off[1..3].parse::<i64>(), off[3..5].parse::<i64>()) {
            t -= sign * (oh * 3600 + om * 60);
        }
    }
    Some(t)
}

fn attr(e: &quick_xml::events::BytesStart, name: &str) -> Option<String> {
    e.try_get_attribute(name).ok().flatten().and_then(|a| a.unescape_value().ok().map(|v| v.into_owned()))
}

/// Reads one XMLTV stream, keeping what matches `keys` (catalogue key ->
/// itself) or `names` (normalised name -> catalogue key).
fn read(
    src: impl BufRead,
    keys: &HashMap<String, String>,
    names: &HashMap<String, String>,
    from: i64,
    to: i64,
    out: &mut HashMap<String, Vec<Prog>>,
) {
    let mut r = quick_xml::Reader::from_reader(src);
    r.config_mut().trim_text(true);
    let mut buf = Vec::new();
    let mut ids: HashMap<String, String> = HashMap::new(); // guide id -> key
    let mut chan_id: Option<String> = None;
    let mut cur: Option<(String, Prog)> = None;
    let mut field: Option<&'static str> = None;
    loop {
        match r.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => match e.name().as_ref() {
                b"channel" => {
                    chan_id = attr(&e, "id");
                    if let Some(id) = &chan_id {
                        if let Some(k) = keys.get(&id.to_lowercase()) {
                            ids.insert(id.clone(), k.clone());
                        }
                    }
                }
                b"display-name" if chan_id.is_some() => field = Some("name"),
                b"programme" => {
                    let ch = attr(&e, "channel").and_then(|c| ids.get(&c).cloned());
                    let (start, stop) = (attr(&e, "start").and_then(|s| xmltv_time(&s)), attr(&e, "stop").and_then(|s| xmltv_time(&s)));
                    cur = match (ch, start, stop) {
                        (Some(k), Some(a), Some(b)) if b > from && a < to => {
                            Some((k, Prog { start: a, stop: b, title: String::new(), category: None, desc: None }))
                        }
                        _ => None,
                    };
                }
                b"title" if cur.is_some() => field = Some("title"),
                b"category" if cur.is_some() => field = Some("category"),
                b"desc" if cur.is_some() => field = Some("desc"),
                _ => field = None,
            },
            Ok(Event::Text(t)) => {
                let Some(f) = field else { continue };
                let Ok(text) = t.unescape() else { continue };
                match (f, &mut cur) {
                    ("name", _) => {
                        if let (Some(id), Some(k)) = (&chan_id, names.get(&norm(&text))) {
                            ids.entry(id.clone()).or_insert_with(|| k.clone());
                        }
                    }
                    ("title", Some((_, p))) if p.title.is_empty() => p.title = text.into_owned(),
                    ("category", Some((_, p))) if p.category.is_none() => p.category = Some(text.into_owned()),
                    ("desc", Some((_, p))) if p.desc.is_none() => {
                        let mut d = text.trim().to_string();
                        if d.chars().count() > 400 {
                            d = d.chars().take(400).collect::<String>() + "…";
                        }
                        p.desc = Some(d);
                    }
                    _ => {}
                }
            }
            Ok(Event::End(e)) => {
                field = None;
                match e.name().as_ref() {
                    b"channel" => chan_id = None,
                    b"programme" => {
                        if let Some((k, p)) = cur.take() {
                            if !p.title.is_empty() {
                                out.entry(k).or_default().push(p);
                            }
                        }
                    }
                    _ => {}
                }
            }
            Ok(Event::Eof) | Err(_) => break,
            _ => {}
        }
        buf.clear();
    }
}

impl Guide {
    pub fn load() -> Self {
        store::load(&store::cache_dir().join("guide.json"))
    }

    pub fn save(&self) {
        store::save(&store::cache_dir().join("guide.json"), self)
    }

    /// Once a day is enough: the files are rebuilt daily.
    pub fn due(&self) -> bool {
        store::now().saturating_sub(self.fetched) > 20 * 3600
    }

    /// `channels`: (key, name) of every channel in the catalogue.
    pub fn fetch(urls: &[String], channels: &[(String, String)]) -> Option<Guide> {
        let keys: HashMap<String, String> = channels.iter().map(|(k, _)| (k.to_lowercase(), k.clone())).collect();
        let names: HashMap<String, String> = channels.iter().map(|(k, n)| (norm(n), k.clone())).collect();
        let now = store::now() as i64;
        let (from, to) = (now - 3 * 3600, now + 36 * 3600);
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(8))
            .timeout_read(Duration::from_secs(60))
            .user_agent(crate::catalog::BROWSER_UA)
            .build();
        let mut progs = HashMap::new();
        let mut any = false;
        for url in urls {
            let Ok(resp) = agent.get(url).call() else { continue };
            let mut raw = BufReader::new(resp.into_reader().take(200 << 20));
            let gz = raw.fill_buf().map(|b| b.starts_with(&[0x1f, 0x8b])).unwrap_or(false);
            if gz {
                read(BufReader::new(flate2::bufread::GzDecoder::new(raw)), &keys, &names, from, to, &mut progs);
            } else {
                read(raw, &keys, &names, from, to, &mut progs);
            }
            any = true;
        }
        if !any {
            return None;
        }
        for v in progs.values_mut() {
            v.sort_by_key(|p| p.start);
            v.dedup_by_key(|p| p.start);
        }
        Some(Guide { fetched: store::now(), progs })
    }

    pub fn of(&self, key: &str) -> &[Prog] {
        self.progs.get(key).map(Vec::as_slice).unwrap_or(&[])
    }

    pub fn at(&self, key: &str, t: i64) -> Option<&Prog> {
        self.of(key).iter().find(|p| p.start <= t && t < p.stop)
    }
}

/// "21:05" in local time.
/// "today at 09:44", "yesterday at 23:35", "21 Nov at 18:02".
pub fn day_at(t: i64) -> String {
    let (Ok(d), Ok(now)) = (gtk4::glib::DateTime::from_unix_local(t), gtk4::glib::DateTime::now_local()) else { return hm(t) };
    let days = |x: &gtk4::glib::DateTime| x.year() as i64 * 400 + x.day_of_year() as i64;
    let day = match days(&now) - days(&d) {
        0 => "today".to_string(),
        1 => "yesterday".to_string(),
        _ => d.format("%-d %b").map(|s| s.to_string()).unwrap_or_default(),
    };
    format!("{day} at {}", hm(t))
}

/// The same, capitalised, to begin a line.
pub fn day_at_cap(t: i64) -> String {
    let s = day_at(t);
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        None => s,
    }
}

pub fn hm(t: i64) -> String {
    gtk4::glib::DateTime::from_unix_local(t)
        .ok()
        .and_then(|d| d.format("%H:%M").ok())
        .map(|s| s.to_string())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times() {
        // 2026-11-21 20:30 at +01:00 is 19:30 UTC
        assert_eq!(xmltv_time("20261121203000 +0100"), xmltv_time("20261121193000 +0000"));
        assert_eq!(xmltv_time("20261121193000 +0000"), Some(1795289400));
        assert_eq!(xmltv_time("19700101000000 +0000"), Some(0));
        assert_eq!(xmltv_time("19700101010000 +0100"), Some(0));
    }

    #[test]
    fn names() {
        assert_eq!(norm("TF1 HD"), "tf1");
        assert_eq!(norm("FR: TF1"), "tf1");
        assert_eq!(norm("L'Équipe"), "lequipe");
        assert_eq!(norm("13e Rue"), "13erue");
        assert_eq!(norm("HD1"), "hd1");
    }

    #[test]
    fn reads_and_matches() {
        let xml = r#"<?xml version="1.0"?><tv>
<channel id="TF1.fr"><display-name>TF1</display-name></channel>
<channel id="13eRue.fr"><display-name>13e Rue</display-name></channel>
<channel id="Other.fr"><display-name>Other</display-name></channel>
<programme start="19700101010000 +0000" stop="19700101020000 +0000" channel="TF1.fr"><title>Rugby</title><category>Sport</category><desc>France / Argentine</desc></programme>
<programme start="19700101010000 +0000" stop="19700101020000 +0000" channel="13eRue.fr"><title>Polar</title></programme>
<programme start="19700101010000 +0000" stop="19700101020000 +0000" channel="Other.fr"><title>Nope</title></programme>
</tv>"#;
        let keys: HashMap<String, String> = [("tf1.fr".into(), "tf1.fr".into())].into();
        let names: HashMap<String, String> = [(norm("13eme Rue"), "13emerue.fr".into()), (norm("13e Rue"), "13emerue.fr".into())].into();
        let mut out = HashMap::new();
        read(xml.as_bytes(), &keys, &names, 0, 100_000, &mut out);
        assert_eq!(out["tf1.fr"][0].title, "Rugby");
        assert_eq!(out["tf1.fr"][0].desc.as_deref(), Some("France / Argentine"));
        assert_eq!(out["13emerue.fr"][0].title, "Polar");
        assert_eq!(out.len(), 2);
    }
}

#[cfg(test)]
mod live {
    /// cargo test --release -- --ignored --nocapture: the real guide against
    /// the cached French list.
    #[test]
    #[ignore]
    fn real_guide() {
        let settings = crate::store::Settings::default();
        let cat = crate::catalog::load(&settings, true);
        let names: Vec<(String, String)> = cat.channels.iter().map(|c| (c.key.clone(), c.name.clone())).collect();
        let t = std::time::Instant::now();
        let g = super::Guide::fetch(&[super::XMLTVFR.to_string()], &names).expect("download");
        let n: usize = g.progs.values().map(Vec::len).sum();
        println!("{} channels of {} matched, {} programmes, {:.1} s", g.progs.len(), names.len(), n, t.elapsed().as_secs_f64());
        let now = crate::store::now() as i64;
        if let Some(p) = g.at("tf1.fr", now) {
            println!("TF1 now: {} ({} - {})", p.title, super::hm(p.start), super::hm(p.stop));
        }
        println!("cache: {} bytes", serde_json::to_vec(&g).unwrap().len());
    }
}
