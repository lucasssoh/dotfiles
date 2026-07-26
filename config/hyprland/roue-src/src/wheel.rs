//! Widget `RoueWheel` : la roue de sélection radiale elle-même (dessin,
//! survol souris/clavier, animation, confirmation). Générique sur la liste
//! de secteurs reçue à la construction -- aucune connaissance de "power" ou
//! "powerprofile" ici, c'est ce qui permet de réutiliser ce widget tel quel
//! pour toute future roue (cf. config.rs).
//!
//! Dessiné entièrement en GSK (comme card.rs/carousel.rs dans Prisme) :
//! chaque secteur est un polygone échantillonné le long de ses deux arcs
//! (gsk::PathBuilder n'a pas de primitive d'arc dédiée dans cette version),
//! rempli via push_fill/append_color, exactement la même technique que le
//! parallélogramme de card.rs -- juste avec plus de points.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk, pango};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::time::Instant;

use crate::config::Segment;
use crate::icons::{self, IconPair};

/// Vitesse de convergence de l'interpolation exponentielle (ouverture en
/// éventail + surlignage du secteur survolé) -- même valeur et même
/// raisonnement que carousel.rs (~220ms pour converger à 95%, indépendant du
/// taux de rafraîchissement grâce au dt réel du frame clock).
const EASE_RATE: f64 = 14.0;

