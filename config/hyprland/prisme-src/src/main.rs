//! Prisme — native Wayland wallpaper picker (GTK4 + layer-shell),
//! replacing the old rofi menu (scripts/set_wallpaper.sh). A single
//! fullscreen window previews the focused wallpaper across the whole
//! screen (backdrop.rs, preview.rs) above a strip of thumbnails
//! (carousel.rs, card.rs); the choice is applied via awww/systemd, reusing
//! the same state format as the historical bash scripts (apply.rs).

mod apply;
mod backdrop;
mod cache;
mod card;
mod carousel;
mod illus;
mod keymap;
mod palette;
mod preview;
mod roll;
mod theme;
mod themes;
mod thumbs;
mod wallpapers;

use gtk4::gio::{self, ApplicationFlags};
use gtk4::prelude::*;
use gtk4::{gdk, glib, Application};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::{Cell, RefCell};
use std::collections::{HashSet, VecDeque};
use std::rc::Rc;
use std::time::Duration;

const APP_ID: &str = "com.prisme.app";

/// Bounds of the slideshow duration (seconds), adjustable by scrolling on
/// the "N picked · every …" line -- see `picked_label` in `build_ui`.
const DURATION_MIN: u32 = 5;
const DURATION_MAX: u32 = 3600;
const DURATION_STEP: u32 = 10;

/// Radius (in number of cards, on the ring) of the thumbnail window kept
/// LOADED around the focus -- beyond it, the texture is freed (see
/// `Card::clear_texture`), reloaded on demand if focus comes back to it
/// (see `refresh_thumb_window` in `build_ui`). Generous compared to what
/// fits on screen, to leave headroom for fast scrolling without visible
/// "pop-in", while still keeping the memory peak bounded (2×24+1 ≈ 49
/// thumbnails max in memory, versus the WHOLE collection before -- hundreds
/// for a large library).
const THUMB_WINDOW_RADIUS: i64 = 24;

/// How long the focus has to rest on a card before its sharp preview is
/// decoded: holding an arrow key decodes nothing but the card it stops on.
const PREVIEW_DELAY_MS: u64 = 90;

/// Sharp previews kept: the one shown, the one it faded from, the other
/// half of a pair and the neighbour preloaded in the direction of travel.
const PREVIEW_CACHE: usize = 4;
/// How long the preview waits for the sharp picture before showing the
/// thumbnail instead. The thumbnail is cropped from the original, not from
/// the screen-fit cache (which may keep the subject whole over a blurred
/// background), so showing it first and swapping made the picture jump.
const THUMB_FALLBACK_MS: u64 = 300;

/// How long a hint stays before fading out.
const HINT_MS: u64 = 3000;

/// The preview's width, as a share of the screen's; its height follows at
/// 16:10.
const PREVIEW_SHARE: f64 = 0.525;
/// Room kept under the panel for the bands and the bottom line: the panel
/// is centred in what is left above them.
const PANEL_CLEARANCE_PX: i32 = 560;
/// The caption's height under the preview, kept when the preview is fitted
/// to a short screen.
const LEGEND_PX: i32 = 84;

/// Interface strings -- fixed English (no system language detection, see
/// keymap.rs for the same choice on the shortcuts side), like the rest of
/// the shell. The screen looks like the desktop, so the words say plainly
/// that nothing is set yet: Esc keeps the current wallpaper.
const HINT_OPEN: &str = "Enter to apply · Esc to keep current · ↑↓ for themes · Tab for slideshow";
const HINT_SLIDESHOW: &str = "Shift ↓ to pick, Enter to start the slideshow";

/// The primary ink, for the parts of a markup line that stand out.
const INK: &str = "#f2f2f7";
const INK_LIGHT: &str = "#1c1c1e";

/// One band of the stack: Glass (no theme) or an Ink theme, its
/// wallpapers in ring order, and the one it was left on.
struct Band {
    theme: Option<usize>,
    order: Vec<usize>,
    focus: usize,
}

/// A band's name at the left of its row.
struct BandTitle {
    root: gtk4::Box,
    up: gtk4::Label,
    down: gtk4::Label,
    swatch: gtk4::DrawingArea,
}

/// "45 s", "2 min", "2 min 10 s", "1 h".
fn format_every(secs: u32) -> String {
    match (secs / 60, secs % 60) {
        (60, _) => "1 h".into(),
        (0, s) => format!("{s} s"),
        (m, 0) => format!("{m} min"),
        (m, s) => format!("{m} min {s} s"),
    }
}

/// The desktop's colour scheme, as the bar's light/dark toggle writes it
/// (quickshell's AppearanceState.qml) -- None when the schema isn't
/// installed, rather than GSettings aborting the process.
fn scheme_settings() -> Option<gio::Settings> {
    const SCHEMA: &str = "org.gnome.desktop.interface";
    gio::SettingsSchemaSource::default()?.lookup(SCHEMA, true)?;
    Some(gio::Settings::new(SCHEMA))
}

/// Same reading as wallpaper-set: prefer-dark is dark, anything else light.
fn prefers_dark(settings: &gio::Settings) -> bool {
    settings.string("color-scheme") == "prefer-dark"
}

/// Mode used to apply the chosen wallpaper, see apply.rs: a single static
/// image, or a slideshow cycling through a selection of several images.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Static,
    Dynamic,
}

