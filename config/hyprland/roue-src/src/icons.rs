//! Rasterizes SVG icons (Lucide/Tabler, see
//! config/hyprland/roue/icons/) into GTK textures -- native Rust rendering
//! (resvg/tiny-skia), no dependency on gdk-pixbuf's SVG loader: absent by
//! default on this machine (Fedora no longer ships
//! libpixbufloader-svg.so, checked by looking for the file under
//! /usr/lib64/gdk-pixbuf-2.0/), so `Pixbuf::from_file` on an SVG would fail
//! silently at runtime there.

use gtk4::prelude::*;
use gtk4::{gdk, glib};
use resvg::{tiny_skia, usvg};
use std::collections::HashMap;
use std::path::PathBuf;

use crate::color;
use crate::config::Segment;

/// Rasterization resolution -- noticeably larger than the actual display
/// size (~30-45px, see wheel.rs) to stay crisp once enlarged on hover
/// (append_scaled_texture, Trilinear filter).
const RASTER_PX: u32 = 128;

const COLOR_NORMAL: &str = "#f2f2f7";

/// An icon rasterized in the two colors that matter -- hover animates a
/// crossfade between the two (see wheel.rs) rather than a GPU color-matrix
/// recolor, simpler for such a small number of icons. The "accent" variant
/// is baked with THE sector's color (see `color::resolve`), not a global
/// constant -- that's what lets powerprofile.toml have a different
/// green/yellow/cyan hover per sector.
pub struct IconPair {
    pub normal: gdk::Texture,
    pub accent: gdk::Texture,
}

fn icons_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(".config/roue/icons")
}

/// A sector's cache key -- icon file AND resolved accent color, not the
/// file alone: two sectors sharing the same SVG file but a different tint
/// must get distinct "accent" textures. Used both here (at load time) and
/// in wheel.rs (at draw time), so centralized here so the two can't drift
/// apart.
pub fn cache_key(seg: &Segment) -> String {
    format!("{}{}", seg.icon, color::resolve(seg.accent.as_deref()).hex)
}

/// Loads and rasterizes the icon of each sector in `segments` (deduplicated
/// by `cache_key`) -- silently ignores (stderr message) a missing file or
/// an invalid SVG: wheel.rs then falls back to the sector's plain text, a
/// missing icon must not prevent the rest of the wheel from displaying.
pub fn load(segments: &[Segment]) -> HashMap<String, IconPair> {
    let dir = icons_dir();
    let mut cache = HashMap::new();
    for seg in segments {
        let key = cache_key(seg);
        if cache.contains_key(&key) {
            continue;
        }
        let path = dir.join(&seg.icon);
        let Ok(svg) = std::fs::read_to_string(&path) else {
            eprintln!("[roue] icon not found: {path:?}");
            continue;
        };
        let accent_hex = color::resolve(seg.accent.as_deref()).hex;
        match (rasterize(&svg, COLOR_NORMAL), rasterize(&svg, &accent_hex)) {
            (Some(normal), Some(accent)) => {
                cache.insert(key, IconPair { normal, accent });
            }
            _ => eprintln!("[roue] invalid SVG: {path:?}"),
        }
    }
    cache
}

/// Rasterizes `svg_source` (with `currentColor` replaced by `color` -- all
/// our Lucide/Tabler icons use it for the stroke) into a RASTER_PX x
/// RASTER_PX texture.
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
