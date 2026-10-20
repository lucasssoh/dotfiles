//! Prisme — native Wayland wallpaper picker (GTK4 + layer-shell),
//! replacing the old rofi menu (scripts/set_wallpaper.sh). A single
//! fullscreen window previews the focused wallpaper across the whole
//! screen (backdrop.rs, preview.rs) above a strip of thumbnails
//! (carousel.rs, card.rs); the choice is applied via awww/systemd, reusing
//! the same state format as the historical bash scripts (apply.rs).

mod apply;
mod backdrop;
mod card;
mod carousel;
mod keymap;
mod preview;
mod theme;
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
/// decoded: the thumbnail stands in meanwhile, so holding an arrow key
/// decodes nothing but the card it stops on.
const PREVIEW_DELAY_MS: u64 = 90;

/// Sharp previews kept: the one shown, the one it faded from, and the
/// neighbour preloaded in the direction of travel.
const PREVIEW_CACHE: usize = 3;

/// How long a hint stays before fading out.
const HINT_MS: u64 = 3000;

/// The preview's width, as a share of the screen's; its height follows at
/// 16:10.
const PREVIEW_SHARE: f64 = 0.525;
/// Room kept under the panel for the cards and the bottom line: the panel
/// is centred in what is left above them.
const PANEL_CLEARANCE_PX: i32 = 284;

/// Interface strings -- fixed English (no system language detection, see
/// keymap.rs for the same choice on the shortcuts side), like the rest of
/// the shell. The screen looks like the desktop, so the words say plainly
/// that nothing is set yet: Esc keeps the current wallpaper.
const HINT_OPEN: &str = "Enter to apply · Esc to keep current · Tab for slideshow";
const HINT_SLIDESHOW: &str = "Press ↓ to pick, Enter to start the slideshow";

/// The primary ink, for the parts of a markup line that stand out.
const INK: &str = "#f2f2f7";

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
    /// C pressed on a pair: the preview shows the half the scheme
    /// would not. Cleared when the focus moves on.
    peek: Cell<bool>,
    preview: preview::PreviewLoader,
    sharp: RefCell<VecDeque<(preview::Key, gdk::Texture)>>,
    /// The backdrop shows the sharp preview, not a stretched thumbnail.
    showing_sharp: Cell<bool>,
    focus: Cell<usize>,
    /// +1 or -1: where the next preview is preloaded.
    direction: Cell<i64>,
    hint_serial: Cell<u64>,
}

impl Ui {
    fn card(&self, i: usize) -> Option<card::Card> {
        self.carousel.card_at(i)
    }

