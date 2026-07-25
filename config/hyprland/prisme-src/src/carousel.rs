use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk};
use std::cell::{Cell, RefCell};
use std::time::Instant;

use crate::card::{self, Card};

/// Vitesse de convergence de l'interpolation exponentielle de l'offset
/// animé vers sa cible (plus haut = plus rapide) -- ~14 converge à ~95% en
/// ~220ms, ce qui donne la sensation d'un ressort amorti sans en calculer un
/// explicitement. Indépendant de la fréquence d'écran : `tick()` utilise le
/// dt réel du frame clock (180Hz ici), donc l'animation garde la même durée
/// perçue à 60 comme à 180Hz -- seule sa fluidité change.
const EASE_RATE: f64 = 14.0;

const CASCADE_STAGGER_MS: f64 = 40.0;
const CASCADE_DURATION_MS: f64 = 320.0;

/// Marge (px) entre le bas de la rangée (carte la plus haute possible,
/// focus + sélection) et le bas de la zone allouée -- la rangée est centrée
/// bas (pas au milieu de l'écran) pour laisser le plus clair de l'écran
/// visible derrière l'overlay pendant qu'on navigue.
const BOTTOM_MARGIN_PX: f64 = 24.0;

/// Supplément de hauteur (px) pour une carte sélectionnée (mode Diaporama)
/// -- vient s'ajouter à l'interpolation de focus, pour que les cartes
/// choisies "dépassent" visiblement de la rangée même hors focus.
const SELECTED_HEIGHT_BOOST: f64 = 26.0;

