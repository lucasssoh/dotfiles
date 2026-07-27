//! Prisme — native Wayland wallpaper picker (GTK4 + layer-shell),
//! replacing the old rofi menu (scripts/set_wallpaper.sh). A single
//! fullscreen window presents a carousel of thumbnails (carousel.rs,
//! card.rs); the choice is applied via awww/systemd, reusing the same
//! state format as the historical bash scripts (apply.rs).

mod apply;
mod card;
mod carousel;
mod keymap;
mod theme;
mod thumbs;
mod wallpapers;

use gtk4::gio::ApplicationFlags;
use gtk4::prelude::*;
use gtk4::{glib, Application};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::rc::Rc;

const APP_ID: &str = "com.prisme.app";

/// Bounds of the slideshow duration (seconds), adjustable by scrolling on
/// the header chip -- see `duration_chip` in `build_ui`.
const DURATION_MIN: u32 = 5;
const DURATION_MAX: u32 = 3600;
const DURATION_STEP: u32 = 10;

/// Radius (in number of cards, on the ring) of the thumbnail window kept
/// LOADED around the focus -- beyond it, the texture is freed (see
/// `Card::clear_texture`), reloaded on demand if focus comes back to it
/// (see `refresh_thumb_window` in `build_ui`). Chosen generously compared
/// to what actually fits on screen (~13 cards on each side on a 2560px
/// monitor, see `carousel.rs::visible_margin`) to leave headroom for fast
/// scrolling without visible "pop-in", while still keeping the memory
/// peak bounded (2×24+1 ≈ 49 thumbnails max in memory, versus the WHOLE
/// collection before this rewrite -- hundreds for a large library).
const THUMB_WINDOW_RADIUS: i64 = 24;

/// Interface strings -- fixed English (no system language detection, see
/// keymap.rs for the same choice on the shortcuts side) rather than the
/// locale detection that used to live here: simplifies the code and stays
/// consistent with the rest of the repo (roue-src, install scripts).
const MODE_STATIC: &str = "Static";
const MODE_DYNAMIC: &str = "Slideshow";
const FOOTER_HINT: &str = "Esc close · ← → h l navigate · ↓ j select · ↑ k deselect · Tab mode · Enter apply";

/// Label for the selection counter in the bottom bar.
fn selected_count(n: usize) -> String {
    format!("{n} selected")
}

/// Mode used to apply the chosen wallpaper, see apply.rs: a single static
/// image, or a slideshow cycling through a selection of several images.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Static,
    Dynamic,
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

