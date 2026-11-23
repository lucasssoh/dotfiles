//! wallpaper-filter [--size WxH]... <image>... — recomposes images to exactly
//! fill each screen's resolution: every connected screen by default (see
//! `screens`), or the sizes given. One decode per image, every size derived
//! from it (see `resize`), and none at all when every size is already
//! fresh. Each result lands in `~/.cache/filtered_wallpapers/<W>x<H>/`,
//! read by `hypr/scripts/wallpaper-set`. Prints `fitted <name> <W>x<H>` for
//! every file it writes. Two modes, picked per-file (see `is_safe_mode`):
//!
//! - "fill" (default): plain cover + center-crop, no safe axis, no blur,
//!   no background compositing -- both axes are cropped as needed to fill
//!   the canvas exactly. Meant for abstract/pattern art and landscape
//!   photos, where cropping doesn't lose anything worth protecting and a
//!   fake blurred backdrop would only be a distraction.
//! - "safe": never crops the axis that would carry the main subject
//!   (height in landscape, width in portrait) -- that axis is only scaled.
//!   Only the remaining ("free") axis is adjusted: cropped if too large,
//!   or extended (blurred background -- dominant color of the 4 corners if
//!   the image has a near-uniform background, otherwise the whole image
//!   stretched, darkened further when it covers a large share of the
//!   canvas to disguise it as a duplicate of the sharp subject -- with a
//!   gradient fade on the edges) if too short. Meant for images with a
//!   subject that must stay fully visible (portraits, character art).
//!
//! Native rewrite of the old wallpaper-filter-one.sh (ImageMagick): same
//! algorithm, but all decoding/processing stays in memory in a single
//! process rather than calling `magick` five times per image with an
//! encode/decode round trip at every step -- JPEG XL sources included
//! (jxl-oxide, pure Rust, no `magick`/`djxl` subprocess).
//!
//! Also maintains the carousel's thumbnail cache (~/.cache/wallpaper_thumbs,
//! see cache.rs), from the same decode.
//!
//! Called by scripts/wallpaper-cache-watcher.sh with every wallpaper in one
//! run (that script handles inotify watching, the pass over all
//! wallpapers, and the FILTER_VERSION marker -- see it for the version to
//! bump if the algorithm below changes). The images are processed one at a
//! time: each holds a full-resolution decode in memory.

#[path = "../cache.rs"]
mod cache;

use cache::{parse_size, resize};
use fast_image_resize::FilterType;
use image::{Rgb, RgbImage};
use std::path::{Path, PathBuf};
use std::process::Command;

const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "jxl"];
/// Sigma of the background's Gaussian blur -- bumped from the old
/// ImageMagick `-blur 0x40` look (18.0) to better disguise the "cover +
/// crop" background as a duplicate of the sharp subject on portrait
/// sources under a landscape target (see EXTENSION_VEIL_* below).
const BLUR_SIGMA: f32 = 30.0;
/// Standard deviation (0..1, averaged over the 3 channels) below which the
/// image's 4 corners are considered a uniform background. Deliberately
/// tight: a looser threshold (0.045, the original ImageMagick-equivalent
/// value) also caught dark/vignetted cinematic scenes with real detail,
/// filling their background with a flat, unblurred color band instead of
/// extending the scene (no texture survives blurring an already-flat
/// fill). Only true flat-color sources (posters, solid backgrounds)
/// should land here now.
const UNIFORM_THRESHOLD: f64 = 0.015;
/// Extension ratio (free axis: how much of it isn't covered by the sharp
/// "fit" image) above which the background starts getting darkened -- see
/// `veil_alpha`. Below this, the fit image dominates the canvas enough
/// that a duplicated/rescaled background isn't distracting.
const EXTENSION_VEIL_START: f64 = 0.3;
/// Darkening applied to the background at EXTENSION_VEIL_START (ramps up
/// to EXTENSION_VEIL_MAX_ALPHA as the ratio approaches 1.0). Keeps a
/// portrait source's duplicated background from reading as an obvious
/// second copy of the subject, without going full letterbox-black.
const EXTENSION_VEIL_MIN_ALPHA: f32 = 0.15;
const EXTENSION_VEIL_MAX_ALPHA: f32 = 0.45;

/// How much darkening to apply to the background, given how much of the
/// free axis it has to cover on its own (0 = fit image fills the canvas,
/// 1 = fit image contributes nothing to that axis).
fn veil_alpha(extension_ratio: f64) -> f32 {
    if extension_ratio <= EXTENSION_VEIL_START {
        return 0.0;
    }
    let t = ((extension_ratio - EXTENSION_VEIL_START) / (1.0 - EXTENSION_VEIL_START)).min(1.0);
    EXTENSION_VEIL_MIN_ALPHA + (t as f32) * (EXTENSION_VEIL_MAX_ALPHA - EXTENSION_VEIL_MIN_ALPHA)
}

