//! Asynchronous decoding and scaling of wallpaper thumbnails. Decoding
//! (CPU-heavy) runs on dedicated threads off the GTK loop; only the final
//! GObject texture construction goes back to the main thread, as GTK
//! requires.
//!
//! Reads wallpaper-filter.rs's small pre-made thumbnail cache
//! (~/.cache/wallpaper_thumbs) rather than decoding each full-resolution
//! original (up to 8K in this collection) on every launch -- falls back
//! to that full decode only when no fresh thumbnail exists yet.

use gtk4::gdk::{self, MemoryFormat, MemoryTexture};
use gtk4::glib;
use gtk4::prelude::*;
use image::imageops::FilterType;
use image::DynamicImage;
use std::path::{Path, PathBuf};

/// Height shared by all thumbnails -- only card width animates (see
/// card.rs), height stays fixed.
pub const CARD_HEIGHT: i32 = 460;

/// Raw pixels decoded on a thread -- no GObject type here (`gdk::Texture`
/// isn't Send), just bytes that get wrapped into a texture on the GTK
/// thread.
struct DecodedImage {
    rgba: Vec<u8>,
    width: i32,
    height: i32,
    orig_width: i32,
    orig_height: i32,
}

/// Decoding result for a thumbnail, ready to be placed on a card by index.
/// `texture` is `None` if the image couldn't be decoded.
pub struct ThumbResult {
    pub index: usize,
    pub texture: Option<gdk::Texture>,
    pub orig_width: i32,
    pub orig_height: i32,
}

/// Number of decoding threads -- bounded (unlike the old "one thread per
/// image launched all at once"): with loading now WINDOWED (see main.rs --
/// only cards near the focus are requested, not the whole collection), the
/// peak of simultaneous threads was already reduced in practice, but
/// nothing previously stopped a fast stream of requests (rapid scrolling)
/// from spawning as many threads as cards visited. Bounding the pool also
/// caps transient memory: each decode briefly holds the FULL-RESOLUTION
/// source image in RAM before downscaling (a 6000×4000 photo ≈ 96 MB raw),
/// so an unbounded pool of concurrent threads could inflate the RSS peak
/// well past the steady-state level, even when that level stayed
/// reasonable.
const WORKER_COUNT: usize = 4;

/// Handle to the decoding pool -- `request()` can be called at any time
/// after construction (not a batch fixed once and for all like the old
/// `spawn_loader`), to allow on-demand loading driven by the visible
/// window (see main.rs). `Clone` is just a clone of the `Sender` (shared
/// channel), no new threads.
#[derive(Clone)]
pub struct ThumbLoader {
    request_tx: async_channel::Sender<(usize, PathBuf)>,
}

impl ThumbLoader {
    /// Starts `WORKER_COUNT` persistent decoding threads (not one thread
    /// per image) and the GLib task that builds textures on the main
    /// thread. The returned receiver is consumed exactly like the old
    /// `spawn_loader`'s was.
    pub fn new() -> (Self, async_channel::Receiver<ThumbResult>) {
        let (request_tx, request_rx) = async_channel::unbounded::<(usize, PathBuf)>();
        let (raw_tx, raw_rx) = async_channel::unbounded();

        for _ in 0..WORKER_COUNT {
            let request_rx = request_rx.clone();
            let raw_tx = raw_tx.clone();
            std::thread::spawn(move || {
                while let Ok((index, path)) = request_rx.recv_blocking() {
                    let decoded = decode_and_scale(&path);
                    // Texture (GObject) construction must stay on the GTK
                    // thread -- the channel only carries raw bytes up to
                    // this point; it's the receiver below that calls
                    // MemoryTexture::new.
                    if raw_tx.send_blocking((index, decoded)).is_err() {
                        break;
                    }
                }
            });
        }

        let (out_tx, out_rx) = async_channel::unbounded();
        glib::MainContext::default().spawn_local(async move {
            while let Ok((index, decoded)) = raw_rx.recv().await {
                let (texture, orig_width, orig_height) = match decoded {
                    Some(d) => {
                        let rowstride = (d.width * 4) as usize;
                        let bytes = glib::Bytes::from_owned(d.rgba);
                        let tex = MemoryTexture::new(
                            d.width,
                            d.height,
                            MemoryFormat::R8g8b8a8,
                            &bytes,
                            rowstride,
                        );
                        (Some(tex.upcast::<gdk::Texture>()), d.orig_width, d.orig_height)
                    }
                    None => (None, 0, 0),
                };
                if out_tx
                    .send(ThumbResult {
                        index,
                        texture,
                        orig_width,
                        orig_height,
                    })
                    .await
                    .is_err()
                {
                    break;
                }
            }
        });

        (Self { request_tx }, out_rx)
    }