/// Distance non signée sur l'anneau entre deux positions (le plus court des
/// deux chemins possibles) -- utilisée pour l'entrée en cascade (`tick`) et
/// par main.rs pour l'ordre de chargement des vignettes, afin que les deux
/// s'accordent sur la même notion de "proche du point de départ".
pub(crate) fn ring_distance(i: f64, origin: f64, len: f64) -> f64 {
    if len <= 0.0 {
        return 0.0;
    }
    let raw = (i - origin).rem_euclid(len);
    raw.min(len - raw)
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Carousel {
        pub entries: RefCell<Vec<Card>>,
        /// Position "logique" visée sur l'anneau -- un flottant NON borné
        /// (jamais de modulo appliqué ici). ± N à chaque tour complet, donc
        /// toujours croissant/décroissant de façon monotone selon la
        /// navigation : c'est ce qui permet un défilement infini sans jamais
        /// avoir à décider d'un sens de rembobinage.
        pub target: Cell<f64>,
        /// Position animée, converge vers `target` par interpolation
        /// exponentielle. Le modulo n'intervient qu'au moment de dessiner
        /// (distance par carte, cf. `size_allocate`), jamais sur ces deux
        /// valeurs -- ça évite toute ambiguïté de sens au passage du dernier
        /// au premier élément.
        pub offset: Cell<f64>,
        /// Indice de départ de l'animation d'entrée en cascade -- figé une
        /// fois pour toutes par `set_focus_index` (0 par défaut), jamais mis
        /// à jour ensuite. Contrairement à `target`/`offset`, ce point ne
        /// doit PAS suivre le défilement : si on recalculait la distance à
        /// chaque frame à partir du focus courant, faire défiler pendant la
        /// première seconde ferait "dé-révéler" des cartes déjà apparues
        /// (leur délai changerait sous leurs pieds).
        pub reveal_origin: Cell<f64>,
        pub scroll_accum: Cell<f64>,
        pub start: Cell<Option<Instant>>,
        pub last_frame_us: Cell<Option<i64>>,
        pub activate_cb: RefCell<Option<Box<dyn Fn(usize)>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Carousel {
        const NAME: &'static str = "PrismeCarousel";
        type Type = super::Carousel;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Carousel {
        fn dispose(&self) {
            for card in self.entries.borrow_mut().drain(..) {
                card.unparent();
            }
        }
    }

    impl WidgetImpl for Carousel {
        // Comme Card::measure : aucune taille propre, pour ne jamais
        // remonter de contrainte vers la fenêtre layer-shell -- c'est le
        // bug qui gonflait la surface à 3300px sur un écran de 2560px avec
        // l'ancien GtkFixed (measure() y renvoyait l'union des coordonnées
        // absolues des enfants, indépendamment de Overflow::Hidden).
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (0, 0, -1, -1)
        }

        // Repositionne toutes les cartes à partir de la taille réellement
        // allouée par le parent (donc jamais circulaire) -- appelé à chaque
        // frame via `queue_allocate()` dans `tick()`, pas seulement au
        // redimensionnement.
        fn size_allocate(&self, width: i32, height: i32, _baseline: i32) {
            let entries = self.entries.borrow();
            let len = entries.len();
            if len == 0 {
                return;
            }
            let width = width as f64;
            let height = height as f64;
            let len_f = len as f64;
            let offset = self.offset.get();
            // Deux parallélogrammes de même largeur ET même hauteur,
            // décalés exactement de (largeur - pente), ont leurs bords en
            // pente qui coïncident pile (vérifié géométriquement sur les 4
            // sommets) -- valeur de repos (cartes non focus, non
            // sélectionnées) prise comme référence pour l'espacement.
            let step = card::WIDTH_UNFOCUSED
                - card::skew_for(card::WIDTH_UNFOCUSED, card::HEIGHT_UNFOCUSED);
            // Écart supplémentaire à reporter sur les voisines quand la
            // carte au focus grandit -- PAS juste la moitié du gain de
            // largeur : la pente étant proportionnelle à la hauteur
            // (card::SKEW_RATIO), une carte qui grandit aussi en hauteur
            // "mange" une partie de cet écart avec son bord plus incliné.
            // Démonstration : deux bords voisins ont exactement la même
            // pente (skew_i/h_i = SKEW_RATIO pour toute carte i), donc
            // l'écart entre eux est CONSTANT sur toute la hauteur commune
            // (les deux droites sont parallèles) et vaut
            // (w_i+w_j)/2 - SKEW_RATIO·(h_i+h_j)/2 -- d'où ce terme en
            // largeur ET en hauteur, pas en largeur seule comme une v1 de
            // ce calcul le faisait (elle laissait un mince espace visible
            // près du focus, la carte y étant nettement plus haute aussi).
            let extra_reach = (card::WIDTH_FOCUSED - card::WIDTH_UNFOCUSED) / 2.0
                - card::SKEW_RATIO * (card::HEIGHT_FOCUSED - card::HEIGHT_UNFOCUSED) / 2.0;
            let cx = width / 2.0;
            // Centre vertical commun de la rangée, choisi pour que même la
            // carte la plus haute possible (focus + sélection cumulés) ne
            // dépasse pas BOTTOM_MARGIN_PX du bas -- chaque carte grandit
            // ensuite à parts égales vers le haut ET le bas depuis cette
            // ligne (plutôt qu'un ancrage bas qui ferait tout grimper d'un
            // seul côté, cassant la coïncidence des bords en pente avec les
            // voisines de hauteur différente).
            let max_h = card::HEIGHT_FOCUSED + SELECTED_HEIGHT_BOOST;
            let row_center_y = height - BOTTOM_MARGIN_PX - max_h / 2.0;
            let visible_margin = card::WIDTH_FOCUSED + 40.0;

            for (i, card) in entries.iter().enumerate() {
                // Distance signée sur l'anneau, ramenée dans [-N/2, N/2) --
                // seul endroit où le modulo intervient (cf. doc de `target`
                // dans Inner). Reste continue pendant l'animation puisque
                // `offset` l'est.
                let mut d = (i as f64 - offset) % len_f;
                if d > len_f / 2.0 {
                    d -= len_f;
                } else if d < -len_f / 2.0 {
                    d += len_f;
                }

                let focus_amount = (1.0 - d.abs()).max(0.0);
                card.set_focus(focus_amount);

                let w = card::WIDTH_UNFOCUSED
                    + (card::WIDTH_FOCUSED - card::WIDTH_UNFOCUSED) * focus_amount;
                let mut h = card::HEIGHT_UNFOCUSED
                    + (card::HEIGHT_FOCUSED - card::HEIGHT_UNFOCUSED) * focus_amount;
                if card.is_selected() {
                    h += SELECTED_HEIGHT_BOOST;
                }

                let sign = d.signum();
                // La carte au focus (d≈0) est exactement centrée par
                // construction : à d=0, ce terme s'annule.
                let x_center = cx + d * step + sign * d.abs().min(1.0) * extra_reach;

                if x_center + w / 2.0 < -visible_margin
                    || x_center - w / 2.0 > width + visible_margin
                {
                    card.set_child_visible(false);
                    continue;
                }
                card.set_child_visible(true);

                let x = (x_center - w / 2.0).round() as f32;
                let y = (row_center_y - h / 2.0).round() as f32;
                let transform = gsk::Transform::new().translate(&graphene::Point::new(x, y));
                card.allocate(w.round() as i32, h.round() as i32, -1, Some(transform));
            }
        }
    }

    impl Carousel {
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
            let elapsed_ms = self.start.get().unwrap().elapsed().as_secs_f64() * 1000.0;
            let len_f = self.entries.borrow().len() as f64;
            // Point le plus loin possible sur l'anneau depuis le départ de
            // la cascade -- passé son délai + sa durée, plus aucune carte
            // ne peut encore changer de valeur de reveal.
            let cascade_running =
                elapsed_ms < (len_f / 2.0).floor() * CASCADE_STAGGER_MS + CASCADE_DURATION_MS;
            let target = self.target.get();
            let offset = self.offset.get();
            let still_easing = (target - offset).abs() > 0.0005;

            // Rien à animer -- ne touche à rien et surtout ne redemande pas
            // de frame via queue_allocate(). Mesuré à ~65% d'un cœur en
            // continu (relayout + redessin des ~25 cartes 120-180 fois par
            // seconde) avant ce garde-fou, alors que rien ne bouge à
            // l'écran ; quasi nul après. Les changements hors-animation
            // (sélection, cf. main.rs) redemandent un allocate eux-mêmes au
            // moment où ils se produisent, donc rien ne reste figé par
            // erreur.
            if !still_easing && !cascade_running {
                return;
            }

            let ease = 1.0 - (-EASE_RATE * dt).exp();
            let next = offset + (target - offset) * ease;
            self.offset
                .set(if (next - target).abs() < 0.0005 { target } else { next });

            let entries = self.entries.borrow();
            let origin = self.reveal_origin.get();
            for (i, card) in entries.iter().enumerate() {
                // Distance sur l'anneau depuis le point de départ (pas
                // l'indice brut) -- l'entrée en cascade part de la carte
                // initialement au focus et déborde vers les deux côtés à la
                // fois, plutôt qu'un simple balayage gauche→droite.
                let dist = ring_distance(i as f64, origin, len_f);
                let delay = dist * CASCADE_STAGGER_MS;
                let t = ((elapsed_ms - delay) / CASCADE_DURATION_MS).clamp(0.0, 1.0);
                let eased = 1.0 - (1.0 - t).powi(3);
                card.set_reveal(eased);
            }

            // Redéclenche size_allocate au prochain passage du frame clock,
            // avec le nouvel `offset` -- jamais queue_resize (cf. mesure()).
            self.obj().queue_allocate();
        }
    }
}

