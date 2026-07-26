//! Prisme — sélecteur de wallpaper natif Wayland (GTK4 + layer-shell),
//! remplaçant l'ancien menu rofi (scripts/set_wallpaper.sh). Une seule
//! fenêtre plein écran présente un carrousel de vignettes (carousel.rs,
//! card.rs) ; le choix est appliqué via awww/systemd en réutilisant le
//! même format d'état que les scripts bash historiques (apply.rs).

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
use std::rc::Rc;

const APP_ID: &str = "com.prisme.app";

/// Bornes de la durée du diaporama (secondes) réglable au scroll sur la
/// puce d'en-tête -- cf. `duration_chip` dans `build_ui`.
const DURATION_MIN: u32 = 5;
const DURATION_MAX: u32 = 3600;
const DURATION_STEP: u32 = 10;

/// Chaînes d'interface -- anglais fixe (pas de détection de langue système,
/// cf. keymap.rs pour le même choix côté raccourcis) plutôt que la
/// détection de locale qu'il y avait ici auparavant : simplifie le code et
/// reste cohérent avec le reste du dépôt (roue-src, scripts d'install).
const MODE_STATIC: &str = "Static";
const MODE_DYNAMIC: &str = "Slideshow";
const FOOTER_HINT: &str = "Esc close · ← → h l navigate · ↓ j select · ↑ k deselect · Tab mode · Enter apply";

/// Libellé du compteur de sélection dans la barre du bas.
fn selected_count(n: usize) -> String {
    format!("{n} selected")
}

/// Mode d'application du wallpaper choisi, cf. apply.rs : image fixe
/// unique, ou diaporama tournant sur une sélection de plusieurs images.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Static,
    Dynamic,
}

/// Point d'entrée : force le rendu GPU puis délègue la construction de
/// l'unique fenêtre à `build_ui` à chaque activation de la GApplication.
fn main() -> glib::ExitCode {
    // Sans ça, GSK choisit ici un rendu logiciel de repli, invisible dans
    // les logs sauf via GDK_DEBUG=opengl (aucune ligne EGL/GL n'apparaît) --
    // mesuré à ~25-40fps en carrousel, décroissant, contre ~120fps+ (montée
    // en charge continue vers le taux de rafraîchissement de l'écran, cf.
    // carousel.rs) une fois le rendu GPU forcé. On respecte une valeur déjà
    // définie par l'environnement (debug, autre machine, etc.).
    if std::env::var_os("GSK_RENDERER").is_none() {
        std::env::set_var("GSK_RENDERER", "opengl");
    }

    let app = Application::new(Some(APP_ID), ApplicationFlags::empty());
    app.connect_activate(build_ui);
    app.run()
}