/// Everything the callbacks share, in one place rather than a clone of
/// each widget per closure.
struct Ui {
    window: gtk4::ApplicationWindow,
    carousel: carousel::Carousel,
    backdrop: backdrop::Backdrop,
    walls: Vec<wallpapers::Wallpaper>,
    name: gtk4::Label,
    details: gtk4::Label,
    /// "C · Light | Dark" under the dimensions, for a pair only.
    halves: gtk4::Box,
    light: gtk4::Label,
    dark: gtk4::Label,
    position: gtk4::Label,
    picked: gtk4::Label,
    hint: gtk4::Label,
    mode: Cell<Mode>,
    duration: Cell<u32>,
    scheme_dark: Cell<bool>,
    /// C pressed: the preview shows the mode the scheme would not.
    peek: Cell<bool>,
    preview: preview::PreviewLoader,
    sharp: RefCell<VecDeque<(preview::Key, gdk::Texture)>>,
    /// The backdrop shows the sharp preview, not a stretched thumbnail.
    showing_sharp: Cell<bool>,
    focus: Cell<usize>,
    /// +1 or -1: where the next preview is preloaded.
    direction: Cell<i64>,
    hint_serial: Cell<u64>,
    /// The shell's themes; the bands (Glass, then one per Ink theme), the
    /// one in the middle, and the one in use when Prisme opened (written
    /// back on Enter if it changed).
    themes: Vec<themes::Theme>,
    bands: RefCell<Vec<Band>>,
    band_i: Cell<usize>,
    initial_band: usize,
    /// Per theme, the wallpapers that suit it (palette.rs); None until
    /// the colours are read.
    matches: RefCell<Option<Vec<Vec<usize>>>>,
    roll: roll::Roll,
    titles: Vec<BandTitle>,
    swatch_dark: Rc<Cell<bool>>,
    legend: gtk4::Box,
    frame: gtk4::Overlay,
    illus: gtk4::DrawingArea,
    look: Rc<RefCell<illus::State>>,
}

impl Ui {
    fn card(&self, i: usize) -> Option<card::Card> {
        self.carousel.card_at(i)
    }

    /// The mode the preview shows: the desktop's, or the other one after
    /// C. Everything follows it: the half of a pair, the sketch, the dress.
    fn view_dark(&self) -> bool {
        self.scheme_dark.get() != self.peek.get()
    }

    /// Which half of card `i` the preview shows.
    fn shown_dark(&self, i: usize) -> bool {
        self.walls.get(i).is_some_and(|w| w.dark.is_some()) && self.view_dark()
    }

    fn key(&self, i: usize) -> preview::Key {
        (i, self.shown_dark(i))
    }

    fn path(&self, (i, dark): preview::Key) -> Option<std::path::PathBuf> {
        let w = self.walls.get(i)?;
        Some(if dark { w.dark.clone()? } else { w.path.clone() })
    }

    /// The screen Prisme covers, in device pixels: the resolution
    /// wallpaper-filter fitted its cache to (wallpaper-set reads it from
    /// hyprctl, which reports the same mode size).
    fn screen_size(&self) -> (u32, u32) {
        let display = WidgetExt::display(&self.window);
        let monitor = self
            .window
            .surface()
            .and_then(|s| display.monitor_at_surface(&s))
            .or_else(|| display.monitors().item(0).and_downcast::<gdk::Monitor>());
        match monitor {
            Some(m) => {
                let g = m.geometry();
                let scale = m.scale();
                ((g.width() as f64 * scale).round() as u32, (g.height() as f64 * scale).round() as u32)
            }
            None => (1920, 1200),
        }
    }

    /// Shows the preview in light or dark (C, or a click on Light |
    /// Dark): the half of a pair, the sketch and the dress follow; held
    /// from one wallpaper to the next.
    fn show_half(self: &Rc<Self>, dark: bool) {
        if self.view_dark() == dark {
            return;
        }
        self.peek.set(dark != self.scheme_dark.get());
        let i = self.focus.get();
        if self.walls.get(i).is_some_and(|w| w.dark.is_some()) {
            if let Some(card) = self.card(i) {
                card.set_shown_dark(dark, true);
            }
            self.show_preview(false);
        }
        self.refresh_caption();
        self.apply_look();
    }

    /// Sizes the preview to the monitor Prisme opened on.
    fn fit_preview(&self) {
        let display = WidgetExt::display(&self.window);
        let monitor = self
            .window
            .surface()
            .and_then(|s| display.monitor_at_surface(&s))
            .or_else(|| display.monitors().item(0).and_downcast::<gdk::Monitor>());
        let (width, height) = monitor.map(|m| (m.geometry().width(), m.geometry().height())).unwrap_or((1920, 1200));
        // As wide as the share allows, as long as it fits above the bands.
        let room = (height - PANEL_CLEARANCE_PX - LEGEND_PX - 32).max(200) as f64;
        let w = (width as f64 * PREVIEW_SHARE).min(room * 16.0 / 10.0).round() as i32;
        self.backdrop.set_size_request(w, (w as f64 * 10.0 / 16.0).round() as i32);
        self.legend.set_size_request(w, -1);
    }

    fn refresh_caption(&self) {
        let i = self.focus.get();
        let Some(wall) = self.walls.get(i) else {
            return;
        };
        self.name.set_label(&wall.display_name());
        let mut parts = Vec::new();
        if let Some((w, h)) = self.card(i).map(|c| c.orig_dims()).filter(|&(w, h)| w > 0 && h > 0) {
            parts.push(format!("{w} × {h}"));
        }
        // Held in place while the thumbnail brings the size: a line coming
        // and going made the centred panel jump.
        self.details.set_markup(if parts.is_empty() { "\u{a0}" } else { "" });
        if !parts.is_empty() {
            self.details.set_markup(&parts.join(" · "));
        }
        self.halves.set_visible(true);
        let dark = self.view_dark();
        let light_class = if dark { "prisme-half" } else { "prisme-half-on" };
        let dark_class = if dark { "prisme-half-on" } else { "prisme-half" };
        self.light.set_css_classes(&[light_class]);
        self.dark.set_css_classes(&[dark_class]);
    }

    fn refresh_bottom(&self) {
        let ink = self.ink_hex();
        let total = self.carousel.slots();
        if total > 0 {
            let at = self.carousel.slot_of(self.focus.get()).map(|s| s + 1).unwrap_or(1);
            let tag = match (self.matches.borrow().is_some(), self.band_theme()) {
                (true, Some(t)) => format!(" · matching Ink · {}", glib::markup_escape_text(&t.name)),
                _ => String::new(),
            };
            self.position.set_markup(&format!("<span foreground=\"{ink}\">{at}</span> / {total}{tag}"));
        }
        let dynamic = self.mode.get() == Mode::Dynamic;
        self.picked.set_visible(dynamic);
        if dynamic {
            let n = (0..self.carousel.len()).filter_map(|i| self.card(i)).filter(|c| c.is_selected()).count();
            self.picked.set_markup(&format!(
                "{n} picked · every <span foreground=\"{ink}\">{}</span>",
                format_every(self.duration.get())
            ));
        }
    }

