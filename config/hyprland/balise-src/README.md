# Balise

Panneau natif Wayland de gestion **WiFi / Bluetooth / Ethernet**, écrit
pour cette configuration. Remplace Orbit depuis la bascule.

Pas de VPN, et ce n'est pas un oubli : c'est un choix explicite.

## Ce que c'est

Un binaire Rust + GTK4 + `gtk4-layer-shell`, en surface layer-shell
ancrée dans un coin (pas un overlay plein écran comme Roue ou Prisme).
Il tourne en **daemon** et se pilote par une socket Unix, de sorte qu'un
clic sur la barre réutilise le processus existant au lieu d'en relancer
un à chaque fois.

- Backends : NetworkManager et BlueZ en D-Bus brut (`zbus`, sans proxy
  typé), en interrogation périodique + relecture après action.
- Agent d'appairage Bluetooth (`org.bluez.Agent1`) enregistré par le
  daemon : c'est lui qui affiche les demandes de code PIN / passkey /
  confirmation.
- Thème : `config/hyprland/balise/style.css` fait autorité, rechargeable
  à chaud (`balise reload-theme`, sans redémarrer le daemon).
  `src/theme.rs` en contient une copie de secours, utilisée uniquement
  si le fichier n'est pas atteignable — les deux doivent rester
  synchronisés.

## Commandes

    balise daemon                  # le service (voir systemd/balise.service)
    balise toggle --tab wifi       # wifi | bluetooth | ethernet
    balise show / hide
    balise reload-theme            # relit style.css
    balise reload-config           # relit config.toml (position, marges)

Sondes headless, sans daemon ni GTK — utilisées pour valider chaque
capacité du backend contre `nmcli` / `bluetoothctl` avant de construire
l'UI par-dessus :

    balise status | list [--scan] | saved
    balise ethernet
    balise bluetooth-status | bluetooth-scan
    balise wifi-details <ssid>

## Lignée Orbit

Balise a été construit en portant, morceau par morceau, la logique D-Bus
d'**Orbit** (`LifeOfATitan/orbit`), qui vivait auparavant dans
`config/hyprland/orbit-vendor/`. **Ce dossier a été supprimé lors de la
bascule** : il reste consultable dans l'historique git.

De nombreux commentaires du code disent « adapted from
orbit-vendor/src/… » avec un numéro de ligne. Ces chemins ne résolvent
plus dans l'arbre de travail — ils renvoient à cet historique, et sont
conservés parce qu'ils expliquent *pourquoi* telle logique a la forme
qu'elle a.

Ce qui a changé au passage, et qui vaut d'être su :

- **Deux bugs corrigés** dans le portage. `saved_networks().is_active`
  était toujours faux chez Orbit (il comparait un chemin Settings à des
  chemins ActiveConnection, deux espaces de noms différents), et
  `get_active_ssid` renvoyait le libellé `Id` de la connexion au lieu du
  vrai SSID, ce qui casse dès qu'un profil est renommé.
- **Un bit corrigé** dans la classification de sécurité : Orbit teste
  `rsn_flags & 0x100` en croyant que c'est WPA3-SAE ; c'est en fait
  WPA2-PSK. Le vrai bit SAE est `0x400` (vérifié en direct au `busctl`
  contre de vrais points d'accès).
- **Pas de VPN**, alors qu'Orbit en avait.
- L'UI ne reprend rien d'Orbit : navigation par page détail avec retour,
  saisie du mot de passe dépliée sous sa propre ligne, listes groupées
  en une carte par section. Orbit n'a aucun équivalent de tout ça.

## Saisie des identifiants (WiFi)

Le formulaire vit sur la page détail du réseau, côté QML
(`quickshell/bar/modules/balise/BaliseDetailPage.qml`). Il s'ouvre tout
seul pour un réseau sécurisé sans profil enregistré, et se rouvre à la
demande (« Change credentials ») ou automatiquement après un refus, pour
un réseau déjà enregistré dont le secret ne marche plus.

Deux formes :

- **Personnel** — un champ mot de passe. `key-mgmt` est choisi d'après le
  type réel du réseau : `wpa-psk`, `sae` pour du WPA3, ou la clé statique
  WEP. Avant, tout réseau sécurisé recevait `wpa-psk`, ce qu'un point
  d'accès WPA3-only refuse.
- **Entreprise (802.1X : eduroam & compagnie)** — identifiant + mot de
  passe, plus une section repliée pour la méthode EAP (PEAP / TTLS /
  PWD), la phase 2 (MSCHAPv2 / PAP / GTC) et l'identité anonyme. Les
  défauts (PEAP + MSCHAPv2) couvrent la quasi-totalité des déploiements
  eduroam.

Deux points à savoir :

- **Le bandeau doit prendre le focus clavier pour ça.** C'est une surface
  layer-shell déclarée `focusable: false` — sans quoi le compositeur ne
  lui envoie aucun événement clavier et un champ de saisie y est
  simplement mort. `shell.qml` bascule `focusable` le temps que le
  formulaire est à l'écran, et seulement sur l'écran concerné.
- **Aucun certificat CA n'est écrit** (`802-1x.ca-cert`,
  `domain-suffix-match`). Il n'y a pas d'UI pour en choisir un ;
  NetworkManager se connecte sans, sans valider le certificat du serveur.
  C'est le même compromis que `nmcli device wifi connect`.

## Limite connue

L'appairage Bluetooth n'est pas joignable depuis le panneau QML : il
demande de ponter l'agent BlueZ (`org.bluez.Agent1`, déjà enregistré par
le daemon) jusqu'à QML. Un appareil déjà appairé se connecte
normalement ; c'est la fenêtre GTK qui affiche encore les demandes de
code PIN / passkey.