const WHEEL_SIZE_PX: i32 = 520;
const OUTER_MARGIN_PX: f64 = 24.0;
/// Moyeu plus généreux -- ce qui compacte d'autant la bande occupée par les
/// secteurs entre lui et le bord extérieur (moins de "vide" radial dans
/// chaque secteur, qui ne contient plus qu'un logo).
const INNER_RADIUS_RATIO: f64 = 0.56;
/// Largeur totale (px, mesurée perpendiculairement au rayon de séparation)
/// de l'écart entre deux secteurs -- PAS un angle constant : cf. `wedge_path`
/// pour pourquoi (un angle constant fait converger les deux bords en pointe
/// au centre, ce qu'on veut justement éviter).
const WEDGE_GAP_PX: f64 = 10.0;
const HOVER_RADIUS_BOOST_PX: f64 = 12.0;
/// Rayon (px) autour du centre où le survol souris est ignoré -- évite un
/// angle qui saute de façon erratique quand le curseur passe tout près du
/// centre (atan2(0,0) n'est pas défini de façon stable), même rôle qu'une
/// zone morte de joystick analogique.
const HOVER_DEADZONE_PX: f64 = 28.0;
const ARC_STEPS: usize = 20;
/// Taille d'affichage (px) du logo SVG dans un secteur -- grandit un peu
/// avec `t` au survol, comme l'ancien rendu en glyphe. `ICON_FONT_PX` reste
/// utilisée pour le repli en texte brut (cf. `draw_icon` dans snapshot()) --
/// secteurs de confirmation, ou icône introuvable/invalide.
const ICON_SIZE_PX: f64 = 34.0;
const ICON_HOVER_GROW_PX: f64 = 6.0;
const ICON_FONT_PX: f64 = 32.0;
const HUB_ICON_SIZE_PX: f64 = 46.0;
const HUB_LABEL_FONT_PX: f64 = 15.0;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Wheel {
        /// Secteurs de la roue racine, jamais modifiés après construction --
        /// sert à revenir en arrière quand on quitte le sous-menu de
        /// confirmation (cf. `Wheel::exit_confirm`).
        pub root_segments: RefCell<Vec<Segment>>,
        /// Secteurs effectivement affichés/survolés -- identiques à
        /// `root_segments`, sauf pendant une confirmation où ils valent
        /// temporairement [Confirmer, Annuler].
        pub segments: RefCell<Vec<Segment>>,
        /// Textures rasterisées une fois à la construction (cf.
        /// `RoueWheel::new`), indexées par le champ `icon` des secteurs
        /// RACINE uniquement -- les secteurs synthétiques Confirmer/Annuler
        /// (cf. `enter_confirm`) n'y figurent jamais, `snapshot()` retombe
        /// alors sur un rendu texte brut pour eux (cf. `draw_icon`).
        pub icons: RefCell<HashMap<String, IconPair>>,
        pub hovered: Cell<usize>,
        /// A-t-on visé au moins une fois (souris hors zone morte, flèche,
        /// chiffre) depuis l'ouverture de ce niveau de roue (racine ou
        /// sous-menu de confirmation) -- cf. `activate_hovered` : sans
        /// mouvement, valider n'exécute JAMAIS le secteur par défaut
        /// (index 0), ça annule à la place.
        pub moved: Cell<bool>,
        /// 0 = fermée, 1 = pleinement ouverte -- anime le rayon ET l'alpha
        /// de tout ce qui est dessiné (effet d'éventail à l'ouverture).
        pub open_progress: Cell<f64>,
        /// 0 = secteur survolé pas encore mis en avant, 1 = surlignage
        /// pleinement appliqué -- repart de 0 à chaque changement de
        /// secteur survolé (cf. `set_hover_index`).
        pub hover_anim: Cell<f64>,
        pub confirming: Cell<bool>,
        pub pending: RefCell<Option<Segment>>,
        pub start: Cell<Option<Instant>>,
        pub last_frame_us: Cell<Option<i64>>,
        pub commit_cb: RefCell<Option<Box<dyn Fn(&Segment)>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Wheel {
        const NAME: &'static str = "RoueWheel";
        type Type = super::RoueWheel;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Wheel {}

    impl WidgetImpl for Wheel {
        // Taille fixe et constante (contrairement à Card/Carousel dans
        // Prisme) : rien ici ne change la taille ALLOUÉE au widget d'une
        // frame à l'autre, seul ce qui est dessiné dedans (rayon, alpha)
        // s'anime -- measure() n'a donc pas besoin du contournement
        // "(0,0,-1,-1)" utilisé là-bas pour éviter un queue_resize en boucle.
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (WHEEL_SIZE_PX, WHEEL_SIZE_PX, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let widget = self.obj();
            let w = widget.width() as f64;
            let h = widget.height() as f64;
            if w <= 0.0 || h <= 0.0 {
                return;
            }
            let segments = self.segments.borrow();
            let n = segments.len();
            if n == 0 {
                return;
            }

            let open = self.open_progress.get();
            let cx = w / 2.0;
            let cy = h / 2.0;
            let max_radius = (w.min(h) / 2.0 - OUTER_MARGIN_PX).max(0.0);
            let outer_radius = max_radius * open;
            let inner_radius = max_radius * INNER_RADIUS_RATIO * open;

            let angle_per = std::f64::consts::TAU / n as f64;
            let base = -std::f64::consts::FRAC_PI_2 - angle_per / 2.0;
            let hovered = self.hovered.get();
            let hover_t = self.hover_anim.get() as f32;

            for (i, seg) in segments.iter().enumerate() {
                let t = if i == hovered { hover_t } else { 0.0 };
                // Angles "purs" de la découpe, SANS rognage -- l'écart entre
                // secteurs est désormais géré à largeur constante en pixels
                // à l'intérieur de wedge_path (cf. sa doc), pas en rognant
                // ces angles.
                let angle_left = base + i as f64 * angle_per;
                let angle_right = base + (i + 1) as f64 * angle_per;
                let boost = HOVER_RADIUS_BOOST_PX * t as f64 * open;
                let path = wedge_path(
                    cx,
                    cy,
                    inner_radius,
                    outer_radius + boost,
                    angle_left,
                    angle_right,
                    WEDGE_GAP_PX * open,
                );

                snapshot.push_fill(&path, gsk::FillRule::Winding);
                let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                snapshot.append_color(&wedge_color(t, open as f32), &full);
                snapshot.pop();

                if open <= 0.05 {
                    continue;
                }

                let mid_angle = (angle_left + angle_right) / 2.0;
                let mid_radius = (inner_radius + outer_radius + boost) / 2.0;
                let px = cx + mid_radius * mid_angle.cos();
                let py = cy + mid_radius * mid_angle.sin();

                // Juste le logo dans le secteur -- le libellé texte ne
                // s'affiche qu'au moyeu central (cf. plus bas), pas ici.
                let size = ICON_SIZE_PX + t as f64 * ICON_HOVER_GROW_PX;
                draw_icon(&widget, snapshot, &self.icons.borrow(), &seg.icon, px, py, size, t, open);
            }

            // Moyeu central -- affiche icône + label du secteur actuellement
            // survolé, lecture immédiate du choix en cours (comme le nom
            // d'arme centré dans une roue de jeu).
            if open > 0.02 {
                let hub_path = circle_path(cx, cy, inner_radius);
                snapshot.push_fill(&hub_path, gsk::FillRule::Winding);
                let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                snapshot.append_color(
                    &gdk::RGBA::new(0.078, 0.078, 0.086, (0.88 * open) as f32),
                    &full,
                );
                snapshot.pop();

                if let Some(seg) = segments.get(hovered) {
                    let mut hub_label_font = pango::FontDescription::new();
                    hub_label_font.set_absolute_size(HUB_LABEL_FONT_PX * pango::SCALE as f64);
                    let hub_label = widget.create_pango_layout(Some(&seg.label));
                    hub_label.set_font_description(Some(&hub_label_font));
                    let (lw, lh) = hub_label.pixel_size();

                    // Bloc icône+label vertical -- hauteur d'icône nominale
                    // fixe pour la mise en page (HUB_ICON_SIZE_PX), que le
                    // rendu réel soit une texture SVG ou (repli) un glyphe
                    // Pango d'une taille légèrement différente : ça n'a pas
                    // besoin d'être pixel-parfait pour un repli rare.
                    const GAP: f64 = 6.0;
                    let block_h = HUB_ICON_SIZE_PX + GAP + lh as f64;
                    let icon_cy = cy - block_h / 2.0 + HUB_ICON_SIZE_PX / 2.0;

                    // Toujours en accent plein (t=1) -- c'est le secteur
                    // actuellement retenu, pas un survol animé de plus.
                    draw_icon(
                        &widget,
                        snapshot,
                        &self.icons.borrow(),
                        &seg.icon,
                        cx,
                        icon_cy,
                        HUB_ICON_SIZE_PX,
                        1.0,
                        open,
                    );

                    let label_color = gdk::RGBA::new(0.949, 0.949, 0.969, open as f32);
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new(
                        (cx - lw as f64 / 2.0) as f32,
                        (cy - block_h / 2.0 + HUB_ICON_SIZE_PX + GAP) as f32,
                    ));
                    snapshot.append_layout(&hub_label, &label_color);
                    snapshot.restore();
                }
            }
        }
    }

    impl Wheel {
        pub(super) fn tick(&self, clock: &gdk::FrameClock) {
            let now_us = clock.frame_time();
            let dt = match self.last_frame_us.get() {
                Some(prev) => ((now_us - prev).max(0) as f64 / 1_000_000.0).min(0.1),
                None => 1.0 / 60.0,
            };
            self.last_frame_us.set(Some(now_us));
            if self.start.get().is_none() {
                self.start.set(Some(Instant::now()));
            }

            let op = self.open_progress.get();
            let ha = self.hover_anim.get();
            let op_moving = (1.0 - op).abs() > 0.0005;
            let ha_moving = (1.0 - ha).abs() > 0.0005;
            // Rien à animer -- ne redemande pas de frame, comme
            // carousel.rs::tick (coût quasi nul une fois stabilisé).
            if !op_moving && !ha_moving {
                return;
            }

            let ease = 1.0 - (-EASE_RATE * dt).exp();
            if op_moving {
                let next = op + (1.0 - op) * ease;
                self.open_progress.set(if (1.0 - next).abs() < 0.0005 { 1.0 } else { next });
            }
            if ha_moving {
                let next = ha + (1.0 - ha) * ease;
                self.hover_anim.set(if (1.0 - next).abs() < 0.0005 { 1.0 } else { next });
            }
            self.obj().queue_draw();
        }
    }
}

