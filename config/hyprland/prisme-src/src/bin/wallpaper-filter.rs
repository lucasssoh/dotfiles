//! wallpaper-filter <image> — recomposes an image to exactly fill the
//! active screen's resolution, without ever cropping the axis that would
//! carry the main subject (height in landscape, width in portrait) -- this
//! "safe" axis is only scaled, never cropped. Only the remaining ("free")
//! axis is then adjusted: cropped if too large, or extended (blurred
//! background -- dominant color of the 4 corners if the image has a
//! near-uniform background, otherwise the whole image stretched -- with a
//! gradient fade on the edges) if too short. Native rewrite of the old
//! wallpaper-filter-one.sh (ImageMagick): same algorithm, but all
//! decoding/processing stays in memory in a single process rather than
//! calling `magick` five times per image with an encode/decode round trip
//! at every step.
//!
//! Called by scripts/wallpaper-cache-watcher.sh for every added/modified
//! image (that script handles inotify watching, the initial parallel
//! pass, and the FILTER_VERSION marker -- see it for the version to bump
//! if the algorithm below changes).

use image::{imageops::FilterType, DynamicImage, GenericImageView, Rgb, RgbImage};
use std::path::{Path, PathBuf};
use std::process::Command;

const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp"];
/// Sigma of the background's Gaussian blur -- eyeballed to match the old
/// ImageMagick `-blur 0x40` look.
const BLUR_SIGMA: f32 = 18.0;
/// Standard deviation (0..1, averaged over the 3 channels) below which the
/// image's 4 corners are considered a uniform background -- calibrated on
/// this repo's wallpaper collection (same images as the old ImageMagick
/// version's equivalent threshold).
const UNIFORM_THRESHOLD: f64 = 0.045;

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

fn cache_dir() -> PathBuf {
    home().join(".cache/filtered_wallpapers")
}

fn has_known_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// Cache already up to date (file present, mtime >= the source's) ->
/// nothing to do. Same contract as the historical bash test.
fn cache_is_fresh(src: &Path, cached: &Path) -> bool {
    let (Ok(src_meta), Ok(cached_meta)) = (std::fs::metadata(src), std::fs::metadata(cached))
    else {
        return false;
    };
    let (Ok(src_time), Ok(cached_time)) = (src_meta.modified(), cached_meta.modified()) else {
        return false;
    };
    cached_time >= src_time
}

/// Target resolution: internal screen if active, otherwise the 1st active
/// screen (via `hyprctl monitors -j`, never `monitors all -j` -- we want
/// the screen that's actually displaying pixels right now, see the
/// historical wallpaper-filter-one.sh). Falls back to 1920x1080 outside a
/// Hyprland session or if hyprctl/its JSON output are unusable.
fn target_resolution() -> (u32, u32) {
    const DEFAULT: (u32, u32) = (1920, 1080);
    let Ok(output) = Command::new("hyprctl").args(["monitors", "-j"]).output() else {
        return DEFAULT;
    };
    if !output.status.success() {
        return DEFAULT;
    }
    let Ok(monitors) = serde_json::from_slice::<serde_json::Value>(&output.stdout) else {
        return DEFAULT;
    };
    let Some(monitors) = monitors.as_array() else {
        return DEFAULT;
    };
    let is_internal = |m: &serde_json::Value| {
        m.get("name")
            .and_then(|n| n.as_str())
            .is_some_and(|n| n.starts_with("eDP") || n.starts_with("LVDS") || n.starts_with("DSI"))
    };
    let Some(chosen) = monitors.iter().find(|m| is_internal(m)).or_else(|| monitors.first())
    else {
        return DEFAULT;
    };
    let w = chosen.get("width").and_then(|v| v.as_u64());
    let h = chosen.get("height").and_then(|v| v.as_u64());
    match (w, h) {
        (Some(w), Some(h)) if w > 0 && h > 0 => (w as u32, h as u32),
        _ => DEFAULT,
    }
}

