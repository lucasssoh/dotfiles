#!/usr/bin/env bash
# install.sh -- the boot splash (Plymouth), from GRUB's hand-off to the greeter.
#
# What this module fixes, on the machine it was written for: nothing was
# drawn at all between picking a kernel in GRUB and tuigreet appearing.
# On an OLED panel a black screen is indistinguishable from a powered-off
# laptop, so the machine looked dead for several seconds on every boot.
#
# The cause was not the theme. `plymouth-graphics-libs` was not installed,
# and that package owns /usr/lib64/plymouth/renderers/{drm,frame-buffer}.so
# -- every renderer Plymouth has. Without one it cannot put a pixel on a
# screen whatever theme is selected, and the selected theme was `text`,
# which draws nothing under `rhgb quiet` anyway. Both halves are handled
# below: the packages first, then the theme.
#
#   ./install.sh                  packages, theme, default theme, initramfs
#   ./install.sh --no-initramfs   everything except the rebuild (see preview.sh)
#
# The initramfs rebuild is the slow part (tens of seconds, every installed
# kernel) and it is the only reason this module is not cheap to re-run, so
# it is skipped unless something that ends up *inside* the initramfs
# actually changed.

set -Eeuo pipefail

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../scripts/lib/pkg.sh"

BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; RESET="\e[0m"
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
THEME_SRC="$REPO_DIR/theme"
THEME_NAME="coucou"
THEME_DST="/usr/share/plymouth/themes/$THEME_NAME"

REBUILD_INITRAMFS=1
[ "${1:-}" = "--no-initramfs" ] && REBUILD_INITRAMFS=0

section "BOOT SPLASH (PLYMOUTH · $THEME_NAME)"

# ============================================================
# PACKAGES
#
# Fedora splits Plymouth finely enough that the base package alone is a
# daemon with no way to draw. Named here in full rather than leaning on
# `plymouth-system-theme`, which would also drag in the distro's bgrt
# theme and set it as the default.
# ============================================================
case "$(pkg_mgr)" in
    dnf)    PKGS=(plymouth plymouth-scripts plymouth-graphics-libs
                  plymouth-plugin-script plymouth-plugin-label
                  jetbrains-mono-fonts) ;;
    pacman) PKGS=(plymouth ttf-jetbrains-mono) ;;  # arch ships one plymouth package
    apt)    PKGS=(plymouth plymouth-themes fonts-jetbrains-mono) ;;
    *)      PKGS=(plymouth) ;;
esac

PKGS_WERE_MISSING=0
for p in "${PKGS[@]}"; do
    pkg_installed "$p" || { PKGS_WERE_MISSING=1; break; }
done

pkg_ensure "${PKGS[@]}"

# Everything past this point is system-wide and needs root. In user scope
# (`cc-pkg-mng update` without --system) pkg_ensure has just recorded the
# missing packages in the deferred ledger; doing the rest here would break
# the promise that an everyday update never asks for a password.
if [ "${CCPKG_ALLOW_ROOT:-1}" = "0" ]; then
    warn "user scope: the boot splash is system-wide — deferred."
    warn "run  cc-pkg-mng update --system  or  ./config/boot/plymouth/install.sh"
    exit 0
fi

# Without a renderer Plymouth is a daemon that cannot draw, which is the
# exact failure this module was written to fix -- so a package that did
# not land is fatal here rather than a warning nobody reads.
if [ "$PKGS_WERE_MISSING" = 1 ]; then
    declare -a STILL_MISSING=()
    for p in "${PKGS[@]}"; do
        pkg_installed "$p" || STILL_MISSING+=("$p")
    done
    [ "${#STILL_MISSING[@]}" -gt 0 ] && err "could not install: ${STILL_MISSING[*]}"
    ok "renderers and script plugin in place."
fi

# ============================================================
# THEME
#
# Deployed file by file and compared by content hash, because the answer
# to "did anything change?" is what decides whether the initramfs gets
# rebuilt. The hash covers names as well as contents, so a renamed or
# deleted asset counts as a change.
# ============================================================
section "Theme"