/// Darkens `img` in place by blending every pixel toward black by `alpha`
/// (0 = no change, 1 = fully black).
fn apply_dark_veil(img: &mut RgbImage, alpha: f32) {
    if alpha <= 0.0 {
        return;
    }
    for p in img.pixels_mut() {
        for c in p.0.iter_mut() {
            *c = (*c as f32 * (1.0 - alpha)).round() as u8;
        }
    }
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

fn has_known_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// User config file listing filename glob patterns (one per line, `#`
/// comments, blank lines ignored) that should use "safe" mode (subject
/// axis never cropped, blurred background) instead of the default "fill"
/// mode -- see the module doc comment. Only a single `*` wildcard per
/// pattern is supported (prefix/suffix/exact match).
/// Symlinked by install.sh like wallpapers.conf and wallpapers-extra.conf.
fn safe_mode_conf_path() -> PathBuf {
    home().join(".config/prisme/wallpaper-safe-mode.conf")
}

fn glob_match(pattern: &str, name: &str) -> bool {
    match pattern.split_once('*') {
        None => pattern == name,
        Some((prefix, suffix)) => {
            name.len() >= prefix.len() + suffix.len()
                && name.starts_with(prefix)
                && name.ends_with(suffix)
        }
    }
}

/// wallpaper-safe-mode.conf's patterns, read once per run. Missing/empty
/// file -> every image uses the default "fill" mode.
fn safe_mode_patterns() -> Vec<String> {
    let Ok(content) = std::fs::read_to_string(safe_mode_conf_path()) else {
        return Vec::new();
    };
    content
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(String::from)
        .collect()
}

/// Every connected screen's resolution: what Hyprland drives
/// (`hyprctl monitors -j`, rotated screens swapped to their real shape),
/// else what the kernel reports (`/sys/class/drm`, native mode of each
/// connected connector -- this is what an install sees, before any session),
/// else 1920x1080. No duplicates.
fn screens() -> Vec<(u32, u32)> {
    let mut found = hyprland_screens();
    if found.is_empty() {
        found = drm_screens();
    }
    if found.is_empty() {
        found.push((1920, 1080));
    }
    let mut unique = Vec::new();
    for s in found {
        if !unique.contains(&s) {
            unique.push(s);
        }
    }
    unique
}

fn hyprland_screens() -> Vec<(u32, u32)> {
    let Ok(output) = Command::new("hyprctl").args(["monitors", "-j"]).output() else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    let Ok(serde_json::Value::Array(monitors)) = serde_json::from_slice(&output.stdout) else {
        return Vec::new();
    };
    monitors
        .iter()
        .filter_map(|m| {
            let w = m.get("width")?.as_u64()? as u32;
            let h = m.get("height")?.as_u64()? as u32;
            let rotated = m.get("transform").and_then(|t| t.as_u64()).unwrap_or(0) % 2 == 1;
            (w > 0 && h > 0).then_some(if rotated { (h, w) } else { (w, h) })
        })
        .collect()
}

/// `card*-<connector>/status` == connected, first line of `modes` (the
/// preferred, native mode). Internal panels first.
fn drm_screens() -> Vec<(u32, u32)> {
    let Ok(entries) = std::fs::read_dir("/sys/class/drm") else {
        return Vec::new();
    };
    let mut found: Vec<(bool, (u32, u32))> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            let connector = name.split_once('-')?.1.to_string();
            let dir = e.path();
            let status = std::fs::read_to_string(dir.join("status")).ok()?;
            if status.trim() != "connected" {
                return None;
            }
            let modes = std::fs::read_to_string(dir.join("modes")).ok()?;
            let size = parse_size(modes.lines().next()?)?;
            let internal = ["eDP", "LVDS", "DSI"].iter().any(|p| connector.starts_with(p));
            Some((internal, size))
        })
        .collect();
    found.sort_by_key(|(internal, _)| !internal);
    found.into_iter().map(|(_, s)| s).collect()
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

