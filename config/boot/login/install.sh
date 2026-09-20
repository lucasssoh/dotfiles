#!/usr/bin/env bash
# install.sh -- the login screen: greetd + tuigreet on VT1, in JetBrains Mono.
#
# Two greeters were tried here and both were reverted, which is worth
# recording so neither gets tried a third time by someone reading only the
# result.
#
# regreet (GTK4, under cage) was too rigid, and cost a near-lockout: cage
# takes its keyboard layout from XKB rather than from /etc/vconsole.conf,
# so with no XKB_DEFAULT_LAYOUT set the greeter came up in US QWERTY on an
# AZERTY machine, at a masked password prompt.
#
# ly's good argument was that Fedora packaged it where tuigreet came from
# a copr -- which turned out to be stale: Fedora ships tuigreet too, and
# this module was simply asking for the wrong package name. Its
# session_log also looked like a cleaner answer than wrapping the session
# in systemd-cat. In practice it cost three separate lockouts -- a bullet
# character that made it discard its whole config file, a session log path
# SELinux refuses, and a minimal config that dropped the `/bin/sh` Fedora
# puts in front of its non-executable setup.sh -- and when it finally
# worked, the greeter itself was not better than tuigreet.
#
# tuigreet asks the console keymap for its layout, like every other thing
# on a VT, and greetd passes the session command straight through. What
# the two experiments did leave behind is kept: the console renders in
# JetBrains Mono, the keymap repair survives Plymouth holding the VT, and
# the word stays on screen through the gap before Hyprland's first frame.
#
# THIS MODULE REWRITES SYSTEM LOGIN. Opt-in, and it asks first.

set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$MODULE_DIR/../../../scripts/lib/pkg.sh"

BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; RESET="\e[0m"
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

# Read from vconsole.conf rather than repeated here. That file is what
# setfont is ultimately handed, so it is the one place the name can be
# wrong in a way that matters; a second copy in this script could drift
# from it silently and the console would fall back to the kernel default
# with no error worth reading.
CONSOLE_FONT="$(sed -n 's/^FONT="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' \
                "$MODULE_DIR/console/vconsole.conf")"
[ -n "$CONSOLE_FONT" ] || err "no FONT= line in console/vconsole.conf"
# setfont's search path, and the directory dracut's i18n module looks in
# when it copies the font named by vconsole.conf into the initramfs.
# /usr/local has neither property, which is the whole reason this lands in
# package territory instead.
CONSOLE_FONT_DIR="/usr/lib/kbd/consolefonts"

section "LOGIN SCREEN (GREETD + TUIGREET)"

warn "This script rewrites the system login manager."
read -rp "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || err "Installation aborted."

# ============================================================
# PACKAGES
# ============================================================
section "Packages"

# The package is `tuigreet`, and it is in Fedora proper -- no copr.
#
# This module asked for `greetd-tuigreet` from pennbauman/ports for a long
# time, which is a name that does not exist in any enabled repository; the
# binary on this machine is owned by tuigreet-0.9.1-7.fc44 from `fedora`.
# `verify` reported it missing forever and nobody read the line.
#
# It also retires the one real argument for replacing tuigreet. ly was
# considered mainly because Fedora packaged it where tuigreet supposedly
# did not -- that has not been true for some time.
case "$(pkg_mgr)" in
    dnf)    PKGS=(greetd tuigreet kbd jetbrains-mono-fonts) ;;
    pacman) PKGS=(greetd greetd-tuigreet kbd ttf-jetbrains-mono) ;;
    apt)    PKGS=(greetd kbd fonts-jetbrains-mono) ;;
    *)      PKGS=(greetd) ;;
esac
pkg_ensure "${PKGS[@]}"

if [ "${CCPKG_ALLOW_ROOT:-1}" = "0" ]; then
    warn "user scope: the login screen is system-wide — deferred."
    warn "run  ./config/boot/login/install.sh  directly."
    exit 0
fi

command -v tuigreet >/dev/null 2>&1 || err "tuigreet is missing and could not be installed."

# ============================================================
# REGREET REMOVAL
#
# Everything the previous version of this module deployed, removed rather
# than left behind. An 11 MB binary that nothing starts, and a
# /etc/greetd/ holding two greeters' configuration, is exactly the state
# that makes the next person guess which one is live.
# ============================================================
section "Removing the regreet and ly attempts"

LEFTOVERS=(
    /etc/ly/config.ini
    /etc/ly/custom-sessions/hyprland.desktop
    /usr/local/bin/regreet
    /usr/local/lib/regreet.built
    /etc/greetd/regreet.toml
    /etc/greetd/regreet.css
    /etc/tmpfiles.d/regreet.conf
    /usr/local/share/wayland-sessions/hyprland-dotfiles.desktop
)
REMOVED=0
for f in "${LEFTOVERS[@]}"; do
    [ -e "$f" ] || continue
    sudo rm -f "$f"
    REMOVED=1
done
# State and logs they wrote.
sudo rm -rf /var/lib/regreet /var/log/regreet
# ly is a packaged binary, so it goes through the package manager rather
# than rm: leaving it installed but unconfigured is the state that makes
# the next person guess which greeter is live.
if pkg_installed ly && [ "$(pkg_mgr)" = dnf ]; then
    sudo dnf remove -y ly >/dev/null && REMOVED=1
fi
if [ "$REMOVED" = 1 ]; then
    ok "regreet and ly removed, with their configuration."
else
    info "nothing left from regreet or ly."
