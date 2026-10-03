//! One gamepad's event node: what it is, and what it says.
//!
//! The kernel already speaks one language for every pad (xpad, hid-microsoft,
//! hid-playstation, hid-nintendo, hid-steam all report BTN_SOUTH, BTN_MODE,
//! ABS_X…), so a pad is recognised by its capabilities, never by a model list.
//!
//! Idle, EVIOCSMASK leaves this client with the Guide button alone: stick and
//! trigger traffic is filtered in the kernel before it is queued, and an empty
//! SYN_REPORT never wakes a reader, so a game in progress costs the daemon
//! nothing. While the popup holds the pad, the mask widens to the buttons and
//! axes it navigates with, and EVIOCGRAB keeps them from the game behind.

use std::fs::{File, OpenOptions};
use std::io::{self, Read};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const EV_ABS: u16 = 0x03;
const SYN_REPORT: u16 = 0;
const SYN_DROPPED: u16 = 3;

const BTN_SOUTH: u16 = 0x130;
const BTN_EAST: u16 = 0x131;
const BTN_NORTH: u16 = 0x133;
const BTN_WEST: u16 = 0x134;
const BTN_TL: u16 = 0x136;
const BTN_TR: u16 = 0x137;
const BTN_TL2: u16 = 0x138;
const BTN_TR2: u16 = 0x139;
const BTN_SELECT: u16 = 0x13a;
const BTN_START: u16 = 0x13b;
const BTN_MODE: u16 = 0x13c;
const BTN_DPAD_UP: u16 = 0x220;
const BTN_DPAD_DOWN: u16 = 0x221;
const BTN_DPAD_LEFT: u16 = 0x222;
const BTN_DPAD_RIGHT: u16 = 0x223;

const ABS_X: u16 = 0x00;
const ABS_Y: u16 = 0x01;
const ABS_Z: u16 = 0x02;
const ABS_RX: u16 = 0x03;
const ABS_RZ: u16 = 0x05;
const ABS_GAS: u16 = 0x09;
const ABS_BRAKE: u16 = 0x0a;
const ABS_HAT0X: u16 = 0x10;
const ABS_HAT0Y: u16 = 0x11;

const KEY_BYTES: usize = 0x300 / 8;
const ABS_BYTES: usize = 0x40 / 8;
// EVIOCSMASK wants whole longs: 0x20 event types still take 8 bytes.
const EV_BYTES: usize = 8;

const BUS_USB: u16 = 0x03;
const BUS_BLUETOOTH: u16 = 0x05;

/// Held this long, Guide opens the popup even over a game or Steam.
const LONG_PRESS: Duration = Duration::from_millis(600);
/// A direction held in the popup repeats, so a long app grid can be crossed.
const REPEAT_DELAY: Duration = Duration::from_millis(380);
const REPEAT_EVERY: Duration = Duration::from_millis(110);
/// Stick travel (of half its range) that counts as a direction, and the
/// travel it has to fall back under before it can count again.
const STICK_ON: f32 = 0.6;
const STICK_OFF: f32 = 0.35;
/// The press that wakes a pad up is often Guide itself: for this long after
/// a pad arrives, Guide does not open the popup.
const WAKE_QUIET: Duration = Duration::from_millis(2000);

const fn ioc(dir: u64, nr: u64, size: usize) -> u64 {
    (dir << 30) | ((size as u64) << 16) | ((b'E' as u64) << 8) | nr
}
const IOC_WRITE: u64 = 1;
const IOC_READ: u64 = 2;
const EVIOCGID: u64 = ioc(IOC_READ, 0x02, 8);
const EVIOCGRAB: u64 = ioc(IOC_WRITE, 0x90, 4);
const EVIOCSMASK: u64 = ioc(IOC_WRITE, 0x93, 16);
fn eviocgname(len: usize) -> u64 { ioc(IOC_READ, 0x06, len) }
fn eviocguniq(len: usize) -> u64 { ioc(IOC_READ, 0x08, len) }
fn eviocgbit(ev: u16, len: usize) -> u64 { ioc(IOC_READ, 0x20 + ev as u64, len) }
fn eviocgabs(abs: u16) -> u64 { ioc(IOC_READ, 0x40 + abs as u64, 24) }

