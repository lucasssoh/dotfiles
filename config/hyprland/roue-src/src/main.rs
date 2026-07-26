//! Roue — sélecteur radial générique natif Wayland (GTK4 + layer-shell),
//! façon menu d'arme RPG (appui = ouvre, relâchement ou clic/Entrée =
//! valide). Remplace les menus rofi-power.sh/rofi-performance.sh, sur le
//! même principe que Prisme pour le sélecteur de wallpaper.
//!
//! Un seul binaire pour toutes les roues : `roue <nom>` charge sa
//! définition depuis `~/.config/roue/wheels/<nom>.toml` (cf. config.rs).
//! Ajouter une nouvelle roue plus tard ne demande donc aucun changement de
//! code ici, juste un nouveau fichier TOML et un déclencheur (raccourci,
//! clic waybar...).
//!
//! Le geste "maintien = LB/L1" n'a pas besoin d'IPC maison : `roue <nom>
//! --commit`/`--cancel` est une deuxième invocation du MÊME binaire, routée
//! vers l'instance déjà ouverte par le mécanisme natif de GApplication
//! (activation D-Bus par application-id, avec ApplicationFlags::
//! HANDLES_COMMAND_LINE pour recevoir les arguments de cette deuxième
//! invocation dans le process primaire). Voir keybinds.lua pour le
//! câblage appui (`bind`) / relâchement (`bind ... { release = true }`).

mod actions;
mod color;
mod config;
mod icons;
mod theme;
mod wheel;

use gtk4::gdk;
use gtk4::gio::ApplicationFlags;
use gtk4::prelude::*;
use gtk4::{glib, graphene, Application, ApplicationWindow};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use wheel::RoueWheel;

/// Actions clavier de la roue -- jeu de touches fixe (pas de fichier
/// keymap.conf séparé comme dans Prisme : une seule roue, une interaction
/// volontairement simple, pas besoin d'être reconfigurable par fichier ici).
#[derive(Clone, Copy)]
enum KeyAction {
    Cancel,
    MoveLeft,
    MoveRight,
    Activate,
    Select(usize),
}

/// Résout les noms de touches (convention X11/GDK, cf.
/// prisme-src/src/keymap.rs) en actions -- `gdk::Key::from_name` plutôt que
/// de deviner les identifiants d'enum Rust générés pour les touches chiffres.
fn build_keymap() -> HashMap<gdk::Key, KeyAction> {
    let mut m = HashMap::new();
    let mut bind = |names: &[&str], action: KeyAction| {
        for name in names {
            if let Some(key) = gdk::Key::from_name(*name) {
                m.insert(key, action);
            }
        }
    };
    bind(&["Escape"], KeyAction::Cancel);
    bind(&["Left", "h", "H"], KeyAction::MoveLeft);
    bind(&["Right", "l", "L"], KeyAction::MoveRight);
    bind(&["Return", "KP_Enter", "space"], KeyAction::Activate);
    for (i, name) in ["1", "2", "3", "4", "5", "6", "7", "8", "9"].iter().enumerate() {
        bind(&[name], KeyAction::Select(i));
    }
    m
}

/// Annule sans rien exécuter -- depuis un sous-menu de confirmation, revient
/// juste à la roue racine ; sinon ferme la fenêtre. Point unique partagé par
/// Échap et le clic droit (cf. leurs deux appelants) pour que les deux
/// gestes restent garantis identiques.
fn cancel(wheel: &RoueWheel, window: &ApplicationWindow) {
    if wheel.is_confirming() {
        wheel.cancel_confirm();
    } else {
        window.close();
    }
}

/// État de l'unique fenêtre ouverte (au plus une, quel que soit le nom de
/// roue) -- lu/écrit depuis `connect_command_line`, aussi bien pour la
/// construction initiale que pour router `--commit`/`--cancel` d'une
/// invocation secondaire.
type State = Rc<RefCell<Option<(ApplicationWindow, RoueWheel)>>>;