/// Dessine le logo d'un secteur centré en `(cx, cy)`, carré de côté `size`
/// -- texture SVG pré-rasterisée si `icon_key` en a une dans `icons` (cf.
/// icons.rs), sinon repli en glyphe Pango brut (secteurs de confirmation
/// Confirmer/Annuler, ou icône introuvable/invalide -- cf. `icons::load`).
/// `t` anime un fondu vers la couleur accent au survol (0 = couleur
/// normale, 1 = accent plein) ; `open` multiplie l'alpha (fondu à
/// l'ouverture de la roue).
fn draw_icon(
    widget: &RoueWheel,
    snapshot: &gtk4::Snapshot,
    icons: &HashMap<String, IconPair>,
    icon_key: &str,
    cx: f64,
    cy: f64,
    size: f64,
    t: f32,
    open: f64,
) {
    if let Some(pair) = icons.get(icon_key) {
        let rect = graphene::Rect::new(
            (cx - size / 2.0) as f32,
            (cy - size / 2.0) as f32,
            size as f32,
            size as f32,
        );
        // Texture "normale" en base, texture "accent" fondue par-dessus
        // avec `t` -- crossfade entre deux rasters plutôt qu'une
        // recoloration GPU par color-matrix (cf. icons.rs).
        draw_texture(snapshot, &pair.normal, &rect, open);
        if t > 0.001 {
            draw_texture(snapshot, &pair.accent, &rect, open * t as f64);
        }
        return;
    }

    let color = text_color(t, open as f32);
    let mut font = pango::FontDescription::new();
    font.set_absolute_size((ICON_FONT_PX + t as f64 * 4.0) * pango::SCALE as f64);
    let layout = widget.create_pango_layout(Some(icon_key));
    layout.set_font_description(Some(&font));
    let (iw, ih) = layout.pixel_size();
    snapshot.save();
    snapshot.translate(&graphene::Point::new(
        (cx - iw as f64 / 2.0) as f32,
        (cy - ih as f64 / 2.0) as f32,
    ));
    snapshot.append_layout(&layout, &color);
    snapshot.restore();
}

