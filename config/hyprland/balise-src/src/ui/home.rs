//! Control Center home page -- the Stack's root page (see window.rs),
//! replacing the old WiFi/Bluetooth/Ethernet tab bar entirely. Six
//! tiles, macOS/iOS Control-Center-flavored: a 2x2 grid of square tiles
//! (big icon + title + one line of live status) for WiFi/Bluetooth/
//! Ethernet/Airplane Mode, then two wide action rows (icon + label, no
//! status line) for Night Mode and Screenshot -- neither has a page of
//! its own to drill into.
//!
//! Airplane Mode has no OS-level single toggle to call (there's no
//! unified "airplane mode" D-Bus API on Linux the way there is on a
//! phone -- `rfkill block all` is the underlying primitive both GNOME
//! and KDE's own airplane-mode switches ultimately drive). Balise
//! already has both radios' own on/off calls, so its tile just flips
//! WiFi and Bluetooth together via the exact same `toggle_radio()`
//! app/mod.rs uses everywhere else -- no new backend call, no shelling
//! out to `rfkill`.
//!
//! WiFi/Bluetooth/Ethernet are dual-purpose, macOS-style:
//!   - left click (GtkButton's own `clicked`, also keyboard activation)
//!     toggles the radio in place -- WiFi/Bluetooth only, Ethernet has no
//!     radio-enable concept and just navigates either way.
//!   - right click (a secondary-button GestureClick, added in app/mod.rs
//!     since window.rs only builds widgets) opens the section page.
//! A gear button was considered for the second action and dropped --
//! asked for "pour que ça soit propre, pas de bouton d'engrenage mais
//! clic droit" -- so there's nothing on the tile's face beyond the
//! icon/title/status that a plain click-toggle already needs.

use gtk4::prelude::*;
use gtk4::{self as gtk, Orientation};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

/// One tile's three live-updating parts. Built by `build_tile` below,
/// kept together so callers (`set_wifi_state` etc.) update all three
/// consistently rather than reaching into the widget tree by hand.
struct TileParts {
    button: gtk::Button,
    icon: gtk::Label,
    status: gtk::Label,
}

fn build_tile(glyph: &str, title: &str) -> TileParts {
    let icon = super::icon::icon_label(glyph);
    icon.add_css_class("balise-tile-icon");

    let title_label = gtk::Label::builder().label(title).css_classes(["balise-tile-title"]).halign(gtk::Align::Start).build();
    let status = gtk::Label::builder().label("").css_classes(["balise-tile-status"]).halign(gtk::Align::Start).build();
    status.set_ellipsize(gtk::pango::EllipsizeMode::End);

    let text_col = gtk::Box::builder().orientation(Orientation::Vertical).spacing(1).build();
    text_col.append(&title_label);
    text_col.append(&status);

    let content = gtk::Box::builder().orientation(Orientation::Vertical).spacing(10).css_classes(["balise-tile-content"]).build();
    content.append(&icon);
    content.append(&text_col);

    let button = gtk::Button::builder().child(&content).css_classes(["balise-tile", "flat"]).hexpand(true).build();

    TileParts { button, icon, status }
}

#[derive(Clone)]
pub struct HomeView {
    container: gtk::Box,

    wifi: Rc<TileParts>,
    bluetooth: Rc<TileParts>,
    ethernet: Rc<TileParts>,
    airplane: Rc<TileParts>,
    night_tile: gtk::Button,
    screenshot_tile: gtk::Button,

    // Each tile's status text needs to combine two independently-arriving
    // signals ("is the radio on" and "what's it connected to"), which
    // land as separate AppEvents (WifiPowerState/ScanResult,
    // BtPowerState/BtScanResult) at unpredictable relative times --
    // cached here so whichever one fires can recompute the combined
    // label without stomping on the other's last known value. Also
    // doubles as the read side for the left-click toggle (app/mod.rs
    // reads `wifi_enabled()`/`bluetooth_enabled()` to know which way to
    // flip before the backend call confirms anything).
    wifi_enabled: Rc<Cell<bool>>,
    wifi_ssid: Rc<RefCell<Option<String>>>,
    bt_enabled: Rc<Cell<bool>>,
    bt_connected_names: Rc<RefCell<Vec<String>>>,
}

