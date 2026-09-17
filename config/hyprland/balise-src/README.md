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
    balise wifi-share <ssid>       # URI WIFI: + QR ASCII (voir plus bas)

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

## Partage d'un réseau (QR code)

La page détail d'un réseau **enregistré** propose « Share this
network » : le daemon relit la clé stockée, en fait une URI `WIFI:` et
la rend en QR code, que le panneau affiche. Un téléphone le vise et
rejoint le réseau sans que personne ait à épeler la passphrase.

Trois choses valent d'être sues.

- **La clé ne sort jamais du daemon.** L'URI `WIFI:` contient la
  passphrase en clair. Elle est construite, encodée et jetée dans le
  thread de travail (`run_wifi_share`, app/mod.rs) ; ce qui traverse la
  socket, et ce que QML reçoit, c'est une grille de modules noirs et
  blancs. Pareil côté GTK : le code est peint au cairo, rien n'atterrit
  sur le disque.
- **eduroam n'est pas partageable, et le bouton n'apparaît pas.** Le
  format `WIFI:` ne sait transporter ni identifiant, ni méthode EAP, ni
  certificat : un QR eduroam se scannerait puis échouerait à se
  connecter. Le refus est double — l'UI ne propose pas l'action, et
  `wifi_share_uri` la refuse aussi, avec une phrase affichable.
- **Il faut un profil enregistré.** La clé est lue dans le profil local
  (`Settings.Connection.GetSecrets`), pas captée sur l'air. Sur cette
  machine l'appel passe sans invite polkit — `settings.modify.own` est
  accordé à une session locale active — et échoue proprement ailleurs.

Le format lui-même est celui de ZXing, que toutes les caméras de
téléphone implémentent. Il a été recoupé octet par octet avec celui de
`nmcli device wifi show-password` (les briques sont lisibles dans le
binaire : jeu d'échappement `\":;,`, jetons `T:` `S:` `P:` `H:true;`
`nopass`, même ordre de champs). **Une divergence délibérée** : nmcli
écrit `T:WPA` pour tout ce qui a une PSK, WPA3 compris ; ici un profil
en `key-mgmt=sae` reçoit `T:SAE`. Un téléphone à qui l'on annonce `WPA`
fabrique un profil WPA2-PSK, qui s'associe à un AP en mode transition
mais pas à un AP WPA3 strict.

Sonde headless, comme pour chaque capacité du backend :

    balise wifi-share <ssid>

Elle imprime l'URI et dessine le QR dans le terminal. **Elle affiche
donc la passphrase en clair**, comme `nmcli device wifi show-password` —
c'est ce que le QR encode, et un partage invérifiable à l'œil est
indébogable.

## Limite connue

L'appairage Bluetooth n'est pas joignable depuis le panneau QML : il
demande de ponter l'agent BlueZ (`org.bluez.Agent1`, déjà enregistré par
le daemon) jusqu'à QML. Un appareil déjà appairé se connecte
normalement ; c'est la fenêtre GTK qui affiche encore les demandes de
code PIN / passkey.