fn draw_texture(snapshot: &gtk4::Snapshot, texture: &gdk::Texture, rect: &graphene::Rect, alpha: f64) {
    if alpha <= 0.001 {
        return;
    }
    if alpha < 0.999 {
        snapshot.push_opacity(alpha);
        snapshot.append_scaled_texture(texture, gsk::ScalingFilter::Trilinear, rect);
        snapshot.pop();
    } else {
        snapshot.append_scaled_texture(texture, gsk::ScalingFilter::Trilinear, rect);
    }
}

/// Polygone échantillonné approximant un secteur d'anneau (arc extérieur,
/// puis arc intérieur en sens inverse, ou un simple sommet au centre si
/// `inner_r` est ~0) -- même technique que `parallelogram_path` dans
/// card.rs (PathBuilder + move_to/line_to/close), avec un nombre de points
/// fixe (`ARC_STEPS`) plutôt qu'une primitive d'arc dédiée.
///
/// `angle_left`/`angle_right` sont les angles PURS de la découpe (la ligne
/// imaginaire qui part du centre, sans rognage) -- l'écart avec le secteur
/// voisin n'est PAS créé en rognant ces angles (ce qui ferait converger les
/// deux bords en pointe exactement au centre, formant un angle entre les
/// deux découpes voisines -- le défaut signalé). Il est créé en décalant
/// chaque bord PERPENDICULAIREMENT à sa propre ligne imaginaire, de
/// `gap_px / 2` de chaque côté : les deux bords qui bornent un même écart
/// restent alors des droites parallèles entre elles (parallèles à la ligne
/// imaginaire du bord commun), quel que soit le rayon -- exactement le
/// tracé "deux lignes parallèles à côté de la ligne imaginaire" demandé,
/// plutôt que deux rayons qui se rejoignent au centre.
fn wedge_path(
    cx: f64,
    cy: f64,
    inner_r: f64,
    outer_r: f64,
    angle_left: f64,
    angle_right: f64,
    gap_px: f64,
) -> gsk::Path {
    let half_gap = (gap_px / 2.0).max(0.0);

    // Angle et rayon EXACTS du point du rayon `theta` (longueur `r`) décalé
    // perpendiculairement de `offset` (positif = vers les angles
    // croissants) -- identité géométrique directe (triangle rectangle
    // rayon/perpendiculaire), jamais un atan2(y,x) sur des coordonnées
    // cartésiennes : ça évite tout repli d'angle à ±π, y compris pour les
    // derniers secteurs dont `angle_right` dépasse 2π en valeur brute (cf.
    // `base` dans snapshot()).
    let offset_ray = |theta: f64, r: f64, offset: f64| -> (f64, f64) {
        (theta + offset.atan2(r), r.hypot(offset))
    };

    let (a_out_l, r_out_l) = offset_ray(angle_left, outer_r, half_gap);
    let (a_out_r, r_out_r) = offset_ray(angle_right, outer_r, -half_gap);

    let builder = gsk::PathBuilder::new();
    for step in 0..=ARC_STEPS {
        let t = step as f64 / ARC_STEPS as f64;
        let a = a_out_l + (a_out_r - a_out_l) * t;
        let r = r_out_l + (r_out_r - r_out_l) * t;
        let x = cx + r * a.cos();
        let y = cy + r * a.sin();
        if step == 0 {
            builder.move_to(x as f32, y as f32);
        } else {
            builder.line_to(x as f32, y as f32);
        }
    }
    if inner_r > half_gap + 1.0 {
        let (a_in_l, r_in_l) = offset_ray(angle_left, inner_r, half_gap);
        let (a_in_r, r_in_r) = offset_ray(angle_right, inner_r, -half_gap);
        for step in 0..=ARC_STEPS {
            let t = step as f64 / ARC_STEPS as f64;
            let a = a_in_r + (a_in_l - a_in_r) * t;
            let r = r_in_r + (r_in_l - r_in_r) * t;
            let x = cx + r * a.cos();
            let y = cy + r * a.sin();
            builder.line_to(x as f32, y as f32);
        }
    } else {
        builder.line_to(cx as f32, cy as f32);
    }
    builder.close();
    builder.to_path()
}

