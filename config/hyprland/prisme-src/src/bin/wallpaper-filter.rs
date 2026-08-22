//! wallpaper-filter <image> — recomposes an image to exactly fill the
//! active screen's resolution. Two modes, picked per-file (see
//! `is_fill_mode`):
//!
//! - "safe" (default): never crops the axis that would carry the main
//!   subject (height in landscape, width in portrait) -- that axis is only
//!   scaled. Only the remaining ("free") axis is adjusted: cropped if too
//!   large, or extended (blurred background -- dominant color of the 4
//!   corners if the image has a near-uniform background, otherwise the
//!   whole image stretched, darkened further when it covers a large share
//!   of the canvas to disguise it as a duplicate of the sharp subject --
//!   with a gradient fade on the edges) if too short. Meant for images with
//!   a subject that must stay fully visible (portraits, character art).
//! - "fill": plain cover + center-crop, no safe axis, no blur, no
//!   background compositing -- both axes are cropped as needed to fill the
//!   canvas exactly. Meant for abstract/pattern art and landscape photos,
//!   where cropping doesn't lose anything worth protecting and a fake
//!   blurred backdrop would only be a distraction.
//!
//! Native rewrite of the old wallpaper-filter-one.sh (ImageMagick): same
//! algorithm, but all decoding/processing stays in memory in a single
//! process rather than calling `magick` five times per image with an
//! encode/decode round trip at every step -- JPEG XL sources included
//! (jxl-oxide, pure Rust, no `magick`/`djxl` subprocess).
//!
//! Called by scripts/wallpaper-cache-watcher.sh for every added/modified
//! image (that script handles inotify watching, the initial parallel
//! pass, and the FILTER_VERSION marker -- see it for the version to bump
//! if the algorithm below changes).

use image::{imageops::FilterType, DynamicImage, GenericImageView, Rgb, RgbImage, RgbaImage};
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

fn cache_dir() -> PathBuf {
    home().join(".cache/filtered_wallpapers")
}

fn has_known_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// Decodes a JPEG XL file into an in-memory `DynamicImage` -- jxl-oxide
/// only exposes an interleaved-sample stream (`Render::stream`), not an
/// `image`-crate buffer directly, so this copies through a flat `Vec<u8>`
/// first. 1/3/4-channel sources (grayscale/RGB/RGBA, covering everything
/// GNOME's backgrounds ship as) are supported; anything else (e.g. CMYK)
/// is treated as a decode failure like a corrupt file would be.
fn decode_jxl(path: &Path) -> Option<DynamicImage> {
    let image = jxl_oxide::JxlImage::builder().open(path).ok()?;
    let render = image.render_frame(0).ok()?;
    let mut stream = render.stream();
    let (w, h, channels) = (stream.width(), stream.height(), stream.channels());
    let mut buf = vec![0u8; (w as usize) * (h as usize) * (channels as usize)];
    stream.write_to_buffer(&mut buf);
    match channels {
        1 => image::GrayImage::from_raw(w, h, buf).map(DynamicImage::ImageLuma8),
        3 => RgbImage::from_raw(w, h, buf).map(DynamicImage::ImageRgb8),
        4 => RgbaImage::from_raw(w, h, buf).map(DynamicImage::ImageRgba8),
        _ => None,
    }
}

/// Opens any supported image, JPEG XL included -- the `image` crate itself
/// has no JXL support, so that extension is routed to jxl-oxide instead.
fn open_image(path: &Path) -> Option<DynamicImage> {
    let is_jxl = path
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("jxl"));
    if is_jxl {
        decode_jxl(path)
    } else {
        image::open(path).ok()
    }
}

