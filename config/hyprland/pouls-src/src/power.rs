//! The charger and the battery's charge policy. Unlike the figures in
//! stats.rs these have a kernel event: power_supply emits a uevent when the
//! adapter comes or goes and when the battery changes, so main.rs re-reads
//! them on that, after its own writes and when the screen comes back on.

use std::path::Path;

use serde_json::{json, Value};

use crate::attr::{read_trimmed, sorted_dir, Attr};

pub struct Power {
    mains: Option<Attr>,
    conservation: Option<(String, Attr)>,
    charge_types: Option<(String, Attr)>,
    buf: Vec<u8>,
}

#[derive(Default, Clone, PartialEq)]
pub struct PowerState {
    pub mains: Option<bool>,
    conservation: Option<bool>,
    fast: bool,
    fast_available: bool,
}

impl PowerState {
    pub fn to_json(&self) -> Value {
        json!({
            "event": "power",
            "hasMains": self.mains.is_some(),
            "mains": self.mains.unwrap_or(false),
            "hasConservation": self.conservation.is_some(),
            "conservation": self.conservation.unwrap_or(false),
            "fastCharge": self.fast,
            "fastChargeAvailable": self.fast_available,
        })
    }
}

impl Power {
    pub fn open() -> Power {
        let supplies = sorted_dir("/sys/class/power_supply");
        let typed: Vec<(String, String)> =
            supplies.iter().filter_map(|d| Some((read_trimmed(format!("{d}/type"))?, d.clone()))).collect();
        let of_type = |t: &'static str| typed.iter().filter(move |(ty, _)| ty == t).map(|(_, d)| d);

        // Matched on type, not on a name: ADP1, AC and ACAD are all ACPI
        // artefacts. Stays empty on a desktop.
        let mains = of_type("Mains").find_map(|d| Attr::open(format!("{d}/online")));

        // Lenovo IdeaPad's ~60 % cap. ideapad-laptop binds an ACPI node, so
        // the device is not under /sys/devices/platform; the bus-wide view
        // lists it by name wherever it is parented.
        let conservation = sorted_dir("/sys/bus/platform/devices")
            .iter()
            .map(|d| format!("{d}/conservation_mode"))
            .find(|p| Path::new(p).exists())
            .and_then(|p| Attr::open(&p).map(|a| (p, a)));

        // On the battery, not on the platform device: a separate attribute
        // the EC is free to change by itself, on unplug, resume or heat.
        let charge_types = of_type("Battery")
            .map(|d| format!("{d}/charge_types"))
            .find(|p| Path::new(p).exists())
            .and_then(|p| Attr::open(&p).map(|a| (p, a)));

        Power { mains, conservation, charge_types, buf: Vec::with_capacity(256) }
    }

    pub fn read(&mut self) -> PowerState {
        let mut s = PowerState::default();
        if let Some(m) = &self.mains {
            s.mains = m.read_int(&mut self.buf).map(|v| v == 1);
        }
        if let Some((_, c)) = &self.conservation {
            s.conservation = c.read_int(&mut self.buf).map(|v| v == 1);
        }
        if let Some((_, t)) = &self.charge_types {
            if let Some(text) = t.read(&mut self.buf) {
                // `Fast [Standard] Long_Life`: only the bracketed word is the
                // active mode, Fast is listed whether or not it is selected.
                let active = text.split('[').nth(1).and_then(|r| r.split(']').next());
                s.fast = active == Some("Fast");
                s.fast_available = text.contains("Fast");
            }
        }
        s
    }

    /// Writable by the session thanks to the udev rules that hand these
    /// attributes to group wheel. A refusal is not an error here: the caller
    /// reads the state back and the bar shows what the kernel kept.
    pub fn set_conservation(&self, on: bool) {
        if let Some((p, _)) = &self.conservation {
            let _ = std::fs::write(p, if on { "1" } else { "0" });
        }
    }

    pub fn set_fast_charge(&self, on: bool) {
        if let Some((p, _)) = &self.charge_types {
            let _ = std::fs::write(p, if on { "Fast" } else { "Standard" });
        }
    }
}

/// A 45 W brick on this machine latches off in overcurrent protection while
/// staying negotiated: mains reads 0 but a USB-PD partner is still attached.
/// An ordinary unplug tears the partner down, which takes the typec layer a
/// moment, hence the caller's two seconds of settle before asking.
/// `power_role` cannot tell: it was found stuck at [sink] with nothing on it.
pub fn adapter_dropped() -> bool {
    sorted_dir("/sys/class/typec").iter().any(|p| {
        Path::new(&format!("{p}-partner")).exists()
            && read_trimmed(format!("{p}/power_operation_mode")).as_deref() == Some("usb_power_delivery")
    })
}
