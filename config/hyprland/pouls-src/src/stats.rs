//! The figures with no kernel event behind them: CPU load and frequency,
//! memory, the package temperature, the fan and the download rate. Load and
//! rate are deltas between two reads, so something has to sample; this is
//! that something, and it only runs while the bar is looking (main.rs).

use std::time::Instant;

use serde_json::{json, Value};

use crate::attr::{read_trimmed, sorted_dir, Attr};

pub struct Sampler {
    stat: Option<Attr>,
    meminfo: Option<Attr>,
    /// scaling_cur_freq of every CPU. /proc/cpuinfo said the same thing for
    /// 312 µs a read on this 18-thread machine; these take a few µs together.
    freqs: Vec<Attr>,
    /// Only when cpufreq is missing (some VMs).
    cpuinfo: Option<Attr>,
    temp: Option<Attr>,
    fan: Option<Attr>,
    rx: Option<(String, Attr)>,
    prev_cpu: Option<(u64, u64)>,
    prev_rx: Option<(u64, Instant)>,
    buf: Vec<u8>,
    pub now: Figures,
}

#[derive(Default, Clone)]
pub struct Figures {
    cpu: u32,
    ghz: f64,
    mem_gb: f64,
    mem_pct: u32,
    temp: Option<i64>,
    fan: Option<i64>,
    net: f64,
}

impl Figures {
    pub fn to_json(&self, has_temp: bool, has_fan: bool) -> Value {
        json!({
            "event": "stats",
            "cpu": self.cpu,
            "ghz": self.ghz,
            "memGB": self.mem_gb,
            "memPct": self.mem_pct,
            "hasTemp": has_temp,
            "temp": self.temp,
            "hasFan": has_fan,
            "fan": self.fan,
            "net": self.net,
        })
    }

    /// What the bar would draw, rounded the way its modules round. Two
    /// samples with the same key look the same on screen, so the second is
    /// not sent and the bar is not woken for it.
    pub fn shown(&self) -> String {
        format!(
            "{} {:.1} {:.1} {} {:?} {:?} {}",
            self.cpu,
            self.ghz,
            self.mem_gb,
            self.mem_pct,
            self.temp,
            self.fan,
            rate_shown(self.net)
        )
    }
}

/// Traffic.qml's rateValue and rateUnit, as one string.
fn rate_shown(bps: f64) -> String {
    if bps < 1024.0 {
        format!("{bps:.0}B")
    } else if bps < 1024.0 * 1024.0 {
        format!("{:.1}K", bps / 1024.0)
    } else {
        format!("{:.1}M", bps / 1024.0 / 1024.0)
    }
}

impl Sampler {
    pub fn open() -> Sampler {
        let freqs: Vec<Attr> = sorted_dir("/sys/devices/system/cpu")
            .iter()
            .filter(|p| p.rsplit('/').next().is_some_and(|n| n.len() > 3 && n.starts_with("cpu") && n[3..].bytes().all(|b| b.is_ascii_digit())))
            .filter_map(|p| Attr::open(format!("{p}/cpufreq/scaling_cur_freq")))
            .collect();
        let cpuinfo = if freqs.is_empty() { Attr::open("/proc/cpuinfo") } else { None };
        Sampler {
            stat: Attr::open("/proc/stat"),
            meminfo: Attr::open("/proc/meminfo"),
            freqs,
            cpuinfo,
            temp: temp_path().and_then(Attr::open),
            fan: sorted_dir("/sys/class/hwmon").iter().find_map(|h| Attr::open(format!("{h}/fan1_input"))),
            rx: None,
            prev_cpu: None,
            prev_rx: None,
            buf: Vec::with_capacity(8192),
            now: Figures::default(),
        }
    }

    pub fn has_temp(&self) -> bool {
        self.temp.is_some()
    }

    pub fn has_fan(&self) -> bool {
        self.fan.is_some()
    }

    /// The interface whose download rate is shown, picked by the bar from
    /// NetworkManager (Ethernet over Wi-Fi). Empty when offline.
    pub fn set_iface(&mut self, name: &str) {
        if self.rx.as_ref().is_some_and(|(n, _)| n == name) {
            return;
        }
        self.prev_rx = None;
        self.now.net = 0.0;
        self.rx = if name.is_empty() || name.contains('/') || name.starts_with('.') {
            None
        } else {
            Attr::open(format!("/sys/class/net/{name}/statistics/rx_bytes")).map(|a| (name.to_string(), a))
        };
    }

