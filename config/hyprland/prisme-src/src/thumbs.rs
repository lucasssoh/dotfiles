//! Asynchronous decoding and scaling of wallpaper thumbnails. Decoding
//! (CPU-heavy) runs on dedicated threads off the GTK loop; only the final
//! GObject texture construction goes back to the main thread, as GTK
//! requires.

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

/// Decodes the image and resizes it to `CARD_HEIGHT`, keeping the
/// original dimensions for the display ratio calculation (see card.rs).
fn decode_and_scale(path: &std::path::Path) -> Option<DecodedImage> {
    let is_jxl = path
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("jxl"));
    let img = if is_jxl { decode_jxl(path)? } else { image::open(path).ok()? };
    let (orig_width, orig_height) = (img.width() as i32, img.height() as i32);
    // `resize` scales while preserving the ratio to fit within the given
    // box -- a generous width leaves height as the only limiting factor.
    let resized = img.resize(8192, CARD_HEIGHT as u32, FilterType::Triangle);
    let rgba = resized.to_rgba8();
    let (width, height) = rgba.dimensions();
    Some(DecodedImage {
        rgba: rgba.into_raw(),
        width: width as i32,
        height: height as i32,
        orig_width,
        orig_height,
    })
}
