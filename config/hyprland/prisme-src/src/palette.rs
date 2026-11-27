//! Which wallpapers suit which theme ("Matching").
//!
//! Each wallpaper's dominant colours come from its thumbnail (cache.rs,
//! the light and the dark half of a pair): six k-means clusters in OKLab
//! on a 48×32 reduction, kept in ~/.cache/prisme-palettes.json against
//! the original's mtime, so a wallpaper is read once. Then, per theme, a
//! distance: vivid colours to the theme's accents, neutral ones (weighted
//! down) to its surfaces. Ranked relative to the wallpaper's own average
//! over all themes: otherwise a neutral wallpaper sits close to every
//! theme's dark surfaces and tops every list.

use crate::cache;
use crate::themes::{self, Theme};
use crate::wallpapers::Wallpaper;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub type Lab = (f64, f64, f64);
/// A wallpaper's palette: (colour, weight), weights summing to 1.
pub type Palette = Vec<(Lab, f64)>;

const CLUSTERS: usize = 6;
const CHROMA_VIVID: f64 = 0.045;
const NEUTRAL_WEIGHT: f64 = 0.6;

fn lin(c: f64) -> f64 {
    if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
}

pub fn oklab((r, g, b): (f64, f64, f64)) -> Lab {
    let (r, g, b) = (lin(r), lin(g), lin(b));
    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).cbrt();
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).cbrt();
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).cbrt();
    (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )
}

fn dist(a: Lab, b: Lab) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2) + (a.2 - b.2).powi(2)).sqrt()
}

/// Six dominant colours of a picture, by k-means in OKLab.
fn dominant(img: &image::RgbImage) -> Palette {
    let small = cache::resize(img, 48, 32, fast_image_resize::FilterType::Box, false);
    let px: Vec<Lab> = small.pixels().map(|p| oklab((p[0] as f64 / 255.0, p[1] as f64 / 255.0, p[2] as f64 / 255.0))).collect();
    if px.is_empty() {
        return Vec::new();
    }
    // Seeds spread over the pixels sorted by lightness: deterministic, and
    // covering dark to light.
    let mut sorted = px.clone();
    sorted.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut centers: Vec<Lab> = (0..CLUSTERS).map(|k| sorted[(k * 2 + 1) * sorted.len() / (CLUSTERS * 2)]).collect();
    let mut counts = vec![0usize; CLUSTERS];
    for _ in 0..10 {
        let mut sums = vec![(0.0, 0.0, 0.0); CLUSTERS];
        counts = vec![0; CLUSTERS];
        for &p in &px {
            let k = (0..CLUSTERS).min_by(|&a, &b| dist(p, centers[a]).total_cmp(&dist(p, centers[b]))).unwrap_or(0);
            sums[k].0 += p.0;
            sums[k].1 += p.1;
            sums[k].2 += p.2;
            counts[k] += 1;
        }
        for k in 0..CLUSTERS {
            if counts[k] > 0 {
                let n = counts[k] as f64;
                centers[k] = (sums[k].0 / n, sums[k].1 / n, sums[k].2 / n);
            }
        }
    }
    let total = px.len() as f64;
    centers.into_iter().zip(counts).filter(|&(_, n)| n > 0).map(|(c, n)| (c, n as f64 / total)).collect()
}

fn cache_path() -> Option<PathBuf> {
    Some(PathBuf::from(std::env::var("HOME").ok()?).join(".cache/prisme-palettes.json"))
}

