#!/usr/bin/env bash
# scripts/install-hardware.sh — installs the packages this machine's CPU/GPU
# actually needs, as decided by scripts/lib/hardware.sh.
#
# Run by setup_fedora.sh as part of the system phase, and re-runnable on its
# own (`./install hardware`) after a hardware change -- swapping laptops,
# adding a GPU -- without redoing the whole base install.
#
# Everything here is idempotent: dnf skips what's already present, and the
# systemd units are enabled with --now only if their package landed.
set -Eeuo pipefail

BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ ERR]${RESET}  $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${RESET}\n"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hardware.sh
source "$DOTFILES_DIR/scripts/lib/hardware.sh"

command -v dnf >/dev/null 2>&1 || err "Not a dnf system — hardware profiles are Fedora-only for now."

section "Hardware detection"
hw_detect
hw_report

# ============================================================
# PACKAGES
# ============================================================
section "Hardware packages"

mapfile -t PKGS < <(hw_packages)

if [ "${#PKGS[@]}" -eq 0 ]; then
    warn "No hardware-specific package for this machine (profile: ${HW_CPU_PROFILE:-generic})."
else
    info "Installing: ${PKGS[*]}"
    # --skip-unavailable so a package renamed or retired in some future
    # Fedora can't abort the whole run. That makes dnf silent about
    # what it dropped, though, so the loop below re-checks and names
    # anything that didn't actually land -- a silently missing
    # libva-intel-media-driver is exactly the kind of thing that turns
    # into "why is video decode on the CPU" three weeks later.
    sudo dnf install -y --skip-unavailable "${PKGS[@]}"

    missing=()
    for p in "${PKGS[@]}"; do
        rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        warn "Not installed (unavailable in the configured repos): ${missing[*]}"
        warn "Check the package names in scripts/lib/hardware.sh against this Fedora release."
    else
        ok "All ${#PKGS[@]} hardware packages installed."
    fi
fi

# ============================================================
# SERVICES
# ============================================================
# Both are installed by the profiles above but ship disabled; neither does
# anything until enabled. thermald only exists on the Intel profiles,
# power-profiles-daemon is in the common set -- hence the rpm -q guard
# rather than assuming either is present.
section "Hardware services"

for svc in thermald power-profiles-daemon; do
    if rpm -q "$svc" >/dev/null 2>&1; then
        if sudo systemctl enable --now "$svc" 2>/dev/null; then
            ok "$svc enabled."
        else
            warn "$svc is installed but could not be enabled."
        fi
    else
        info "$svc not installed for this profile — skipping."
    fi
done

# ============================================================
# UDEV RULES
# ============================================================
# Hardware-specific permission fixes. Installed here rather than from the
# Hyprland module because they are a property of the MACHINE, not of the
# desktop config -- and because `./install hardware` is the thing you
# re-run after swapping laptops.
section "Hardware udev rules"

install_udev_rule() {
    local src="$1" name
    name="$(basename "$src")"
    if sudo install -Dm644 "$src" "/etc/udev/rules.d/$name"; then
        ok "Installed /etc/udev/rules.d/$name"
        return 0
    fi
    warn "Could not install $name"
    return 1
}

# Lenovo IdeaPad conservation mode (~60% charge cap). Gated on the
# attribute actually existing rather than on the vendor string: a Lenovo
# without ideapad-laptop, or a ThinkPad (which exposes the generic
# charge_control_*_threshold knobs instead), should not get a rule that
# can never match.
CONSERVATION_ATTR="$(find /sys/devices/platform -name conservation_mode 2>/dev/null | head -n1)"

if [ -n "$CONSERVATION_ATTR" ]; then
    info "IdeaPad conservation mode found at $CONSERVATION_ATTR"
    if install_udev_rule "$DOTFILES_DIR/config/hyprland/udev/99-ideapad-conservation.rules"; then
        sudo udevadm control --reload-rules 2>/dev/null || true
        # The rule only fires on the next add/change event, i.e. the next
        # boot. Apply the same thing now so the toggle works immediately.
        if sudo chgrp wheel "$CONSERVATION_ATTR" && sudo chmod 0664 "$CONSERVATION_ATTR"; then
            ok "conservation_mode is now writable by group wheel."
        else
            warn "Rule installed, but the live chgrp/chmod failed — it will take effect on the next boot."
        fi
        id -nG | tr ' ' '\n' | grep -qx wheel \
            || warn "$USER is NOT in the wheel group — the rule grants write to wheel, so add yourself: sudo usermod -aG wheel $USER"
    fi
else
    info "No conservation_mode attribute on this machine — skipping the IdeaPad rule."
fi

# ============================================================
# MANUAL FOLLOW-UPS
# ============================================================
notes="$(hw_notes)"
if [ -n "$notes" ]; then
    section "Manual follow-ups"
    echo "$notes"
    echo
fi

ok "Hardware phase done."
