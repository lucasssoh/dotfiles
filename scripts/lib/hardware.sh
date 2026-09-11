#!/usr/bin/env bash
# scripts/lib/hardware.sh — hardware detection → Fedora package set.
#
# Sourced by setup_fedora.sh (to actually install) and by
# scripts/hardware-detect.sh (to just report). Pure detection + a lookup
# table: this file never installs anything and never needs sudo.
#
# ── Why a table instead of `if intel; then ...` ──────────────────────────
# The packages a machine needs are driven by the CPU's *microarchitecture
# generation*, not by its marketing name: every Gen12+ Intel iGPU (Tiger
# Lake through Panther Lake and whatever follows) wants the same iHD VAAPI
# driver, thermald, and SOF audio firmware; every Zen wants the same
# nothing-extra (Mesa already ships the AMD VAAPI drivers on Fedora 44).
# So the table maps CPUID family/model → a *profile*, and profiles map to
# packages.
#
# ── Forward compatibility (the whole point) ─────────────────────────────
# A CPU released after this file was last edited must still be handled
# correctly, without an entry. Two rules do that:
#
#   Intel: family 6, model >= 0x8C (Tiger Lake, the first Xe iGPU) → the
#          modern profile. Intel model numbers only ever go up from there,
#          so Lunar Lake (0xBD), Arrow Lake (0xC5/0xC6), Panther Lake
#          (0xCC), Nova Lake (unassigned at time of writing) and every
#          later part land on it automatically.
#   AMD:   family >= 0x17 (Zen) → the Zen profile. Zen 6 (expected family
#          0x1B) and beyond land on it automatically.
#
# In both cases HW_CPU_KNOWN is set to "forward" rather than "yes", so the
# report can say "recognised by rule, not by name" instead of pretending
# it knows the codename. Adding a new codename below is then purely
# cosmetic — it never gates the packages.
#
# All parsing reads /proc/cpuinfo and /sys/class/dmi, never `lscpu`:
# lscpu's field labels are translated (this session runs fr_FR.UTF-8, where
# "CPU family" comes out as "Famille de processeur"), sysfs and procfs are
# not.

# ── Detected facts (populated by hw_detect) ─────────────────────────────
HW_CPU_VENDOR=""     # GenuineIntel | AuthenticAMD | <other>
HW_CPU_FAMILY=""     # decimal, from CPUID
HW_CPU_MODEL=""      # decimal, from CPUID
HW_CPU_NAME=""       # marketing string, e.g. "Intel(R) Core(TM) Ultra 5 135H"
HW_CPU_UARCH=""      # e.g. "Meteor Lake", "Zen 3+"
HW_CPU_PROFILE=""    # intel-modern | intel-legacy | amd-zen | amd-legacy | generic
HW_CPU_KNOWN=""      # yes (named entry) | forward (matched by rule) | no
HW_GPUS=()           # intel-igpu | intel-dgpu | amd-gpu | nvidia-dgpu
HW_IS_LAPTOP=""      # yes | no
HW_SYS_VENDOR=""     # e.g. "LENOVO", "ASUSTeK COMPUTER INC."
HW_PRODUCT=""        # e.g. "83DA" / "IdeaPad Slim 5 14IMH10"

# ── /proc/cpuinfo field reader ──────────────────────────────────────────
# Format is "key<tabs>: value". Trims both sides and stops at the first
# core's block — every core reports the same family/model.
_hw_cpuinfo() {
    LC_ALL=C awk -v key="$1" -F':' '
        {
            k = $1; sub(/[ \t]+$/, "", k)
            v = $2; sub(/^[ \t]+/, "", v)
            if (k == key) { print v; exit }
        }
    ' /proc/cpuinfo
}

