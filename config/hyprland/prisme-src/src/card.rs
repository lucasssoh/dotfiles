//! Widget "carte" du carrousel : une vignette de wallpaper dessinée en
//! parallélogramme (effet "italique"), dont le focus, la révélation et la
//! sélection sont pilotés par carousel.rs. Rendu entièrement en GSK
//! (snapshot) plutôt qu'en Cairo pour rester fluide sur une surface
//! layer-shell — voir la note sur `measure` plus bas pour la contrainte
//! de taille la plus importante du fichier.

use gtk4::glib;
use gtk4::prelude::*;
use gtk4::subclass::prelude::*;
use gtk4::{gdk, graphene, gsk, pango};
use std::cell::{Cell, OnceCell, RefCell};
use std::path::Path;

use crate::wallpapers::Wallpaper;

/// Nom de fichier brut -> libellé lisible pour l'étiquette de la carte :
/// extension retirée, tirets et underscores traités comme des espaces,
/// tout en majuscules. Ex : "oleksandr-kozachenko-hands-study-5.jpg" ->
/// "OLEKSANDR KOZACHENKO HANDS STUDY 5".
fn display_name(filename: &str) -> String {
    let stem = Path::new(filename)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(filename);
    stem.replace(['-', '_'], " ").to_uppercase()
}

/// Pente de l'angle "italique" en fraction de la hauteur de la carte (pas
/// un nombre de pixels fixe) -- la hauteur varie avec le focus et la
/// sélection (cf. carousel.rs), donc un décalage en px constant donnerait
/// un angle VISUELLEMENT différent selon la taille de la carte (une carte
/// courte semble plus penchée qu'une carte haute pour le même décalage en
/// px). En le dérivant de la hauteur, toutes les cartes gardent exactement
/// la même pente, quelle que soit leur taille du moment.
pub const SKEW_RATIO: f64 = 0.1;

pub const WIDTH_UNFOCUSED: f64 = 180.0;
pub const WIDTH_FOCUSED: f64 = 520.0;
pub const HEIGHT_UNFOCUSED: f64 = 320.0;
pub const HEIGHT_FOCUSED: f64 = 460.0;

