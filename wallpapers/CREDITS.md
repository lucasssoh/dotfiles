# Credits

- `gnome-*` — GNOME default background designs, from
  [GNOME/gnome-backgrounds](https://gitlab.gnome.org/GNOME/gnome-backgrounds),
  each in both variants: `gnome-<design>.jxl` is upstream's light (`-l`),
  `gnome-<design>-dark.jxl` its dark (`-d`). Kept as the original JPEG XL
  (`.jxl`) except the `gnome-morphogenesis*.jpg` pair (upstream only ships
  that one as SVG, rasterized here at 4096x4096). The light `.jxl` files
  are a bare JXL codestream, the dark ones upstream's current ISOBMFF
  container — `jxl-oxide` reads both, so wallpaper-filter.rs/thumbs.rs
  need no change. Licensed
  [CC BY-SA 3.0 US](https://gitlab.gnome.org/GNOME/gnome-backgrounds/-/raw/main/COPYING) —
  kept here under the same license.
- All `gnome-*` and `macos-*` (private repo) files use "fill" mode in
  wallpaper-filter.rs (plain cover + center-crop, no blur) — see
  `prisme/wallpaper-fill-mode.conf`.
- Nothing else lives here on purpose: this folder is the GNOME set and
  only that, so the public repo carries one coherent, uniformly licensed
  collection. Personal picks (and the `macos-*` files) live in
  `~/code/wallpapers-private` (not public), merged into the same wallpaper
  folder at runtime via `prisme/wallpapers-extra.conf`.