fn main() -> glib::ExitCode {
    // Contrairement à Prisme (qui force "opengl" -- carrousel de ~25 photos
    // haute résolution, le logiciel y décrochait franchement) : la roue ne
    // dessine que quelques polygones plats et une poignée de petites
    // textures d'icônes, un contenu bien trop simple pour justifier le coût
    // mémoire d'un contexte GL -- mesuré à ~182 Mo de RSS stabilisé en
    // "opengl" contre ~68 Mo en "cairo" (logiciel), sans différence de
    // fluidité perceptible vu la faible complexité de la scène. On respecte
    // une valeur déjà définie par l'environnement (debug, autre machine...).
    if std::env::var_os("GSK_RENDERER").is_none() {
        std::env::set_var("GSK_RENDERER", "cairo");
    }

    let wheel_name = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: roue <wheel-name> [--commit|--cancel]");
        std::process::exit(1);
    });

    // Un application-id par roue (pas un seul "com.roue.app" partagé) :
    // `roue power --commit` doit être routé vers l'instance `roue power`
    // déjà ouverte, jamais vers une roue `powerprofile` qui tournerait en
    // même temps -- chacune est un process GApplication indépendant.
    let app_id = format!("com.roue.{wheel_name}");
    let app = Application::new(Some(&app_id), ApplicationFlags::HANDLES_COMMAND_LINE);

    let state: State = Rc::new(RefCell::new(None));

    {
        let state = state.clone();
        app.connect_command_line(move |app, cmdline| {
            // `cmdline.arguments()` donne les arguments de CETTE invocation
            // précise (la primaire à l'ouverture, ou celle forwardée par
            // D-Bus depuis une invocation secondaire pendant que la roue est
            // déjà ouverte) -- jamais un mélange des deux.
            let args: Vec<String> = cmdline
                .arguments()
                .into_iter()
                .map(|a| a.to_string_lossy().into_owned())
                .collect();
            let control = args.iter().skip(2).find_map(|a| match a.as_str() {
                "--commit" => Some(true),
                "--cancel" => Some(false),
                _ => None,
            });

            // Cloné hors du RefCell (Ref/RefMut sur des wrapper GObject,
            // donc juste un refcount de plus) avant de brancher : sinon le
            // Ref emprunté par `state.borrow()` reste vivant jusqu'à la fin
            // du if/else (y compris dans la branche `else`, qui elle a
            // besoin d'emprunter `state` en écriture via build_ui) --
            // panique `already borrowed` sinon, vérifié en lançant le
            // binaire en conditions réelles.
            let existing = state.borrow().clone();
            if let Some((window, wheel)) = existing {
                match control {
                    // Relâchement de touche (bindr) : valide le secteur
                    // survolé (ou annule, si rien n'a été visé -- cf.
                    // wheel.rs::activate_hovered). Si c'était un secteur
                    // `confirm`, ça bascule juste sur Confirmer/Annuler (la
                    // fenêtre reste ouverte, activate_hovered renvoie
                    // false).
                    Some(true) => {
                        if wheel.activate_hovered() {
                            window.close();
                        }
                    }
                    Some(false) => {
                        cancel(&wheel, &window);
                    }
                    // Deuxième appui simple (pas notre relâchement) pendant
                    // que la roue est déjà ouverte -- ramène juste la
                    // fenêtre au premier plan (comme Prisme, cf. sa doc).
                    None => window.present(),
                }
            } else {
                build_ui(app, &wheel_name, &state);
            }
            0
        });
    }

    app.run()
}