glib::wrapper! {
    /// Le carrousel : un conteneur `gtk4::Widget` qui recalcule lui-même la
    /// position/largeur/hauteur de chaque carte à chaque frame -- nécessaire
    /// puisque ces valeurs s'animent en continu (focus, entrée en cascade,
    /// défilement), ce qu'aucun layout manager standard ne permet nativement
    /// sans réimplémenter, justement, un layout manager complet. Remplace le
    /// `GtkFixed` de la première version, dont `measure()` remontait les
    /// coordonnées absolues des enfants jusqu'à la fenêtre layer-shell.
    pub struct Carousel(ObjectSubclass<imp::Carousel>) @extends gtk4::Widget;
}

impl Carousel {
    pub fn new(cards: Vec<Card>) -> Self {
        let carousel: Self = glib::Object::builder().build();
        carousel.set_overflow(gtk4::Overflow::Hidden);
        carousel.set_hexpand(true);
        carousel.set_vexpand(true);

        {
            let mut entries = carousel.imp().entries.borrow_mut();
            for (index, card) in cards.into_iter().enumerate() {
                card.set_parent(&carousel);

                // Clic : sélectionne la carte visée (déplace le focus en
                // suivant le plus court chemin sur l'anneau), ou l'active si
                // elle avait déjà le focus.
                let click = gtk4::GestureClick::new();
                let carousel_weak = carousel.downgrade();
                click.connect_pressed(move |_, _, _, _| {
                    if let Some(carousel) = carousel_weak.upgrade() {
                        carousel.handle_card_click(index);
                    }
                });
                card.add_controller(click);

                entries.push(card);
            }
        }

        // Molette / trackpad -- accumulateur plutôt qu'un pas fixe par
        // évènement : un geste trackpad (beaucoup de petits deltas) avance
        // en continu, un cran de molette physique (delta ≈ ±1) avance
        // immédiatement d'une carte.
        let scroll =
            gtk4::EventControllerScroll::new(gtk4::EventControllerScrollFlags::BOTH_AXES);
        {
            let carousel_weak = carousel.downgrade();
            scroll.connect_scroll(move |_, dx, dy| {
                if let Some(carousel) = carousel_weak.upgrade() {
                    carousel.handle_scroll(dx, dy);
                }
                glib::Propagation::Stop
            });
        }
        carousel.add_controller(scroll);

        // Boucle d'animation -- tourne en continu tant que la fenêtre est
        // ouverte (fenêtre transitoire, coût négligeable). Référence faible
        // pour ne pas créer de cycle fort avec le callback que le widget
        // conserve lui-même.
        {
            let carousel_weak = carousel.downgrade();
            carousel.add_tick_callback(move |_, clock| {
                if let Some(carousel) = carousel_weak.upgrade() {
                    carousel.imp().tick(clock);
                }
                glib::ControlFlow::Continue
            });
        }

        carousel
    }