/// Dimensions of the image scaled on the safe axis only -- same integer
/// rule-of-three as the old bash version, to land exactly on `target_h`
/// (landscape) or `target_w` (portrait).
fn fit_dims(src_w: u32, src_h: u32, target_w: u32, target_h: u32, landscape: bool) -> (u32, u32) {
    if landscape {
        let fit_w = ((src_w as u64 * target_h as u64 + src_h as u64 / 2) / src_h as u64) as u32;
        (fit_w.max(1), target_h)
    } else {
        let fit_h = ((src_h as u64 * target_w as u64 + src_w as u64 / 2) / src_w as u64) as u32;
        (target_w, fit_h.max(1))
    }
}

/// Dimensions covering the whole target canvas (like `-resize WxH^`) --
/// never smaller than the target on either axis, rounding up to the next
/// pixel if needed.
fn cover_dims(src_w: u32, src_h: u32, target_w: u32, target_h: u32) -> (u32, u32) {
    let scale = (target_w as f64 / src_w as f64).max(target_h as f64 / src_h as f64);
    let cover_w = ((src_w as f64 * scale).ceil() as u32).max(target_w);
    let cover_h = ((src_h as f64 * scale).ceil() as u32).max(target_h);
    (cover_w, cover_h)
}

/// Center-crops `img` (already scaled to cover_w x cover_h) down to
/// exactly target_w x target_h.
fn center_crop(img: &DynamicImage, target_w: u32, target_h: u32) -> DynamicImage {
    let (w, h) = img.dimensions();
    let x = w.saturating_sub(target_w) / 2;
    let y = h.saturating_sub(target_h) / 2;
    img.crop_imm(x, y, target_w.min(w), target_h.min(h))
}

/// Average color of the 4 corners if their combined standard deviation
/// (noise within each corner AND hue difference between corners) is below
/// UNIFORM_THRESHOLD -- same principle as the old bash version, but
/// measured directly on the decoded pixels rather than calling `magick`
/// again. Sample size as a % of the smallest dimension.
fn uniform_corner_color(img: &DynamicImage) -> Option<Rgb<u8>> {
    let (w, h) = img.dimensions();
    let cs = (w.min(h) * 6 / 100).clamp(24, 200).min(w).min(h);
    let rgb = img.to_rgb8();
    let corners = [(0, 0), (w - cs, 0), (0, h - cs), (w - cs, h - cs)];

    let mut sum = [0f64; 3];
    let mut sum_sq = [0f64; 3];
    let mut n = 0f64;
    for &(cx, cy) in &corners {
        for y in cy..cy + cs {
            for x in cx..cx + cs {
                let p = rgb.get_pixel(x, y);
                for c in 0..3 {
                    let v = p[c] as f64;
                    sum[c] += v;
                    sum_sq[c] += v * v;
                }
                n += 1.0;
            }
        }
    }
    if n == 0.0 {
        return None;
    }

    let mut mean = [0u8; 3];
    let mut variance_sum = 0f64;
    for c in 0..3 {
        let m = sum[c] / n;
        variance_sum += ((sum_sq[c] / n) - (m * m)).max(0.0);
        mean[c] = m.round().clamp(0.0, 255.0) as u8;
    }
    let combined_std = (variance_sum / 3.0).sqrt() / 255.0;

    (combined_std < UNIFORM_THRESHOLD).then_some(Rgb(mean))
}

/// Blurred background behind the sharp image: dominant color of the 4
/// corners if detected as near-uniform (avoids the subject's colors
/// "bleeding" into the stretch), otherwise the whole image scaled to
/// cover the whole canvas then center-cropped. The blur applies in both
/// cases -- on an already-uniform fill it just dilutes any residual noise
/// from the sample.
fn build_background(img: &DynamicImage, target_w: u32, target_h: u32) -> RgbImage {
    let base = match uniform_corner_color(img) {
        Some(color) => RgbImage::from_pixel(target_w, target_h, color),
        None => {
            let (cover_w, cover_h) = cover_dims(img.width(), img.height(), target_w, target_h);
            let covered = img.resize_exact(cover_w, cover_h, FilterType::Lanczos3);
            center_crop(&covered, target_w, target_h).to_rgb8()
        }
    };
    image::imageops::blur(&base, BLUR_SIGMA)
}