# ── Intel: model number → "codename|profile" ────────────────────────────
# Model numbers are the ones in the kernel's arch/x86/include/asm/
# intel-family.h. Only the codename is looked up here; the profile for
# anything >= Tiger Lake is decided by the forward rule in
# _hw_classify_intel, so an unlisted new part still gets the right
# packages.
_hw_intel_codename() {
    case "$1" in
        # ── Gen12+ (Xe / Xe-LPG / Xe2 / Xe3) — the modern profile ──
        204)          echo "Panther Lake" ;;                   # 0xCC
        197|198|181)  echo "Arrow Lake" ;;                     # 0xC5 / 0xC6 / 0xB5
        189)          echo "Lunar Lake" ;;                     # 0xBD
        170|172)      echo "Meteor Lake" ;;                    # 0xAA / 0xAC
        183|186|191)  echo "Raptor Lake" ;;                    # 0xB7 / 0xBA / 0xBF
        151|154)      echo "Alder Lake" ;;                     # 0x97 / 0x9A
        190)          echo "Alder Lake-N / Twin Lake" ;;       # 0xBE
        140|141)      echo "Tiger Lake" ;;                     # 0x8C / 0x8D
        # ── Gen9–Gen11: older, but iHD still covers them ──
        167)          echo "Rocket Lake" ;;                     # 0xA7
        125|126)      echo "Ice Lake" ;;                        # 0x7D / 0x7E
        156)          echo "Jasper Lake" ;;                     # 0x9C
        150)          echo "Elkhart Lake" ;;                    # 0x96
        165|166)      echo "Comet Lake" ;;                      # 0xA5 / 0xA6
        142|158)      echo "Kaby Lake / Coffee Lake / Whiskey Lake" ;;  # 0x8E / 0x9E
        78|94)        echo "Skylake" ;;                         # 0x4E / 0x5E
        85)           echo "Skylake-SP / Cascade Lake" ;;        # 0x55
        # ── Gen8: the oldest generation iHD supports ──
        61|71|79|86)  echo "Broadwell" ;;                       # 0x3D / 0x47 / 0x4F / 0x56
        *)            echo "" ;;
    esac
}

# ── AMD: family → "codename|profile" ────────────────────────────────────
# AMD's family number alone carries the generation; the model only refines
# the marketing codename, which nothing downstream depends on.
_hw_amd_codename() {
    local family="$1" model="$2"
    case "$family" in
        26)  # 0x1A — Zen 5
            case "$model" in
                68)     echo "Zen 5 (Granite Ridge)" ;;   # 0x44
                32|36)  echo "Zen 5 (Strix Point)" ;;      # 0x20 / 0x24
                112)    echo "Zen 5 (Krackan Point)" ;;    # 0x70
                2)      echo "Zen 5 (Turin)" ;;            # 0x02
                *)      echo "Zen 5" ;;
            esac ;;
        25)  # 0x19 — Zen 3 / Zen 3+ / Zen 4
            case "$model" in
                0|1|8|33|80)        echo "Zen 3" ;;
                64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79)
                                    echo "Zen 3+ (Rembrandt)" ;;
                17|18|96|97|116|120|121)
                                    echo "Zen 4" ;;
                160|161|162|163|164|165|166|167)
                                    echo "Zen 4c (Bergamo)" ;;
                *)                  echo "Zen 3 / Zen 4" ;;
            esac ;;
        23)  # 0x17 — Zen / Zen+ / Zen 2
            case "$model" in
                1|17|32)            echo "Zen" ;;
                8|24)               echo "Zen+" ;;
                49|96|113|144|145|160)
                                    echo "Zen 2" ;;
                *)                  echo "Zen / Zen+ / Zen 2" ;;
            esac ;;
        *)   echo "" ;;
    esac
}

_hw_classify_intel() {
    local model="$1" name
    name="$(_hw_intel_codename "$model")"

    # Forward rule: Tiger Lake (0x8C = 140) is the first Xe iGPU and the
    # floor of the modern profile. Everything Intel ships after it has a
    # higher model number, so this one comparison covers unreleased parts.
    if [ "$model" -ge 140 ]; then
        HW_CPU_PROFILE="intel-modern"
        if [ -n "$name" ]; then
            HW_CPU_UARCH="$name"; HW_CPU_KNOWN="yes"
        else
            HW_CPU_UARCH="Intel Gen12+ (model $(printf '0x%02X' "$model"), unlisted)"
            HW_CPU_KNOWN="forward"
        fi
        return
    fi

    if [ -n "$name" ]; then
        # Named but pre-Tiger-Lake: Broadwell (Gen8) onwards is still iHD
        # territory, so it gets the same profile; only the pre-Broadwell
        # tail falls off it.
        HW_CPU_UARCH="$name"; HW_CPU_KNOWN="yes"
        HW_CPU_PROFILE="intel-modern"
        return
    fi

    HW_CPU_UARCH="Intel (model $(printf '0x%02X' "$model"), pre-Gen8 or unlisted)"
    HW_CPU_KNOWN="no"
    HW_CPU_PROFILE="intel-legacy"
}