fi

# ============================================================
# GREETER USER
# ============================================================
section "Greeter user"

if ! id greeter &>/dev/null; then
    sudo useradd -r -M -G video,render -s /sbin/nologin greeter
    ok "user 'greeter' created."
else
    sudo usermod -aG video,render greeter
    ok "user 'greeter' groups updated."
fi

# ============================================================
# CONSOLE: FONT, KEYMAP, AND THE REPAIR THAT MAKES THEM STICK
# ============================================================
section "Console"

[ -f "$MODULE_DIR/console/$CONSOLE_FONT.psfu" ] \
    || err "console/$CONSOLE_FONT.psfu is missing — run ./make-console-font.py"

# Earlier cell sizes, if any. The filename carries the geometry, so a
# change of size leaves the old file behind -- and a stale font in
# setfont's search path is a name someone can still load by accident.
for stale in "$CONSOLE_FONT_DIR"/jetbrains-mono-*.psfu; do
    [ -e "$stale" ] || continue
    [ "$(basename "$stale")" = "$CONSOLE_FONT.psfu" ] && continue
    sudo rm -f "$stale"
    info "removed the superseded $(basename "$stale")"
done

sudo install -Dm644 "$MODULE_DIR/console/$CONSOLE_FONT.psfu" \
                    "$CONSOLE_FONT_DIR/$CONSOLE_FONT.psfu"
sudo install -Dm644 "$MODULE_DIR/console/vconsole.conf" /etc/vconsole.conf
sudo install -Dm755 "$MODULE_DIR/console/console-setup-late.sh" \
                    /usr/local/libexec/console-setup-late
sudo install -Dm644 "$MODULE_DIR/console/console-setup-late.service" \
                    /etc/systemd/system/console-setup-late.service
sudo systemctl daemon-reload
sudo systemctl enable console-setup-late.service
ok "console font, keymap and the late repair unit installed."

# Applied now as well as at boot, so the running console matches without
# waiting for a reboot to find out whether the font even loads.
if sudo setfont "$CONSOLE_FONT" 2>/dev/null; then
    ok "$CONSOLE_FONT loaded into the running console."
else
    warn "setfont could not load $CONSOLE_FONT right now."
    warn "expected while a splash owns the VT; the late unit retries at boot."
fi

# ============================================================
# CONFIGURATION
# ============================================================
section "Configuration"

sudo install -Dm644 "$MODULE_DIR/greetd/config.toml" /etc/greetd/config.toml
sudo mkdir -p /var/cache/tuigreet
sudo chown greeter:greeter /var/cache/tuigreet
sudo chmod 0755 /var/cache/tuigreet

# The session wrapper, which greetd's --cmd points at. It writes the word
# to the console and then execs the real session, so the black gap before
# Hyprland's first frame is covered. It survived the ly experiment intact
# because it never depended on the greeter: a VT keeps showing whatever
# was last drawn on it, whoever drew it.
sudo install -Dm755 "$MODULE_DIR/session-splash.sh" \
                    /usr/local/libexec/coucou-session-splash
ok "greetd configured for tuigreet, with the hand-over splash."

# An /etc/issue banner an older version of this module used to deploy.
sudo systemctl disable --now restore-issue.service &>/dev/null || true
sudo rm -f /etc/systemd/system/restore-issue.service /usr/local/share/tuigreet/issue.txt
if [ ! -L /etc/issue ]; then
    sudo rm -f /etc/issue
    sudo ln -s ../usr/lib/issue /etc/issue
fi

# ============================================================
# SERVICE
#
# The new greeter is enabled BEFORE the old one is disabled, and the old
# one is never stopped. Both halves of that were learned the hard way.
#
# An earlier version ran `systemctl disable --now ly@tty1` first, with a
# comment explaining that --now avoided two greeters fighting over VT1 at
# the next boot. It does not: `disable` alone already means the unit does
# not start again. What --now actually did was stop the unit that OWNED
# THE RUNNING DESKTOP -- the session lives in the greeter's cgroup --
#
#     Stopping ly@tty1.service ...
#     Stopped ly@tty1.service
#     Removed session c1
#
# which killed the session, and with it the terminal running this script,
# before it reached `enable greetd`. The machine was left with no greeter
# enabled at all.
#
# Hence the order: whatever happens after this point, a greeter is already
# enabled for the next boot.
# ============================================================
section "Service"

sudo systemctl daemon-reload
sudo systemctl enable greetd
ok "greetd enabled for the next boot."

# No --now anywhere below: the greeter currently on VT1 may be hosting
# this very session.
for dm in 'ly@tty1.service' gdm sddm lightdm; do
    sudo systemctl disable "$dm" &>/dev/null || true
done
ok "ly, gdm, sddm and lightdm disabled."

if systemctl is-active --quiet 'ly@tty1.service' 2>/dev/null; then
    warn "ly is still RUNNING and may be hosting your current session."
    warn "it is disabled, so greetd takes VT1 at the next boot. Do not stop"
    warn "it by hand from inside a session it started."
fi

echo
ok "Login screen ready. It starts at the next boot."
info "Keyboard: $(grep -oP 'KEYMAP="\K[^"]+' "$MODULE_DIR/console/vconsole.conf"), applied by"
info "console-setup-late.service after the splash quits — keymap before font,"
info "so a font that will not load can no longer cost you the layout."
info ""
info "If the greeter does not come up: Ctrl+Alt+F2 gives a getty, and"
info "  journalctl -b -u greetd    says why."