#[repr(C)]
struct InputMask {
    kind: u32,
    codes_size: u32,
    codes_ptr: u64,
}

#[repr(C)]
#[derive(Default)]
struct AbsInfo {
    value: i32,
    minimum: i32,
    maximum: i32,
    fuzz: i32,
    flat: i32,
    resolution: i32,
}

fn ioctl_ptr<T>(fd: RawFd, req: u64, arg: *mut T) -> io::Result<i32> {
    // SAFETY: every request above is paired with a buffer of the size it
    // encodes; the kernel writes at most that many bytes.
    let r = unsafe { libc::ioctl(fd, req as _, arg) };
    if r < 0 { Err(io::Error::last_os_error()) } else { Ok(r) }
}

fn bit(bits: &[u8], n: u16) -> bool {
    bits.get(n as usize / 8).is_some_and(|b| b & (1 << (n % 8)) != 0)
}

fn set(bits: &mut [u8], n: u16) {
    bits[n as usize / 8] |= 1 << (n % 8);
}

fn string_ioctl(fd: RawFd, req: fn(usize) -> u64) -> String {
    let mut buf = [0u8; 128];
    match ioctl_ptr(fd, req(buf.len()), buf.as_mut_ptr()) {
        Ok(_) => {
            let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
            String::from_utf8_lossy(&buf[..end]).trim().to_string()
        }
        Err(_) => String::new(),
    }
}

/// What a pad tells the daemon.
pub enum Out {
    /// Guide pressed and let go before LONG_PRESS.
    GuideShort,
    /// Guide held for LONG_PRESS (or Select + Start, on a pad without Guide).
    GuideLong,
    /// A button or direction while the popup holds the pad.
    Nav(&'static str),
}

#[derive(Clone, Copy)]
struct Axis {
    centre: f32,
    half: f32,
}

pub struct Pad {
    /// The node's name, `event10`.
    pub id: String,
    file: File,
    name: String,
    uniq: String,
    bus: u16,
    family: &'static str,
    has_guide: bool,
    has_hat: bool,
    stick: [Option<Axis>; 2],
    /// The analog triggers, LT then RT, as (code, range), when the pad has
    /// them. Which codes they are depends on the driver: xpad reports
    /// ABS_Z/ABS_RZ, the Bluetooth Xbox pad ABS_BRAKE/ABS_GAS, and uses
    /// ABS_Z/ABS_RZ for the right stick instead.
    triggers: Option<[(u16, Axis); 2]>,
    trigger_down: [bool; 2],
    quiet_until: Option<Instant>,

    grabbed: bool,
    dropped: bool,
    guide_down: Option<Instant>,
    long_sent: bool,
    select_down: bool,
    start_down: bool,

