//! wallpaper-filter <image> — recompose une image pour remplir exactement
//! la résolution de l'écran actif, sans jamais recadrer l'axe qui
//! porterait le sujet principal (hauteur en paysage, largeur en portrait)
//! -- cet axe "sûr" n'est que mis à l'échelle, jamais rogné. Seul l'axe
//! restant ("libre") est ensuite ajusté : recadré s'il est trop grand,
//! ou étendu (fond flouté -- couleur dominante des 4 coins si l'image a
//! un fond quasi uni, sinon l'image entière étirée -- fondu en dégradé
//! sur les bords) s'il est trop court. Réécriture native de l'ancien
//! wallpaper-filter-one.sh (ImageMagick) : même algorithme, mais tout le
//! décodage/traitement reste en mémoire dans un seul process plutôt que
//! de rappeler `magick` cinq fois par image avec un aller-retour
//! encodage/décodage à chaque étape.
//!
//! Appelé par scripts/wallpaper-cache-watcher.sh pour chaque image
//! ajoutée/modifiée (celui-ci gère la surveillance inotify, la passe
//! initiale parallèle, et le marqueur FILTER_VERSION -- cf. ce script
//! pour la version à incrémenter si l'algorithme ci-dessous change).

use image::{imageops::FilterType, DynamicImage, GenericImageView, Rgb, RgbImage};
use std::path::{Path, PathBuf};
use std::process::Command;

const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp"];
/// Sigma du flou gaussien du fond -- calibré à l'œil pour un rendu proche
/// de l'ancien `-blur 0x40` ImageMagick.
const BLUR_SIGMA: f32 = 18.0;
/// Écart-type (0..1, moyenné sur les 3 canaux) en dessous duquel les 4
/// coins de l'image sont considérés comme un fond uni -- calibré sur la
/// collection de fonds d'écran de ce dépôt (mêmes images que le seuil
/// équivalent de l'ancienne version ImageMagick).
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

/// Cache déjà à jour (fichier présent, mtime >= celui de la source) ->
/// rien à faire. Même contrat que le test bash historique.
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

/// Résolution cible : écran interne si actif, sinon 1er écran actif (via
/// `hyprctl monitors -j`, jamais `monitors all -j` -- on veut l'écran qui
/// affiche réellement des pixels maintenant, cf. wallpaper-filter-one.sh
/// historique). Repli 1920x1080 hors session Hyprland ou si hyprctl/la
/// sortie JSON sont inutilisables.
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

/// Dimensions de l'image mise à l'échelle sur l'axe sûr uniquement --
/// même règle de trois entière que l'ancienne version bash, pour
/// atterrir exactement sur `target_h` (paysage) ou `target_w` (portrait).
fn fit_dims(src_w: u32, src_h: u32, target_w: u32, target_h: u32, landscape: bool) -> (u32, u32) {
    if landscape {
        let fit_w = ((src_w as u64 * target_h as u64 + src_h as u64 / 2) / src_h as u64) as u32;
        (fit_w.max(1), target_h)
    } else {
        let fit_h = ((src_h as u64 * target_w as u64 + src_w as u64 / 2) / src_w as u64) as u32;
        (target_w, fit_h.max(1))
    }
}

/// Dimensions couvrant tout le canevas cible (comme `-resize WxH^`) --
/// jamais plus petit que la cible sur aucun axe, quitte à arrondir au
/// pixel supérieur.
fn cover_dims(src_w: u32, src_h: u32, target_w: u32, target_h: u32) -> (u32, u32) {
    let scale = (target_w as f64 / src_w as f64).max(target_h as f64 / src_h as f64);
    let cover_w = ((src_w as f64 * scale).ceil() as u32).max(target_w);
    let cover_h = ((src_h as f64 * scale).ceil() as u32).max(target_h);
    (cover_w, cover_h)
}

/// Recadre `img` (déjà mis à l'échelle à cover_w x cover_h) au centre sur
/// exactement target_w x target_h.
fn center_crop(img: &DynamicImage, target_w: u32, target_h: u32) -> DynamicImage {
    let (w, h) = img.dimensions();
    let x = w.saturating_sub(target_w) / 2;
    let y = h.saturating_sub(target_h) / 2;
    img.crop_imm(x, y, target_w.min(w), target_h.min(h))
}

/// Couleur moyenne des 4 coins si leur écart-type combiné (bruit propre à
/// chaque coin ET différence de teinte d'un coin à l'autre) est sous
/// UNIFORM_THRESHOLD -- même principe que l'ancienne version bash, mais
/// mesuré directement sur les pixels décodés plutôt qu'en rappelant
/// `magick`. Taille d'échantillon en % de la plus petite dimension.
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

/// Fond flouté derrière l'image nette : couleur dominante des 4 coins si
/// détectée quasi unie (évite que les couleurs du sujet ne "bavent" dans
/// l'étirement), sinon l'image entière mise à l'échelle pour couvrir tout
/// le canevas puis recadrée au centre. Le flou s'applique dans les deux
/// cas -- sur un aplat déjà uni il ne fait que diluer un éventuel bruit
/// résiduel de l'échantillon.
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

/// Poids de fondu (0..255) pour un pixel à `pos` sur un axe de longueur
/// `len` : 0 au bord (dans les `feather` premiers/derniers pixels),
/// rampe linéaire jusqu'à 255 à `feather` px du bord, plateau opaque au
/// centre. Un seul axe compte -- l'axe sûr n'a jamais besoin de fondu,
/// il correspond déjà exactement au bord du canevas.
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

/// Compose l'image nette (`fit`, fondue sur son axe libre) au centre du
/// fond flouté (`bg`, déjà à target_w x target_h).
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

    // Axe sûr + décision recadrage/extension (multiplication croisée en
    // entiers -- pas de flottant, pas d'ambiguïté d'arrondi).
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