fn circle_path(cx: f64, cy: f64, r: f64) -> gsk::Path {
    const STEPS: usize = 48;
    let builder = gsk::PathBuilder::new();
    for step in 0..=STEPS {
        let a = std::f64::consts::TAU * step as f64 / STEPS as f64;
        let x = cx + r * a.cos();
        let y = cy + r * a.sin();
        if step == 0 {
            builder.move_to(x as f32, y as f32);
        } else {
            builder.line_to(x as f32, y as f32);
        }
    }
    builder.close();
    builder.to_path()
}

/// Couleur de remplissage d'un secteur -- interpole du gris neutre vers une
/// teinte sombre proche de l'accent cyan (`#4fefff`) avec `t` (surlignage
/// du survol), jamais l'accent plein : reste un fond de secteur, pas un
/// bouton cyan. `open` multiplie l'alpha (fondu à l'ouverture).
fn wedge_color(t: f32, open: f32) -> gdk::RGBA {
    let base = (0.145_f32, 0.145, 0.153);
    let accent = (0.157_f32, 0.286, 0.302);
    gdk::RGBA::new(
        base.0 + (accent.0 - base.0) * t,
        base.1 + (accent.1 - base.1) * t,
        base.2 + (accent.2 - base.2) * t,
        (0.80 + 0.10 * t) * open,
    )
}

/// Couleur du texte/icône d'un secteur -- blanc cassé au repos, plein accent
/// cyan une fois survolé (`t` -> 1).
fn text_color(t: f32, open: f32) -> gdk::RGBA {
    let base = (0.949_f32, 0.949, 0.969);
    let accent = (0.310_f32, 0.937, 1.0);
    gdk::RGBA::new(
        base.0 + (accent.0 - base.0) * t,
        base.1 + (accent.1 - base.1) * t,
        base.2 + (accent.2 - base.2) * t,
        open,
    )
}

glib::wrapper! {
    /// Roue de sélection radiale générique -- toute la logique vit dans
    /// `imp::Wheel` (pattern subclass GObject standard, comme Card/Carousel
    /// dans Prisme).
    pub struct RoueWheel(ObjectSubclass<imp::Wheel>) @extends gtk4::Widget;
}