fn mtime(path: &Path) -> u64 {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn to_json(p: &Palette) -> Value {
    Value::Array(p.iter().map(|((l, a, b), w)| json!([l, a, b, w])).collect())
}

fn from_json(v: &Value) -> Option<Palette> {
    v.as_array()?
        .iter()
        .map(|c| {
            let c = c.as_array()?;
            Some(((c.first()?.as_f64()?, c.get(1)?.as_f64()?, c.get(2)?.as_f64()?), c.get(3)?.as_f64()?))
        })
        .collect()
}

/// Every wallpaper's palette (None when its thumbnail is not there yet),
/// from the cache or the thumbnails; the cache is rewritten when it grew.
/// Runs off the GTK thread.
pub fn compute(walls: &[Wallpaper]) -> Vec<Option<Palette>> {
    let stored: Value = cache_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Value::Null);
    let mut out = Vec::with_capacity(walls.len());
    let mut fresh: HashMap<String, Value> = HashMap::new();
    let mut changed = false;
    for w in walls {
        let stamp = mtime(&w.path) ^ w.dark.as_deref().map(mtime).unwrap_or(0);
        let hit = stored
            .get(&w.name)
            .filter(|e| e.get("mtime").and_then(Value::as_u64) == Some(stamp))
            .and_then(|e| from_json(e.get("colors")?));
        let palette = hit.or_else(|| {
            let mut halves: Vec<Palette> = Vec::new();
            for path in std::iter::once(&w.path).chain(w.dark.as_ref()) {
                if let Some((img, _)) = cache::read_thumb(path) {
                    halves.push(dominant(&img));
                }
            }
            if halves.is_empty() {
                return None;
            }
            changed = true;
            let n = halves.len() as f64;
            Some(halves.into_iter().flatten().map(|(c, w)| (c, w / n)).collect())
        });
        if let Some(p) = &palette {
            fresh.insert(w.name.clone(), json!({ "mtime": stamp, "colors": to_json(p) }));
        }
        out.push(palette);
    }
    if changed {
        if let Some(path) = cache_path() {
            let tmp = path.with_extension("json.tmp");
            if std::fs::write(&tmp, Value::Object(fresh.into_iter().collect()).to_string()).is_ok() {
                let _ = std::fs::rename(&tmp, &path);
            }
        }
    }
    out
}

fn theme_points(t: &Theme) -> (Vec<Lab>, Vec<Lab>) {
    let mut accents = Vec::new();
    let mut surfaces = Vec::new();
    for c in [&t.dark, &t.light] {
        for h in [&c.accent, &c.highlight, &c.success, &c.info, &c.warning, &c.danger].into_iter().chain(c.extra.iter()) {
            accents.push(oklab(themes::rgb(h)));
        }
        surfaces.push(oklab(themes::rgb(&c.panel)));
        surfaces.push(oklab(themes::rgb(&c.card)));
    }
    if let Some(f) = &t.folder {
        accents.push(oklab(themes::rgb(f)));
    }
    (accents, surfaces)
}

fn score(p: &Palette, accents: &[Lab], surfaces: &[Lab]) -> f64 {
    let near = |c: Lab, set: &[Lab]| set.iter().map(|&s| dist(c, s)).fold(f64::MAX, f64::min);
    p.iter()
        .map(|&(c, w)| {
            if c.1.hypot(c.2) > CHROMA_VIVID { w * near(c, accents) } else { w * NEUTRAL_WEIGHT * near(c, surfaces) }
        })
        .sum()
}

/// For each theme (same order as `themes`), the wallpapers that suit it
/// best, as indices into `palettes`, best first: a quarter of them, at
/// least eight.
pub fn matches(palettes: &[Option<Palette>], themes: &[Theme]) -> Vec<Vec<usize>> {
    let points: Vec<_> = themes.iter().map(theme_points).collect();
    // rel[w][t]: how much better theme t suits wallpaper w than the
    // average theme does, in standard deviations (lower is better).
    let rel: Vec<Option<Vec<f64>>> = palettes
        .iter()
        .map(|p| {
            let p = p.as_ref()?;
            let s: Vec<f64> = points.iter().map(|(a, su)| score(p, a, su)).collect();
            let mean = s.iter().sum::<f64>() / s.len().max(1) as f64;
            let sd = (s.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / s.len().max(1) as f64).sqrt().max(1e-9);
            Some(s.iter().map(|v| (v - mean) / sd).collect())
        })
        .collect();
    let known = rel.iter().filter(|r| r.is_some()).count();
    let keep = (known / 4).max(8).min(known);
    (0..themes.len())
        .map(|t| {
            let mut ranked: Vec<(usize, f64)> =
                rel.iter().enumerate().filter_map(|(w, r)| Some((w, r.as_ref()?[t]))).collect();
            ranked.sort_by(|a, b| a.1.total_cmp(&b.1));
            ranked.into_iter().take(keep).map(|(w, _)| w).collect()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oklab_white_and_black() {
        let w = oklab((1.0, 1.0, 1.0));
        assert!((w.0 - 1.0).abs() < 1e-3 && w.1.abs() < 1e-3);
        assert!(oklab((0.0, 0.0, 0.0)).0.abs() < 1e-6);
    }

    #[test]
    fn dominant_finds_two_halves() {
        let mut img = image::RgbImage::new(64, 32);
        for (x, _, p) in img.enumerate_pixels_mut() {
            *p = if x < 32 { image::Rgb([255, 0, 0]) } else { image::Rgb([0, 0, 255]) };
        }
        let p = dominant(&img);
        let red = oklab((1.0, 0.0, 0.0));
        assert!(p.iter().any(|&(c, w)| dist(c, red) < 0.05 && w > 0.3));
    }
}