theme_hash() {
    [ -d "$1" ] || { printf 'absent'; return 0; }
    ( cd "$1" && find . -type f | LC_ALL=C sort | xargs -r sha256sum ) | sha256sum | cut -d' ' -f1
}

SRC_HASH="$(theme_hash "$THEME_SRC")"
DST_HASH="$(theme_hash "$THEME_DST")"
THEME_CHANGED=0

if [ "$SRC_HASH" != "$DST_HASH" ]; then
    sudo install -d -m 0755 "$THEME_DST"
    sudo install -m 0644 "$THEME_SRC"/* "$THEME_DST/"
    # Drop anything the repo no longer carries: a stale PNG left behind
    # would keep riding into every initramfs.
    if [ -d "$THEME_DST" ]; then
        for f in "$THEME_DST"/*; do
            [ -e "$THEME_SRC/$(basename "$f")" ] || sudo rm -f "$f"
        done
    fi
    THEME_CHANGED=1
    ok "theme deployed to $THEME_DST"
else
    info "theme already up to date."
fi

# The assets are cut for one panel width and Plymouth scales them for any
# other. Its scaler is not make-assets.py's, so a machine whose panel is a
# different width gets a softer word mark than it needs to -- and the fix
# is a one-line regeneration, which is worth saying out loud rather than
# leaving to be noticed.
REF_WIDTH="$(sed -n 's/^REF_WIDTH[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' \
             "$THEME_SRC/coucou.script")"
PANEL_WIDTH=""
for st in /sys/class/drm/card*-*/status; do
    [ -r "$st" ] || continue
    [ "$(cat "$st")" = connected ] || continue
    PANEL_WIDTH="$(head -n1 "${st%/status}/modes" 2>/dev/null)"
    PANEL_WIDTH="${PANEL_WIDTH%%x*}"
    [ -n "$PANEL_WIDTH" ] && break
done

if [ -n "$PANEL_WIDTH" ] && [ -n "$REF_WIDTH" ] && [ "$PANEL_WIDTH" != "$REF_WIDTH" ]; then
    warn "panel is ${PANEL_WIDTH}px wide, assets are cut for ${REF_WIDTH}px."
    warn "layout and proportions still hold — only sharpness is lost. To fix:"
    warn "  ./config/boot/plymouth/make-assets.py --width $PANEL_WIDTH  (then re-run this)"
fi

# ============================================================
# STATUS FEED
#
# The one-line boot log under the bar. It is a separate unit rather than
# part of the theme because Plymouth has no way to ask systemd anything:
# the status channel exists, and nothing on a Fedora system writes to it.
# Neither file goes into the initramfs, so changing them never costs a
# dracut run — but it also means the feed only starts after switch-root,
# and the initramfs phase shows Plymouth's own messages alone.
# ============================================================
section "Status feed"

FEED_BIN="/usr/local/libexec/coucou-splash-status"
FEED_UNIT="/etc/systemd/system/coucou-splash-status.service"
FEED_UNIT_NAME="coucou-splash-status.service"

# Returns 0 when it actually wrote something.
deploy_if_changed() {
    if cmp -s "$1" "$2" 2>/dev/null; then
        return 1
    fi
    sudo install -D -m "$3" "$1" "$2"
    return 0
}

if deploy_if_changed "$REPO_DIR/status-feed.sh" "$FEED_BIN" 0755; then
    ok "feed script deployed to $FEED_BIN"
else
    info "feed script already up to date."
fi

if deploy_if_changed "$REPO_DIR/$FEED_UNIT_NAME" "$FEED_UNIT" 0644; then
    sudo systemctl daemon-reload
    ok "unit deployed to $FEED_UNIT"
else
    info "unit already up to date."
fi

if systemctl is-enabled --quiet "$FEED_UNIT_NAME" 2>/dev/null; then
    info "$FEED_UNIT_NAME is already enabled."
else
    sudo systemctl enable "$FEED_UNIT_NAME"
    ok "$FEED_UNIT_NAME enabled."
fi

