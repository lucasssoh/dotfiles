# Orbit — code source vendorisé

Copie du code source d'[Orbit](https://github.com/LifeOfATitan/orbit)
(gestionnaire WiFi/Bluetooth/VPN natif Wayland), **modifiée et intégrée
directement dans ce repo** plutôt que clonée depuis GitHub à l'installation.

## Pourquoi vendoriser plutôt que cloner

`install.sh` clonait auparavant Orbit depuis GitHub à chaque installation.
C'est un projet solo-dev avec peu d'étoiles : si le repo disparaît, devient
privé, ou que le mainteneur l'abandonne, une future installation sur une
nouvelle machine casserait silencieusement (plus de WiFi/Bluetooth graphique,
retour aux TUI). Vendoriser le code ici élimine cette dépendance -- le build
ne dépend plus que de crates.io (l'écosystème Rust dans son ensemble, pas un
seul repo).

Licence MIT (cf. `LICENSE`) -- vendoriser avec la notice de copyright
conservée est explicitement autorisé.

## Provenance

- Source : https://github.com/LifeOfATitan/orbit
- Version vendorisée : v2.4.13 (commit `eb77261`, mai 2026)
- Auteur upstream : Amadeus (LifeOfATitan)

## Nos modifications par rapport à l'upstream

Toutes appliquées directement dans `src/` (plus de système de patch séparé --
avant, `orbit-build/apply-patches.py` réappliquait ces changements sur un
clone frais à chaque install ; ce fichier documente juste ce qui a changé) :

1. **`src/ui/header.rs`** -- logo et titre "Orbit" retirés (pas de branding
   dans les popups système, cohérence avec le reste de la barre). Le bouton
   Ethernet est placé avant le switch WiFi, et le sélecteur d'onglets
   WiFi/Bluetooth/VPN est maintenant au-dessus de cette ligne plutôt qu'en
   dessous (design plus stable visuellement -- la partie qui bouge le moins
   est en haut). Espacement de la ligne du bas augmenté (4px -> 12px).
2. **`src/ui/window.rs`** -- le détail Bluetooth (nom, adresse) tronque
   maintenant les valeurs trop longues avec "…" au lieu de forcer le panneau
   à s'agrandir, comme le fait déjà le détail WiFi upstream.
3. **`src/ui/network_list.rs`** -- le nom (SSID) d'un réseau WiFi dans la
   liste tronque avec "…" s'il est trop long, au lieu d'étirer la ligne.
4. **`src/ui/device_list.rs`** -- même chose pour le nom d'un appareil
   Bluetooth dans la liste.
5. **`src/app/mod.rs`** -- `orbit toggle --tab X` bascule directement vers
   l'onglet X s'il est déjà ouvert sur un autre onglet, au lieu de fermer le
   panneau (avant : cliquer WiFi puis Bluetooth dans waybar refermait le
   panneau au lieu de changer d'onglet).

Le thème (couleurs, police, aplat visuel) n'est PAS ici -- il vit dans
`config/hyprland/orbit/` (`theme.toml`, `style.css`, `config.toml`),
symlinké vers `~/.config/orbit/` et rechargeable à chaud (`orbit
reload-theme`), sans recompilation.

## Mettre à jour depuis une nouvelle version d'upstream

Pas automatique (c'est le but du vendoring). Pour intégrer une nouvelle
version d'Orbit à la main :

1. Cloner la nouvelle version upstream ailleurs (`git clone
   https://github.com/LifeOfATitan/orbit.git /tmp/orbit-new`).
2. Comparer `/tmp/orbit-new/src` à `src/` ici (`diff -ru`) pour voir ce qui a
   changé côté upstream.
3. Reporter à la main nos modifications (section ci-dessus) sur la nouvelle
   version.
4. Remplacer `src/`, `Cargo.toml`, `Cargo.lock` ici par les nouveaux, avec
   nos modifications réappliquées.
5. `cargo build --release` pour vérifier que ça compile, tester en isolation
   avant de committer.
