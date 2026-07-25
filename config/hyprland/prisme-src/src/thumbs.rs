//! Décodage et mise à l'échelle asynchrones des vignettes de wallpapers.
//! Le décodage (coûteux, CPU) tourne sur des threads dédiés hors de la
//! boucle GTK ; seule la construction finale de la texture GObject revient
//! sur le thread principal, GTK l'exigeant.

use gtk4::gdk::{self, MemoryFormat, MemoryTexture};
use gtk4::glib;
use gtk4::prelude::*;
use image::imageops::FilterType;
use std::path::PathBuf;

/// Hauteur commune de toutes les vignettes -- seule la largeur des cartes
/// s'anime (cf. card.rs), la hauteur reste fixe.
pub const CARD_HEIGHT: i32 = 460;

/// Pixels bruts décodés en thread -- pas de type GObject ici (`gdk::Texture`
/// n'est pas Send), juste des octets qu'on emballera en texture sur le
/// thread GTK.
struct DecodedImage {
    rgba: Vec<u8>,
    width: i32,
    height: i32,
    orig_width: i32,
    orig_height: i32,
}

/// Résultat de décodage d'une vignette, prêt à être posé sur une carte par
/// index. `texture` est `None` si l'image n'a pas pu être décodée.
pub struct ThumbResult {
    pub index: usize,
    pub texture: Option<gdk::Texture>,
    pub orig_width: i32,
    pub orig_height: i32,
}

/// Charge les vignettes en arrière-plan (un thread court par image -- une
/// collection de wallpapers va typiquement de quelques unités à quelques
/// centaines, pas besoin d'un pool borné) et renvoie un récepteur consommé
/// sur la boucle GLib principale via `glib::MainContext::spawn_local`.
pub fn spawn_loader(paths: Vec<(usize, PathBuf)>) -> async_channel::Receiver<ThumbResult> {
    let (tx, rx) = async_channel::unbounded();
    for (index, path) in paths {
        let tx = tx.clone();
        std::thread::spawn(move || {
            let decoded = decode_and_scale(&path);
            // La construction de la texture (GObject) doit rester sur ce
            // thread -- le canal ne porte donc que les octets bruts jusqu'ici ;
            // c'est le récepteur (thread GTK) qui appelle MemoryTexture::new.
            let _ = tx.send_blocking((index, decoded));
        });
    }

    let (out_tx, out_rx) = async_channel::unbounded();
    glib::MainContext::default().spawn_local(async move {
        while let Ok((index, decoded)) = rx.recv().await {
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

    out_rx
}

/// Décode l'image et la redimensionne à `CARD_HEIGHT`, en conservant les
/// dimensions d'origine pour le calcul du ratio d'affichage (cf. card.rs).
fn decode_and_scale(path: &std::path::Path) -> Option<DecodedImage> {
    let img = image::open(path).ok()?;
    let (orig_width, orig_height) = (img.width() as i32, img.height() as i32);
    // `resize` met à l'échelle en préservant le ratio pour tenir dans la
    // boîte donnée -- une largeur généreuse rend la hauteur seule limitante.
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
