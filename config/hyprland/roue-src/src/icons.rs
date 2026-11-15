//! Rasterizes SVG icons (MingCute, see
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

use crate::config::Segment;
use crate::palette::{self, Palette};

/// Rasterization resolution -- noticeably larger than the actual display
/// size (~26-28px, see wheel.rs) to stay crisp on a HiDPI output
/// (append_scaled_texture, Trilinear filter).
const RASTER_PX: u32 = 128;

/// The icons of the confirmation sub-menu's two sectors (see
/// wheel.rs::enter_confirm), loaded with the root sectors' own.
pub const CANCEL_ICON: &str = "x.svg";
pub const CONFIRM_ICON: &str = "check.svg";

/// An icon rasterized in the two inks a pastille shows it in -- the aim
/// crossfades from one to the other (see wheel.rs) rather than recolouring
/// on the GPU, simpler for so few icons.
pub struct IconPair {
    /// The palette's primary ink: a pastille at rest.
    pub rest: gdk::Texture,
    /// `on_ink`: drawn on the aimed pastille's inverted fill.
    pub on: gdk::Texture,
}

fn icons_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(".config/roue/icons")
}

/// Loads and rasterizes, by file name, the icon of each sector in
/// `segments` plus Cancel's and Confirm's. A missing file or an invalid
/// SVG is only reported on stderr: wheel.rs then shows that pastille
/// without an icon rather than not opening.
pub fn load(segments: &[Segment], palette: &Palette) -> HashMap<String, IconPair> {
    let dir = icons_dir();
    let rest_hex = palette::to_hex(palette.primary);
    let on_hex = palette::to_hex(palette.on_ink);
    let mut cache = HashMap::new();
    let names = segments.iter().map(|s| s.icon.as_str()).chain([CANCEL_ICON, CONFIRM_ICON]);
    for name in names {
        if cache.contains_key(name) {
            continue;
        }
        let path = dir.join(name);
        let Ok(svg) = std::fs::read_to_string(&path) else {
            eprintln!("[roue] icon not found: {path:?}");
            continue;
        };
        match (rasterize(&svg, &rest_hex), rasterize(&svg, &on_hex)) {
            (Some(rest), Some(on)) => {
                cache.insert(name.to_string(), IconPair { rest, on });
            }
            _ => eprintln!("[roue] invalid SVG: {path:?}"),
        }
    }
    cache
}

/// Rasterizes `svg_source` (with `currentColor` replaced by `color` -- all
/// our icons use it for the fill or the stroke) into a RASTER_PX x
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