    /// Shows `text` along the bottom, then fades it out.
    fn flash(self: &Rc<Self>, text: &str) {
        self.hint.set_label(text);
        self.hint.remove_css_class("faded");
        let serial = self.hint_serial.get() + 1;
        self.hint_serial.set(serial);
        let ui = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_millis(HINT_MS), move || {
            if let Some(ui) = ui.upgrade() {
                if ui.hint_serial.get() == serial {
                    ui.hint.add_css_class("faded");
                }
            }
        });
    }

    fn focus_changed(self: &Rc<Self>, i: usize) {
        let len = self.carousel.slots() as i64;
        let previous_index = self.focus.replace(i);
        let previous = self.carousel.slot_of(previous_index).unwrap_or(0) as i64;
        let previous_index = previous_index as i64;
        let slot = self.carousel.slot_of(i).unwrap_or(0) as i64;
        if len > 0 {
            // Signed step on the ring, wrapping the short way round.
            let diff = (slot - previous).rem_euclid(len);
            if diff != 0 {
                self.direction.set(if diff <= len / 2 { 1 } else { -1 });
            }
        }
        // The card left behind closes back to the desktop's half: only the
        // focused card follows C, the others keep their thumbnail.
        let prev = previous_index as usize;
        if prev != i {
            if let Some(card) = self.card(prev) {
                let pair = self.walls.get(prev).is_some_and(|w| w.dark.is_some());
                card.set_shown_dark(pair && self.scheme_dark.get(), false);
            }
        }
        if let Some(card) = self.card(i) {
            card.set_shown_dark(self.shown_dark(i), false);
        }
        self.refresh_caption();
        self.refresh_bottom();
        self.show_preview(true);
    }

    /// Puts the focused card's preview up: the sharp one if it's cached,
    /// otherwise its thumbnail at once and the sharp one once decoded.
    fn show_preview(self: &Rc<Self>, delay: bool) {
        let i = self.focus.get();
        let key = self.key(i);
        let cached = self.sharp.borrow().iter().find(|(k, _)| *k == key).map(|(_, t)| t.clone());
        let generation = self.preview.next_generation();
        if let Some(tex) = cached {
            self.showing_sharp.set(true);
            self.backdrop.show(tex);
            self.preload(generation);
            return;
        }
        self.showing_sharp.set(false);
        // Nothing on screen yet (at launch): the thumbnail at once.
        // Otherwise the current picture stays until the sharp one comes,
        // and the thumbnail only stands in if that takes too long.
        if self.backdrop.is_empty() {
            if let Some(thumb) = self.card(i).and_then(|c| c.texture(key.1)) {
                self.backdrop.show(thumb);
            }
        } else {
            let ui = Rc::downgrade(self);
            glib::timeout_add_local_once(Duration::from_millis(THUMB_FALLBACK_MS), move || {
                let Some(ui) = ui.upgrade() else {
                    return;
                };
                if ui.preview.generation() == generation && !ui.showing_sharp.get() {
                    if let Some(thumb) = ui.card(i).and_then(|c| c.texture(key.1)) {
                        ui.backdrop.show(thumb);
                    }
                }
            });
        }
        let Some(path) = self.path(key) else {
            return;
        };
        if !delay {
            self.preview.request(generation, key, path, self.screen_size());
            return;
        }
        let ui = Rc::downgrade(self);
        glib::timeout_add_local_once(Duration::from_millis(PREVIEW_DELAY_MS), move || {
            if let Some(ui) = ui.upgrade() {
                if ui.preview.generation() == generation {
                    ui.preview.request(generation, key, path, ui.screen_size());
                }
            }
        });
    }

    /// Decodes ahead of time, one picture at a time (the loader keeps only
    /// the latest request): the other half of a focused pair, so C swaps
    /// at once, then the next card in the direction of travel.
    fn preload(&self, generation: u64) {
        let i = self.focus.get();
        let mut wanted = Vec::new();
        if self.walls.get(i).is_some_and(|w| w.dark.is_some()) {
            let (_, dark) = self.key(i);
            wanted.push((i, !dark));
        }
        if self.carousel.slots() >= 2 {
            let slot = self.carousel.slot_of(i).unwrap_or(0) as i64;
            if let Some(next) = self.carousel.index_at_slot(slot + self.direction.get()) {
                wanted.push(self.key(next));
            }
        }
        let missing = wanted.into_iter().find(|key| !self.sharp.borrow().iter().any(|(k, _)| k == key));
        if let Some(key) = missing {
            if let Some(path) = self.path(key) {
                self.preview.request(generation, key, path, self.screen_size());
            }
        }
    }

    fn preview_ready(&self, result: preview::PreviewResult) {
        if result.generation != self.preview.generation() {
            return;
        }
        {
            let mut sharp = self.sharp.borrow_mut();
            sharp.retain(|(k, _)| *k != result.key);
            sharp.push_back((result.key, result.texture.clone()));
            while sharp.len() > PREVIEW_CACHE {
                sharp.pop_front();
            }
        }
        if result.key == self.key(self.focus.get()) {
            self.showing_sharp.set(true);
            self.backdrop.show(result.texture);
        }
        self.preload(result.generation);
    }

    /// A thumbnail landed: the focused card's fills in for the preview
    /// until the sharp one is ready, and brings the caption's dimensions.
    fn thumb_ready(&self, i: usize) {
        if i != self.focus.get() {
            return;
        }
        self.refresh_caption();
        if self.backdrop.is_empty() {
            if let Some(thumb) = self.card(i).and_then(|c| c.texture(self.shown_dark(i))) {
                self.backdrop.show(thumb);
            }
        }
    }
}

