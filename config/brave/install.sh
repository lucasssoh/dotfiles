#!/usr/bin/env bash
set -Eeuo pipefail

BLUE="\e[34m"; GREEN="\e[32m"; YELLOW="\e[33m"; RESET="\e[0m"
info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLAGS_FILE="$DOTFILES_DIR/config/brave/brave-flags.conf"

# ============================================================
# 1. Brave
# ============================================================
# Brave is not in Fedora's repos and has no copr worth using -- it ships
# its own signed rpm repo, which is what every other third-party stack in
# this repo does too (docker in scripts/dev_setup.sh uses this exact
# `config-manager addrepo --from-repofile` form; the copr calls elsewhere
# are for things that DO have one).
#
# dnf5 syntax: Fedora 41 dropped `dnf config-manager --add-repo URL`, the
# dnf4 spelling, in favour of `addrepo --from-repofile=`. Getting this
# wrong fails loudly rather than silently, but it fails at the one moment
# a fresh install can least afford it.
if ! command -v brave-browser &> /dev/null; then
    if command -v dnf &> /dev/null; then
        info "Adding the Brave rpm repo..."
        sudo dnf install -y dnf-plugins-core
        sudo dnf config-manager addrepo --overwrite \
            --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        info "Installing Brave..."
        sudo dnf install -y brave-browser
    elif command -v pacman &> /dev/null; then
        # AUR, so not something this script can do unattended.
        warn "Arch: install brave-bin from the AUR by hand, then re-run this module."
        exit 0
    else
        warn "No supported package manager for Brave -- skipping."
        exit 0
    fi
else
    ok "Brave already installed."
fi

command -v brave-browser &> /dev/null || { warn "Brave still not on PATH -- stopping here."; exit 0; }

# ============================================================
# 2. Flags -> a user .desktop override
# ============================================================
# See brave-flags.conf's own header for why this is a .desktop copy and
# not a flags file Brave reads for itself.
FLAGS="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$FLAGS_FILE" | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/ $//')"
[ -n "$FLAGS" ] || { warn "No flags parsed from $FLAGS_FILE -- leaving the desktop entry alone."; exit 0; }
info "Flags: $FLAGS"

# Verify every --enable-features token really exists in THIS build. A
# Chromium feature name that has been renamed is not an error: the switch
# parses, the unknown name is dropped, and the only symptom is the feature
# silently never turning on. Catching it here costs one grep; catching it
# from YouTube's stats-for-nerds costs an evening.
# Resolve to the real ELF, not the launcher. `brave-browser` is Chromium's
# stock wrapper SCRIPT (it sanitises std{in,out,err} and execs "$HERE/brave"),
# so `strings` on it searches 1 KB of bash and finds no feature name at all
# -- which is exactly the false "feature renamed" warning this check emitted
# on its first real run. The ELF is the wrapper's sibling `brave`.
BRAVE_BIN="$(readlink -f "$(command -v brave-browser)")"
if [ "$(od -An -c -N4 "$BRAVE_BIN" 2>/dev/null | tr -d ' ')" != "177ELF" ]; then
    _cand="$(dirname "$BRAVE_BIN")/brave"
    [ -x "$_cand" ] && BRAVE_BIN="$_cand"
fi
if command -v strings &> /dev/null && [ -r "$BRAVE_BIN" ]; then
    for tok in $FLAGS; do
        case "$tok" in --enable-features=*) ;; *) continue ;; esac
        IFS=',' read -ra feats <<< "${tok#--enable-features=}"
        for f in "${feats[@]}"; do
            # Either spelling counts. Chromium's BASE_FEATURE macro derives
            # the runtime name by stripping the leading "k" from the C++
            # identifier, and it is the IDENTIFIER that survives into the
            # binary -- `WaylandWpColorManagerV1` appears there only as a
            # substring of `kWaylandWpColorManagerV1`, never on a line of
            # its own. Checking only the bare form fails on every feature.
            # NOT `grep -q`, and that is load-bearing: this script runs
            # under `set -o pipefail`, -q makes grep exit at the first
            # match, `strings` then dies of SIGPIPE with status 141, and
            # pipefail reports the whole pipeline as FAILED even though
            # the match succeeded -- which is the second reason this check
            # cried wolf on its first real runs. Letting grep drain the
            # stream costs a few seconds on a 320 MB binary and is right.
            if strings -- "$BRAVE_BIN" | grep -Fx -e "$f" -e "k$f" > /dev/null; then
                ok "feature '$f' présente dans ce build."
            else
                warn "feature '$f' INTROUVABLE dans $BRAVE_BIN -- probablement renommée."
                warn "  Cherche le nom courant:  strings '$BRAVE_BIN' | grep -i colormanage"
                warn "  puis corrige config/brave/brave-flags.conf."
            fi
        done
    done
else
    warn "'strings' absent (paquet binutils) -- vérification des features sautée."
fi

SRC="$(ls /usr/share/applications/brave-browser*.desktop 2>/dev/null | head -n1 || true)"
if [ -z "$SRC" ]; then
    warn "No system brave .desktop found -- flags not applied."
    exit 0
fi
DEST_DIR="$HOME/.local/share/applications"
mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/$(basename "$SRC")"

# Insert the flags straight after the binary, BEFORE the trailing %U /
# %F field code: a field code has to stay last for the desktop spec, and
# some launchers stop parsing the line at it. Every Exec= is rewritten,
# not just the first -- Brave's entry carries Actions (new window, new
# private window) with an Exec= each, and flags that applied only to the
# main entry would make "new private window" behave differently for no
# visible reason.
awk -v flags="$FLAGS" '
    /^Exec=/ {
        line = substr($0, 6)
        n = index(line, " ")
        if (n == 0) print "Exec=" line " " flags
        else       print "Exec=" substr(line, 1, n - 1) " " flags substr(line, n)
        next
    }
    { print }
' "$SRC" > "$DEST"

command -v update-desktop-database &> /dev/null && update-desktop-database "$DEST_DIR" 2>/dev/null || true

ok "Brave configured ($(basename "$DEST"), $(grep -c '^Exec=' "$DEST") Exec lines patched)."