_hw_classify_amd() {
    local family="$1" model="$2" name
    name="$(_hw_amd_codename "$family" "$model")"

    # Forward rule: family 0x17 (23) is Zen, and AMD has only gone up
    # since. Zen 6 is expected at 0x1B (27); it lands here with no edit.
    if [ "$family" -ge 23 ]; then
        HW_CPU_PROFILE="amd-zen"
        if [ -n "$name" ]; then
            HW_CPU_UARCH="$name"; HW_CPU_KNOWN="yes"
        else
            HW_CPU_UARCH="AMD Zen (family $(printf '0x%02X' "$family"), unlisted)"
            HW_CPU_KNOWN="forward"
        fi
        return
    fi

    HW_CPU_UARCH="AMD pre-Zen (family $(printf '0x%02X' "$family"))"
    HW_CPU_KNOWN="no"
    HW_CPU_PROFILE="amd-legacy"
}

# ── GPU discovery ───────────────────────────────────────────────────────
# PCI classes 0300 (VGA), 0302 (3D controller — how a laptop's discrete GPU
# shows up in a hybrid setup) and 0380 (Display controller). One lspci call
# PER class, not one call with three -d flags: lspci honours only the LAST
# -d given and warns "Multiple -d options are given, only the last one has
# effect" on stderr, silently narrowing the search to 0380 (found the hard
# way -- it reported "no GPU" on a machine with two).
#
# Vendor only, no iGPU/dGPU split: Intel now brands integrated graphics
# "Arc" too (Lunar Lake reports "Intel Arc Graphics 130V"), so the device
# string can't separate them, and nothing downstream needs it -- an Arc
# dGPU and an Intel iGPU want exactly the same packages.
_hw_detect_gpus() {
    HW_GPUS=()
    command -v lspci >/dev/null 2>&1 || return 0

    local class line
    for class in 0300 0302 0380; do
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in
                *"Intel Corporation"*)               _hw_add_gpu "intel-gpu" ;;
                *NVIDIA*)                            _hw_add_gpu "nvidia-dgpu" ;;
                *"Advanced Micro Devices"*|*"ATI "*) _hw_add_gpu "amd-gpu" ;;
            esac
        done < <(LC_ALL=C lspci -mm -d "::$class" 2>/dev/null)
    done
}

_hw_add_gpu() {
    local g
    for g in ${HW_GPUS[@]+"${HW_GPUS[@]}"}; do
        [ "$g" = "$1" ] && return 0
    done
    HW_GPUS+=("$1")
}

# ── Chassis / vendor, from sysfs (no dmidecode, no sudo) ────────────────
# SMBIOS chassis types: 8 portable, 9 laptop, 10 notebook, 11 hand-held,
# 14 sub-notebook, 30 tablet, 31 convertible, 32 detachable.
_hw_detect_chassis() {
    local dmi=/sys/class/dmi/id ctype=""
    HW_SYS_VENDOR="$(cat "$dmi/sys_vendor" 2>/dev/null || echo "unknown")"
    HW_PRODUCT="$(cat "$dmi/product_name" 2>/dev/null || echo "unknown")"
    ctype="$(cat "$dmi/chassis_type" 2>/dev/null || echo "")"
    case "$ctype" in
        8|9|10|11|14|30|31|32) HW_IS_LAPTOP="yes" ;;
        *)                     HW_IS_LAPTOP="no"  ;;
    esac
}

# hw_detect — populates every HW_* global above. Idempotent, cheap, no
# network and no sudo. Safe to call more than once.
hw_detect() {
    HW_CPU_VENDOR="$(_hw_cpuinfo vendor_id)"
    HW_CPU_FAMILY="$(_hw_cpuinfo 'cpu family')"
    HW_CPU_MODEL="$(_hw_cpuinfo model)"
    HW_CPU_NAME="$(_hw_cpuinfo 'model name')"

    # A non-numeric family/model means something very unusual (a VM hiding
    # CPUID, a non-x86 port): fall through to the generic profile rather
    # than letting the arithmetic comparisons below blow up under `set -e`.
    if ! [[ "$HW_CPU_FAMILY" =~ ^[0-9]+$ && "$HW_CPU_MODEL" =~ ^[0-9]+$ ]]; then
        HW_CPU_UARCH="unknown"; HW_CPU_KNOWN="no"; HW_CPU_PROFILE="generic"
    else
        case "$HW_CPU_VENDOR" in
            GenuineIntel)
                # Family 6 is every modern Intel core. Family 15 is the
                # NetBurst/Pentium-4 era and family 19 is the upcoming
                # split; both are handled generically.
                if [ "$HW_CPU_FAMILY" -eq 6 ]; then
                    _hw_classify_intel "$HW_CPU_MODEL"
                else
                    HW_CPU_UARCH="Intel (family $HW_CPU_FAMILY)"
                    HW_CPU_KNOWN="no"; HW_CPU_PROFILE="intel-legacy"
                fi ;;
            AuthenticAMD)
                _hw_classify_amd "$HW_CPU_FAMILY" "$HW_CPU_MODEL" ;;
            *)
                HW_CPU_UARCH="${HW_CPU_VENDOR:-unknown}"
                HW_CPU_KNOWN="no"; HW_CPU_PROFILE="generic" ;;
        esac
    fi

    _hw_detect_gpus
    _hw_detect_chassis
}

