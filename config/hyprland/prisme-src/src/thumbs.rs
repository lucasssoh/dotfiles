//! Loads the carousel's thumbnails on worker threads; only the final
//! GObject texture construction goes back to the main thread, as GTK
//! requires.
//!
//! A thumbnail comes from the cache wallpaper-filter keeps (see cache.rs):
//! a small JPEG already at the size uploaded, its original's size in a
//! comment, so a launch decodes ~0.3 Mpx per card and never opens an
//! original. Measured here: ~3 ms per card, against ~30 ms when the cache
//! held 920 px thumbnails resized on every launch, and ~1 s for a JPEG XL
//! original. A missing or stale entry (a wallpaper the cache watcher hasn't
//! reached yet, or no watcher at all) is made here and saved, so only the
//! first launch pays for it.

use gtk4::gdk::{self, MemoryFormat, MemoryTexture};
use gtk4::glib;
use gtk4::prelude::*;
use std::path::{Path, PathBuf};

use crate::cache;

/// Raw pixels decoded on a thread -- no GObject type here (`gdk::Texture`
/// isn't Send), just bytes that get wrapped into a texture on the GTK
/// thread.
struct DecodedImage {
    rgb: Vec<u8>,
    width: i32,
    height: i32,
    orig_width: i32,
    orig_height: i32,
}

/// Decoding result for a thumbnail, ready to be placed on a card by index.
/// `texture` is `None` if the image couldn't be decoded.
pub struct ThumbResult {
    pub index: usize,
    /// Which half of a light/dark pair this is (see wallpapers.rs) --
    /// always false for a wallpaper without a pair.
    pub dark: bool,
    pub texture: Option<gdk::Texture>,
    pub orig_width: i32,
    pub orig_height: i32,
}

/// Bounded pool: a burst of requests (fast scrolling) queues up instead of
/// spawning a thread per card, and caps the memory a first launch holds
/// when it decodes originals (a 6000×4000 photo ≈ 72 MB raw).
const WORKER_COUNT: usize = 4;

/// Handle to the decoding pool -- `request()` can be called at any time,
/// loading follows the window of cards around the focus (see main.rs).
/// `Clone` is just a clone of the `Sender` (shared channel), no new
/// threads.
#[derive(Clone)]
pub struct ThumbLoader {
    request_tx: async_channel::Sender<(usize, bool, PathBuf)>,
}

impl ThumbLoader {
    /// Starts `WORKER_COUNT` persistent decoding threads and the GLib task
    /// that builds textures on the main thread.
    pub fn new() -> (Self, async_channel::Receiver<ThumbResult>) {
        let (request_tx, request_rx) = async_channel::unbounded::<(usize, bool, PathBuf)>();
        let (raw_tx, raw_rx) = async_channel::unbounded();

        for _ in 0..WORKER_COUNT {
            let request_rx = request_rx.clone();
            let raw_tx = raw_tx.clone();
            std::thread::spawn(move || {
                while let Ok((index, dark, path)) = request_rx.recv_blocking() {
                    let decoded = load(&path);
                    // Texture (GObject) construction must stay on the GTK
                    // thread: the channel only carries raw bytes.
                    if raw_tx.send_blocking((index, dark, decoded)).is_err() {
                        break;
                    }
                }
            });
        }

        let (out_tx, out_rx) = async_channel::unbounded();
        glib::MainContext::default().spawn_local(async move {
            while let Ok((index, dark, decoded)) = raw_rx.recv().await {
                let (texture, orig_width, orig_height) = match decoded {
                    Some(d) => {
                        let rowstride = (d.width * 3) as usize;
                        let bytes = glib::Bytes::from_owned(d.rgb);
                        // Opaque RGB: a quarter less to copy and upload
                        // than RGBA, and nothing to premultiply.
                        let tex = MemoryTexture::new(d.width, d.height, MemoryFormat::R8g8b8, &bytes, rowstride);
                        (Some(tex.upcast::<gdk::Texture>()), d.orig_width, d.orig_height)
                    }
                    None => (None, 0, 0),
                };
                let result = ThumbResult { index, dark, texture, orig_width, orig_height };
                if out_tx.send(result).await.is_err() {
                    break;
                }
            }
        });

        (Self { request_tx }, out_rx)
    }

    /// Requests decoding of `path` for card `index` (`dark`: the dark half
    /// of its pair) -- result delivered later via the receiver returned by
    /// `new()`. The channel is unbounded: the GTK thread never blocks here,
    /// the request just waits in the queue.
    pub fn request(&self, index: usize, dark: bool, path: PathBuf) {
        let _ = self.request_tx.send_blocking((index, dark, path));
    }
}

/// The thumbnail of `path` and its original's size: from the cache, else
/// made from the legacy thumbnail or the original and saved for next time.
fn load(path: &Path) -> Option<DecodedImage> {
    let (thumb, (orig_width, orig_height)) = match cache::read_thumb(path) {
        Some(hit) => hit,
        None => {
            let (img, size) = cache::legacy_thumb(path).or_else(|| {
                let img = cache::decode_any(path)?.into_rgb8();
                let size = img.dimensions();
                Some((img, size))
            })?;
            (cache::store_thumb(path, &img, size), size)
        }
    };
    let (width, height) = thumb.dimensions();
    Some(DecodedImage {
        rgb: thumb.into_raw(),
        width: width as i32,
        height: height as i32,
        orig_width: orig_width as i32,
        orig_height: orig_height as i32,
    })
}
