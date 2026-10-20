//! Loads the full-screen preview of the focused wallpaper (backdrop.rs
//! shows it). One dedicated thread, apart from thumbs.rs's pool, so a
//! preview never waits behind a queue of thumbnails.
//!
//! Reads the screen-fit cache wallpaper-filter already keeps up to date
//! (~/.cache/filtered_wallpapers/<W>x<H>/NAME, the same file wallpaper-set
//! hands to awww) -- measured here at 16 ms median for a 1920×1200 one,
//! against several hundred for an 8K original. The original is only
//! decoded for a wallpaper the cache watcher hasn't reached yet.

use gtk4::gdk::{self, MemoryFormat, MemoryTexture};
use gtk4::glib;
use gtk4::prelude::*;
use image::imageops::FilterType;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use crate::thumbs;

/// Which picture: a card, and which half of its pair.
pub type Key = (usize, bool);

struct Request {
    generation: u64,
    key: Key,
    path: PathBuf,
    size: (u32, u32),
}

struct Decoded {
    rgb: Vec<u8>,
    width: i32,
    height: i32,
}

/// A decoded preview, ready for backdrop.rs. `generation` is the request's:
/// main.rs drops a result that a newer request has overtaken.
pub struct PreviewResult {
    pub generation: u64,
    pub key: Key,
    pub texture: gdk::Texture,
}

#[derive(Clone)]
pub struct PreviewLoader {
    tx: async_channel::Sender<Request>,
    generation: Arc<AtomicU64>,
}

impl PreviewLoader {
    pub fn new() -> (Self, async_channel::Receiver<PreviewResult>) {
        let (tx, rx) = async_channel::unbounded::<Request>();
        let (raw_tx, raw_rx) = async_channel::unbounded::<(u64, Key, Decoded)>();
        let generation = Arc::new(AtomicU64::new(0));

        {
            let generation = generation.clone();
            std::thread::spawn(move || {
                while let Ok(mut req) = rx.recv_blocking() {
                    // Latest wins: with an arrow key held, only the card
                    // the focus stops on gets decoded.
                    while let Ok(newer) = rx.try_recv() {
                        req = newer;
                    }
                    if req.generation < generation.load(Ordering::Relaxed) {
                        continue;
                    }
                    if let Some(decoded) = decode(&req.path, req.size) {
                        if raw_tx.send_blocking((req.generation, req.key, decoded)).is_err() {
                            break;
                        }
                    }
                }
            });
        }

        // The texture (a GObject) is built on the GTK thread.
        let (out_tx, out_rx) = async_channel::unbounded();
        glib::MainContext::default().spawn_local(async move {
            while let Ok((generation, key, d)) = raw_rx.recv().await {
                let stride = (d.width * 3) as usize;
                let bytes = glib::Bytes::from_owned(d.rgb);
                let texture = MemoryTexture::new(d.width, d.height, MemoryFormat::R8g8b8, &bytes, stride)
                    .upcast::<gdk::Texture>();
                if out_tx.send(PreviewResult { generation, key, texture }).await.is_err() {
                    break;
                }
            }
        });

        (Self { tx, generation }, out_rx)
    }

    /// Starts a new generation: every request made before is stale.
    pub fn next_generation(&self) -> u64 {
        self.generation.fetch_add(1, Ordering::Relaxed) + 1
    }

    pub fn generation(&self) -> u64 {
        self.generation.load(Ordering::Relaxed)
    }

    /// Asks for `path` fitted to a `size` screen, tagged with `generation`.
    pub fn request(&self, generation: u64, key: Key, path: PathBuf, size: (u32, u32)) {
        let _ = self.tx.send_blocking(Request { generation, key, path, size });
    }
}

/// wallpaper-filter's version of `path` for a `size` screen, when it exists
/// and is newer than the original.
fn cached(path: &std::path::Path, size: (u32, u32)) -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let file = PathBuf::from(home)
        .join(".cache/filtered_wallpapers")
        .join(format!("{}x{}", size.0, size.1))
        .join(path.file_name()?);
    thumbs::cache_is_fresh(path, &file).then_some(file)
}

fn decode(path: &std::path::Path, size: (u32, u32)) -> Option<Decoded> {
    let img = match cached(path, size).and_then(|c| thumbs::decode_any(&c)) {
        Some(img) => img,
        // Not fitted yet: cover-crop the original the way the cache would.
        None => thumbs::decode_any(path)?.resize_to_fill(size.0, size.1, FilterType::Triangle),
    };
    // Opaque RGB: a quarter less to copy and upload than RGBA.
    let rgb = img.to_rgb8();
    let (width, height) = rgb.dimensions();
    Some(Decoded { rgb: rgb.into_raw(), width: width as i32, height: height as i32 })
}