impl HomeView {
    pub fn new() -> Self {
        let container = gtk::Box::builder().orientation(Orientation::Vertical).css_classes(["balise-home"]).spacing(10).build();

        let wifi = build_tile(super::icon::WIFI, "WiFi");
        let bluetooth = build_tile(super::icon::BLUETOOTH, "Bluetooth");
        let ethernet = build_tile(super::icon::PLUGS, "Ethernet");
        let airplane = build_tile(super::icon::AIRPLANE, "Airplane Mode");

        // 2x2 grid via two Rows -- Grid would work too, but these tiles
        // are all the same size and don't need Grid's column-alignment
        // machinery, and a Row already gets equal-width children for
        // free from `hexpand` on each tile.
        let row1 = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(10).homogeneous(true).build();
        row1.append(&wifi.button);
        row1.append(&bluetooth.button);

        let row2 = gtk::Box::builder().orientation(Orientation::Horizontal).spacing(10).homogeneous(true).build();
        row2.append(&ethernet.button);
        row2.append(&airplane.button);

        // Night Mode + Screenshot: wide action rows, icon+label side by
        // side instead of the square tiles' stacked icon-over-text shape
        // -- same treatment icon_text_button already gives the network
        // list's own footer buttons. Night Mode moved here from the 2x2
        // grid (Airplane Mode took its old slot, asked for together --
        // "descendre le bouton nightmode au même style que screenshot").
        // No status label on either (unlike the square tiles): a wide
        // action row's own fill (see set_night_mode's tile_classes call)
        // is the only state either needs to carry.
        let night_tile = super::icon::icon_text_button(super::icon::MOON, "Night Mode", &["balise-tile", "balise-tile-wide", "flat"]);
        night_tile.set_hexpand(true);

        let screenshot_tile = super::icon::icon_text_button(super::icon::CAMERA, "Screenshot", &["balise-tile", "balise-tile-wide", "flat"]);
        screenshot_tile.set_hexpand(true);

        container.append(&row1);
        container.append(&row2);
        container.append(&night_tile);
        container.append(&screenshot_tile);

        Self {
            container,
            wifi: Rc::new(wifi),
            bluetooth: Rc::new(bluetooth),
            ethernet: Rc::new(ethernet),
            airplane: Rc::new(airplane),
            night_tile,
            screenshot_tile,
            wifi_enabled: Rc::new(Cell::new(false)),
            wifi_ssid: Rc::new(RefCell::new(None)),
            bt_enabled: Rc::new(Cell::new(false)),
            bt_connected_names: Rc::new(RefCell::new(Vec::new())),
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn wifi_tile(&self) -> &gtk::Button {
        &self.wifi.button
    }

    pub fn bluetooth_tile(&self) -> &gtk::Button {
        &self.bluetooth.button
    }

    pub fn ethernet_tile(&self) -> &gtk::Button {
        &self.ethernet.button
    }

    pub fn airplane_mode_tile(&self) -> &gtk::Button {
        &self.airplane.button
    }

    pub fn night_tile(&self) -> &gtk::Button {
        &self.night_tile
    }

    pub fn screenshot_tile(&self) -> &gtk::Button {
        &self.screenshot_tile
    }

    /// Read by the left-click handler (app/mod.rs) to know which way to
    /// flip -- the click toggles, it doesn't carry its own target state.
    pub fn wifi_enabled(&self) -> bool {
        self.wifi_enabled.get()
    }

    pub fn bluetooth_enabled(&self) -> bool {
        self.bt_enabled.get()
    }

    pub fn set_wifi_enabled(&self, enabled: bool) {
        self.wifi_enabled.set(enabled);
        self.refresh_wifi();
    }

    /// `ssid` is `None` when nothing is connected (still meaningful while
    /// `enabled` is true -- radio on, no association yet).
    pub fn set_wifi_ssid(&self, ssid: Option<String>) {
        *self.wifi_ssid.borrow_mut() = ssid;
        self.refresh_wifi();
    }

    fn refresh_wifi(&self) {
        let enabled = self.wifi_enabled.get();
        self.wifi.icon.set_label(if enabled { super::icon::WIFI } else { super::icon::WIFI_SLASH });
        self.wifi.button.set_css_classes(&tile_classes(enabled));
        self.wifi.status.set_label(&if !enabled {
            "Off".to_string()
        } else {
            self.wifi_ssid.borrow().clone().unwrap_or_else(|| "On".to_string())
        });
        self.refresh_airplane();
    }

    pub fn set_bluetooth_enabled(&self, enabled: bool) {
        self.bt_enabled.set(enabled);
        self.refresh_bluetooth();
    }

    /// Names of every currently-connected device (a phone might have
    /// earbuds AND a keyboard connected at once, unlike WiFi's single
    /// association) -- shows the first, "+N" for the rest.
    pub fn set_bluetooth_connected(&self, names: Vec<String>) {
        *self.bt_connected_names.borrow_mut() = names;
        self.refresh_bluetooth();
    }

    fn refresh_bluetooth(&self) {
        let enabled = self.bt_enabled.get();
        let names = self.bt_connected_names.borrow();
        self.bluetooth.icon.set_label(if enabled && !names.is_empty() { super::icon::BLUETOOTH_CONNECTED } else { super::icon::BLUETOOTH });
        self.bluetooth.button.set_css_classes(&tile_classes(enabled));
        self.bluetooth.status.set_label(&if !enabled {
            "Off".to_string()
        } else {
            match names.len() {
                0 => "On".to_string(),
                1 => names[0].clone(),
                n => format!("{} +{}", names[0], n - 1),
            }
        });
        drop(names);
        self.refresh_airplane();
    }

    /// Airplane Mode has no independent state of its own -- "active"
    /// just means WiFi and Bluetooth are both currently off, recomputed
    /// here whenever either one changes (called from the tail of
    /// `refresh_wifi`/`refresh_bluetooth` above). The tile's own click
    /// handler (app/mod.rs) reads `wifi_enabled()`/`bluetooth_enabled()`
    /// the same way the WiFi/Bluetooth tiles' own toggle does, to decide
    /// which way to flip both radios at once.
    fn refresh_airplane(&self) {
        let active = !self.wifi_enabled.get() && !self.bt_enabled.get();
        self.airplane.button.set_css_classes(&tile_classes(active));
        self.airplane.status.set_label(if active { "On" } else { "Off" });
    }

    /// `state` is WiredList's own "off"/"on"/"connected" vocabulary
    /// (see ui/wired_list.rs) -- passed straight through rather than
    /// re-deriving it here, one source of truth for what "connected"
    /// means for a wired profile. `device_name` is the active profile's
    /// name, shown the same way WiFi/Bluetooth show what they're
    /// attached to.
    pub fn set_ethernet_state(&self, state: &str, device_name: Option<&str>) {
        let connected = state == "connected";
        self.ethernet.icon.set_label(if state == "off" { super::icon::PLUGS } else { super::icon::PLUGS_CONNECTED });
        self.ethernet.button.set_css_classes(&tile_classes(connected));
        self.ethernet.status.set_label(&match state {
            "connected" => device_name.unwrap_or("Connected").to_string(),
            "on" => "Cable Connected".to_string(),
            _ => "Not Connected".to_string(),
        });
    }

    /// No status label to update here (unlike the square tiles) -- a
    /// wide action row only has icon+title, see its construction above.
    /// Not `tile_classes()` directly: that drops "balise-tile-wide",
    /// which this row needs to keep (it's what gives it its shorter
    /// min-height, see style.css) alongside whichever base/active pair
    /// tile_classes() would otherwise return on its own.
    pub fn set_night_mode(&self, enabled: bool) {
        let mut classes = tile_classes(enabled);
        classes.push("balise-tile-wide");
        self.night_tile.set_css_classes(&classes);
    }
}

/// Active tiles pick up the same translucent accent fill Balise's own
/// "connected" rows/switches use (see style.css's `.balise-tile.active`)
/// -- same "color carries state" principle the bar's own icon modules
/// already follow, just as a fill instead of a glyph-color swap since
/// these tiles are big enough for a whole-tile treatment to read clearly.
fn tile_classes(active: bool) -> Vec<&'static str> {
    if active {
        vec!["balise-tile", "flat", "active"]
    } else {
        vec!["balise-tile", "flat"]
    }
}
