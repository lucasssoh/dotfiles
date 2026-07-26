//! Rasterisation des icônes SVG (Lucide/Tabler, cf.
//! config/hyprland/roue/icons/) en textures GTK -- rendu natif Rust
//! (resvg/tiny-skia), pas de dépendance au loader SVG de gdk-pixbuf : absent
//! par défaut sur cette machine (Fedora ne fournit plus
//! libpixbufloader-svg.so, vérifié en cherchant le fichier dans
//! /usr/lib64/gdk-pixbuf-2.0/), donc `Pixbuf::from_file` sur un SVG y
//! échouerait silencieusement à l'exécution.

use gtk4::prelude::*;
use gtk4::{gdk, glib};
use resvg::{tiny_skia, usvg};
use std::collections::HashMap;
use std::path::PathBuf;

/// Résolution de rasterisation -- nettement plus grande que la taille
/// d'affichage réelle (~30-45px, cf. wheel.rs) pour rester net une fois
/// agrandie au survol (append_scaled_texture, filtre Trilinear).
const RASTER_PX: u32 = 128;

const COLOR_NORMAL: &str = "#f2f2f7";
const COLOR_ACCENT: &str = "#4fefff";

/// Une icône rasterisée dans les deux couleurs utiles -- le survol anime un
/// fondu entre les deux (cf. wheel.rs) plutôt qu'une recoloration GPU par
/// color-matrix, plus simple pour un si petit nombre d'icônes.
pub struct IconPair {
    pub normal: gdk::Texture,
    pub accent: gdk::Texture,
}

fn icons_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME non défini");
    PathBuf::from(home).join(".config/roue/icons")
}

/// Charge et rasterise chaque fichier de `names` (dédupliqués) -- ignore
/// silencieusement (message sur stderr) un fichier introuvable ou un SVG
/// invalide : wheel.rs retombe alors sur le texte brut du secteur, une
/// icône manquante ne doit pas empêcher le reste de la roue de s'afficher.
pub fn load(names: impl Iterator<Item = String>) -> HashMap<String, IconPair> {
    let dir = icons_dir();
    let mut cache = HashMap::new();
    for name in names {
        if cache.contains_key(&name) {
            continue;
        }
        let path = dir.join(&name);
        let Ok(svg) = std::fs::read_to_string(&path) else {
            eprintln!("[roue] icône introuvable : {path:?}");
            continue;
        };
        match (rasterize(&svg, COLOR_NORMAL), rasterize(&svg, COLOR_ACCENT)) {
            (Some(normal), Some(accent)) => {
                cache.insert(name, IconPair { normal, accent });
            }
            _ => eprintln!("[roue] SVG invalide : {path:?}"),
        }
    }
    cache
}

/// Rasterise `svg_source` (avec `currentColor` remplacé par `color` --
/// toutes nos icônes Lucide/Tabler l'utilisent pour le trait) en une
/// texture RASTER_PX x RASTER_PX.
fn rasterize(svg_source: &str, color: &str) -> Option<gdk::Texture> {
    let recolored = svg_source.replace("currentColor", color);
    let opt = usvg::Options::default();
    let tree = usvg::Tree::from_str(&recolored, &opt).ok()?;
    let size = tree.size();
    if size.width() <= 0.0 || size.height() <= 0.0 {
        return None;
    }

    let mut pixmap = tiny_skia::Pixmap::new(RASTER_PX, RASTER_PX)?;
    let transform = tiny_skia::Transform::from_scale(
        RASTER_PX as f32 / size.width(),
        RASTER_PX as f32 / size.height(),
    );
    resvg::render(&tree, transform, &mut pixmap.as_mut());

    let bytes = glib::Bytes::from(pixmap.data());
    Some(
        gdk::MemoryTexture::new(
            RASTER_PX as i32,
            RASTER_PX as i32,
            gdk::MemoryFormat::R8g8b8a8Premultiplied,
            &bytes,
            RASTER_PX as usize * 4,
        )
        .upcast(),
    )
}