    /// Which half of card `i` the preview shows.
    fn shown_dark(&self, i: usize) -> bool {
        self.walls.get(i).is_some_and(|w| w.dark.is_some()) && (self.scheme_dark.get() != self.peek.get())
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

    /// Sizes the preview to the monitor Prisme opened on.
    fn fit_preview(&self) {
        let display = WidgetExt::display(&self.window);
        let monitor = self
            .window
            .surface()
            .and_then(|s| display.monitor_at_surface(&s))
            .or_else(|| display.monitors().item(0).and_downcast::<gdk::Monitor>());
        let width = monitor.map(|m| m.geometry().width()).unwrap_or(1920) as f64;
        let w = (width * PREVIEW_SHARE).round() as i32;
        self.backdrop.set_size_request(w, (w as f64 * 10.0 / 16.0).round() as i32);
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
        self.details.set_markup(&parts.join(" · "));
        self.details.set_visible(!parts.is_empty());
        self.halves.set_visible(wall.dark.is_some());
        let dark = self.shown_dark(i);
        let light_class = if dark { "prisme-half" } else { "prisme-half-on" };
        let dark_class = if dark { "prisme-half-on" } else { "prisme-half" };
        self.light.set_css_classes(&[light_class]);
        self.dark.set_css_classes(&[dark_class]);
    }

    fn refresh_bottom(&self) {
        let total = self.walls.len();
        if total > 0 {
            self.position
                .set_markup(&format!("<span foreground=\"{INK}\">{}</span> / {total}", self.focus.get() + 1));
        }
        let dynamic = self.mode.get() == Mode::Dynamic;
        self.picked.set_visible(dynamic);
        if dynamic {
            let n = (0..self.carousel.len()).filter_map(|i| self.card(i)).filter(|c| c.is_selected()).count();
            self.picked.set_markup(&format!(
                "{n} picked · every <span foreground=\"{INK}\">{}</span>",
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
        let len = self.walls.len() as i64;
        let previous = self.focus.replace(i) as i64;
        if len > 0 {
            // Signed step on the ring, wrapping the short way round.
            let diff = (i as i64 - previous).rem_euclid(len);
            if diff != 0 {
                self.direction.set(if diff <= len / 2 { 1 } else { -1 });
            }
        }
        self.peek.set(false);
        // The card left behind closes back to the scheme's half.
        for j in [previous as usize, i] {
            if let Some(card) = self.card(j) {
                card.set_shown_dark(self.shown_dark(j), false);
            }
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
        if let Some(thumb) = self.card(i).and_then(|c| c.texture(key.1)) {
            self.backdrop.show(thumb);
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

    /// Decodes the next card in the direction of travel ahead of time.
    fn preload(&self, generation: u64) {
        let len = self.walls.len() as i64;
        if len < 2 {
            return;
        }
        let next = (self.focus.get() as i64 + self.direction.get()).rem_euclid(len) as usize;
        let key = self.key(next);
        if self.sharp.borrow().iter().any(|(k, _)| *k == key) {
            return;
        }
        if let Some(path) = self.path(key) {
            self.preview.request(generation, key, path, self.screen_size());
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
            self.preload(result.generation);
        }
    }

    /// A thumbnail landed: the focused card's fills in for the preview
    /// until the sharp one is ready, and brings the caption's dimensions.
    fn thumb_ready(&self, i: usize) {
        if i != self.focus.get() {
            return;
        }
        self.refresh_caption();
        if !self.showing_sharp.get() {
            if let Some(thumb) = self.card(i).and_then(|c| c.texture(self.shown_dark(i))) {
                self.backdrop.show(thumb);
            }
        }
    }
}

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

    // ── The panel, centred above the cards: the preview, then its caption
    // and, for a pair, the light/dark toggle.
    let panel = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .css_classes(["prisme-panel"])
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .margin_bottom(PANEL_CLEARANCE_PX)
        .can_target(false)
        .build();
    let backdrop = backdrop::Backdrop::new();
    let legend = gtk4::Box::builder().orientation(gtk4::Orientation::Horizontal).css_classes(["prisme-legend"]).build();
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
    // The pair toggle: the key, then the two halves in a pill.
    let halves = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .css_classes(["prisme-halves"])
        .halign(gtk4::Align::End)
        .valign(gtk4::Align::Center)
        .visible(false)
        .build();
    let key_cap = gtk4::Label::builder().label("C").css_classes(["prisme-key"]).build();
    let pill = gtk4::Box::builder().orientation(gtk4::Orientation::Horizontal).css_classes(["prisme-pill"]).build();
    let light = gtk4::Label::builder().label("Light").css_classes(["prisme-half"]).build();
    let dark = gtk4::Label::builder().label("Dark").css_classes(["prisme-half"]).build();
    pill.append(&light);
    pill.append(&dark);
    halves.append(&key_cap);
    halves.append(&pill);
    caption.append(&name);
    caption.append(&details);
    legend.append(&caption);
    legend.append(&halves);
    panel.append(&backdrop);
    panel.append(&legend);
    overlay.set_child(Some(&panel));

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

    overlay.add_overlay(&carousel);
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
    });

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
            }
        };
        let dark = prefers_dark(&settings);
        ui.scheme_dark.set(dark);
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
    }
    ui.focus.set(initial_index.unwrap_or(0));

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
    {
        let ui = Rc::downgrade(&ui);
        glib::MainContext::default().spawn_local(async move {
            while let Ok(result) = thumb_rx.recv().await {
                let Some(ui) = ui.upgrade() else {
                    continue;
                };
                if let (Some(card), Some(tex)) = (ui.card(result.index), result.texture) {
                    card.set_texture(result.dark, tex, result.orig_width, result.orig_height);
                    ui.thumb_ready(result.index);
                }
            }
        });
    }

    // Indices currently loaded OR being decoded -- avoids re-requesting a
    // card already in the window on every recompute, and serves as the
    // list to walk to unload cards that fall out of it.
    let loaded_thumbs: Rc<RefCell<HashSet<usize>>> = Rc::new(RefCell::new(HashSet::new()));

    let refresh_thumb_window: Rc<dyn Fn(usize)> = {
        let walls = walls.clone();
        let carousel = carousel.clone();
        let loaded_thumbs = loaded_thumbs.clone();
        Rc::new(move |focus: usize| {
            let len = walls.len();
            if len == 0 {
                return;
            }
            let len_f = len as f64;
            // Sorted by distance to the focus (not just filtered) -- the
            // order of THIS vector is the order requests are sent in just
            // below, hence the order thumbs.rs's threads pick them up in:
            // the focused card (and its closest neighbors) must appear
            // first.
            let mut wanted_by_distance: Vec<usize> = (0..len)
                .filter(|&i| carousel::ring_distance(i as f64, focus as f64, len_f) <= THUMB_WINDOW_RADIUS as f64)
                .collect();
            wanted_by_distance.sort_by(|&a, &b| {
                let da = carousel::ring_distance(a as f64, focus as f64, len_f);
                let db = carousel::ring_distance(b as f64, focus as f64, len_f);
                da.total_cmp(&db)
            });
            let wanted: HashSet<usize> = wanted_by_distance.iter().copied().collect();

            let mut loaded = loaded_thumbs.borrow_mut();
            for &i in &wanted_by_distance {
                // `insert` returns true only if the index wasn't already
                // there -- neither loaded nor already queued.
                if loaded.insert(i) {
                    loader.request(i, false, walls[i].path.clone());
                    if let Some(dark) = &walls[i].dark {
                        loader.request(i, true, dark.clone());
                    }
                }
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
        key_controller.connect_key_pressed(move |_, key, _, _| {
            use keymap::Action;
            let (Some(action), Some(ui)) = (keymap.action(key), ui.upgrade()) else {
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
                Action::ToggleHalf if ui.walls.get(ui.focus.get()).is_some_and(|w| w.dark.is_some()) => {
                    ui.peek.set(!ui.peek.get());
                    let i = ui.focus.get();
                    if let Some(card) = ui.card(i) {
                        card.set_shown_dark(ui.shown_dark(i), true);
                    }
                    ui.refresh_caption();
                    ui.show_preview(false);
                }
                Action::Select | Action::Deselect | Action::ToggleHalf => return glib::Propagation::Proceed,
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

    {
        let ui = Rc::downgrade(&ui);
        window.connect_map(move |_| {
            if let Some(ui) = ui.upgrade() {
                ui.fit_preview();
            }
        });
    }

    window.present();
    ui.refresh_caption();
    ui.refresh_bottom();
    ui.show_preview(false);
    ui.flash(HINT_OPEN);
}