impl Ui {
    /// The ink for the parts of a markup line that stand out.
    fn ink_hex(&self) -> &'static str {
        if self.view_dark() { INK } else { INK_LIGHT }
    }

    /// The Ink theme of the band in the middle; None for Glass.
    fn band_theme(&self) -> Option<&themes::Theme> {
        self.bands.borrow().get(self.band_i.get()).and_then(|b| b.theme).and_then(|t| self.themes.get(t))
    }

    /// Prisme itself only follows light or dark; the preview alone shows
    /// the shell, in the middle band's look and colours.
    fn apply_look(&self) {
        let dark = self.view_dark();
        for (class, on) in [("dark", dark), ("light", !dark)] {
            if on { self.window.add_css_class(class) } else { self.window.remove_css_class(class) }
        }
        let theme = self.band_theme();
        if theme.is_some() { self.frame.add_css_class("ink") } else { self.frame.remove_css_class("ink") }
        let colors = theme.map(|t| t.colors(dark).clone()).unwrap_or_default();
        illus::set_look(&self.illus, &self.look, illus::Look { ink: theme.is_some(), dark, colors });
        self.swatch_dark.set(dark);
        for t in &self.titles {
            t.swatch.queue_draw();
        }
        self.refresh_bottom();
    }

    /// Lights the middle band's name, and the keys beside its neighbours'.
    fn refresh_titles(&self) {
        let current = self.band_i.get() as i64;
        for (k, t) in self.titles.iter().enumerate() {
            let d = k as i64 - current;
            let class = match d {
                0 => "cur",
                -1 => "up",
                1 => "down",
                _ => "far",
            };
            t.root.set_css_classes(&["prisme-band", class]);
            t.up.set_visible(d == -1);
            t.down.set_visible(d == 1);
        }
    }

    /// Rolls to band `i` (clamped): the carousel takes its wallpapers, on
    /// the one it was left on, and the stack slides from where it was.
    fn set_band(self: &Rc<Self>, i: i64) {
        let n = self.bands.borrow().len() as i64;
        let i = i.clamp(0, (n - 1).max(0)) as usize;
        let old = self.band_i.get();
        if i == old {
            return;
        }
        if let Some(b) = self.bands.borrow_mut().get_mut(old) {
            b.focus = self.focus.get();
        }
        self.band_i.set(i);
        self.refresh_titles();
        self.roll.set_current(i, true);
        let (order, focus) = {
            let bands = self.bands.borrow();
            (bands[i].order.clone(), bands[i].focus)
        };
        self.carousel.set_order(order, focus);
        self.apply_look();
    }

    /// The colours are read: each Ink band keeps its theme's wallpapers,
    /// best first. The band Prisme opened on keeps the wallpaper in use.
    fn set_matches(&self, m: Vec<Vec<usize>>, keep: Option<usize>) {
        {
            let mut bands = self.bands.borrow_mut();
            for (k, band) in bands.iter_mut().enumerate() {
                let Some(t) = band.theme else {
                    continue;
                };
                let mut order = m.get(t).cloned().unwrap_or_default();
                if order.is_empty() {
                    continue;
                }
                if k == self.initial_band {
                    if let Some(w) = keep.filter(|w| !order.contains(w)) {
                        order.insert(0, w);
                    }
                }
                if !order.contains(&band.focus) {
                    band.focus = order[0];
                }
                band.order = order;
            }
        }
        *self.matches.borrow_mut() = Some(m);
        let (order, focus) = {
            let bands = self.bands.borrow();
            let b = &bands[self.band_i.get()];
            (b.order.clone(), if b.order.contains(&self.focus.get()) { self.focus.get() } else { b.focus })
        };
        self.carousel.set_order(order, focus);
        self.roll.queue_draw();
        self.refresh_bottom();
    }

    /// For the stack (roll.rs): the cards of the band `delta` from the
    /// middle, around the one it was left on.
    fn band_slots(&self, delta: i64) -> Vec<roll::Slot> {
        let b = self.band_i.get() as i64 + delta;
        let bands = self.bands.borrow();
        let Some(band) = (b >= 0).then(|| bands.get(b as usize)).flatten() else {
            return Vec::new();
        };
        let len = band.order.len() as i64;
        let at = band.order.iter().position(|&i| i == band.focus).unwrap_or(0) as i64;
        let reach = BAND_REACH.min((len - 1) / 2);
        (-reach..=reach)
            .filter_map(|d| {
                let index = band.order[(at + d).rem_euclid(len) as usize];
                let card = self.card(index)?;
                let pair = card.wallpaper().dark.is_some();
                Some(roll::Slot { d, light: card.texture(false), dark: if pair { card.texture(true) } else { None }, pair })
            })
            .collect()
    }

    /// The wallpapers of the bands just above and below, around where they
    /// were left: their thumbnails are loaded with the middle band's.
    fn neighbour_cards(&self) -> Vec<(usize, f64)> {
        let bands = self.bands.borrow();
        let mut out = Vec::new();
        for delta in [-1i64, 1] {
            let b = self.band_i.get() as i64 + delta;
            let Some(band) = (b >= 0).then(|| bands.get(b as usize)).flatten() else {
                continue;
            };
            let len = band.order.len() as i64;
            let at = band.order.iter().position(|&i| i == band.focus).unwrap_or(0) as i64;
            let reach = BAND_REACH.min((len - 1) / 2);
            for d in -reach..=reach {
                out.push((band.order[(at + d).rem_euclid(len) as usize], d.abs() as f64 + 1.0));
            }
        }
        out
    }
}

/// How many cards either side of its focus a neighbouring band shows.
const BAND_REACH: i64 = 12;

/// Glass's dots: neutral, as its shell is.
const GLASS_DOTS: [&str; 4] = ["#f2f2f7", "#a9a9b2", "#3a3a40", "#e9dcc3"];