# ============================================================
# THE DAEMON CONFIG FILE, AND THE COMMENT THAT BROKE EVERYTHING
#
# Fedora ships /etc/plymouth/plymouthd.conf with its example commented
# out:
#
#     # Administrator customizations go in this file
#     #[Daemon]
#     #Theme=fade-in
#
# and plymouth-set-default-theme reads the theme back out of it with
#
#     BEGIN { FS="[=[:space:]]+"; ORS="" }
#     $1 ~ /Theme/ { print $2 }
#
# an UNANCHORED regex with an empty output separator. "#Theme" matches
# /Theme/, so the two values concatenate: with Theme=coucou set, the file
# reads back as "fade-incoucou". No such theme exists, so it falls
# through to plymouthd.defaults (bgrt, not installed), then to the
# default.plymouth symlink (which that same tool deletes), and lands on
# its last resort: "text".
#
# That single wrong word is the whole of the boot splash never appearing.
# plymouth-populate-initrd asks exactly this command which theme to bake
# in (`PLYMOUTH_THEME_NAME=$(plymouth-set-default-theme)`), got "text",
# and dutifully baked in the text theme and text.so -- while plymouthd at
# boot read Theme=coucou from the same file with its OWN, correct parser,
# looked for a theme that was not there, and fell back to the text splash,
# which under `quiet` draws nothing.
#
# So the commented Theme line goes. It is an example nobody needs and a
# landmine for a parser that cannot tell a comment from a setting.
#
# UseSimpledrm=0 is set here too, in the same pass over the same file.
# Left alone the splash appears twice: once at ~1.07s on simpledrm, then
# black for ~1.8s while i915 takes the panel, then again. The device log
# is unambiguous -- card0 removed at 01.806, card1 added at 03.573 --
# and between them there is no display device at all, so no theme can do
# anything about it. Upstream describes the same thing in the commit that
# added Fedora's UseSimpledrmNoLuks default: "the unlock screen will
# briefly show and then the screen goes black while the native GPU driver
# loads leading to a jarring experience". UseSimpledrm is read BEFORE
# UseSimpledrmNoLuks in load_settings() and the second block is skipped
# once the first has a value, so this beats the distribution default
# rather than fighting it. The trade is a 0.7s flash at 1.1s for nothing
# until ~3.6s; both reach a stable splash at the same moment, but this way
# the machine goes from black to the word once and stays there.
#
# This runs BEFORE the theme is selected, because the selection step
# verifies itself by reading the theme back -- and that read is the thing
# being repaired.
# ============================================================
section "Daemon configuration"

PLYMOUTHD_CONF="/etc/plymouth/plymouthd.conf"

if grep -qE '^\s*#\s*Theme\s*=' "$PLYMOUTHD_CONF" 2>/dev/null; then
    sudo sed -i -E '/^\s*#\s*Theme\s*=/d' "$PLYMOUTHD_CONF"
    ok "removed the commented Theme= line (it parsed as a real setting)."
else
    info "no commented Theme= line to remove."
fi

if ! grep -q '^[[]Daemon[]]' "$PLYMOUTHD_CONF" 2>/dev/null; then
    printf '[Daemon]\n' | sudo tee -a "$PLYMOUTHD_CONF" >/dev/null
fi
if grep -qE '^\s*UseSimpledrm\s*=' "$PLYMOUTHD_CONF" 2>/dev/null; then
    sudo sed -i -E 's/^\s*UseSimpledrm\s*=.*/UseSimpledrm=0/' "$PLYMOUTHD_CONF"
else
    sudo sed -i -E '0,/^\[Daemon\]/s//[Daemon]\nUseSimpledrm=0/' "$PLYMOUTHD_CONF"
fi
grep -qE '^UseSimpledrm=0$' "$PLYMOUTHD_CONF" \
    || err "could not set UseSimpledrm=0 in $PLYMOUTHD_CONF"
ok "UseSimpledrm=0 — the splash waits for the real driver and shows once."

# ============================================================
# DEFAULT THEME
# ============================================================
CURRENT_THEME="$(plymouth-set-default-theme 2>/dev/null || echo unknown)"
THEME_SELECTED=0
if [ "$CURRENT_THEME" != "$THEME_NAME" ]; then
    sudo plymouth-set-default-theme "$THEME_NAME"
    THEME_SELECTED=1
    ok "default theme: $CURRENT_THEME → $THEME_NAME"