    stick_pos: [f32; 2],
    stick_dir: Option<&'static str>,
    held: Option<&'static str>,
    repeat_at: Option<Instant>,
}

impl AsRawFd for Pad {
    fn as_raw_fd(&self) -> RawFd {
        self.file.as_raw_fd()
    }
}

impl Pad {
    /// Opens `/dev/input/<id>` and keeps it if it is a physical gamepad.
    /// `Ok(None)`: readable but not a pad. `Err`: not readable (yet).
    pub fn open(id: &str) -> io::Result<Option<Pad>> {
        // A pad Steam Input or another remapper re-exposes through uinput is
        // the same pad twice: only the physical one counts. uinput devices
        // live under /devices/virtual/input; a Bluetooth LE pad comes in
        // through uhid (/devices/virtual/misc/uhid) and is a real one.
        let sys = std::fs::canonicalize(Path::new("/sys/class/input").join(id))?;
        if sys.to_string_lossy().contains("/devices/virtual/input/") {
            return Ok(None);
        }

        let file = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
            .open(Path::new("/dev/input").join(id))?;
        let fd = file.as_raw_fd();

        let mut types = [0u8; EV_BYTES];
        let mut keys = [0u8; KEY_BYTES];
        let mut abs = [0u8; ABS_BYTES];
        ioctl_ptr(fd, eviocgbit(0, types.len()), types.as_mut_ptr())?;
        if !bit(&types, EV_KEY) || !bit(&types, EV_ABS) {
            return Ok(None);
        }
        ioctl_ptr(fd, eviocgbit(EV_KEY, keys.len()), keys.as_mut_ptr())?;
        ioctl_ptr(fd, eviocgbit(EV_ABS, abs.len()), abs.as_mut_ptr())?;
        if !bit(&keys, BTN_SOUTH) {
            return Ok(None);
        }

        let mut ids = [0u16; 4];
        ioctl_ptr(fd, EVIOCGID, ids.as_mut_ptr())?;
        let (bus, vendor) = (ids[0], ids[1]);

        let axis = |code: u16| -> Option<Axis> {
            if !bit(&abs, code) {
                return None;
            }
            let mut info = AbsInfo::default();
            ioctl_ptr(fd, eviocgabs(code), &mut info).ok()?;
            let half = (info.maximum as f32 - info.minimum as f32) / 2.0;
            (half > 0.0).then(|| Axis { centre: info.minimum as f32 + half, half })
        };

        let triggers = if bit(&abs, ABS_BRAKE) && bit(&abs, ABS_GAS) {
            axis(ABS_BRAKE).zip(axis(ABS_GAS)).map(|(l, r)| [(ABS_BRAKE, l), (ABS_GAS, r)])
        } else if bit(&abs, ABS_RX) && bit(&abs, ABS_Z) && bit(&abs, ABS_RZ) {
            axis(ABS_Z).zip(axis(ABS_RZ)).map(|(l, r)| [(ABS_Z, l), (ABS_RZ, r)])
        } else {
            None
        };

        let mut pad = Pad {
            id: id.to_string(),
            name: string_ioctl(fd, eviocgname),
            uniq: string_ioctl(fd, eviocguniq).to_lowercase(),
            bus,
            family: match vendor {
                0x045e => "xbox",
                0x054c => "playstation",
                0x057e => "nintendo",
                0x28de => "steam",
                _ => "generic",
            },
            has_guide: bit(&keys, BTN_MODE),
            has_hat: bit(&abs, ABS_HAT0X),
            stick: [axis(ABS_X), axis(ABS_Y)],
            triggers,
            trigger_down: [false; 2],
            quiet_until: None,
            file,
            grabbed: false,
            dropped: false,
            guide_down: None,
            long_sent: false,
            select_down: false,
            start_down: false,
            stick_pos: [0.0; 2],
            stick_dir: None,
            held: None,
            repeat_at: None,
        };
        pad.apply_mask()?;
        Ok(Some(pad))
    }

    /// Called for a pad that just arrived, as opposed to one already there
    /// when the daemon started.
    pub fn arrived(&mut self, now: Instant) {
        self.quiet_until = Some(now + WAKE_QUIET);
    }

    pub fn describe(&self) -> Value {
        let (battery, charging) = self.battery();
        json!({
            "id": self.id,
            "name": self.name,
            "family": self.family,
            "bus": match self.bus {
                BUS_USB => "usb",
                BUS_BLUETOOTH => "bluetooth",
                _ => "other",
            },
            "address": self.uniq,
            // Without one, Select + Start opens the popup.
            "guide": self.has_guide,
            "battery": battery,
            "charging": charging,
        })
    }

    /// The driver's own battery, when it has one (hid-playstation,
    /// hid-nintendo…). Xbox pads over Bluetooth report theirs to BlueZ
    /// instead, which the bar reads through Balise.
    fn battery(&self) -> (Option<u8>, bool) {
        let dir = Path::new("/sys/class/input").join(&self.id).join("device/device/power_supply");
        let Some(supply) = std::fs::read_dir(dir).ok().and_then(|mut d| d.next()).and_then(Result::ok) else {
            return (None, false);
        };
        let read = |f: &str| std::fs::read_to_string(supply.path().join(f)).unwrap_or_default();
        (read("capacity").trim().parse().ok(), read("status").trim() == "Charging")
    }