/// Entry point: forces GPU rendering then delegates building the single
/// window to `build_ui` on every GApplication activation.
fn main() -> glib::ExitCode {
    // Without this, GSK falls back to software rendering here, invisible
    // in the logs except via GDK_DEBUG=opengl (no EGL/GL line appears) --
    // measured at ~25-40fps in the carousel, decreasing, versus ~120fps+
    // (climbing steadily toward the screen's refresh rate, see
    // carousel.rs) once GPU rendering is forced. Respects a value already
    // set by the environment (debug, another machine, etc.).
    if std::env::var_os("GSK_RENDERER").is_none() {
        std::env::set_var("GSK_RENDERER", "opengl");
    }

    let app = Application::new(Some(APP_ID), ApplicationFlags::empty());
    app.connect_activate(build_ui);
    app.run()
}

/// Builds the fullscreen layer-shell window: the live preview, its
/// caption, the strip of cards and the bottom line, and wires up keyboard
/// shortcuts and asynchronous loading.
fn build_ui(app: &Application) {
    // GApplication reactivates the already-running instance instead of
    // launching a new one (e.g. Super+W pressed twice before the first
    // window closes) -- without this guard, `connect_activate` would call
    // `build_ui` again and stack a second window/carousel (hence a second
    // animation loop) in the same process.
    if let Some(existing) = app.windows().first() {
        existing.present();
        return;
    }

    let window = gtk4::ApplicationWindow::new(app);
    window.add_css_class("background");

    // Overlay layer, above every window and the bar: the veil covers the
    // bar too. Its ink is tinted for the wallpaper that is set
    // (bar-tint.py), so it would not read reliably over another one. The
    // blur behind the veil is Hyprland's (windowrules.lua).
    window.init_layer_shell();
    window.set_namespace("prisme");
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_exclusive_zone(-1);
    for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
        window.set_anchor(edge, true);
    }
    if let Some(display) = gdk::Display::default() {
        theme::load(&display);
    }

    let overlay = gtk4::Overlay::new();
    // An empty base: everything is laid over it, the window gives the size.
    overlay.set_child(Some(&gtk4::Box::new(gtk4::Orientation::Vertical, 0)));

    // ── The panel, centred above the cards: the preview, then its caption
    // and, for a pair, the light/dark toggle.
    let panel = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .css_classes(["prisme-panel"])
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .margin_bottom(PANEL_CLEARANCE_PX)
        .build();
    let backdrop = backdrop::Backdrop::new();
    let legend = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .css_classes(["prisme-legend"])
        .halign(gtk4::Align::Center)
        .build();
    let caption = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .css_classes(["prisme-caption"])
        .hexpand(true)
        .build();
    let name = gtk4::Label::builder()
        .css_classes(["prisme-name"])
        .xalign(0.0)
        .ellipsize(gtk4::pango::EllipsizeMode::End)
        .max_width_chars(36)
        .build();
    let details = gtk4::Label::builder().css_classes(["prisme-details"]).xalign(0.0).use_markup(true).build();
    // The pair toggle: two quiet words, the half on screen lit. A click
    // picks a half, like C.
    let halves = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .css_classes(["prisme-halves"])
        .halign(gtk4::Align::End)
        .valign(gtk4::Align::Start)
        .tooltip_text("C")
        .visible(false)
        .build();
    let light = gtk4::Label::builder().label("Light").css_classes(["prisme-half"]).build();
    let dark = gtk4::Label::builder().label("Dark").css_classes(["prisme-half"]).build();
    for word in [&light, &dark] {
        word.set_cursor_from_name(Some("pointer"));
    }
    halves.append(&light);
    halves.append(&dark);
    caption.append(&name);
    caption.append(&details);
    legend.append(&caption);
    legend.append(&halves);
    // The preview in a frame (the Ink outline is the frame's), the
    // illustration laid over it.
    let (illus_area, look) = illus::new();
    let frame = gtk4::Overlay::builder().css_classes(["prisme-frame"]).halign(gtk4::Align::Center).build();
    frame.set_overflow(gtk4::Overflow::Hidden);
    frame.set_child(Some(&backdrop));
    frame.add_overlay(&illus_area);
    panel.append(&frame);
    panel.append(&legend);

    // ── The bands' names: Glass, then the Ink themes (Coucou first, as
    // the shell's theme picker lists them).
    let mut all_themes = themes::load_all();
    if let Some(k) = all_themes.iter().position(|t| t.id == "coucou") {
        let coucou = all_themes.remove(k);
        all_themes.insert(0, coucou);
    }
    let (ink, current_theme) = themes::selection();
    let initial_band = if ink {
        current_theme.and_then(|id| all_themes.iter().position(|t| t.id == id)).map(|t| t + 1).unwrap_or(0)
    } else {
        0
    };
    let swatch_dark = Rc::new(Cell::new(true));
    let band_title = |name: &str, dots: Rc<dyn Fn(bool) -> [String; 4]>| {
        let root = gtk4::Box::builder().orientation(gtk4::Orientation::Vertical).spacing(6).css_classes(["prisme-band"]).build();
        let line = gtk4::Box::builder().orientation(gtk4::Orientation::Horizontal).spacing(6).build();
        let up = gtk4::Label::builder().label("↑").css_classes(["prisme-band-key"]).visible(false).build();
        let down = gtk4::Label::builder().label("↓").css_classes(["prisme-band-key"]).visible(false).build();
        let label = gtk4::Label::builder().label(name).xalign(0.0).ellipsize(gtk4::pango::EllipsizeMode::End).build();
        line.append(&up);
        line.append(&down);
        line.append(&label);
        let swatch = gtk4::DrawingArea::builder().content_width(44).content_height(9).halign(gtk4::Align::Start).build();
        let dark = swatch_dark.clone();
        swatch.set_draw_func(move |_, cr, _, h| {
            for (k, hex) in dots(dark.get()).iter().enumerate() {
                let (r, g, b) = themes::rgb(hex);
                cr.arc(4.5 + k as f64 * 11.0, h as f64 / 2.0, 4.0, 0.0, std::f64::consts::TAU);
                cr.set_source_rgb(r, g, b);
                let _ = cr.fill();
            }
        });
        root.append(&line);
        root.append(&swatch);
        root.set_cursor_from_name(Some("pointer"));
        BandTitle { root, up, down, swatch }
    };
    let mut titles = vec![band_title("Glass", Rc::new(|_| GLASS_DOTS.map(str::to_string)))];
    for t in &all_themes {
        let theme = t.clone();
        titles.push(band_title(
            &format!("Ink · {}", t.name),
            Rc::new(move |dark| {
                let c = theme.colors(dark);
                [c.accent.clone(), c.highlight.clone(), c.success.clone(), c.danger.clone()]
            }),
        ));
    }

    // ── Bottom line: position, hint, and the slideshow summary.
    let bar = gtk4::CenterBox::builder().css_classes(["prisme-bar"]).valign(gtk4::Align::End).build();
    let position = gtk4::Label::builder().css_classes(["prisme-position"]).use_markup(true).can_target(false).build();
    let hint = gtk4::Label::builder().css_classes(["prisme-hint", "faded"]).can_target(false).build();
    let picked = gtk4::Label::builder().css_classes(["prisme-picked"]).use_markup(true).visible(false).build();
    bar.set_start_widget(Some(&position));
    bar.set_center_widget(Some(&hint));
    bar.set_end_widget(Some(&picked));

    let source_dir = wallpapers::originals_dir();
    let walls = wallpapers::scan(&source_dir);
    let cards: Vec<card::Card> = walls.iter().map(|w| card::Card::new(w.clone())).collect();
    let carousel = carousel::Carousel::new(cards);
    let roll = roll::Roll::new(&carousel, titles.iter().map(|t| t.root.clone().upcast()).collect());
    roll.set_current(initial_band, false);
    let all: Vec<usize> = (0..walls.len()).collect();
    // The Ink sets are drawn for their theme: Glass leaves them out.
    let glass: Vec<usize> = all.iter().copied().filter(|&i| !palette::is_ink(&walls[i].name)).collect();
    let glass = if glass.is_empty() { all.clone() } else { glass };
    let bands: Vec<Band> = std::iter::once(None)
        .chain((0..all_themes.len()).map(Some))
        .map(|theme| Band { theme, order: if theme.is_none() { glass.clone() } else { all.clone() }, focus: 0 })
        .collect();

    overlay.add_overlay(&roll);
    // Above the carousel, which takes the wheel over the whole window: the
    // Light | Dark words need the clicks over the panel.
    overlay.add_overlay(&panel);
    overlay.add_overlay(&bar);
    window.set_child(Some(&overlay));

    let (preview_loader, preview_rx) = preview::PreviewLoader::new();
    let ui = Rc::new(Ui {
        window: window.clone(),
        carousel: carousel.clone(),
        backdrop,
        walls: walls.clone(),
        name,
        details,
        halves,
        light,
        dark,
        position,
        picked: picked.clone(),
        hint,
        mode: Cell::new(Mode::Static),
        duration: Cell::new(120),
        scheme_dark: Cell::new(true),
        peek: Cell::new(false),
        preview: preview_loader,
        sharp: RefCell::new(VecDeque::new()),
        showing_sharp: Cell::new(false),
        focus: Cell::new(0),
        direction: Cell::new(1),
        hint_serial: Cell::new(0),
        themes: all_themes,
        bands: RefCell::new(bands),
        band_i: Cell::new(initial_band),
        initial_band,
        matches: RefCell::new(None),
        roll: roll.clone(),
        titles,
        swatch_dark,
        legend: legend.clone(),
        frame: frame.clone(),
        illus: illus_area,
        look,
    });
    // The neighbouring bands come from the same cards; a click on one, or
    // on its name, rolls to it.
    {
        let weak = Rc::downgrade(&ui);
        roll.set_provider(Box::new(move |delta| weak.upgrade().map(|ui| ui.band_slots(delta)).unwrap_or_default()));
        let weak = Rc::downgrade(&ui);
        roll.connect_clicked(move |d| {
            if let Some(ui) = weak.upgrade() {
                ui.set_band(ui.band_i.get() as i64 + d);
            }
        });
    }

    // Each wallpaper's colours, read off the GTK thread (palette.rs); the
    // filter applies once they are in.
    {
        let (tx, rx) = async_channel::bounded(1);
        let walls = walls.clone();
        std::thread::spawn(move || {
            let _ = tx.send_blocking(palette::compute(&walls));
        });
        let weak = Rc::downgrade(&ui);
        glib::MainContext::default().spawn_local(async move {
            if let Ok(palettes) = rx.recv().await {
                if let Some(ui) = weak.upgrade() {
                    let names: Vec<String> = ui.walls.iter().map(|w| w.name.clone()).collect();
                    let m = palette::matches(&palettes, &names, &ui.themes);
                    let keep = apply::last_static().and_then(|name| ui.walls.iter().position(|w| w.answers_to(&name)));
                    ui.set_matches(m, keep);
                }
            }
        });
    }

    // Duration: no text field to click into, the wheel over the summary
    // adjusts it (same vocabulary as the carousel's scroll).
    {
        let ui = Rc::downgrade(&ui);
        let scroll = gtk4::EventControllerScroll::new(gtk4::EventControllerScrollFlags::BOTH_AXES);
        scroll.connect_scroll(move |_, dx, dy| {
            let Some(ui) = ui.upgrade() else {
                return glib::Propagation::Stop;
            };
            let delta = if dx.abs() > dy.abs() { dx } else { dy };
            if delta.abs() < 0.01 {
                return glib::Propagation::Stop;
            }
            let step = if delta > 0.0 { -(DURATION_STEP as i64) } else { DURATION_STEP as i64 };
            let next = (ui.duration.get() as i64 + step).clamp(DURATION_MIN as i64, DURATION_MAX as i64) as u32;
            ui.duration.set(next);
            ui.refresh_bottom();
            glib::Propagation::Stop
        });
        picked.add_controller(scroll);
    }

    // Each pair shows the half the desktop's colour scheme asks for, and
    // follows it live if the scheme changes while Prisme is open.
    if let Some(settings) = scheme_settings() {
        let set_all = {
            let ui = Rc::downgrade(&ui);
            move |settings: &gio::Settings| {
                let Some(ui) = ui.upgrade() else {
                    return;
                };
                let dark = prefers_dark(settings);
                ui.scheme_dark.set(dark);
                ui.roll.set_dark_scheme(dark);
                for i in 0..ui.carousel.len() {
                    if let Some(card) = ui.card(i) {
                        card.set_dark_scheme(dark);
                    }
                }
                let i = ui.focus.get();
                if let Some(card) = ui.card(i) {
                    card.set_shown_dark(ui.shown_dark(i), false);
                }
                ui.refresh_caption();
                ui.show_preview(false);
                ui.apply_look();
            }
        };
        let dark = prefers_dark(&settings);
        ui.scheme_dark.set(dark);
        roll.set_dark_scheme(dark);
        for i in 0..carousel.len() {
            if let Some(card) = carousel.card_at(i) {
                card.set_dark_scheme(dark);
            }
        }
        settings.connect_changed(Some("color-scheme"), move |s, _| set_all(s));
        // Kept alive with the window: a dropped GSettings stops emitting
        // `changed`.
        window.connect_destroy(move |_| {
            let _ = &settings;
        });
    }

    // Opens directly on the last wallpaper applied in Static mode
    // (independent of the current mode -- switching to Dynamic must not
    // lose this reference point, see apply::last_static) rather than the
    // first card in the list. So the preview starts on the desktop as it
    // already is.
    let initial_index = apply::last_static().and_then(|name| walls.iter().position(|w| w.answers_to(&name)));
    if let Some(index) = initial_index {
        carousel.set_focus_index(index);
        for band in ui.bands.borrow_mut().iter_mut() {
            // An Ink wallpaper in use stays in the Glass band it opens on.
            if !band.order.contains(&index) {
                band.order.insert(0, index);
            }
            band.focus = index;
        }
    }
    ui.focus.set(initial_index.unwrap_or(0));
    {
        let bands = ui.bands.borrow();
        let b = &bands[initial_band];
        if b.order.len() != walls.len() {
            carousel.set_order(b.order.clone(), b.focus);
        }
    }

    {
        let ui = Rc::downgrade(&ui);
        glib::MainContext::default().spawn_local(async move {
            while let Ok(result) = preview_rx.recv().await {
                if let Some(ui) = ui.upgrade() {
                    ui.preview_ready(result);
                }
            }
        });
    }

    // Thumbnails in the background (thumbs.rs) -- doesn't block display
    // on decoding. Only the window around the focus (see
    // THUMB_WINDOW_RADIUS) is requested, not the whole collection:
    // `refresh_thumb_window` decides what to load/unload, called once here
    // for the initial position then on every interactive focus change.
    let (loader, thumb_rx) = thumbs::ThumbLoader::new();

    // Indices currently loaded OR being decoded -- avoids re-requesting a
    // card already in the window on every recompute, and serves as the
    // list to walk to unload cards that fall out of it.
    let loaded_thumbs: Rc<RefCell<HashSet<usize>>> = Rc::new(RefCell::new(HashSet::new()));
    {
        let ui = Rc::downgrade(&ui);
        let loaded_thumbs = loaded_thumbs.clone();
        glib::MainContext::default().spawn_local(async move {
            while let Ok(result) = thumb_rx.recv().await {
                let Some(ui) = ui.upgrade() else {
                    continue;
                };
                // A card scrolled out of the window while its thumbnail was
                // queued: dropped, or it would hold a texture nothing frees.
                if !loaded_thumbs.borrow().contains(&result.index) {
                    continue;
                }
                if let (Some(card), Some(tex)) = (ui.card(result.index), result.texture) {
                    card.set_texture(result.dark, tex, result.orig_width, result.orig_height);
                    ui.thumb_ready(result.index);
                    ui.roll.queue_draw();
                }
            }
        });
    }

    let refresh_thumb_window: Rc<dyn Fn(usize)> = {
        let walls = walls.clone();
        let carousel = carousel.clone();
        let loaded_thumbs = loaded_thumbs.clone();
        let weak = Rc::downgrade(&ui);
        Rc::new(move |focus: usize| {
            let len = walls.len();
            if len == 0 {
                return;
            }
            // Sorted by distance to the focus (not just filtered) -- the
            // order of THIS vector is the order requests are sent in just
            // below, hence the order thumbs.rs's threads pick them up in:
            // the focused card (and its closest neighbors) must appear
            // first.
            // The middle band's window, then the bands above and below
            // around where they were left (roll.rs draws them).
            let mut distance: std::collections::HashMap<usize, f64> = (0..len)
                .filter_map(|i| carousel.slot_distance(i, focus).filter(|&d| d <= THUMB_WINDOW_RADIUS as f64).map(|d| (i, d)))
                .collect();
            if let Some(ui) = weak.upgrade() {
                for (i, d) in ui.neighbour_cards() {
                    let e = distance.entry(i).or_insert(d);
                    *e = e.min(d);
                }
            }
            let mut wanted_by_distance: Vec<usize> = distance.keys().copied().collect();
            wanted_by_distance.sort_by(|a, b| distance[a].total_cmp(&distance[b]));
            let wanted: HashSet<usize> = wanted_by_distance.iter().copied().collect();

            let mut loaded = loaded_thumbs.borrow_mut();
            // `insert` returns true only if the index wasn't already there
            // -- neither loaded nor already queued.
            let new: Vec<usize> = wanted_by_distance.iter().copied().filter(|&i| loaded.insert(i)).collect();
            // The half each card shows at rest, nearest first, then the
            // other halves of pairs: only the focused card shows both,
            // either side of its cut, so a resting pair's hidden half never
            // keeps a card on screen blank.
            let mut shown = Vec::new();
            let mut hidden = Vec::new();
            for &i in &new {
                let light = (false, walls[i].path.clone());
                let (first, second) = match &walls[i].dark {
                    None => (light, None),
                    Some(dark) if carousel.card_at(i).is_some_and(|c| c.dark_scheme()) => {
                        ((true, dark.clone()), Some(light))
                    }
                    Some(dark) => (light, Some((true, dark.clone()))),
                };
                shown.push((i, first));
                match second {
                    Some(second) if i == focus => shown.push((i, second)),
                    Some(second) => hidden.push((i, second)),
                    None => {}
                }
            }
            for (i, (dark, path)) in shown.into_iter().chain(hidden) {
                loader.request(i, dark, path);
            }
            loaded.retain(|&i| {
                if wanted.contains(&i) {
                    return true;
                }
                if let Some(card) = carousel.card_at(i) {
                    card.clear_texture();
                }
                false
            });
        })
    };
    refresh_thumb_window(ui.focus.get());
    {
        let ui = Rc::downgrade(&ui);
        carousel.connect_target_changed(move |focus| {
            refresh_thumb_window(focus);
            if let Some(ui) = ui.upgrade() {
                ui.focus_changed(focus);
            }
        });
    }

    // Enter / click on the already-focused card: applies according to the
    // current mode, like steps 5 (dynamic) and 21 (static) of
    // scripts/set_wallpaper.sh (see apply.rs).
    {
        let ui = Rc::downgrade(&ui);
        carousel.connect_activate(move |index| {
            let Some(ui) = ui.upgrade() else {
                return;
            };
            let source_dir = wallpapers::originals_dir();
            match ui.mode.get() {
                Mode::Static => {
                    if let Some(card) = ui.card(index) {
                        apply::apply_static(&source_dir, &card.wallpaper().path, &card.wallpaper().name);
                    }
                }
                Mode::Dynamic => {
                    let selected: Vec<String> = (0..ui.carousel.len())
                        .filter_map(|i| ui.card(i))
                        .filter(|c| c.is_selected())
                        .map(|c| c.wallpaper().name.clone())
                        .collect();
                    // Nothing picked -- slideshow over the whole source,
                    // like set_wallpaper.sh's fallback when $CHOSEN is
                    // empty.
                    let names = if selected.is_empty() {
                        ui.walls.iter().map(|w| w.name.clone()).collect()
                    } else {
                        selected
                    };
                    apply::apply_dynamic(&source_dir, ui.duration.get(), &names);
                }
            }
            // The band's look and theme become the shell's, if they changed.
            if ui.band_i.get() != ui.initial_band {
                themes::select(ui.band_theme().map(|t| t.id.as_str()));
            }
            ui.window.close();
        });
    }

    // Tab: Static ⇄ Dynamic -- a state change, never a rebuild.
    let toggle_mode = {
        let ui = Rc::downgrade(&ui);
        move || {
            let Some(ui) = ui.upgrade() else {
                return;
            };
            let next = if ui.mode.get() == Mode::Static { Mode::Dynamic } else { Mode::Static };
            ui.mode.set(next);
            ui.refresh_bottom();
            ui.flash(if next == Mode::Dynamic { HINT_SLIDESHOW } else { HINT_OPEN });
        }
    };

    let set_picked = {
        let ui = Rc::downgrade(&ui);
        move |on: bool| {
            let Some(ui) = ui.upgrade() else {
                return;
            };
            if let Some(card) = ui.card(ui.carousel.focused_index()) {
                card.set_selected(on);
            }
            // Selection changes the card's allocated height (see
            // carousel.rs) -- an allocate must be explicitly requested
            // here: the tick loop no longer does it on its own once
            // settled, so as not to cost a full relayout every frame.
            ui.carousel.queue_allocate();
            ui.refresh_bottom();
        }
    };

    let keymap = keymap::Keymap::load();
    let key_controller = gtk4::EventControllerKey::new();
    {
        let ui = Rc::downgrade(&ui);
        key_controller.connect_key_pressed(move |_, key, _, state| {
            use keymap::Action;
            let (Some(action), Some(ui)) = (keymap.action(key, state.contains(gdk::ModifierType::SHIFT_MASK)), ui.upgrade()) else {
                return glib::Propagation::Proceed;
            };
            let dynamic = ui.mode.get() == Mode::Dynamic;
            match action {
                Action::Close => ui.window.close(),
                Action::MoveLeft => ui.carousel.move_focus(-1),
                Action::MoveRight => ui.carousel.move_focus(1),
                Action::Activate => ui.carousel.activate_focused(),
                Action::ToggleMode => toggle_mode(),
                Action::Select if dynamic => set_picked(true),
                Action::Deselect if dynamic => set_picked(false),
                Action::ToggleHalf => ui.show_half(!ui.view_dark()),
                Action::Select | Action::Deselect => return glib::Propagation::Proceed,
                Action::ThemePrev => ui.set_band(ui.band_i.get() as i64 - 1),
                Action::ThemeNext => ui.set_band(ui.band_i.get() as i64 + 1),
            }
            glib::Propagation::Stop
        });
    }
    window.add_controller(key_controller);

    // Every callback above holds `ui` weakly; this is the one strong
    // reference, living as long as the window.
    {
        let ui = ui.clone();
        window.connect_destroy(move |_| {
            let _ = &ui;
        });
    }

    for (word, dark) in [(&ui.light, false), (&ui.dark, true)] {
        let ui = Rc::downgrade(&ui);
        let click = gtk4::GestureClick::new();
        click.connect_released(move |_, _, _, _| {
            if let Some(ui) = ui.upgrade() {
                ui.show_half(dark);
            }
        });
        word.add_controller(click);
    }
    {
        let ui = Rc::downgrade(&ui);
        window.connect_map(move |_| {
            if let Some(ui) = ui.upgrade() {
                ui.fit_preview();
            }
        });
    }

    window.present();
    ui.refresh_titles();
    ui.apply_look();
    ui.refresh_caption();
    ui.refresh_bottom();
    ui.show_preview(false);
    ui.flash(HINT_OPEN);
}