/// Décalage horizontal (px) de la pente pour une carte de taille (w,h) --
/// centralisé ici, réutilisé par `carousel.rs` pour calculer l'espacement
/// entre cartes (cf. sa doc), afin que les deux restent en accord.
pub fn skew_for(w: f64, h: f64) -> f64 {
    (h * SKEW_RATIO).min(w * 0.3)
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Card {
        pub texture: RefCell<Option<gdk::Texture>>,
        /// Dimensions du fichier source (pas de la texture réduite), pour
        /// l'étiquette -- ex. "3840×2160" même si la vignette affichée est
        /// plus petite.
        pub orig_dims: Cell<(i32, i32)>,
        pub focus: Cell<f64>,
        pub reveal: Cell<f64>,
        pub selected: Cell<bool>,
        pub wallpaper: OnceCell<Wallpaper>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Card {
        const NAME: &'static str = "PrismeCard";
        type Type = super::Card;
        type ParentType = gtk4::Widget;
    }

    impl ObjectImpl for Card {}

    impl WidgetImpl for Card {
        // La taille est entièrement pilotée par le carrousel (via
        // `size_allocate` sur ce widget) -- aucune préférence de taille
        // propre, sinon chaque changement de focus déclencherait un
        // `queue_resize` remontant jusqu'à la fenêtre à 180 fois par
        // seconde (c'est exactement ce qui gonflait la surface layer-shell
        // avant cette réécriture).
        fn measure(&self, _orientation: gtk4::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
            (0, 0, -1, -1)
        }

        fn snapshot(&self, snapshot: &gtk4::Snapshot) {
            let widget = self.obj();
            let w = widget.width() as f64;
            let h = widget.height() as f64;
            let reveal = self.reveal.get();
            if w <= 0.0 || h <= 0.0 || reveal <= 0.001 {
                return;
            }

            let skew = skew_for(w, h);
            let path = parallelogram_path(w, h, skew);

            // Remplissage clippé au parallélogramme -- équivalent GPU du
            // clip Cairo + paint de l'ancienne implémentation.
            snapshot.push_fill(&path, gsk::FillRule::Winding);
            match &*self.texture.borrow() {
                Some(tex) => {
                    let tw = tex.width() as f64;
                    let th = tex.height() as f64;
                    // "cover" : le plus grand des deux ratios remplit toute
                    // la boîte, quitte à rogner.
                    let scale = (w / tw).max(h / th).max(0.0001);
                    let dw = tw * scale;
                    let dh = th * scale;
                    let dx = (w - dw) / 2.0;
                    let dy = (h - dh) / 2.0;
                    let bounds =
                        graphene::Rect::new(dx as f32, dy as f32, dw as f32, dh as f32);
                    snapshot.append_scaled_texture(tex, gsk::ScalingFilter::Trilinear, &bounds);

                    // Cartes non focus assombries.
                    let dim = (1.0 - self.focus.get()) * 0.55;
                    if dim > 0.001 {
                        let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                        snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, dim as f32), &full);
                    }
                }
                None => {
                    // Vignette pas encore chargée -- aplat neutre.
                    let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                    snapshot
                        .append_color(&gdk::RGBA::new(0.11, 0.11, 0.12, 1.0), &full);
                }
            }
            snapshot.pop();

            // Pas de contour -- le focus et la sélection se lisent déjà à
            // la taille/luminosité (focus) et à la hauteur (sélection, cf.
            // carousel.rs), une bordure en plus n'apportait rien.
            let focus = self.focus.get();

            // Nom + dimensions -- apparition progressive avec le focus au
            // lieu du seuil binaire de l'ancienne version DrawingArea.
            if focus > 0.15 {
                let alpha = (((focus - 0.15) / 0.45) as f32).clamp(0.0, 1.0);
                if let Some(wallpaper) = self.wallpaper.get() {
                    // Padding et tailles de police volontairement compacts
                    // (étiquette discrète, pas un bandeau d'infos) --
                    // mesurés via pixel_size() plutôt que des décalages
                    // devinés, pour que le bandeau colle exactement au
                    // contenu réel quelle que soit la police système.
                    const PAD_X: f64 = 10.0;
                    const PAD_TOP: f64 = 5.0;
                    const PAD_BOTTOM: f64 = 5.0;
                    const LINE_GAP: f64 = 1.0;
                    const NAME_FONT_PX: f64 = 13.0;
                    const DIMS_FONT_PX: f64 = 11.0;

                    // Ancré à droite plutôt qu'à gauche : le coin bas-droit
                    // du parallélogramme est plus ouvert (angle obtus) que
                    // le bas-gauche (angle aigu, cf. skewed_slice_path) --
                    // le texte respire mieux du côté large.
                    //
                    // La largeur retire `skew` en plus du padding : le bord
                    // droit de la carte n'est vertical qu'à x=w tout en haut
                    // (y=0) ; il recule jusqu'à x=w-skew en bas (y=h, cf.
                    // skewed_slice_path). Une boîte de texte droite (non
                    // penchée) alignée à droite doit donc viser ce point le
                    // plus reculé -- sinon le texte déborde du côté oblique
                    // de la carte près du bas du bandeau, là où l'écart entre
                    // "w" et le bord réel est le plus grand.
                    let mut name_font = pango::FontDescription::new();
                    name_font.set_absolute_size(NAME_FONT_PX * pango::SCALE as f64);
                    let name_layout = widget.create_pango_layout(Some(&display_name(&wallpaper.name)));
                    name_layout.set_font_description(Some(&name_font));
                    name_layout.set_ellipsize(pango::EllipsizeMode::Middle);
                    name_layout.set_alignment(pango::Alignment::Right);
                    name_layout.set_width(((w - skew - PAD_X * 2.0).max(0.0) * pango::SCALE as f64) as i32);
                    let name_h = name_layout.pixel_size().1 as f64;

                    let (dw, dh) = self.orig_dims.get();
                    let dims_layout = (dw > 0 && dh > 0).then(|| {
                        let mut dims_font = pango::FontDescription::new();
                        dims_font.set_absolute_size(DIMS_FONT_PX * pango::SCALE as f64);
                        let layout = widget.create_pango_layout(Some(&format!("{dw}\u{00d7}{dh}")));
                        layout.set_font_description(Some(&dims_font));
                        layout.set_alignment(pango::Alignment::Right);
                        layout.set_width(((w - skew - PAD_X * 2.0).max(0.0) * pango::SCALE as f64) as i32);
                        layout
                    });
                    let dims_h = dims_layout.as_ref().map_or(0.0, |l| l.pixel_size().1 as f64);

                    // Bandeau noir derrière le texte, dimensionné pile sur
                    // le contenu mesuré ci-dessus. Découpé en tranche du
                    // MÊME parallélogramme que la carte (cf.
                    // skewed_slice_path) plutôt qu'un rectangle droit --
                    // ses côtés suivent donc la pente des bords de la
                    // carte au lieu de couper à angle droit dedans. Léger
                    // débord (1px) au-delà du bord réel de chaque côté :
                    // sans lui, l'anti-aliasing du GPU sur cette arête et
                    // celle -- légèrement différente -- du clip de l'image
                    // laissaient un mince liseré non couvert.
                    let content_h = name_h + if dims_layout.is_some() { LINE_GAP + dims_h } else { 0.0 };
                    let band_top = (h - (PAD_TOP + content_h + PAD_BOTTOM)).max(0.0);
                    let band_path = skewed_slice_path(w, h, skew, band_top, h, 1.0);
                    snapshot.push_fill(&band_path, gsk::FillRule::Winding);
                    let full = graphene::Rect::new(0.0, 0.0, w as f32, h as f32);
                    snapshot.append_color(&gdk::RGBA::new(0.0, 0.0, 0.0, 0.8 * alpha), &full);
                    snapshot.pop();

                    let text_color = gdk::RGBA::new(0.949, 0.949, 0.969, alpha);
                    let name_y = band_top + PAD_TOP;
                    snapshot.save();
                    snapshot.translate(&graphene::Point::new(PAD_X as f32, name_y as f32));
                    snapshot.append_layout(&name_layout, &text_color);
                    snapshot.restore();

                    if let Some(dims_layout) = dims_layout {
                        let dims_color = gdk::RGBA::new(0.557, 0.557, 0.576, alpha);
                        let dims_y = name_y + name_h + LINE_GAP;
                        snapshot.save();
                        snapshot.translate(&graphene::Point::new(PAD_X as f32, dims_y as f32));
                        snapshot.append_layout(&dims_layout, &dims_color);
                        snapshot.restore();
                    }
                }
            }
        }
    }
}