    /// Takes the pad for the popup, or gives it back.
    pub fn set_grab(&mut self, on: bool) -> io::Result<()> {
        if self.grabbed == on {
            return Ok(());
        }
        // EVIOCGRAB takes its argument by value, not through a pointer.
        // SAFETY: no memory is passed.
        let r = unsafe { libc::ioctl(self.file.as_raw_fd(), EVIOCGRAB as _, on as libc::c_long) };
        if r < 0 && on {
            return Err(io::Error::last_os_error());
        }
        self.grabbed = on;
        self.guide_down = None;
        self.long_sent = false;
        self.stick_pos = [0.0; 2];
        self.stick_dir = None;
        self.held = None;
        self.repeat_at = None;
        self.trigger_down = [false; 2];
        self.apply_mask()
    }

    fn apply_mask(&mut self) -> io::Result<()> {
        let fd = self.file.as_raw_fd();
        let mut types = [0u8; EV_BYTES];
        let mut keys = [0u8; KEY_BYTES];
        let mut abs = [0u8; ABS_BYTES];
        set(&mut types, EV_KEY);
        set(&mut keys, BTN_MODE);
        if !self.has_guide || self.grabbed {
            set(&mut keys, BTN_SELECT);
            set(&mut keys, BTN_START);
        }
        if self.grabbed {
            set(&mut types, EV_ABS);
            for k in [BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST, BTN_TL, BTN_TR, BTN_TL2, BTN_TR2,
                      BTN_DPAD_UP, BTN_DPAD_DOWN, BTN_DPAD_LEFT, BTN_DPAD_RIGHT] {
                set(&mut keys, k);
            }
            for a in [ABS_X, ABS_Y, ABS_HAT0X, ABS_HAT0Y] {
                set(&mut abs, a);
            }
            if let Some(t) = self.triggers {
                set(&mut abs, t[0].0);
                set(&mut abs, t[1].0);
            }
        }
        for (kind, bits) in [(0u32, &mut types[..]), (EV_KEY as u32, &mut keys[..]), (EV_ABS as u32, &mut abs[..])] {
            let mut mask = InputMask { kind, codes_size: bits.len() as u32, codes_ptr: bits.as_mut_ptr() as u64 };
            ioctl_ptr(fd, EVIOCSMASK, &mut mask)?;
        }
        Ok(())
    }

    /// Drains the node. `Err` means the pad is gone.
    pub fn read(&mut self, now: Instant, out: &mut Vec<Out>) -> io::Result<()> {
        let mut buf = [0u8; 24 * 64];
        loop {
            let n = match self.file.read(&mut buf) {
                Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
                Ok(n) => n,
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(()),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e),
            };
            for ev in buf[..n].chunks_exact(24) {
                let kind = u16::from_ne_bytes([ev[16], ev[17]]);
                let code = u16::from_ne_bytes([ev[18], ev[19]]);
                let value = i32::from_ne_bytes([ev[20], ev[21], ev[22], ev[23]]);
                self.event(kind, code, value, now, out);
            }
        }
    }

    fn event(&mut self, kind: u16, code: u16, value: i32, now: Instant, out: &mut Vec<Out>) {
        if kind == EV_SYN {
            match code {
                SYN_DROPPED => self.dropped = true,
                SYN_REPORT => self.dropped = false,
                _ => {}
            }
            return;
        }
        if self.dropped {
            return;
        }
        match (kind, self.grabbed) {
            (EV_KEY, false) => self.idle_key(code, value, now, out),
            (EV_KEY, true) => self.nav_key(code, value, now, out),
            (EV_ABS, true) => self.nav_abs(code, value, now, out),
            _ => {}
        }
    }

    fn idle_key(&mut self, code: u16, value: i32, now: Instant, out: &mut Vec<Out>) {
        match (code, value) {
            (BTN_MODE, 1) => {
                if self.quiet_until.is_some_and(|t| now < t) {
                    return;
                }
                self.guide_down = Some(now);
                self.long_sent = false;
            }
            (BTN_MODE, 0) => {
                if self.guide_down.take().is_some() && !self.long_sent {
                    out.push(Out::GuideShort);
                }
            }
            (BTN_SELECT, v) => self.select_down = v != 0,
            (BTN_START, v) => self.start_down = v != 0,
            _ => {}
        }
        if matches!(code, BTN_SELECT | BTN_START) {
            if self.select_down && self.start_down && !self.long_sent {
                self.long_sent = true;
                out.push(Out::GuideLong);
            } else if !self.select_down && !self.start_down && self.guide_down.is_none() {
                self.long_sent = false;
            }
        }
    }