impl RoueWheel {
    /// Construit la roue avec ses secteurs racine et démarre la boucle
    /// d'animation (éventail à l'ouverture + surlignage du survol).
    pub fn new(segments: Vec<Segment>) -> Self {
        let wheel: Self = glib::Object::builder().build();
        // hexpand/vexpand -- SANS ça, le Box parent (mount, un seul enfant
        // sans expand) n'alloue à la roue que sa taille naturelle (520x520)
        // tassée au début de l'axe vertical : halign/valign=Center n'ont
        // alors rien à centrer DEDANS. Avec expand=true, la roue réclame
        // tout l'espace laissé par le parent, et c'est CE surplus que
        // halign/valign centrent -- c'est ce qui manquait pour que le bloc
        // apparaisse au centre de l'écran plutôt que collé en haut.
        wheel.set_hexpand(true);
        wheel.set_vexpand(true);
        wheel.set_halign(gtk4::Align::Center);
        wheel.set_valign(gtk4::Align::Center);

        // Rasterisées une fois ici, à partir des seuls secteurs RACINE --
        // les secteurs synthétiques Confirmer/Annuler (cf. `enter_confirm`)
        // n'ont pas de fichier associé, `draw_icon` retombe sur du texte
        // brut pour eux.
        let icon_names = segments.iter().map(|s| s.icon.clone());
        *wheel.imp().icons.borrow_mut() = icons::load(icon_names);

        *wheel.imp().root_segments.borrow_mut() = segments.clone();
        *wheel.imp().segments.borrow_mut() = segments;

        let wheel_weak = wheel.downgrade();
        wheel.add_tick_callback(move |_, clock| {
            if let Some(wheel) = wheel_weak.upgrade() {
                wheel.imp().tick(clock);
            }
            glib::ControlFlow::Continue
        });

        wheel
    }

    /// Change le secteur survolé vers celui pointé par `(x, y)` (coordonnées
    /// relatives au widget, ex. depuis un EventControllerMotion) -- calcule
    /// l'angle du point par rapport au centre, comme un stick analogique.
    /// Ignoré si le point est trop proche du centre (cf. HOVER_DEADZONE_PX).
    pub fn hover_from_point(&self, x: f64, y: f64) {
        let w = self.width() as f64;
        let h = self.height() as f64;
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let dx = x - w / 2.0;
        let dy = y - h / 2.0;
        if (dx * dx + dy * dy).sqrt() < HOVER_DEADZONE_PX {
            return;
        }
        let n = self.imp().segments.borrow().len();
        if n == 0 {
            return;
        }
        let angle_per = std::f64::consts::TAU / n as f64;
        let base = -std::f64::consts::FRAC_PI_2 - angle_per / 2.0;
        let theta = dy.atan2(dx);
        let rel = (theta - base).rem_euclid(std::f64::consts::TAU);
        let index = (rel / angle_per).floor() as usize % n;
        self.set_hover_index(index);
    }

    /// Déplace le survol de `delta` secteurs (navigation clavier).
    pub fn move_hover(&self, delta: i32) {
        let n = self.imp().segments.borrow().len();
        if n == 0 {
            return;
        }
        let cur = self.imp().hovered.get() as i32;
        let next = (cur + delta).rem_euclid(n as i32) as usize;
        self.set_hover_index(next);
    }

    /// Survole directement le secteur `index` (accès direct au clavier par
    /// chiffre, ou calcul d'angle depuis la souris).
    pub fn set_hover_index(&self, index: usize) {
        let n = self.imp().segments.borrow().len();
        if n == 0 || index >= n {
            return;
        }
        // Marqué même si `index` égale déjà le survol courant (ex. viser
        // délibérément le secteur 0, qui est aussi la valeur par défaut) --
        // cf. `activate_hovered` : c'est un vrai geste de visée qui doit
        // compter, pas seulement un CHANGEMENT d'indice.
        self.imp().moved.set(true);
        if self.imp().hovered.get() != index {
            self.imp().hovered.set(index);
            self.imp().hover_anim.set(0.0);
            self.queue_draw();
        }
    }