glib::wrapper! {
    /// Widget public exposé au reste du programme ; toute la logique vit
    /// dans `imp::Card` (pattern subclass GObject standard de gtk4-rs).
    pub struct Card(ObjectSubclass<imp::Card>) @extends gtk4::Widget;
}

impl Card {
    /// Construit une carte pour ce wallpaper. La vignette n'est pas encore
    /// chargée : `set_texture` est appelée plus tard, une fois le décodage
    /// terminé côté thumbs.rs.
    pub fn new(wallpaper: Wallpaper) -> Self {
        let card: Self = glib::Object::builder().build();
        let _ = card.imp().wallpaper.set(wallpaper);
        card.set_overflow(gtk4::Overflow::Visible);
        card
    }

    pub fn wallpaper(&self) -> &Wallpaper {
        self.imp().wallpaper.get().expect("wallpaper non initialisé")
    }

    /// Reçu depuis thumbs.rs une fois la vignette décodée en arrière-plan.
    pub fn set_texture(&self, texture: gdk::Texture, orig_width: i32, orig_height: i32) {
        self.imp().orig_dims.set((orig_width, orig_height));
        *self.imp().texture.borrow_mut() = Some(texture);
        self.queue_draw();
    }

    /// t ∈ [0,1] -- 0 = carte au repos, 1 = carte au focus. Pilote la
    /// luminosité et l'apparition des labels ; la taille est dérivée de la
    /// même valeur par le carrousel (cf. `carousel.rs`), pas stockée ici.
    pub fn set_focus(&self, t: f64) {
        self.imp().focus.set(t.clamp(0.0, 1.0));
        self.queue_draw();
    }

    /// Valeur de focus courante, cf. `set_focus`.
    pub fn focus(&self) -> f64 {
        self.imp().focus.get()
    }

    /// t ∈ [0,1] -- animation d'entrée en cascade au lancement.
    pub fn set_reveal(&self, t: f64) {
        let t = t.clamp(0.0, 1.0);
        self.imp().reveal.set(t);
        self.set_opacity(t);
        self.queue_draw();
    }

    /// Marque la carte comme incluse dans la sélection multiple (mode
    /// Diaporama). N'affecte que l'état interne : c'est carousel.rs qui
    /// traduit la sélection en changement de hauteur/apparence.
    pub fn set_selected(&self, selected: bool) {
        self.imp().selected.set(selected);
        self.queue_draw();
    }

    pub fn is_selected(&self) -> bool {
        self.imp().selected.get()
    }
}

/// Construit le contour du parallélogramme "italique" de la carte, penché
/// de `skew` pixels vers la droite en haut.
fn parallelogram_path(w: f64, h: f64, skew: f64) -> gsk::Path {
    skewed_slice_path(w, h, skew, 0.0, h, 0.0)
}

/// Contour d'une tranche horizontale du même parallélogramme, entre
/// `y_top` et `y_bottom` (0.0 et h avec bleed=0.0 donnent
/// parallelogram_path ci-dessus). Sert à découper le bandeau d'étiquette
/// avec exactement la même pente que les côtés de la carte, plutôt qu'un
/// rectangle droit qui trancherait dedans à angle droit. `bleed` élargit
/// le tracé de `bleed` px de chaque côté (gauche/droite uniquement) --
/// utile pour le bandeau, dont les bords doivent légèrement déborder au-
/// delà du bord réel de la carte pour ne pas laisser un liseré non couvert
/// par l'anti-aliasing du GPU sur les deux arêtes obliques. `h` non nul
/// garanti par l'appelant (snapshot() retourne plus tôt si h <= 0.0).
fn skewed_slice_path(w: f64, h: f64, skew: f64, y_top: f64, y_bottom: f64, bleed: f64) -> gsk::Path {
    let x_left = |y: f64| skew * (1.0 - y / h) - bleed;
    let x_right = |y: f64| w - skew * (y / h) + bleed;
    let builder = gsk::PathBuilder::new();
    builder.move_to(x_left(y_top) as f32, y_top as f32);
    builder.line_to(x_right(y_top) as f32, y_top as f32);
    builder.line_to(x_right(y_bottom) as f32, y_bottom as f32);
    builder.line_to(x_left(y_bottom) as f32, y_bottom as f32);
    builder.close();
    builder.to_path()
}