    fn handle_card_click(&self, index: usize) {
        let len = self.imp().entries.borrow().len();
        if len == 0 {
            return;
        }
        if index == self.focused_index() {
            self.activate_focused();
            return;
        }
        let len_f = len as f64;
        let focused = self.focused_index() as f64;
        let mut diff = index as f64 - focused;
        if diff > len_f / 2.0 {
            diff -= len_f;
        } else if diff < -len_f / 2.0 {
            diff += len_f;
        }
        self.imp().target.set(self.imp().target.get() + diff);
    }

    fn handle_scroll(&self, dx: f64, dy: f64) {
        let delta = if dx.abs() > dy.abs() { dx } else { dy };
        if delta.abs() < 0.001 {
            return;
        }
        let accum = self.imp().scroll_accum.get() + delta;
        let steps = accum.trunc();
        if steps != 0.0 {
            self.imp().target.set(self.imp().target.get() + steps);
            self.imp().scroll_accum.set(accum - steps);
        } else {
            self.imp().scroll_accum.set(accum);
        }
    }

    pub fn focused_index(&self) -> usize {
        let len = self.imp().entries.borrow().len();
        if len == 0 {
            return 0;
        }
        self.imp().target.get().round().rem_euclid(len as f64) as usize
    }

    pub fn len(&self) -> usize {
        self.imp().entries.borrow().len()
    }

    pub fn card_at(&self, index: usize) -> Option<Card> {
        self.imp().entries.borrow().get(index).cloned()
    }

    pub fn move_focus(&self, delta: i32) {
        self.imp().target.set(self.imp().target.get() + delta as f64);
    }

    /// Positionne le focus directement sur `index`, sans faire défiler
    /// depuis 0 -- utilisé une fois à l'ouverture pour démarrer sur le
    /// dernier fond appliqué en Statique (cf. `apply::last_static`) plutôt
    /// que sur la première carte de la liste. Fixe aussi le point de départ
    /// de l'entrée en cascade (cf. `reveal_origin`) sur ce même indice, pour
    /// que l'animation d'entrée déborde depuis cette carte plutôt que
    /// depuis le début de la liste.
    pub fn set_focus_index(&self, index: usize) {
        let len = self.imp().entries.borrow().len();
        if len == 0 || index >= len {
            return;
        }
        self.imp().target.set(index as f64);
        self.imp().offset.set(index as f64);
        self.imp().reveal_origin.set(index as f64);
    }

    pub fn activate_focused(&self) {
        let idx = self.focused_index();
        if let Some(cb) = self.imp().activate_cb.borrow().as_ref() {
            cb(idx);
        }
    }

    /// Appelé quand la carte au focus est validée (Entrée, ou clic sur une
    /// carte déjà focus).
    pub fn connect_activate(&self, f: impl Fn(usize) + 'static) {
        *self.imp().activate_cb.borrow_mut() = Some(Box::new(f));
    }
}