    /// Requests decoding of `path` for card `index` -- result delivered
    /// later via the receiver returned by `new()`. Any unbounded channel
    /// accepts the send without ever blocking the caller (GTK thread),
    /// even if the workers are busy: the request just waits in the queue.
    pub fn request(&self, index: usize, path: PathBuf) {
        let _ = self.request_tx.send_blocking((index, path));
    }
}

fn is_jxl(path: &Path) -> bool {
    path.extension().and_then(|e| e.to_str()).is_some_and(|e| e.eq_ignore_ascii_case("jxl"))
}

/// Decodes a JPEG XL file -- the `image` crate has no JXL support, so
/// GNOME's default wallpapers (shipped as .jxl) need jxl-oxide instead.
/// Same approach as wallpaper-filter.rs's decode_jxl (duplicated rather
/// than shared: this crate has no lib.rs, wallpaper-filter.rs is a
/// separate `bin/` target with no access to this file's private items).
fn decode_jxl(path: &Path) -> Option<DynamicImage> {
    let image = jxl_oxide::JxlImage::builder().open(path).ok()?;
    let render = image.render_frame(0).ok()?;
    let mut stream = render.stream();
    let (w, h, channels) = (stream.width(), stream.height(), stream.channels());
    let mut buf = vec![0u8; (w as usize) * (h as usize) * (channels as usize)];
    stream.write_to_buffer(&mut buf);
    match channels {
        1 => image::GrayImage::from_raw(w, h, buf).map(DynamicImage::ImageLuma8),
        3 => image::RgbImage::from_raw(w, h, buf).map(DynamicImage::ImageRgb8),
        4 => image::RgbaImage::from_raw(w, h, buf).map(DynamicImage::ImageRgba8),
        _ => None,
    }
}

/// True resolution shown on the card (see card.rs's `dims_layout`) --
/// header-only, no pixel decode: `JxlImage::builder().open()` parses the
/// container/header but doesn't render a frame, and `ImageReader` reads
/// just enough of jpg/png/webp to report dimensions. Cheap even on an 8K
/// source, unlike decoding it fully just to read `.width()`/`.height()`.
fn read_dimensions(path: &Path) -> Option<(u32, u32)> {
    if is_jxl(path) {
        let image = jxl_oxide::JxlImage::builder().open(path).ok()?;
        Some((image.width(), image.height()))
    } else {
        image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.into_dimensions().ok()
    }
}

/// Cache already up to date (file present, mtime >= the source's) -- same
/// check as wallpaper-filter.rs's cache_is_fresh (duplicated, see
/// decode_jxl above for why).
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

/// wallpaper-filter.rs's thumbnail cache for `path`, if it's had the
/// chance to build one yet (wallpaper-cache-watcher.sh, running
/// continuously, processes new/changed wallpapers on its own -- this
/// isn't triggered from here). See its THUMB_HEIGHT/thumb_cache_path for
/// the matching write side.
fn thumb_cache_path(path: &Path) -> Option<PathBuf> {
    let filename = path.file_name()?;
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join(".cache/wallpaper_thumbs").join(format!("{}.thumb.jpg", filename.to_string_lossy())))
}

/// Decodes the image and resizes it to `CARD_HEIGHT`, keeping the true
/// original dimensions for display (see card.rs). Reads the small
/// pre-made thumbnail (~1/10th the bytes of an 8K original, and never
/// needs jxl-oxide since wallpaper-filter.rs always writes it as JPEG)
/// when one is fresh, instead of decoding the full-resolution source on
/// every launch -- that fallback still exists (a brand new wallpaper
/// wallpaper-cache-watcher.sh hasn't reached yet, or wallpapers used
/// outside this repo's pipeline entirely) so the carousel never shows a
/// blank card, just a slower first load for that one.
fn decode_and_scale(path: &std::path::Path) -> Option<DecodedImage> {
    let (orig_width, orig_height) = read_dimensions(path)?;

    let thumb_path = thumb_cache_path(path).filter(|t| cache_is_fresh(path, t));
    let img = match thumb_path.and_then(|t| image::open(t).ok()) {
        Some(img) => img,
        None if is_jxl(path) => decode_jxl(path)?,
        None => image::open(path).ok()?,
    };

    // `resize` scales while preserving the ratio to fit within the given
    // box -- a generous width leaves height as the only limiting factor.
    let resized = img.resize(8192, CARD_HEIGHT as u32, FilterType::Triangle);
    let rgba = resized.to_rgba8();
    let (width, height) = rgba.dimensions();
    Some(DecodedImage {
        rgba: rgba.into_raw(),
        width: width as i32,
        height: height as i32,
        orig_width: orig_width as i32,
        orig_height: orig_height as i32,
    })
}