/// User config file listing filename glob patterns (one per line, `#`
/// comments, blank lines ignored) that should use "fill" mode (plain
/// cover + center-crop, no blur) instead of the default "safe" mode --
/// see the module doc comment. Only a single `*` wildcard per pattern is
/// supported (prefix/suffix/exact match), which is enough for the
/// prefix-based naming this repo's wallpapers use (`gnome-*`, `macos-*`).
/// Symlinked by install.sh like wallpapers.conf and wallpapers-extra.conf.
fn fill_mode_conf_path() -> PathBuf {
    home().join(".config/prisme/wallpaper-fill-mode.conf")
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

/// Whether `filename` should use "fill" mode, per wallpaper-fill-mode.conf.
/// Missing/empty file -> nothing uses fill mode (every image keeps the
/// current "safe" behavior, unaffected by this feature until opted in).
fn is_fill_mode(filename: &str) -> bool {
    let Ok(content) = std::fs::read_to_string(fill_mode_conf_path()) else {
        return false;
    };
    content
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .any(|pattern| glob_match(pattern, filename))
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
/// from the sample. `extension_ratio` (how much of the free axis the fit
/// image leaves uncovered) darkens the result further out -- see
/// `veil_alpha` -- to keep a "cover + crop" background from reading as an
/// obvious duplicate of the sharp subject on portrait sources.
fn build_background(img: &DynamicImage, target_w: u32, target_h: u32, extension_ratio: f64) -> RgbImage {
    let base = match uniform_corner_color(img) {
        Some(color) => RgbImage::from_pixel(target_w, target_h, color),
        None => {
            let (cover_w, cover_h) = cover_dims(img.width(), img.height(), target_w, target_h);
            let covered = img.resize_exact(cover_w, cover_h, FilterType::Lanczos3);
            center_crop(&covered, target_w, target_h).to_rgb8()
        }
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

    let Some(img) = open_image(&img_path) else {
        return;
    };
    let (src_w, src_h) = img.dimensions();
    let (target_w, target_h) = target_resolution();
    let landscape = target_w >= target_h;

    let result = if is_fill_mode(&filename.to_string_lossy()) {
        // Fill mode: plain cover + center-crop, no safe axis, no
        // background -- see the module doc comment.
        let (cover_w, cover_h) = cover_dims(src_w, src_h, target_w, target_h);
        let covered = img.resize_exact(cover_w, cover_h, FilterType::Lanczos3);
        center_crop(&covered, target_w, target_h).to_rgb8()
    } else {
        // Safe axis + crop/extend decision (cross multiplication in
        // integers -- no floats, no rounding ambiguity).
        let crop_mode = if landscape {
            src_w as u64 * target_h as u64 >= target_w as u64 * src_h as u64
        } else {
            src_h as u64 * target_w as u64 >= target_h as u64 * src_w as u64
        };

        let (fit_w, fit_h) = fit_dims(src_w, src_h, target_w, target_h, landscape);
        if crop_mode {
            let fit = img.resize_exact(fit_w, fit_h, FilterType::Lanczos3);
            center_crop(&fit, target_w, target_h).to_rgb8()
        } else {
            let fit = img.resize_exact(fit_w, fit_h, FilterType::Lanczos3).to_rgb8();
            let extension_ratio = if landscape {
                1.0 - (fit_w as f64 / target_w as f64)
            } else {
                1.0 - (fit_h as f64 / target_h as f64)
            };
            let bg = build_background(&img, target_w, target_h, extension_ratio);
            compose(bg, &fit, target_w, target_h, landscape)
        }
    };

    let _ = std::fs::create_dir_all(cache_dir());
    // Always JPEG-encoded regardless of the source's/cached path's own
    // extension (kept identical to the original -- apply.rs and
    // wallpaper-slideshow.sh resolve the cache by plain basename, so it
    // can't change): `.save()` would instead pick an encoder from that
    // extension, which fails outright for "jxl" (not a supported *write*
    // format here, decode-only via jxl-oxide). awww/the `image` crate on
    // the reading end sniff content rather than trust the extension, so a
    // JPEG-content ".jxl" cache file opens the same as any other.
    if result.save_with_format(&cached, image::ImageFormat::Jpeg).is_ok() {
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