    fn nav_key(&mut self, code: u16, value: i32, now: Instant, out: &mut Vec<Out>) {
        let dir = match code {
            BTN_DPAD_UP => Some("up"),
            BTN_DPAD_DOWN => Some("down"),
            BTN_DPAD_LEFT => Some("left"),
            BTN_DPAD_RIGHT => Some("right"),
            _ => None,
        };
        if let Some(d) = dir {
            if value == 1 { self.press(d, now, out) } else if value == 0 { self.release(d) }
            return;
        }
        if value != 1 {
            return;
        }
        out.push(Out::Nav(match code {
            BTN_SOUTH => "a",
            BTN_EAST => "b",
            BTN_NORTH => "y",
            BTN_WEST => "x",
            BTN_TL => "lb",
            BTN_TR => "rb",
            BTN_TL2 => "lt",
            BTN_TR2 => "rt",
            BTN_SELECT => "select",
            BTN_START => "start",
            BTN_MODE => "guide",
            _ => return,
        }));
    }

    fn nav_abs(&mut self, code: u16, value: i32, now: Instant, out: &mut Vec<Out>) {
        if let Some(t) = self.triggers {
            if let Some(i) = t.iter().position(|(c, _)| *c == code) {
                let a = t[i].1;
                let level = (value as f32 - (a.centre - a.half)) / (2.0 * a.half);
                if !self.trigger_down[i] && level > 0.6 {
                    self.trigger_down[i] = true;
                    out.push(Out::Nav(if i == 0 { "lt" } else { "rt" }));
                } else if self.trigger_down[i] && level < 0.3 {
                    self.trigger_down[i] = false;
                }
                return;
            }
        }
        match code {
            ABS_HAT0X | ABS_HAT0Y if self.has_hat => {
                let (neg, pos) = if code == ABS_HAT0X { ("left", "right") } else { ("up", "down") };
                self.release(neg);
                self.release(pos);
                match value.signum() {
                    -1 => self.press(neg, now, out),
                    1 => self.press(pos, now, out),
                    _ => {}
                }
            }
            ABS_X | ABS_Y => {
                let i = (code - ABS_X) as usize;
                let Some(a) = self.stick[i] else { return };
                self.stick_pos[i] = ((value as f32 - a.centre) / a.half).clamp(-1.0, 1.0);
                let [x, y] = self.stick_pos;
                let (mag, dir) = if x.abs() >= y.abs() {
                    (x.abs(), if x < 0.0 { "left" } else { "right" })
                } else {
                    (y.abs(), if y < 0.0 { "up" } else { "down" })
                };
                match self.stick_dir {
                    Some(d) if mag < STICK_OFF => {
                        self.stick_dir = None;
                        self.release(d);
                    }
                    None if mag > STICK_ON => {
                        self.stick_dir = Some(dir);
                        self.press(dir, now, out);
                    }
                    _ => {}
                }
            }
            _ => {}
        }
    }

    fn press(&mut self, dir: &'static str, now: Instant, out: &mut Vec<Out>) {
        out.push(Out::Nav(dir));
        self.held = Some(dir);
        self.repeat_at = Some(now + REPEAT_DELAY);
    }

    fn release(&mut self, dir: &'static str) {
        if self.held == Some(dir) {
            self.held = None;
            self.repeat_at = None;
        }
    }

    /// When `tick` next has something to say, if ever.
    pub fn deadline(&self) -> Option<Instant> {
        if self.grabbed {
            self.repeat_at
        } else if self.long_sent {
            None
        } else {
            self.guide_down.map(|t| t + LONG_PRESS)
        }
    }

    pub fn tick(&mut self, now: Instant, out: &mut Vec<Out>) {
        if self.grabbed {
            if let (Some(dir), Some(at)) = (self.held, self.repeat_at) {
                if now >= at {
                    out.push(Out::Nav(dir));
                    self.repeat_at = Some(now + REPEAT_EVERY);
                }
            }
        } else if let Some(t) = self.guide_down {
            if !self.long_sent && now >= t + LONG_PRESS {
                self.long_sent = true;
                out.push(Out::GuideLong);
            }
        }
    }
}