# ── Profile → packages ──────────────────────────────────────────────────
# Every name below was verified against Fedora 44's own repos with
# `dnf repoquery` — none of them need RPM Fusion. Two traps worth keeping
# in mind if this list is ever edited:
#
#   * The iHD VAAPI driver is `libva-intel-media-driver` on Fedora, NOT
#     `intel-media-driver` (which is the upstream/Arch name and does not
#     resolve here).
#   * `intel_gpu_top` ships in `igt-gpu-tools`, not `intel-gpu-tools`.
#
# There is deliberately no `mesa-va-drivers` / `mesa-vdpau-drivers`: as of
# Fedora 44 / Mesa 26 those were folded into `mesa-dri-drivers` (verified:
# it owns /usr/lib64/dri/radeonsi_drv_video.so), which setup_fedora.sh
# already installs for everyone.

# Needed on every machine regardless of CPU.
_HW_PKGS_COMMON=(
    # SOF audio firmware. Modern Intel (cAVS, Skylake onwards) and modern
    # AMD APUs (ACP) both route their analog audio through it — without
    # this package those laptops boot with NO sound at all, which is the
    # single most common "fresh minimal Fedora" failure.
    alsa-sof-firmware
    # Backs `powerprofilesctl`, which the Roue power-profile wheel calls
    # (waybar/scripts/performance.sh). Used to arrive only as a side
    # effect of the KDE module.
    power-profiles-daemon
    # Diagnostics: `vainfo` is how you check the VAAPI driver above
    # actually loaded, `vulkaninfo` likewise for Vulkan.
    libva-utils vulkan-tools
    # Firmware updates (laptop BIOS / Thunderbolt / dock) via LVFS.
    fwupd
    # Inventory + sensors, used by the bar and by this very script's
    # GPU detection.
    pciutils usbutils lm_sensors dmidecode
)

# Intel Gen8 (Broadwell) and newer.
_HW_PKGS_INTEL_MODERN=(
    libva-intel-media-driver   # iHD: hardware video decode/encode
    intel-vpl-gpu-rt           # oneVPL runtime, Gen12+ encode paths
    igt-gpu-tools              # intel_gpu_top
    thermald                   # Intel thermal daemon — real gains on thin laptops
)

# Pre-Broadwell Intel: no VAAPI driver is packaged on Fedora 44 any more
# (the old i965 `libva-intel-driver` is gone), so this is thermald only.
_HW_PKGS_INTEL_LEGACY=(
    thermald
)

# Any Zen. VAAPI is already covered by mesa-dri-drivers.
_HW_PKGS_AMD_ZEN=(
    radeontop
)

_HW_PKGS_AMD_LEGACY=(
    radeontop
)

_HW_PKGS_GENERIC=()

# hw_packages — echoes the Fedora package list for the detected machine,
# one per line, deduplicated. Calls hw_detect if it hasn't run yet.
hw_packages() {
    [ -n "$HW_CPU_PROFILE" ] || hw_detect

    local pkgs=("${_HW_PKGS_COMMON[@]}")

    case "$HW_CPU_PROFILE" in
        intel-modern) pkgs+=("${_HW_PKGS_INTEL_MODERN[@]}") ;;
        intel-legacy) pkgs+=("${_HW_PKGS_INTEL_LEGACY[@]}") ;;
        amd-zen)      pkgs+=("${_HW_PKGS_AMD_ZEN[@]}") ;;
        amd-legacy)   pkgs+=("${_HW_PKGS_AMD_LEGACY[@]}") ;;
        generic)      pkgs+=(${_HW_PKGS_GENERIC[@]+"${_HW_PKGS_GENERIC[@]}"}) ;;
    esac

    # A GPU can want packages the CPU profile didn't pull in -- an Arc
    # dGPU in an AMD machine, or a Radeon dGPU in an Intel one. Redundant
    # when the GPU is just the CPU's own iGPU; `sort -u` below absorbs it.
    local gpu
    for gpu in ${HW_GPUS[@]+"${HW_GPUS[@]}"}; do
        case "$gpu" in
            intel-gpu) pkgs+=("${_HW_PKGS_INTEL_MODERN[@]}") ;;
            amd-gpu)   pkgs+=("${_HW_PKGS_AMD_ZEN[@]}") ;;
            # nvidia-dgpu is deliberately absent: see hw_notes.
        esac
    done

    printf '%s\n' "${pkgs[@]}" | LC_ALL=C sort -u
}

