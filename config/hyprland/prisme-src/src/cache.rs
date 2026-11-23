//! The two on-disk caches Prisme reads and wallpaper-filter writes, in one
//! place so both binaries agree on paths, freshness and formats. Compiled
//! into each of them (main.rs's `mod cache`, wallpaper-filter.rs's
//! `#[path]` include): the crate has no lib.rs.
//!
//! - Screen-fit cache: ~/.cache/filtered_wallpapers/<W>x<H>/NAME, one
//!   folder per screen resolution, what wallpaper-set hands to awww and
//!   what Prisme's preview shows.
//! - Thumbnail cache: ~/.cache/wallpaper_thumbs/NAME.card.jpg, one per
//!   wallpaper whatever the screens, already at the size the carousel
//!   uploads (see THUMB_HEIGHT) so a launch decodes a small JPEG and
//!   nothing else.
//!
//! An entry is fresh when it is at least as new as its original (mtime,
//! symlinks followed). Every file is written to a temporary name and
//! renamed into place: awww, Prisme and wallpaper-filter may read an entry
//! while another process writes it, and must never see half a JPEG.

use fast_image_resize::{FilterType, ResizeAlg, ResizeOptions, Resizer};
use image::codecs::jpeg::JpegEncoder;
use image::{DynamicImage, ExtendedColorType, ImageEncoder, RgbImage, RgbaImage};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

/// `image`'s encoder defaults to 75, visibly soft on a full-screen
/// wallpaper. Both caches use this.
const JPEG_QUALITY: u8 = 95;

/// Height of a thumbnail: what the carousel uploads as is. Cards are drawn
/// 180 px high, and the focused card's thumbnail also stands in for the
/// preview for a moment at launch, so it keeps room above that.
pub const THUMB_HEIGHT: u32 = 460;

/// First bytes of a thumbnail's JPEG comment, followed by the original's
/// "WxH": the caption shows the original's size without opening it.
const SIZE_COMMENT: &str = "original ";

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

/// Folder of the screen-fit versions for one resolution.
fn fit_dir((w, h): (u32, u32)) -> Option<PathBuf> {
    Some(home()?.join(".cache/filtered_wallpapers").join(format!("{w}x{h}")))
}

/// `original` fitted to a `size` screen. It keeps the original's filename,
/// extension included (wallpaper-set looks it up by name), but is always a
/// JPEG: see `decode_any`.
pub fn fit_path(original: &Path, size: (u32, u32)) -> Option<PathBuf> {
    Some(fit_dir(size)?.join(original.file_name()?))
}

fn thumb_dir() -> Option<PathBuf> {
    Some(home()?.join(".cache/wallpaper_thumbs"))
}

/// `.card.jpg` after the full filename, extension included, so two
/// wallpapers that differ only by extension never share an entry.
pub fn thumb_path(original: &Path) -> Option<PathBuf> {
    Some(thumb_dir()?.join(format!("{}.card.jpg", original.file_name()?.to_string_lossy())))
}

/// The thumbnail format before this one: twice the height, no size
/// comment. Read once to make the new entry without decoding the original,
/// then removed.
fn legacy_thumb_path(original: &Path) -> Option<PathBuf> {
    Some(thumb_dir()?.join(format!("{}.thumb.jpg", original.file_name()?.to_string_lossy())))
}

pub fn is_fresh(original: &Path, cached: &Path) -> bool {
    let (Ok(src), Ok(cached)) = (std::fs::metadata(original), std::fs::metadata(cached)) else {
        return false;
    };
    match (src.modified(), cached.modified()) {
        (Ok(src), Ok(cached)) => cached >= src,
        _ => false,
    }
}

/// "1920x1200" (a DRM mode may carry a suffix: "1920x1080i").
pub fn parse_size(s: &str) -> Option<(u32, u32)> {
    let (w, h) = s.trim().split_once('x')?;
    let h: String = h.chars().take_while(|c| c.is_ascii_digit()).collect();
    Some((w.parse().ok()?, h.parse().ok()?))
}