    /// Drop the baselines, so the first sample after a pause does not report
    /// the average of the whole time the screen was off.
    pub fn forget(&mut self) {
        self.prev_cpu = None;
        self.prev_rx = None;
    }

    pub fn sample(&mut self, now: Instant) {
        self.sample_cpu();
        self.sample_freq();
        self.sample_mem();
        if let Some(t) = &self.temp {
            self.now.temp = t.read_int(&mut self.buf).map(|m| (m as f64 / 1000.0).round() as i64);
        }
        if let Some(f) = &self.fan {
            self.now.fan = f.read_int(&mut self.buf);
        }
        self.sample_rx(now);
    }

    fn sample_cpu(&mut self) {
        let Some(stat) = &self.stat else { return };
        let Some(text) = stat.read(&mut self.buf) else { return };
        let Some(line) = text.lines().next() else { return };
        let parts: Vec<u64> = line.split_ascii_whitespace().skip(1).filter_map(|v| v.parse().ok()).collect();
        if parts.len() < 5 {
            return;
        }
        let idle = parts[3] + parts[4];
        let total: u64 = parts.iter().sum();
        if let Some((pt, pi)) = self.prev_cpu {
            let dt = total.saturating_sub(pt);
            let di = idle.saturating_sub(pi);
            self.now.cpu = if dt > 0 { (100.0 * (1.0 - di as f64 / dt as f64)).round() as u32 } else { 0 };
        }
        self.prev_cpu = Some((total, idle));
    }

    fn sample_freq(&mut self) {
        let mut max_khz = 0i64;
        for f in &self.freqs {
            if let Some(v) = f.read_int(&mut self.buf) {
                max_khz = max_khz.max(v);
            }
        }
        if let Some(info) = &self.cpuinfo {
            if let Some(text) = info.read(&mut self.buf) {
                let mhz = text
                    .lines()
                    .filter(|l| l.starts_with("cpu MHz"))
                    .filter_map(|l| l.split(':').nth(1)?.trim().parse::<f64>().ok())
                    .fold(0.0, f64::max);
                max_khz = (mhz * 1000.0) as i64;
            }
        }
        self.now.ghz = max_khz as f64 / 1e6;
    }

    fn sample_mem(&mut self) {
        let Some(mem) = &self.meminfo else { return };
        let Some(text) = mem.read(&mut self.buf) else { return };
        let field = |name: &str| -> u64 {
            text.lines()
                .find(|l| l.starts_with(name))
                .and_then(|l| l.split_ascii_whitespace().nth(1)?.parse().ok())
                .unwrap_or(0)
        };
        let total = field("MemTotal:");
        let used = total.saturating_sub(field("MemAvailable:"));
        self.now.mem_gb = used as f64 / 1024.0 / 1024.0;
        self.now.mem_pct = if total > 0 { (100.0 * used as f64 / total as f64).round() as u32 } else { 0 };
    }

    fn sample_rx(&mut self, now: Instant) {
        let Some((_, rx)) = &self.rx else {
            self.now.net = 0.0;
            return;
        };
        let Some(v) = rx.read_int(&mut self.buf).map(|v| v as u64) else { return };
        if let Some((pv, pt)) = self.prev_rx {
            // Over the time that really passed: timer slack lets a tick land
            // a little late, and a nominal 3 s would overstate the rate.
            let secs = now.duration_since(pt).as_secs_f64();
            if secs > 0.0 {
                self.now.net = v.saturating_sub(pv) as f64 / secs;
            }
        }
        self.prev_rx = Some((v, now));
    }
}

/// The CPU package sensor, by preference rather than by glob order:
/// thermal_zone0 is `acpitz` on most Intel laptops, a board sensor that lags
/// the die. x86_pkg_temp first, then the coretemp or k10temp hwmon, and only
/// then whatever thermal zone exists.
fn temp_path() -> Option<String> {
    let zones = sorted_dir("/sys/class/thermal");
    let zones: Vec<&String> = zones.iter().filter(|z| z.contains("thermal_zone")).collect();
    if let Some(z) = zones.iter().find(|z| read_trimmed(format!("{z}/type")).as_deref() == Some("x86_pkg_temp")) {
        return Some(format!("{z}/temp"));
    }
    let hwmons = sorted_dir("/sys/class/hwmon");
    for chip in ["coretemp", "k10temp"] {
        if let Some(h) = hwmons.iter().find(|h| read_trimmed(format!("{h}/name")).as_deref() == Some(chip)) {
            return Some(format!("{h}/temp1_input"));
        }
    }
    zones.first().map(|z| format!("{z}/temp"))
}