else
    info "default theme is already $THEME_NAME."
fi

# Re-read rather than assume: the stamp below has to describe what is
# actually selected, not what this script intended to select.
CURRENT_THEME_NOW="$(plymouth-set-default-theme 2>/dev/null || echo unknown)"
[ "$CURRENT_THEME_NOW" = "$THEME_NAME" ] \
    || err "default theme is '$CURRENT_THEME_NOW', not '$THEME_NAME' — refusing to go on."

# ============================================================
# KERNEL COMMAND LINE
#
# `rhgb` is what asks for a graphical boot and `quiet` is what keeps the
# kernel from scribbling over it. Fedora sets both by default, so this
# only ever reports — rewriting boot arguments behind someone's back is
# not worth the one machine in a hundred that needs it.
# ============================================================
CMDLINE="$(cat /proc/cmdline)"
MISSING_ARGS=()
grep -qw rhgb  <<<"$CMDLINE" || MISSING_ARGS+=(rhgb)
grep -qw quiet <<<"$CMDLINE" || MISSING_ARGS+=(quiet)
if [ ${#MISSING_ARGS[@]} -gt 0 ]; then
    warn "kernel command line is missing: ${MISSING_ARGS[*]}"
    warn "the splash will be overdrawn by kernel messages until you run:"
    warn "  sudo grubby --update-kernel=ALL --args=\"${MISSING_ARGS[*]}\""
fi

# ============================================================
# MONOSPACE DEFAULT
#
# The splash's status line asks for "JetBrains Mono", and inside the
# initramfs that resolves through label-freetype's monospace slot rather
# than by family name (see mono-fontconfig.conf, which explains the whole
# chain). The slot is filled by `fc-match monospace` run as root when
# dracut builds the initramfs, so the rule has to be system-wide and in
# place BEFORE the rebuild below.
#
# It also has to count as an initramfs-relevant change: it is not copied
# into the initramfs itself, but it decides which font file is.
# ============================================================
section "Monospace default"

# 55, not 70: fontconfig's prepend inserts at the position of the test, so
# the EARLIEST rule ends up nearest the head of the family list. This has
# to beat 56-google-noto-sans-mono-vf.conf while still letting a per-user
# file (pulled in at 50 by 50-user.conf) override it. See
# mono-fontconfig.conf, which has the measured family list.
FONTCONF_DST="/etc/fonts/conf.d/55-mono-font.conf"
FONTCONF_STALE="/etc/fonts/conf.d/70-mono-font.conf"
FONTCONF_CHANGED=0
# An earlier version of this module shipped the same rule at 70, where it
# was loaded, reported as active by fc-conflist, and did nothing.
if [ -e "$FONTCONF_STALE" ]; then
    sudo rm -f "$FONTCONF_STALE"
    FONTCONF_CHANGED=1
    ok "removed the ineffective $FONTCONF_STALE"
fi
if deploy_if_changed "$REPO_DIR/mono-fontconfig.conf" "$FONTCONF_DST" 0644; then
    FONTCONF_CHANGED=1
    ok "monospace default deployed to $FONTCONF_DST"
else
    info "monospace default already in place."
fi

RESOLVED_MONO="$(XDG_CONFIG_HOME=/nonexistent HOME=/root fc-match -f '%{family}' monospace 2>/dev/null)"
if [ "$RESOLVED_MONO" = "JetBrains Mono" ]; then
    ok "root resolves monospace to JetBrains Mono — the splash will use it."
else
    warn "root resolves monospace to '${RESOLVED_MONO:-nothing}', not JetBrains Mono."
    warn "the boot splash will use that instead; check $FONTCONF_DST"
fi

# ============================================================
# A SECOND ROUTE INTO THE INITRAMFS
#
# With the commented Theme= line gone, plymouth-populate-initrd finally
# asks for the right theme and copies it. This list is not what fixes
# that, and it is worth being clear about which is which: this is a
# backstop.
#
# It exists because the failure it guards against was invisible. The
# populate script is run by dracut with `2> /dev/null`, it takes the
# theme name from a command that answered "text" for months without
# anyone noticing, and the result was a machine that booted black with no
# error anywhere. Stating the files outright means the splash no longer
# depends on that chain being right -- and if someone puts a commented
# Theme= line back in the config, this keeps the boot working while the
# check further down still reports the regression.
#
# script.so is on the list for the same reason it went missing in the
# first place: the populate script reads ModuleName out of the theme's
# .plymouth file to decide which plugin to copy, so a wrong theme name
# took the plugin with it.
#
# The list is generated from what is actually deployed, so an asset added
# to theme/ cannot be forgotten here.
# ============================================================
section "Initramfs contents"

# The check that runs on every future kernel. It builds nothing -- dracut
# already reads the file written below on every run, including the one
# kernel-install triggers -- it only reports, into the output of the very
# dnf transaction that installed the kernel. See kernel-install-check.sh
# for why a check and not a rebuild.
sudo install -Dm755 "$REPO_DIR/kernel-install-check.sh" \
                    /etc/kernel/install.d/99-coucou-splash.install
ok "new kernels will be checked as they are installed."


DRACUT_CONF="/etc/dracut.conf.d/90-coucou-splash.conf"
PLUGIN_DIR="$(plymouth --get-splash-plugin-path 2>/dev/null || echo /usr/lib64/plymouth)"

ITEMS=""
for f in "$THEME_SRC"/*; do
    ITEMS="$ITEMS $THEME_DST/$(basename "$f")"
done
ITEMS="$ITEMS ${PLUGIN_DIR%/}/script.so"

DRACUT_CONF_TMP="$(mktemp)"
cat > "$DRACUT_CONF_TMP" <<EOF
# Written by config/boot/plymouth/install.sh -- do not edit by hand.
#
# plymouth-populate-initrd drops everything it copies from /usr/share on
# this machine, silently, taking the theme and the script plugin with it.
# These are stated explicitly so the splash does not depend on that.
install_items+="$ITEMS "
EOF

if ! cmp -s "$DRACUT_CONF_TMP" "$DRACUT_CONF" 2>/dev/null; then
    sudo install -Dm644 "$DRACUT_CONF_TMP" "$DRACUT_CONF"
    ok "dracut told to carry $(printf '%s' "$ITEMS" | wc -w) files explicitly."
else
    info "dracut include list already up to date."
fi
rm -f "$DRACUT_CONF_TMP"

# ============================================================
# INITRAMFS
#
# The splash starts inside the initramfs, long before / is mounted, so
# the theme, the script plugin and the renderers all have to be baked in.
# --regenerate-all covers every installed kernel: rebuilding only the
# running one leaves the previous kernel — the one GRUB's second entry
# boots, i.e. the one used exactly when something is already wrong —
# showing the old splash.
#
# ── Why this is decided by a stamp and not by what changed just now ────
#
# It used to skip the rebuild when nothing had changed DURING THIS RUN,
# and that was wrong in a way that took a debug log from a real boot to
# find. preview.sh calls this script with --no-initramfs; that run
# installed the packages, deployed the theme and selected it, so it
# consumed every "changed" signal. The next full run then saw four zeroes
# and concluded, correctly by its own logic and falsely in fact, that the
# initramfs was current -- when dracut had never run at all.
#
# The boot that followed said exactly that:
#
#     Trying to load /etc/plymouth/plymouthd.conf
#     key file has comments but no groups
#     failed to load /etc/plymouth/plymouthd.conf
#
# That is Fedora's pristine file, the one where [Daemon] is commented
# out, still sitting in an initramfs built before the theme was ever
# selected. With no Theme= to read and no default.plymouth symlink to
# fall back to (plymouth-set-default-theme deletes it), plymouthd loaded
# the text splash -- which under `quiet` draws nothing. The renderer was
# never the problem; the log shows drm.so opening card1 and creating a
# 1920x1200 head half a second earlier.
#
# So the question is no longer "did anything change in this run?" but
# "does the initramfs on disk match what we would build now?", and that
# is answered by a stamp only a SUCCESSFUL dracut is allowed to write.
# ============================================================
section "Initramfs"

INITRAMFS_STAMP="/var/lib/coucou-splash/initramfs.stamp"
# Everything whose presence inside the initramfs matters. Not the package
# versions: dracut reruns on kernel and plymouth updates through its own
# triggers, and putting versions here would rebuild on every unrelated
# bump.
INITRAMFS_KEY="theme:$SRC_HASH|mono:$(sha256sum < "$REPO_DIR/mono-fontconfig.conf" | cut -d' ' -f1)|conf:$(sha256sum < "$PLYMOUTHD_CONF" | cut -d' ' -f1)|items:$(sha256sum < "$DRACUT_CONF" | cut -d' ' -f1)|selected:$CURRENT_THEME_NOW"

if [ "$REBUILD_INITRAMFS" = 0 ]; then
    info "skipped (--no-initramfs): on-screen changes apply now, boot keeps the previous splash."
    if [ "$(sudo cat "$INITRAMFS_STAMP" 2>/dev/null)" != "$INITRAMFS_KEY" ]; then
        warn "the initramfs does NOT match what is deployed — the boot splash will"
        warn "not be what you just previewed. Re-run this script without the flag."
    fi
elif [ "$(sudo cat "$INITRAMFS_STAMP" 2>/dev/null)" = "$INITRAMFS_KEY" ]; then
    info "initramfs already built from exactly this — no rebuild."
elif command -v dracut >/dev/null 2>&1; then
    info "rebuilding for every installed kernel (this takes a moment)..."
    sudo dracut --force --regenerate-all

    # Verify the result rather than trust it. Both of these were wrong on
    # the boot that prompted all of the above, and neither was visible
    # until the machine had already come up black.
    INITRAMFS_OK=1

    # `lsinitrd -f <path>` extracts one file (it strips the leading slash
    # itself), which is a sharper question than grepping the listing: the
    # listing is a formatted, sorted `cpio -tv` and a miss there can mean
    # the file is absent OR that the shape of the output changed.
    # Every installed kernel, not just the running one. --regenerate-all
    # built them all, and the one that matters on the day something goes
    # wrong is the older entry in the GRUB menu.
    for img in /boot/initramfs-*.img; do
        [ -f "$img" ] || continue
        case "$img" in *rescue*) continue ;; esac   # rescue uses its own theme
        if ! sudo lsinitrd "$img" -f "$THEME_DST/$THEME_NAME.plymouth" 2>/dev/null \
             | grep -q ModuleName; then
            warn "$(basename "$img") does not carry $THEME_NAME.plymouth"
            INITRAMFS_OK=0
        fi
    done
    if ! sudo lsinitrd -f /etc/plymouth/plymouthd.conf 2>/dev/null | grep -qE '^\s*Theme\s*='; then
        warn "the rebuilt initramfs has a plymouthd.conf with no Theme= line"
        warn "(plymouthd then falls back to the text splash, which draws nothing)"
        INITRAMFS_OK=0
    fi

    # A check that only says "missing" sends whoever reads it guessing.
    # Say what IS in there, so one run answers the question instead of
    # starting another round of it.
    if [ "$INITRAMFS_OK" = 0 ]; then
        warn "what the initramfs actually holds for plymouth:"
        sudo lsinitrd 2>/dev/null | grep -i plymouth | sed 's/^/    /' | head -30
        warn "plymouth-populate-initrd would have said:"
        sudo /usr/libexec/plymouth/plymouth-populate-initrd -t /tmp/coucou-populate-check 2>&1 \
            | grep -iE 'theme|error|not found' | sed 's/^/    /' | head -10
        sudo rm -rf /tmp/coucou-populate-check
    fi

    if [ "$INITRAMFS_OK" = 1 ]; then
        sudo install -d -m 0755 "$(dirname "$INITRAMFS_STAMP")"
        printf '%s' "$INITRAMFS_KEY" | sudo tee "$INITRAMFS_STAMP" >/dev/null
        ok "initramfs rebuilt, and verified to carry the theme."
    else
        # No stamp on a bad build, so the next run tries again instead of
        # believing it is done.
        err "initramfs rebuilt but does not carry a usable theme — see above."
    fi
else
    warn "dracut not found — rebuild the initramfs by hand, or the splash stays unchanged at boot."
fi

echo
ok "Boot splash ready. Preview it without rebooting: ./config/boot/plymouth/preview.sh"