/// Decodes any supported file by its content rather than its name: the
/// screen-fit cache keeps the original's filename, so a "NAME.jxl" in it is
/// a JPEG.
pub fn decode_any(path: &Path) -> Option<DynamicImage> {
    if is_jxl(path) {
        decode_jxl(path)
    } else {
        image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()
    }
}

/// A bare JXL codestream (FF 0A) or the ISO container's first box.
fn is_jxl(path: &Path) -> bool {
    let mut head = [0u8; 12];
    std::fs::File::open(path)
        .and_then(|mut f| std::io::Read::read_exact(&mut f, &mut head))
        .is_ok_and(|_| head.starts_with(&[0xFF, 0x0A]) || head == *b"\0\0\0\x0cJXL \r\n\x87\n")
}

/// JPEG XL through jxl-oxide (the `image` crate can't read it): GNOME's
/// default wallpapers ship as .jxl. 1/3/4 channels; anything else (CMYK)
/// counts as a decode failure.
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

/// An image's size from its header alone, no pixel decode.
pub fn read_dimensions(path: &Path) -> Option<(u32, u32)> {
    if is_jxl(path) {
        let image = jxl_oxide::JxlImage::builder().open(path).ok()?;
        Some((image.width(), image.height()))
    } else {
        image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.into_dimensions().ok()
    }
}

/// Resizes with fast_image_resize (SIMD convolution): several times faster
/// than the `image` crate's scalar filters, whose cost grows with the
/// source size even for a tiny output -- an 8K photo took ~1.5 s to
/// thumbnail. `crop_to_fit`: center-crop the source to the destination's
/// aspect ratio first, in the same pass (cover + crop without an
/// intermediate image).
pub fn resize(src: &RgbImage, w: u32, h: u32, filter: FilterType, crop_to_fit: bool) -> RgbImage {
    let mut dst = RgbImage::new(w.max(1), h.max(1));
    let mut options = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(filter));
    if crop_to_fit {
        options = options.fit_into_destination(Some((0.5, 0.5)));
    }
    Resizer::new()
        .resize(src, &mut dst, &options)
        .expect("same pixel type on both sides");
    dst
}

/// `rgb` as a JPEG, with `comment` as its first segment when given.
fn encode_jpeg(rgb: &RgbImage, comment: Option<&str>) -> Option<Vec<u8>> {
    let mut jpeg = Vec::new();
    JpegEncoder::new_with_quality(&mut jpeg, JPEG_QUALITY)
        .write_image(rgb.as_raw(), rgb.width(), rgb.height(), ExtendedColorType::Rgb8)
        .ok()?;
    let Some(text) = comment else {
        return Some(jpeg);
    };
    // A COM segment right after SOI: still a plain JPEG to any viewer.
    let len = u16::try_from(text.len() + 2).ok()?;
    let mut out = Vec::with_capacity(jpeg.len() + text.len() + 4);
    out.extend_from_slice(&jpeg[..2]);
    out.extend_from_slice(&[0xFF, 0xFE]);
    out.extend_from_slice(&len.to_be_bytes());
    out.extend_from_slice(text.as_bytes());
    out.extend_from_slice(&jpeg[2..]);
    Some(out)
}

/// Writes `bytes` to a temporary file beside `path`, then renames it over.
fn write_atomic(path: &Path, bytes: &[u8]) -> bool {
    static SERIAL: AtomicU64 = AtomicU64::new(0);
    let (Some(dir), Some(name)) = (path.parent(), path.file_name()) else {
        return false;
    };
    let _ = std::fs::create_dir_all(dir);
    let serial = SERIAL.fetch_add(1, Ordering::Relaxed);
    let tmp = dir.join(format!(".{}.{}.{serial}.tmp", name.to_string_lossy(), std::process::id()));
    if std::fs::write(&tmp, bytes).is_ok() && std::fs::rename(&tmp, path).is_ok() {
        return true;
    }
    let _ = std::fs::remove_file(&tmp);
    false
}