# hw_notes — advisory lines for things that must NOT be automated: driver
# stacks that need a third-party repo and a reboot, or vendor quirks worth
# knowing about but not worth acting on blindly. One note per line.
hw_notes() {
    [ -n "$HW_CPU_PROFILE" ] || hw_detect
    local gpu

    for gpu in ${HW_GPUS[@]+"${HW_GPUS[@]}"}; do
        case "$gpu" in
            nvidia-dgpu)
                echo "NVIDIA dGPU detected — the proprietary driver is NOT installed automatically (it needs RPM Fusion, a kmod rebuild and a reboot, and it can leave the machine unbootable under Secure Boot). To install it yourself:"
                echo "    sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm"
                echo "    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda"
                ;;
        esac
    done

    if [ "$HW_CPU_PROFILE" = "intel-modern" ] && [ "$HW_IS_LAPTOP" = "yes" ]; then
        echo "Intel laptop: if the brightness keys do nothing (common on OLED panels, which use DPCD backlight rather than the PWM one the kernel assumes by default), add this kernel parameter and reboot:"
        echo "    sudo grubby --update-kernel=ALL --args=\"i915.enable_dpcd_backlight=1\""
    fi

    if [ "$HW_CPU_PROFILE" = "intel-legacy" ]; then
        echo "Pre-Gen8 Intel graphics: Fedora 44 no longer packages a VAAPI driver for it (the old i965 libva-intel-driver was dropped), so hardware video decode will not be available. mpv's hwdec=auto falls back to software on its own."
    fi

    case "$HW_SYS_VENDOR" in
        *LENOVO*|*Lenovo*)
            echo "Lenovo: battery charge limiting (conservation mode, caps at ~60% to spare the cell when mostly plugged in) is exposed by the in-tree ideapad_laptop driver. Check and toggle with:"
            echo "    cat /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode"
            echo "    echo 1 | sudo tee /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode"
            ;;
    esac

    if [ "$HW_CPU_KNOWN" = "forward" ]; then
        echo "This CPU has no named entry in scripts/lib/hardware.sh — it was matched by the forward-compatibility rule, so the package set is right, only the codename is missing. Adding it to _hw_intel_codename/_hw_amd_codename is cosmetic."
    fi
}

# hw_report — human-readable summary, for `hardware-detect.sh --report`
# and for the banner setup_fedora.sh prints before installing.
hw_report() {
    [ -n "$HW_CPU_PROFILE" ] || hw_detect

    local known_label
    case "$HW_CPU_KNOWN" in
        yes)     known_label="recognised" ;;
        forward) known_label="matched by forward rule (no named entry)" ;;
        *)       known_label="unrecognised — generic fallback" ;;
    esac

    printf '  CPU          %s\n' "${HW_CPU_NAME:-unknown}"
    printf '  CPUID        vendor=%s family=%s (0x%02X) model=%s (0x%02X)\n' \
        "${HW_CPU_VENDOR:-?}" "${HW_CPU_FAMILY:-?}" "${HW_CPU_FAMILY:-0}" \
        "${HW_CPU_MODEL:-?}" "${HW_CPU_MODEL:-0}"
    printf '  Generation   %s (%s)\n' "${HW_CPU_UARCH:-unknown}" "$known_label"
    printf '  Profile      %s\n' "${HW_CPU_PROFILE:-generic}"
    printf '  GPU          %s\n' "${HW_GPUS[*]:-none detected}"
    printf '  Machine      %s %s (%s)\n' "$HW_SYS_VENDOR" "$HW_PRODUCT" \
        "$([ "$HW_IS_LAPTOP" = yes ] && echo laptop || echo desktop)"
}
