//! Channel logos for the guide's channel column: downloaded the first time
//! a row comes into view, kept 30 days.
//!
//! Many logos are dark ink on a transparent background, invisible on the
//! dark glass: those get a light plate. Decoding, measuring and scaling
//! all happen on the worker thread (`decode`); the main thread only wraps
//! a few kilobytes of pixels, so a 960 px PNG never stalls the interface.

use crate::store;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

fn dir() -> PathBuf {
    store::cache_dir().join("logos")
}

pub fn path_for(key: &str) -> PathBuf {
    let safe: String = key.chars().map(|c| if c.is_ascii_alphanumeric() || c == '.' { c } else { '_' }).collect();
    dir().join(format!("{safe}.img"))
}

pub fn fresh(path: &PathBuf) -> bool {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|a| a < Duration::from_secs(30 * 24 * 3600))
}

pub fn fetch(url: &str, out: &PathBuf) -> bool {
    // a picture on disk, for a show made of files
    if let Some(local) = url.strip_prefix("file://").or(url.starts_with('/').then_some(url)) {
        let _ = std::fs::create_dir_all(dir());
        return std::fs::copy(local, out).is_ok();
    }
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(6))
        .timeout_read(Duration::from_secs(10))
        .user_agent(crate::catalog::BROWSER_UA)
        .build();
    let Ok(resp) = agent.get(url).call() else { return false };
    let mut bytes = Vec::new();
    if resp.into_reader().take(4 << 20).read_to_end(&mut bytes).is_err() || bytes.is_empty() {
        return false;
    }
    let _ = std::fs::create_dir_all(dir());
    let tmp = out.with_extension("part");
    std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, out).is_ok()
}

/// A logo ready for the guide: RGBA, straight alpha, scaled to fit a box.
pub struct Small {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
    pub light: bool,
}

/// Scaled once, with Lanczos, to fit `max_w` x `max_h` device pixels: the
/// largest the guide ever shows it (the header), never upscaled. The first
/// version fitted every logo in 33 px whatever its shape, so a wide one
/// came out 33 x 7 and the header blew it up into a smear.
pub fn decode(path: &Path, max_w: u32, max_h: u32) -> Option<Small> {
    let img = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let light = needs_light_plate(&img);
    let (w, h) = img.dimensions();
    let k = (max_w as f32 / w.max(1) as f32).min(max_h as f32 / h.max(1) as f32);
    let img = if k < 1.0 {
        image::imageops::resize(&img, ((w as f32 * k).round() as u32).max(1), ((h as f32 * k).round() as u32).max(1), image::imageops::FilterType::Lanczos3)
    } else {
        img
    };
    Some(Small { width: img.width(), height: img.height(), rgba: img.into_raw(), light })
}

/// A picture for a 16:9 cover, `w` × `h` exactly: the middle of it kept
/// (which also drops the black bands of a 4:3 YouTube thumbnail).
pub fn decode_cover(path: &Path, w: u32, h: u32) -> Option<Small> {
    let img = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let (iw, ih) = img.dimensions();
    let target = w as f32 / h.max(1) as f32;
    let (cw, ch) = if iw as f32 / ih.max(1) as f32 > target { ((ih as f32 * target) as u32, ih) } else { (iw, (iw as f32 / target) as u32) };
    let crop = image::imageops::crop_imm(&img, (iw - cw.min(iw)) / 2, (ih - ch.min(ih)) / 2, cw.min(iw), ch.min(ih)).to_image();
    let out = image::imageops::resize(&crop, w.max(1), h.max(1), image::imageops::FilterType::Lanczos3);
    Some(Small { width: out.width(), height: out.height(), rgba: out.into_raw(), light: false })
}

/// A light plate when the logo is mostly dark ink with transparency around
/// it. A logo that brings its own opaque background needs no plate.
fn needs_light_plate(img: &image::RgbaImage) -> bool {
    let (mut lum, mut ink, mut clear) = (0.0f64, 0usize, 0usize);
    for px in img.pixels() {
        let [r, g, b, a] = px.0;
        if a < 32 {
            clear += 1;
        } else if a >= 128 {
            lum += 0.2126 * r as f64 + 0.7152 * g as f64 + 0.0722 * b as f64;
            ink += 1;
        }
    }
    let total = (img.width() * img.height()) as usize;
    ink > 0 && clear * 20 > total && lum / ink as f64 / 255.0 < 0.35
}

#[cfg(test)]
mod look {
    /// cargo test --release logos_look -- --ignored: a few cached logos
    /// decoded to the header's box, side by side, to look at.
    #[test]
    #[ignore]
    fn logos_look() {
        let out = std::env::var("LOGOS_OUT").unwrap_or_else(|_| "/tmp/antenne-logos.png".into());
        let keys = ["sciencevietv.fr", "tebeotv.fr", "13emerue.fr", "20minutestv.fr", "tf1.fr", "france2.fr"];
        let mut sheet = image::RgbaImage::from_pixel(120 * keys.len() as u32, 50, image::Rgba([22, 22, 25, 255]));
        for (i, k) in keys.iter().enumerate() {
            let Some(s) = super::decode(&super::path_for(k), 100, 33) else { continue };
            let img = image::RgbaImage::from_raw(s.width, s.height, s.rgba).unwrap();
            image::imageops::overlay(&mut sheet, &img, (i as i64) * 120 + 10, 8);
            println!("{k}: {}x{}", s.width, s.height);
        }
        sheet.save(&out).unwrap();
    }
}

