//! Which sources answer, and how fast.
//!
//! About one channel in four in iptv-org's French list is dead on any given
//! day (403, 404, timeouts), and the live ones answer anywhere between 0.05
//! and 3 s. So every source is asked once in a while (`check`), the answers
//! are kept in health.json, and zapping (`race`) only ever starts the
//! fastest few at once and keeps whichever answers first.

use crate::catalog::{Source, BROWSER_UA};
use crate::store;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Serialize, Deserialize, Clone, Copy, Debug)]
pub struct Probe {
    pub ok: bool,
    /// Time to the first response, in milliseconds.
    pub ms: u32,
    pub at: u64,
}

#[derive(Serialize, Deserialize, Default, Clone)]
#[serde(default)]
pub struct Health {
    pub last_check: u64,
    pub probes: HashMap<String, Probe>,
}

fn agent(timeout: Duration) -> ureq::Agent {
    ureq::AgentBuilder::new().timeout_connect(timeout).timeout_read(timeout).redirects(5).build()
}

/// One request with the source's own headers. Getting the status line back
/// is enough: a playlist that answers 200 is one mpv can open.
pub fn probe(agent: &ureq::Agent, s: &Source) -> Probe {
    let start = Instant::now();
    // a file is there or not; a camera or a multicast stream cannot be
    // asked over HTTP, so it counts as answering and mpv will tell
    if s.url.starts_with('/') {
        return Probe { ok: std::path::Path::new(&s.url).exists(), ms: 0, at: store::now() };
    }
    if !s.url.starts_with("http://") && !s.url.starts_with("https://") {
        return Probe { ok: true, ms: 999, at: store::now() };
    }
    let mut req = agent.get(&s.url).set("User-Agent", s.user_agent.as_deref().unwrap_or(BROWSER_UA));
    if let Some(r) = &s.referrer {
        req = req.set("Referer", r);
    }
    let ok = matches!(req.call(), Ok(r) if r.status() < 400);
    Probe { ok, ms: start.elapsed().as_millis().min(u32::MAX as u128) as u32, at: store::now() }
}

/// Every source, `threads` at a time.
pub fn check(sources: Vec<Source>, threads: usize) -> HashMap<String, Probe> {
    let queue = Arc::new(Mutex::new(sources));
    let (tx, rx) = mpsc::channel();
    let workers: Vec<_> = (0..threads)
        .map(|_| {
            let queue = queue.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let agent = agent(Duration::from_secs(6));
                loop {
                    let Some(s) = queue.lock().ok().and_then(|mut q| q.pop()) else { break };
                    let p = probe(&agent, &s);
                    let _ = tx.send((s.url, p));
                }
            })
        })
        .collect();
    drop(tx);
    let out = rx.into_iter().collect();
    for w in workers {
        let _ = w.join();
    }
    out
}

/// Asks the candidates all at once and returns the index (into
/// `candidates`) of the first that answers, with its time. None when none
/// does within `timeout`.
pub fn race(candidates: Vec<Source>, timeout: Duration) -> Option<(usize, Probe)> {
    let (tx, rx) = mpsc::channel();
    for (i, s) in candidates.into_iter().enumerate() {
        let tx = tx.clone();
        std::thread::spawn(move || {
            let p = probe(&agent(timeout), &s);
            let _ = tx.send((i, p));
        });
    }
    drop(tx);
    let deadline = Instant::now() + timeout;
    loop {
        let left = deadline.checked_duration_since(Instant::now())?;
        match rx.recv_timeout(left) {
            Ok((i, p)) if p.ok => return Some((i, p)),
            Ok(_) => continue,
            Err(_) => return None,
        }
    }
}

impl Health {
    pub fn load() -> Self {
        store::load(&store::health_path())
    }
    pub fn save(&self) {
        store::save(&store::health_path(), self)
    }

    /// Alive when one source answered at the last check, or when nothing is
    /// known yet (a new channel is tried before it is ever hidden).
    pub fn alive(&self, sources: &[Source]) -> bool {
        sources.iter().any(|s| self.probes.get(&s.url).map_or(true, |p| p.ok))
    }

    /// Indices of `sources`: those that answer within a second first, the
    /// best quality among them leading (1080p before 720p); then the slower
    /// ones by speed, the unknown, and the dead last.
    pub fn order(&self, sources: &[Source]) -> Vec<usize> {
        let mut idx: Vec<usize> = (0..sources.len()).collect();
        idx.sort_by_key(|&i| match self.probes.get(&sources[i].url) {
            Some(p) if p.ok && p.ms < 1000 => (0, -(sources[i].lines() as i64), p.ms as i64),
            Some(p) if p.ok => (1, 0, p.ms as i64),
            None => (2, -(sources[i].lines() as i64), 0),
            Some(_) => (3, 0, 0),
        });
        idx
    }

    pub fn due(&self, every_hours: u64) -> bool {
        store::now().saturating_sub(self.last_check) > every_hours * 3600
    }
}