/// Construit la fenêtre layer-shell plein écran, son carrousel de
/// wallpapers, l'en-tête/pied de page, et branche les raccourcis clavier
/// et le chargement asynchrone des vignettes.
fn build_ui(app: &Application) {
    // GApplication réactive l'instance déjà en cours plutôt que d'en
    // relancer une nouvelle (ex. Super+W pressé deux fois avant que la
    // première fenêtre soit fermée) -- sans cette garde, `connect_activate`
    // rappellerait `build_ui` et empilerait une deuxième fenêtre/carrousel
    // (donc une deuxième boucle d'animation) dans le même process.
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

    // ── En-tête : compteur de sélection + puce de durée -- diaporama
    // seul, la barre entière est masquée en mode Statique (cf.
    // `toggle_mode`). Titre et bouton de mode vivent dans le pied de page
    // (cf. plus bas) : indépendants de cette barre, ils ne bougent jamais
    // quand son contenu apparaît/disparaît.
    let header = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(16)
        .css_classes(["prisme-header"])
        .visible(false)
        .build();

    // Pousse compteur + durée contre le bord droit.
    let header_spacer = gtk4::Box::builder().hexpand(true).build();
    header.append(&header_spacer);

    let counter_label = gtk4::Label::builder()
        .css_classes(["prisme-hint"])
        .label(selected_count(0))
        .build();
    header.append(&counter_label);

    // Puce de durée -- pas de champ texte à cliquer/taper : molette dessus
    // pour ajuster (même vocabulaire d'interaction que la molette du
    // carrousel juste en dessous), le tout tient en une puce discrète.
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

    // ── Point d'ancrage du carrousel ──────────────────────────────────
    let carousel_mount = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .hexpand(true)
        .vexpand(true)
        .build();
    root.append(&carousel_mount);

    // ── Pied de page : titre à gauche, rappel clavier au centre, bouton
    // de mode à droite -- tous les trois plaqués aux bords, indépendants
    // du contenu de l'en-tête du dessus (cf. sa doc).
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
    // Un GtkButton focusable intercepterait Entrée/Espace pour s'auto-
    // activer (donc basculer le mode) avant même que notre
    // EventControllerKey ne voie l'évènement -- c'est ce qui faisait dire
    // "Entrée" alors qu'on voulait "activer la carte" : le bouton était le
    // widget focus par défaut de la fenêtre et volait la touche.
    mode_toggle.set_can_focus(false);
    footer.append(&mode_toggle);

    root.append(&footer);

    window.set_child(Some(&root));

    // ── État partagé ────────────────────────────────────────────────
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

    // Construit le carrousel -- appelé une seule fois (plus de bascule de
    // source à gérer, toujours Images/Wallpapers).
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

        // Ouvre directement sur le dernier fond appliqué en Statique
        // (indépendant du mode courant -- passer en Diaporama ne doit pas
        // faire perdre ce repère, cf. apply::last_static) plutôt que sur la
        // première carte de la liste.
        let initial_index = apply::last_static().and_then(|name| walls.iter().position(|w| w.name == name));
        if let Some(index) = initial_index {
            new_carousel.set_focus_index(index);
        }

        // Vignettes en arrière-plan (thumbs.rs) -- ne bloque pas
        // l'affichage sur le décodage de toute la collection. Chargées à
        // partir de la carte initialement au focus et en éventail vers les
        // deux côtés (même notion de distance que l'entrée en cascade, cf.
        // carousel::ring_distance) : c'est elle qu'on regarde en premier,
        // donc elle doit être la première à afficher sa vraie image plutôt
        // que de suivre l'ordre alphabétique brut.
        let focus_origin = initial_index.unwrap_or(0) as f64;
        let len_f = walls.len() as f64;
        let mut thumb_paths: Vec<(usize, std::path::PathBuf)> = walls
            .iter()
            .enumerate()
            .map(|(i, w)| (i, w.path.clone()))
            .collect();
        thumb_paths.sort_by(|(i, _), (j, _)| {
            let di = carousel::ring_distance(*i as f64, focus_origin, len_f);
            let dj = carousel::ring_distance(*j as f64, focus_origin, len_f);
            di.total_cmp(&dj)
        });
        let rx = thumbs::spawn_loader(thumb_paths);
        let carousel_for_thumbs = new_carousel.clone();
        glib::MainContext::default().spawn_local(async move {
            while let Ok(result) = rx.recv().await {
                if let Some(card) = carousel_for_thumbs.card_at(result.index) {
                    if let Some(tex) = result.texture {
                        card.set_texture(tex, result.orig_width, result.orig_height);
                    }
                }
            }
        });

        // Entrée / clic sur la carte déjà focus : applique selon le mode
        // courant, comme les étapes 5 (dynamique) et 21 (statique) de
        // scripts/set_wallpaper.sh (cf. apply.rs).
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
                        // Rien sélectionné -- diaporama sur toute la
                        // source, comme le fallback de set_wallpaper.sh
                        // quand $CHOSEN est vide.
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

    // ── Bouton/Tab : bascule Statique ⇄ Diaporama -- juste un changement
    // d'état + visibilité, jamais de rebuild (la source ne change pas) ───
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
                    // La sélection change la hauteur allouée à la carte
                    // (cf. carousel.rs) -- il faut redemander un allocate
                    // explicitement ici : le tick loop ne le fait plus tout
                    // seul une fois posé (cf. sa doc), pour ne pas coûter
                    // un relayout complet à chaque frame sans raison.
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