/// Saves `rgb` as a JPEG at `path`, whatever its extension. Only
/// wallpaper-filter writes screen-fit versions.
#[allow(dead_code)]
pub fn save_jpeg(rgb: &RgbImage, path: &Path) -> bool {
    encode_jpeg(rgb, None).is_some_and(|jpeg| write_atomic(path, &jpeg))
}

#[allow(dead_code)]
pub fn thumb_is_fresh(original: &Path) -> bool {
    thumb_path(original).is_some_and(|t| is_fresh(original, &t))
}

/// Scales `img` (the original's pixels, or the legacy thumbnail's) to
/// THUMB_HEIGHT and saves it as `original`'s thumbnail, `size` being the
/// original's. Returns the thumbnail even when it couldn't be saved.
pub fn store_thumb(original: &Path, img: &RgbImage, size: (u32, u32)) -> RgbImage {
    let (w, h) = img.dimensions();
    let thumb_h = THUMB_HEIGHT.min(h.max(1));
    let thumb_w = ((w as u64 * thumb_h as u64 + h.max(1) as u64 / 2) / h.max(1) as u64).max(1) as u32;
    let thumb = if (w, h) == (thumb_w, thumb_h) {
        img.clone()
    } else {
        resize(img, thumb_w, thumb_h, FilterType::Bilinear, false)
    };
    let comment = format!("{SIZE_COMMENT}{}x{}", size.0, size.1);
    let saved = thumb_path(original)
        .zip(encode_jpeg(&thumb, Some(&comment)))
        .is_some_and(|(path, jpeg)| write_atomic(&path, &jpeg));
    if saved {
        if let Some(legacy) = legacy_thumb_path(original) {
            let _ = std::fs::remove_file(legacy);
        }
    }
    thumb
}

/// The legacy thumbnail, when it is fresh, and the original's size (read
/// from its header): enough to make the new entry without a full decode.
pub fn legacy_thumb(original: &Path) -> Option<(RgbImage, (u32, u32))> {
    let legacy = legacy_thumb_path(original).filter(|l| is_fresh(original, l))?;
    let img = image::open(legacy).ok()?.into_rgb8();
    Some((img, read_dimensions(original)?))
}

/// `original`'s thumbnail and the original's size, when the entry is fresh
/// and readable. Only Prisme reads thumbnails.
#[allow(dead_code)]
pub fn read_thumb(original: &Path) -> Option<(RgbImage, (u32, u32))> {
    let path = thumb_path(original).filter(|t| is_fresh(original, t))?;
    let jpeg = std::fs::read(path).ok()?;
    let size = jpeg
        .strip_prefix(&[0xFF, 0xD8, 0xFF, 0xFE])
        .and_then(|rest| {
            let len = u16::from_be_bytes([*rest.first()?, *rest.get(1)?]) as usize;
            std::str::from_utf8(rest.get(2..len)?).ok()
        })
        .and_then(|text| parse_size(text.strip_prefix(SIZE_COMMENT)?))?;
    let img = image::load_from_memory_with_format(&jpeg, image::ImageFormat::Jpeg).ok()?.into_rgb8();
    Some((img, size))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thumb_round_trip() {
        let home = std::env::temp_dir().join(format!("prisme-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&home);
        std::fs::create_dir_all(&home).unwrap();
        std::env::set_var("HOME", &home);
        let original = home.join("fold.jxl");
        std::fs::write(&original, b"").unwrap();
        let img = RgbImage::from_pixel(1840, 920, image::Rgb([200, 120, 40]));
        let thumb = store_thumb(&original, &img, (7680, 3840));
        assert_eq!(thumb.dimensions(), (920, 460));
        let (read, size) = read_thumb(&original).expect("fresh thumbnail");
        assert_eq!(size, (7680, 3840));
        assert_eq!(read.dimensions(), (920, 460));
        let _ = std::fs::remove_dir_all(&home);
    }
}