/// Average color of the 4 corners if their combined standard deviation
/// (noise within each corner AND hue difference between corners) is below
/// UNIFORM_THRESHOLD -- same principle as the old bash version, but
/// measured directly on the decoded pixels rather than calling `magick`
/// again. Sample size as a % of the smallest dimension.
fn uniform_corner_color(rgb: &RgbImage) -> Option<Rgb<u8>> {
    let (w, h) = rgb.dimensions();
    let cs = (w.min(h) * 6 / 100).clamp(24, 200).min(w).min(h);
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
/// from the sample. `extension_ratio` (how much of the free axis the fit
/// image leaves uncovered) darkens the result further out -- see
/// `veil_alpha` -- to keep a "cover + crop" background from reading as an
/// obvious duplicate of the sharp subject on portrait sources.
fn build_background(img: &RgbImage, target_w: u32, target_h: u32, extension_ratio: f64) -> RgbImage {
    let base = match uniform_corner_color(img) {
        Some(color) => RgbImage::from_pixel(target_w, target_h, color),
        None => resize(img, target_w, target_h, FilterType::Lanczos3, true),
    };
    let mut blurred = image::imageops::blur(&base, BLUR_SIGMA);
    apply_dark_veil(&mut blurred, veil_alpha(extension_ratio));
    blurred
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

/// One screen size, safe mode (rare: images listed in
/// wallpaper-safe-mode.conf): the subject's axis is only scaled; the other
/// one is cropped, or extended over a blurred background when too short.
fn fit_safe(img: &RgbImage, target_w: u32, target_h: u32) -> RgbImage {
    let (src_w, src_h) = img.dimensions();
    let landscape = target_w >= target_h;
    // Crop or extend (cross multiplication in integers -- no floats, no
    // rounding ambiguity).
    let crop_mode = if landscape {
        src_w as u64 * target_h as u64 >= target_w as u64 * src_h as u64
    } else {
        src_h as u64 * target_w as u64 >= target_h as u64 * src_w as u64
    };
    if crop_mode {
        // Scaling the safe axis to fit then cropping the other one is a
        // centered cover crop.
        return resize(img, target_w, target_h, FilterType::Lanczos3, true);
    }
    let (fit_w, fit_h) = fit_dims(src_w, src_h, target_w, target_h, landscape);
    let fit = resize(img, fit_w, fit_h, FilterType::Lanczos3, false);
    let extension_ratio = if landscape {
        1.0 - (fit_w as f64 / target_w as f64)
    } else {
        1.0 - (fit_h as f64 / target_h as f64)
    };
    let bg = build_background(img, target_w, target_h, extension_ratio);
    compose(bg, &fit, target_w, target_h, landscape)
}

fn main() {
    let mut sizes = Vec::new();
    let mut images = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        if a == "--size" {
            match args.next().as_deref().and_then(parse_size) {
                Some(s) => sizes.push(s),
                None => {
                    eprintln!("wallpaper-filter: --size takes WxH");
                    std::process::exit(2);
                }
            }
        } else {
            images.push(PathBuf::from(a));
        }
    }
    if images.is_empty() {
        eprintln!("usage: wallpaper-filter [--size WxH]... <image>...");
        std::process::exit(2);
    }
    if sizes.is_empty() {
        sizes = screens();
    }
    let safe_patterns = safe_mode_patterns();

    for path in &images {
        // One image that a decoder chokes on must not end the whole pass.
        let run = std::panic::catch_unwind(|| process(path, &sizes, &safe_patterns));
        if run.is_err() {
            eprintln!("wallpaper-filter: {} skipped", path.display());
        }
    }
}

/// Brings one image's thumbnail and screen-fit versions up to date.
fn process(img_path: &Path, sizes: &[(u32, u32)], safe_patterns: &[String]) {
    if !has_known_extension(img_path) {
        return;
    }
    let Some(filename) = img_path.file_name() else {
        return;
    };
    let name = filename.to_string_lossy().into_owned();
    let thumb_fresh = cache::thumb_is_fresh(img_path);
    let stale: Vec<(u32, u32)> = sizes
        .iter()
        .copied()
        .filter(|&size| !cache::fit_path(img_path, size).is_some_and(|f| cache::is_fresh(img_path, &f)))
        .collect();
    if stale.is_empty() {
        if thumb_fresh {
            return;
        }
        // Only the thumbnail is missing: from the previous format's, when
        // there is one, rather than decoding the original.
        if let Some((img, size)) = cache::legacy_thumb(img_path) {
            cache::store_thumb(img_path, &img, size);
            return;
        }
    }

    let Some(img) = cache::decode_any(img_path) else {
        return;
    };
    let img = img.into_rgb8();

    if !thumb_fresh {
        // Reuses this same decode -- no second pass over the original.
        cache::store_thumb(img_path, &img, img.dimensions());
    }

    let safe = safe_patterns.iter().any(|pattern| glob_match(pattern, &name));
    for (target_w, target_h) in stale {
        let result = if safe {
            fit_safe(&img, target_w, target_h)
        } else {
            // Fill mode: centered cover crop -- see the module doc comment.
            resize(&img, target_w, target_h, FilterType::Lanczos3, true)
        };
        // Always JPEG-encoded whatever the file's own extension, which
        // stays the original's -- wallpaper-set resolves the cache by plain
        // basename. awww and the `image` crate sniff content, not
        // extensions.
        let saved = cache::fit_path(img_path, (target_w, target_h)).is_some_and(|f| cache::save_jpeg(&result, &f));
        if saved {
            println!("fitted {name} {target_w}x{target_h}");
        }
    }
}