/// Fade weight (0..255) for a pixel at `pos` on an axis of length `len`:
/// 0 at the edge (within the first/last `feather` pixels), linear ramp up
/// to 255 at `feather` px from the edge, opaque plateau in the middle.
/// Only one axis matters -- the safe axis never needs a fade, it already
/// matches the canvas edge exactly.
fn edge_weight(pos: u32, len: u32, feather: u32) -> u8 {
    if feather == 0 || len == 0 {
        return 255;
    }
    let dist_from_end = len.saturating_sub(1).saturating_sub(pos);
    let d = pos.min(dist_from_end);
    if d >= feather {
        255
    } else {
        ((d as f64 / feather as f64) * 255.0).round() as u8
    }
}

/// Composes the sharp image (`fit`, faded on its free axis) at the center
/// of the blurred background (`bg`, already at target_w x target_h).
fn compose(bg: RgbImage, fit: &RgbImage, target_w: u32, target_h: u32, landscape: bool) -> RgbImage {
    let (fit_w, fit_h) = fit.dimensions();
    let feather = if landscape { fit_w / 8 } else { fit_h / 8 };
    let off_x = (target_w - fit_w) / 2;
    let off_y = (target_h - fit_h) / 2;

    let mut composed = bg;
    for y in 0..fit_h {
        let alpha = if landscape {
            255
        } else {
            edge_weight(y, fit_h, feather)
        };
        for x in 0..fit_w {
            let alpha = if landscape { edge_weight(x, fit_w, feather) } else { alpha };
            if alpha == 0 {
                continue;
            }
            let src = fit.get_pixel(x, y);
            let dst = composed.get_pixel_mut(off_x + x, off_y + y);
            if alpha == 255 {
                *dst = *src;
            } else {
                let a = alpha as f32 / 255.0;
                for c in 0..3 {
                    dst[c] = (src[c] as f32 * a + dst[c] as f32 * (1.0 - a)).round() as u8;
                }
            }
        }
    }
    composed
}

fn main() {
    let Some(arg) = std::env::args().nth(1) else {
        return;
    };
    let img_path = PathBuf::from(arg);
    if !has_known_extension(&img_path) {
        return;
    }
    let Some(filename) = img_path.file_name() else {
        return;
    };
    let cached = cache_dir().join(filename);
    if cache_is_fresh(&img_path, &cached) {
        return;
    }

    let Ok(img) = image::open(&img_path) else {
        return;
    };
    let (src_w, src_h) = img.dimensions();
    let (target_w, target_h) = target_resolution();
    let landscape = target_w >= target_h;

    // Safe axis + crop/extend decision (cross multiplication in
    // integers -- no floats, no rounding ambiguity).
    let crop_mode = if landscape {
        src_w as u64 * target_h as u64 >= target_w as u64 * src_h as u64
    } else {
        src_h as u64 * target_w as u64 >= target_h as u64 * src_w as u64
    };

    let (fit_w, fit_h) = fit_dims(src_w, src_h, target_w, target_h, landscape);
    let result = if crop_mode {
        let fit = img.resize_exact(fit_w, fit_h, FilterType::Lanczos3);
        center_crop(&fit, target_w, target_h).to_rgb8()
    } else {
        let fit = img.resize_exact(fit_w, fit_h, FilterType::Lanczos3).to_rgb8();
        let bg = build_background(&img, target_w, target_h);
        compose(bg, &fit, target_w, target_h, landscape)
    };

    let _ = std::fs::create_dir_all(cache_dir());
    if result.save(&cached).is_ok() {
        let _ = Command::new("notify-send")
            .arg("Wallpaper ready")
            .arg(format!(
                "{} fitted {target_w}x{target_h}",
                filename.to_string_lossy()
            ))
            .args(["--expire-time", "2000"])
            .status();
    }
}