/// Builds the fullscreen layer-shell window, its wallpaper carousel,
/// header/footer, and wires up keyboard shortcuts and asynchronous
/// thumbnail loading.
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

    window.init_layer_shell();
    window.set_namespace("prisme");
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_exclusive_zone(-1);
    for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
        window.set_anchor(edge, true);
    }
    if let Some(display) = gtk4::gdk::Display::default() {
        theme::load(&display);
    }

    let root = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .hexpand(true)
        .vexpand(true)
        .build();

    // ── Header: selection counter + duration chip -- Dynamic mode only,
    // the whole bar is hidden in Static mode (see `toggle_mode`). Title
    // and mode button live in the footer (see below): independent of
    // this bar, they never move when its content appears/disappears.
    let header = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(16)
        .css_classes(["prisme-header"])
        .visible(false)
        .build();

    // Pushes counter + duration against the right edge.
    let header_spacer = gtk4::Box::builder().hexpand(true).build();
    header.append(&header_spacer);

    let counter_label = gtk4::Label::builder()
        .css_classes(["prisme-hint"])
        .label(selected_count(0))
        .build();
    header.append(&counter_label);

    // Duration chip -- no text field to click/type into: scroll on it to
    // adjust (same interaction vocabulary as the carousel's scroll just
    // below), all packed into a discreet chip.
    let duration = Rc::new(Cell::new(120u32));
    let duration_chip = gtk4::Label::builder()
        .css_classes(["prisme-duration-chip"])
        .label(format!("{}s", duration.get()))
        .build();
    {
        let duration = duration.clone();
        let chip_for_scroll = duration_chip.clone();
        let scroll = gtk4::EventControllerScroll::new(gtk4::EventControllerScrollFlags::BOTH_AXES);
        scroll.connect_scroll(move |_, dx, dy| {
            let delta = if dx.abs() > dy.abs() { dx } else { dy };
            if delta.abs() < 0.01 {
                return glib::Propagation::Stop;
            }
            let step = if delta > 0.0 { -(DURATION_STEP as i64) } else { DURATION_STEP as i64 };
            let next = (duration.get() as i64 + step).clamp(DURATION_MIN as i64, DURATION_MAX as i64) as u32;
            duration.set(next);
            chip_for_scroll.set_label(&format!("{next}s"));
            glib::Propagation::Stop
        });
        duration_chip.add_controller(scroll);
    }
    header.append(&duration_chip);

    root.append(&header);

    // ── Carousel mount point ───────────────────────────────────────────
    let carousel_mount = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .hexpand(true)
        .vexpand(true)
        .build();
    root.append(&carousel_mount);

    // ── Footer: title on the left, keyboard hint in the center, mode
    // button on the right -- all three pinned to the edges, independent
    // of the header's content above (see its doc).
    let footer = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(16)
        .css_classes(["prisme-footer"])
        .build();

    let title = gtk4::Label::builder()
        .label("Prisme")
        .css_classes(["prisme-title"])
        .halign(gtk4::Align::Start)
        .build();
    footer.append(&title);

    let hint_label = gtk4::Label::builder()
        .label(FOOTER_HINT)
        .css_classes(["prisme-hint"])
        .halign(gtk4::Align::Center)
        .hexpand(true)
        .build();
    footer.append(&hint_label);

    let mode_toggle = gtk4::ToggleButton::builder()
        .label(MODE_STATIC)
        .css_classes(["prisme-mode-toggle"])
        .halign(gtk4::Align::End)
        .build();
    // A focusable GtkButton would intercept Enter/Space to self-activate
    // (thus toggling the mode) before our EventControllerKey ever saw the
    // event -- this is what made "Enter" toggle the mode when the intent
    // was "activate the card": the button was the window's default focus
    // widget and stole the key.
    mode_toggle.set_can_focus(false);
    footer.append(&mode_toggle);

    root.append(&footer);

    window.set_child(Some(&root));

    // ── Shared state ────────────────────────────────────────────────
    let mode = Rc::new(Cell::new(Mode::Static));
    let current_carousel: Rc<RefCell<Option<carousel::Carousel>>> = Rc::new(RefCell::new(None));

    let update_counter = {
        let current_carousel = current_carousel.clone();
        let counter_label = counter_label.clone();
        Rc::new(move || {
            if let Some(c) = current_carousel.borrow().as_ref() {
                let n = (0..c.len())
                    .filter_map(|i| c.card_at(i))
                    .filter(|card| card.is_selected())
                    .count();
                counter_label.set_label(&selected_count(n));
            }
        })
    };

    // Builds the carousel -- called once (no more source switching to
    // handle, always Images/Wallpapers).
    {
        let carousel_mount = carousel_mount.clone();
        let current_carousel = current_carousel.clone();
        let counter_label = counter_label.clone();
        let mode = mode.clone();
        let duration = duration.clone();
        let window = window.clone();

        let source_dir = wallpapers::originals_dir();
        let walls = wallpapers::scan(&source_dir);
        let cards: Vec<card::Card> = walls.iter().map(|w| card::Card::new(w.clone())).collect();
        let new_carousel = carousel::Carousel::new(cards);
        carousel_mount.append(&new_carousel);

        // Opens directly on the last wallpaper applied in Static mode
        // (independent of the current mode -- switching to Dynamic must
        // not lose this reference point, see apply::last_static) rather
        // than the first card in the list.
        let initial_index = apply::last_static().and_then(|name| walls.iter().position(|w| w.name == name));
        if let Some(index) = initial_index {
            new_carousel.set_focus_index(index);
        }

        // Thumbnails in the background (thumbs.rs) -- doesn't block
        // display on decoding. Only the window around the focus (see
        // THUMB_WINDOW_RADIUS) is requested, not the whole collection:
        // `refresh_thumb_window` decides what to load/unload, called once
        // here for the initial position then on every interactive focus
        // change (see connect_target_changed below).
        let (loader, thumb_rx) = thumbs::ThumbLoader::new();
        let carousel_for_thumbs = new_carousel.clone();
        glib::MainContext::default().spawn_local(async move {
            while let Ok(result) = thumb_rx.recv().await {
                if let Some(card) = carousel_for_thumbs.card_at(result.index) {
                    if let Some(tex) = result.texture {
                        card.set_texture(tex, result.orig_width, result.orig_height);
                    }
                }
            }
        });

        // Indices currently loaded OR being decoded -- avoids
        // re-requesting a card already in the window on every recompute,
        // and serves as the list to walk to unload cards that fall out of
        // it.
        let loaded_thumbs: Rc<RefCell<HashSet<usize>>> = Rc::new(RefCell::new(HashSet::new()));

        let refresh_thumb_window: Rc<dyn Fn(usize)> = {
            let walls = walls.clone();
            let carousel = new_carousel.clone();
            let loaded_thumbs = loaded_thumbs.clone();
            let loader = loader.clone();
            Rc::new(move |focus: usize| {
                let len = walls.len();
                if len == 0 {
                    return;
                }
                let len_f = len as f64;
                // Sorted by distance to the focus (not just filtered) --
                // the order of THIS vector is the order requests are sent
                // in just below, hence the order thumbs.rs's WORKER_COUNT
                // threads pick them up in: the focused card (and its
                // closest neighbors) must appear first, not in an order
                // dependent on a HashSet's hashing or the source folder's
                // raw alphabetical sort.
                let mut wanted_by_distance: Vec<usize> = (0..len)
                    .filter(|&i| {
                        carousel::ring_distance(i as f64, focus as f64, len_f)
                            <= THUMB_WINDOW_RADIUS as f64
                    })
                    .collect();
                wanted_by_distance.sort_by(|&a, &b| {
                    let da = carousel::ring_distance(a as f64, focus as f64, len_f);
                    let db = carousel::ring_distance(b as f64, focus as f64, len_f);
                    da.total_cmp(&db)
                });
                let wanted: HashSet<usize> = wanted_by_distance.iter().copied().collect();

                let mut loaded = loaded_thumbs.borrow_mut();
                for &i in &wanted_by_distance {
                    // `insert` returns true only if the index wasn't
                    // already there -- neither loaded nor already queued.
                    if loaded.insert(i) {
                        loader.request(i, walls[i].path.clone());
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
        refresh_thumb_window(initial_index.unwrap_or(0));
        {
            let refresh_thumb_window = refresh_thumb_window.clone();
            new_carousel.connect_target_changed(move |focus| refresh_thumb_window(focus));
        }

        // Enter / click on the already-focused card: applies according to
        // the current mode, like steps 5 (dynamic) and 21 (static) of
        // scripts/set_wallpaper.sh (see apply.rs).
        {
            let mode = mode.clone();
            let duration = duration.clone();
            let window = window.clone();
            let carousel_for_activate = new_carousel.clone();
            new_carousel.connect_activate(move |index| {
                let source_dir = wallpapers::originals_dir();
                match mode.get() {
                    Mode::Static => {
                        if let Some(card) = carousel_for_activate.card_at(index) {
                            apply::apply_static(
                                &source_dir,
                                &card.wallpaper().path,
                                &card.wallpaper().name,
                            );
                        }
                    }
                    Mode::Dynamic => {
                        let selected: Vec<String> = (0..carousel_for_activate.len())
                            .filter_map(|i| carousel_for_activate.card_at(i))
                            .filter(|c| c.is_selected())
                            .map(|c| c.wallpaper().name.clone())
                            .collect();
                        // Nothing selected -- slideshow over the whole
                        // source, like set_wallpaper.sh's fallback when
                        // $CHOSEN is empty.
                        let walls = if selected.is_empty() {
                            (0..carousel_for_activate.len())
                                .filter_map(|i| carousel_for_activate.card_at(i))
                                .map(|c| c.wallpaper().name.clone())
                                .collect()
                        } else {
                            selected
                        };
                        apply::apply_dynamic(&source_dir, duration.get(), &walls);
                    }
                }
                window.close();
            });
        }

        counter_label.set_label(&selected_count(0));
        *current_carousel.borrow_mut() = Some(new_carousel);
    }

    // ── Button/Tab: toggles Static ⇄ Dynamic -- just a state + visibility
    // change, never a rebuild (the source doesn't change) ───────────────
    let toggle_mode: Rc<dyn Fn()> = {
        let mode = mode.clone();
        let mode_toggle = mode_toggle.clone();
        let header = header.clone();
        Rc::new(move || {
            let next = if mode.get() == Mode::Static {
                Mode::Dynamic
            } else {
                Mode::Static
            };
            mode.set(next);
            let dynamic = next == Mode::Dynamic;
            mode_toggle.set_active(dynamic);
            mode_toggle.set_label(if dynamic { MODE_DYNAMIC } else { MODE_STATIC });
            header.set_visible(dynamic);
        })
    };
    {
        let toggle_mode = toggle_mode.clone();
        mode_toggle.connect_clicked(move |_| toggle_mode());
    }

    let keymap = keymap::Keymap::load();
    let key_controller = gtk4::EventControllerKey::new();
    let window_for_key = window.clone();
    key_controller.connect_key_pressed(move |_, key, _, _| {
        use keymap::Action;
        let Some(action) = keymap.action(key) else {
            return glib::Propagation::Proceed;
        };
        match action {
            Action::Close => {
                window_for_key.close();
            }
            Action::MoveLeft => {
                if let Some(c) = current_carousel.borrow().as_ref() {
                    c.move_focus(-1);
                }
            }
            Action::MoveRight => {
                if let Some(c) = current_carousel.borrow().as_ref() {
                    c.move_focus(1);
                }
            }
            Action::Activate => {
                if let Some(c) = current_carousel.borrow().as_ref() {
                    c.activate_focused();
                }
            }
            Action::ToggleMode => toggle_mode(),
            Action::Select if mode.get() == Mode::Dynamic => {
                if let Some(c) = current_carousel.borrow().as_ref() {
                    let idx = c.focused_index();
                    if let Some(card) = c.card_at(idx) {
                        card.set_selected(true);
                    }
                    // Selection changes the card's allocated height (see
                    // carousel.rs) -- an allocate must be explicitly
                    // requested here: the tick loop no longer does it on
                    // its own once settled (see its doc), so as not to
                    // cost a full relayout every frame for no reason.
                    c.queue_allocate();
                }
                update_counter();
            }
            Action::Deselect if mode.get() == Mode::Dynamic => {
                if let Some(c) = current_carousel.borrow().as_ref() {
                    let idx = c.focused_index();
                    if let Some(card) = c.card_at(idx) {
                        card.set_selected(false);
                    }
                    c.queue_allocate();
                }
                update_counter();
            }
            Action::Select | Action::Deselect => return glib::Propagation::Proceed,
        }
        glib::Propagation::Stop
    });
    window.add_controller(key_controller);

    window.present();
}
