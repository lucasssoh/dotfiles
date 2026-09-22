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
# MEDIA CODECS (RPM Fusion)
# ============================================================
# Separate from the package block above because these need third-party
# repos, and separate from hw_notes (where the NVIDIA driver lives,
# unautomated) because unlike that one this is safe to automate: no kmod
# rebuild, no reboot, no Secure Boot interaction. See hw_codec_swaps in
# lib/hardware.sh for the pair table and why each half is what it is.
section "Media codecs"

mapfile -t SWAPS < <(hw_codec_swaps)

if [ "${#SWAPS[@]}" -eq 0 ]; then
    info "No codec swap for this machine (profile: ${HW_CPU_PROFILE:-generic})."
else
    # Both repos, not just free: ffmpeg is in RPM Fusion free,
    # intel-media-driver is in nonfree. The rpm -q guard is what makes a
    # re-run a no-op instead of a failed reinstall of the release package.
    repos_ok=yes
    for repo in free nonfree; do
        if rpm -q "rpmfusion-$repo-release" >/dev/null 2>&1; then
            info "RPM Fusion $repo already enabled."
            continue
        fi
        info "Enabling RPM Fusion $repo..."
        if ! sudo dnf install -y \
            "https://mirrors.rpmfusion.org/$repo/fedora/rpmfusion-$repo-release-$(rpm -E %fedora).noarch.rpm"
        then
            warn "Could not enable RPM Fusion $repo."
            repos_ok=no
        fi
    done

    if [ "$repos_ok" != "yes" ]; then
        warn "Skipping the codec swaps — hardware H.264/HEVC decode will not be available."
    else
        for pair in "${SWAPS[@]}"; do
            read -r from to <<<"$pair"

            if rpm -q "$to" >/dev/null 2>&1; then
                ok "$to already installed."
            elif rpm -q "$from" >/dev/null 2>&1; then
                # ffmpeg Conflicts: ffmpeg-free, so a plain install cannot
                # work here; --allowerasing lets dnf drop the stripped
                # build along with whatever depends on it by name.
                info "Swapping $from → $to..."
                sudo dnf swap -y "$from" "$to" --allowerasing \
                    || warn "Swap $from → $to failed."
            else
                # Nothing to replace on this release (the mesa case).
                info "$from not installed — installing $to directly..."
                sudo dnf install -y "$to" \
                    || warn "Install of $to failed."
            fi
        done

        # The deliverable here is a CAPABILITY, not a set of packages --
        # the whole reason this step exists is that the broken state looks
        # perfectly healthy at the package level. vainfo comes from
        # libva-utils in _HW_PKGS_COMMON, and the H264 VLD entrypoint is
        # precisely what is missing when Fedora's stripped driver is the
        # one libva picks up.
        if ! command -v vainfo >/dev/null 2>&1; then
            warn "vainfo not available — cannot verify hardware decode."
        elif vainfo 2>/dev/null | grep -q 'VAProfileH264.*VAEntrypointVLD'; then
            ok "VAAPI decodes H.264 in hardware."
            if vainfo 2>/dev/null | grep -q 'VAProfileHEVCMain.*VAEntrypointVLD'; then
                ok "HEVC too."
            fi
            info "Already-running apps keep whatever driver they dlopen'd at"
            info "startup — restart Firefox/mpv before expecting the change."
        else
            warn "vainfo still reports no H.264 decode entrypoint; video will decode on the CPU."
            warn "Check: vainfo 2>&1 | grep -i 'trying to open'  — it should name"
            warn "/usr/lib64/dri-nonfree (Intel) or /usr/lib64/dri-freeworld (AMD)."
        fi
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
# Searched under /sys/bus/platform/devices/, NOT /sys/devices/platform:
# that second path only holds platform devices parented at the platform bus
# root, and the IdeaPad's VPC2004:00 is not one -- ideapad-laptop binds an
# ACPI node, so the device sits under the EC at
# /sys/devices/pci0000:00/0000:00:1f.0/PNP0C09:00/VPC2004:00. The old path
# matched nothing on a real IdeaPad, so this whole block took the "not an
# IdeaPad, skipping" branch below and the rule was never installed -- on the
# one machine it was written for. -L because the bus entries are symlinks
# and find will not descend into one without it. Kept identical to
# SystemStats.qml's own conservationDiscover probe; the two must agree.
CONSERVATION_ATTR="$(find -L /sys/bus/platform/devices -maxdepth 2 -name conservation_mode 2>/dev/null | head -n1)"

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

# Lenovo fast charge (charge_types). Gated separately from the cap above,
# and NOT on the same attribute: conservation_mode is ideapad_acpi's, on
# the platform bus, while charge_types belongs to the ACPI battery under
# /sys/class/power_supply. A machine can expose one without the other.
#
# The second test is the one that matters. Plenty of batteries expose
# charge_types while offering only Standard and Long_Life, and granting
# write on a knob that cannot reach Fast would install a rule for a tile
# PowerHome will never draw (it gates on the same string).
CHARGE_TYPES_ATTR=""
for d in /sys/class/power_supply/*/; do
    [ "$(cat "$d/type" 2>/dev/null)" = Battery ] || continue
    [ -e "$d/charge_types" ] || continue
    grep -q Fast "$d/charge_types" 2>/dev/null || continue
    CHARGE_TYPES_ATTR="${d}charge_types"
    break
done

if [ -n "$CHARGE_TYPES_ATTR" ]; then
    info "Fast charge found at $CHARGE_TYPES_ATTR ($(cat "$CHARGE_TYPES_ATTR"))"
    if install_udev_rule "$DOTFILES_DIR/config/hyprland/udev/99-ideapad-fastcharge.rules"; then
        sudo udevadm control --reload-rules 2>/dev/null || true
        # Same as above: the rule fires on the next add/change event, so
        # apply it now too and the tile works without a reboot.
        if sudo chgrp wheel "$CHARGE_TYPES_ATTR" && sudo chmod 0664 "$CHARGE_TYPES_ATTR"; then
            ok "charge_types is now writable by group wheel."
        else
            warn "Rule installed, but the live chgrp/chmod failed — it will take effect on the next boot."
        fi
    fi
else
    info "No battery offering a Fast charge_types here — skipping the fast-charge rule."
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