/// Construit la fenêtre layer-shell plein écran et la roue, puis branche
/// souris/clavier. Appelé une seule fois par process (garde dans
/// `connect_command_line`).
fn build_ui(app: &Application, wheel_name: &str, state: &State) {
    let cfg = config::load(wheel_name);

    let window = ApplicationWindow::new(app);
    window.add_css_class("background");

    window.init_layer_shell();
    window.set_namespace("roue");
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_exclusive_zone(-1);
    for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
        window.set_anchor(edge, true);
    }
    if let Some(display) = gtk4::gdk::Display::default() {
        theme::load(&display, wheel_name);
    }

    // Bloc roue + panneau latéral centré comme un tout sur l'écran -- Box
    // horizontal SANS hexpand/vexpand (contrairement à l'ancien layout
    // vertical) : en enfant unique d'une fenêtre plein écran, il reçoit de
    // toute façon le rectangle complet (comportement "bin" standard d'une
    // GtkWindow), c'est son propre halign/valign=Center qui le positionne
    // à SA taille naturelle (roue 520px + espacement + largeur du panneau)
    // au milieu de ce rectangle, plutôt que de l'étirer.
    let root = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(28)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .build();

    // Contrepoids invisible, MÊME largeur que le panneau (cf. size_group
    // plus bas) -- sans lui, c'est le bloc [roue+panneau] dans son
    // ENSEMBLE qui est centré, donc la roue elle-même se retrouve décalée
    // à gauche du centre écran d'exactement la moitié de la largeur du
    // panneau. Avec ce contrepoids du même côté opposé, la roue redevient
    // le milieu géométrique du root, quelle que soit la largeur du panneau
    // (donc quel que soit le texte -- "Power" vs "Power profile" n'ont pas
    // la même largeur naturelle).
    let counterweight = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
    root.append(&counterweight);

    let wheel = RoueWheel::new(cfg.segments);
    root.append(&wheel);

    // Panneau latéral -- titre + rappel des commandes, aligné sur le centre
    // vertical de la roue (valign=Center) plutôt qu'en pied de page.
    let sidebar = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .spacing(10)
        .valign(gtk4::Align::Center)
        .css_classes(["roue-sidebar"])
        .build();
    let title = gtk4::Label::builder()
        .label(&cfg.title)
        .css_classes(["roue-title"])
        .halign(gtk4::Align::Start)
        .build();
    sidebar.append(&title);
    let hint = gtk4::Label::builder()
        .label("Mouse / ←→  aim\nEnter / click  confirm\nEsc / right-click  cancel")
        .css_classes(["roue-hint"])
        .halign(gtk4::Align::Start)
        .justify(gtk4::Justification::Left)
        .build();
    sidebar.append(&hint);
    root.append(&sidebar);

    // Force le contrepoids à toujours rapporter la même largeur naturelle
    // que le panneau (peu importe son contenu) -- c'est ce qui rend le
    // centrage de la roue exact plutôt qu'une valeur en dur qui se
    // désynchroniserait au moindre changement de titre/police.
    let width_group = gtk4::SizeGroup::new(gtk4::SizeGroupMode::Horizontal);
    width_group.add_widget(&counterweight);
    width_group.add_widget(&sidebar);

    window.set_child(Some(&root));

    // Survol souris : attaché à la FENÊTRE entière (pas juste au widget de
    // la roue) -- viser ne doit pas obliger à garder le curseur dans le
    // petit disque de la roue à l'écran, seul l'ANGLE depuis son centre
    // compte (cf. wheel.rs::hover_from_point, qui ignore déjà la distance
    // une fois hors zone morte). Un aller-retour vers le bord de l'écran
    // reste donc "viser tout droit dans cette direction", comme un stick
    // analogique dont on pousserait le curseur au-delà de sa course.
    // Coordonnées reçues relatives à `window` (widget auquel le contrôleur
    // est attaché) -- traduites vers le repère de `wheel` (son propre
    // coin haut-gauche) avant l'appel, seul repère que hover_from_point
    // connaît ; rien d'autre ne change, la zone morte et le calcul d'angle
    // restent identiques.
    let motion = gtk4::EventControllerMotion::new();
    let wheel_for_motion = wheel.clone();
    let window_for_motion = window.clone();
    motion.connect_motion(move |_, x, y| {
        let point = graphene::Point::new(x as f32, y as f32);
        if let Some(translated) = window_for_motion.compute_point(&wheel_for_motion, &point) {
            wheel_for_motion.hover_from_point(translated.x() as f64, translated.y() as f64);
        }
    });
    window.add_controller(motion);

    // Clic gauche : même raisonnement que le survol, valide le secteur
    // survolé depuis n'importe où sur l'écran plutôt que seulement en
    // cliquant pile sur la roue. Restreint au bouton primaire -- SANS ça,
    // GestureClick écoute tous les boutons par défaut (button=0), et le
    // clic droit ci-dessous finirait aussi par valider avant même
    // d'atteindre son propre contrôleur.
    let click = gtk4::GestureClick::new();
    click.set_button(gdk::BUTTON_PRIMARY);
    let wheel_for_click = wheel.clone();
    let window_for_click = window.clone();
    click.connect_pressed(move |_, _, _, _| {
        if wheel_for_click.activate_hovered() {
            window_for_click.close();
        }
    });
    window.add_controller(click);

    // Clic droit : équivalent souris d'Échap -- ferme la roue (ou revient à
    // la roue racine depuis un sous-menu de confirmation) sans jamais rien
    // valider, quel que soit le secteur survolé.
    let right_click = gtk4::GestureClick::new();
    right_click.set_button(gdk::BUTTON_SECONDARY);
    let wheel_for_right_click = wheel.clone();
    let window_for_right_click = window.clone();
    right_click.connect_pressed(move |_, _, _, _| {
        cancel(&wheel_for_right_click, &window_for_right_click);
    });
    window.add_controller(right_click);

    // Seul point où une action est réellement lancée -- jamais appelé pour
    // un secteur `confirm` tant qu'il n'a pas été validé une seconde fois
    // (cf. wheel.rs::activate_hovered). La fermeture de fenêtre est gérée
    // par chaque appelant d'activate_hovered() via sa valeur de retour, pas
    // ici -- ce callback ne fait que le côté effet de bord (lancer
    // l'action), jamais la gestion du cycle de vie de la fenêtre.
    wheel.connect_commit(move |seg| {
        actions::run(&seg.action);
    });

    let keymap = build_keymap();
    let key_controller = gtk4::EventControllerKey::new();
    let window_for_key = window.clone();
    let wheel_for_key = wheel.clone();
    key_controller.connect_key_pressed(move |_, key, _, _| {
        let Some(action) = keymap.get(&key).copied() else {
            return glib::Propagation::Proceed;
        };
        match action {
            KeyAction::Cancel => cancel(&wheel_for_key, &window_for_key),
            KeyAction::MoveLeft => wheel_for_key.move_hover(-1),
            KeyAction::MoveRight => wheel_for_key.move_hover(1),
            KeyAction::Activate => {
                if wheel_for_key.activate_hovered() {
                    window_for_key.close();
                }
            }
            KeyAction::Select(i) => wheel_for_key.set_hover_index(i),
        }
        glib::Propagation::Stop
    });
    window.add_controller(key_controller);

    *state.borrow_mut() = Some((window.clone(), wheel));
    window.present();
}