    /// Valide le secteur actuellement survolé. Retourne `true` si
    /// l'appelant doit fermer la fenêtre maintenant (action lancée, ou
    /// annulation), `false` si la roue doit rester ouverte (bascule sur/
    /// depuis le sous-menu Confirmer/Annuler).
    ///
    /// Si aucune visée n'a eu lieu depuis l'ouverture de ce niveau (racine
    /// ou sous-menu -- cf. `moved`), valider équivaut à annuler plutôt qu'à
    /// choisir le secteur par défaut (index 0) : sans ce garde-fou, un
    /// simple tap de la touche qui ouvre la roue (appui+relâchement quasi
    /// immédiat, souris pas encore repositionnée) exécutait TOUJOURS le
    /// premier secteur -- Verrouiller pour la roue power, donc un
    /// verrouillage d'écran à chaque appui bref au lieu d'afficher la roue.
    pub fn activate_hovered(&self) -> bool {
        let imp = self.imp();
        let moved = imp.moved.get();

        if imp.confirming.get() {
            let confirmed = moved && imp.hovered.get() == 0;
            if confirmed {
                let pending = imp.pending.borrow().clone();
                self.exit_confirm();
                if let Some(seg) = pending {
                    if let Some(cb) = imp.commit_cb.borrow().as_ref() {
                        cb(&seg);
                    }
                }
                true
            } else {
                // Annuler explicite, OU aucun mouvement dans le sous-menu --
                // dans les deux cas retour à la roue racine sans agir,
                // jamais une confirmation par défaut.
                self.exit_confirm();
                false
            }
        } else if !moved {
            true
        } else {
            let idx = imp.hovered.get();
            let Some(seg) = imp.segments.borrow().get(idx).cloned() else {
                return true;
            };
            if seg.confirm {
                self.enter_confirm(seg);
                false
            } else {
                if let Some(cb) = imp.commit_cb.borrow().as_ref() {
                    cb(&seg);
                }
                true
            }
        }
    }

    pub fn is_confirming(&self) -> bool {
        self.imp().confirming.get()
    }

    /// Revient à la roue racine depuis le sous-menu de confirmation (Échap),
    /// sans rien exécuter. Ne fait rien si on n'est pas en confirmation --
    /// c'est alors à l'appelant (main.rs) de fermer la fenêtre à la place.
    pub fn cancel_confirm(&self) {
        if self.imp().confirming.get() {
            self.exit_confirm();
        }
    }

    /// Appelé uniquement quand une action définitive doit s'exécuter :
    /// jamais pour un secteur `confirm` tant qu'il n'a pas été confirmé.
    pub fn connect_commit(&self, f: impl Fn(&Segment) + 'static) {
        *self.imp().commit_cb.borrow_mut() = Some(Box::new(f));
    }

    fn enter_confirm(&self, seg: Segment) {
        let imp = self.imp();
        imp.confirming.set(true);
        *imp.pending.borrow_mut() = Some(seg);
        *imp.segments.borrow_mut() = vec![
            Segment { icon: "✓".into(), label: "Confirmer".into(), action: String::new(), confirm: false },
            Segment { icon: "✗".into(), label: "Annuler".into(), action: String::new(), confirm: false },
        ];
        imp.hovered.set(0);
        imp.hover_anim.set(1.0);
        // Il faut viser À NOUVEAU dans ce sous-menu avant de pouvoir le
        // valider (cf. `activate_hovered`) -- le mouvement fait pour
        // atteindre le secteur `confirm` racine ne compte pas ici.
        imp.moved.set(false);
        self.queue_draw();
    }

    fn exit_confirm(&self) {
        let imp = self.imp();
        imp.confirming.set(false);
        *imp.pending.borrow_mut() = None;
        *imp.segments.borrow_mut() = imp.root_segments.borrow().clone();
        imp.hovered.set(0);
        imp.hover_anim.set(1.0);
        imp.moved.set(false);
        self.queue_draw();
    }
}
