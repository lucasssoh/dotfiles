#!/usr/bin/env bash
set -euo pipefail

# pactl translates its labels according to locale (e.g. "Name"/"Description"
# in French) -- forcing C locale here for stable parsing, independent of
# the system language.
export LC_ALL=C

# =========================================================
# audio.sh — audio device picker (replaces wiremix)
#
#   audio.sh output   -> rofi menu, choose the default output device
#   audio.sh input     -> rofi menu, choose the default input device
#   audio.sh roue-gen  -> regenerates ~/.config/roue/wheels/audio-output.toml
#                          (one sector per sink, `active = true` on the
#                          current default), right before the wheel opens
#                          -- same principle as display-layout.sh roue-gen
#                          / performance.sh roue-gen. Output only: no
#                          input wheel, the rofi menu above still covers
#                          that (see AudioOutput.qml / AudioInput.qml for
#                          the two different click handlers).
#
# pactl backend (pipewire-pulse). Volume/mute stay handled elsewhere
# (wpctl via keyboard shortcuts and clicking the module); this script
# ONLY picks the default device. All user-facing strings in English, like
# every other roue wheel/notification in the repo (display-layout.sh,
# performance.sh, hdr.sh...) -- this file used to be the one exception,
# in French.
# =========================================================

RASI="$HOME/.config/rofi/theme.rasi"

icon_for() {
    local desc="$1"
    case "$desc" in
        *[Hh]eadset*|*[Hh]eadphone*|*[Ee]arbuds*) printf '󰋋' ;;
        *HDMI*|*DisplayPort*)                     printf '󰡁' ;;
        *[Mm]icrophone*|*[Mm]ic*)                  printf '󰍬' ;;
        *)                                          printf '󰓃' ;;
    esac
}

# Roue-only classification (icon_for above still drives the rofi menu's
# Nerd Font glyphs, untouched): resolves a device's (description, bus,
# form-factor, active-port-type) tuple -- see build_rows -- to a roue icon
# file (roue/icons/, Lucide SVGs -- see roue-src/src/icons.rs). Two
# independent axes, not just "what kind of transducer": bluetooth vs wired
# changes the icon too (headphones-bluetooth.svg / volume-2-bluetooth.svg,
# a headphones/speaker glyph with a small bluetooth badge -- see those
# files), so e.g. wired headphones and a bluetooth headset don't render
# identically. Headphone detection prefers the PipeWire-reported port type
# ("Headphones"/"Headset", from the sink's *currently active* port -- a
# combo jack reports "Speaker" or "Headphones" depending on what's plugged
# in right now) or device.form_factor, falling back to the description
# regex only when neither PipeWire property is present (e.g. HDMI/pro
# multichannel sinks expose no Ports section at all).
icon_svg_for() {
    local desc="$1" bus="$2" formfactor="$3" porttype="$4"
    local is_bt=0 is_headphone=0

    [[ "$bus" == "bluetooth" ]] && is_bt=1

    case "$porttype" in Headphones|Headset) is_headphone=1 ;; esac
    case "$formfactor" in headphone|headset) is_headphone=1 ;; esac
    if [[ "$is_headphone" == 0 && -z "$porttype" && -z "$formfactor" ]]; then
        case "$desc" in
            *[Hh]eadset*|*[Hh]eadphone*|*[Ee]arbuds*) is_headphone=1 ;;
        esac
    fi

    case "$desc" in
        *HDMI*|*DisplayPort*) printf 'monitor.svg'; return ;;
    esac

    if [[ "$is_headphone" == 1 && "$is_bt" == 1 ]]; then
        printf 'headphones-bluetooth.svg'
    elif [[ "$is_headphone" == 1 ]]; then
        printf 'headphones.svg'
    elif [[ "$is_bt" == 1 ]]; then
        printf 'volume-2-bluetooth.svg'
    else
        printf 'volume-2.svg'
    fi
}

declare -A NAME_OF        # row shown in rofi -> pactl device name
declare -A DESC_OF         # row shown in rofi -> plain description (roue-gen
                            # needs this back verbatim; re-deriving it from
                            # the row via byte-offset stripping would be
                            # unreliable under LC_ALL=C, where multi-byte
                            # glyphs from icon_for aren't single characters)
declare -A BUS_OF           # row -> device.bus ("bluetooth", "pci", "usb"...)
declare -A FORMFACTOR_OF    # row -> device.form_factor ("headphone",
                             # "speaker"... not always present)
declare -A PORTTYPE_OF      # row -> type of the sink's *active* port
                             # ("Headphones", "Speaker"... absent for sinks
                             # with no Ports section, e.g. HDMI/pro outputs)
ROWS=()
DEFAULT_NAME=""             # pactl device name currently default, set by
                             # build_rows

# One `pactl list <kind>` parsed in a single awk pass -- one block per
# device (Sink #N / Source #N), reset on each new marker -- rather than
# the old approach of re-grepping the WHOLE listing once per device name
# (O(n^2) for no reason). Emits name/description/bus/form-factor/active-
# port-type as one line per device, fields separated by \x1f (ASCII Unit
# Separator) rather than a tab: bash's `read` treats tab as "IFS
# whitespace" and silently collapses runs of it -- including a lone tab
# between two OTHER tabs, i.e. an empty field -- even when IFS is set to
# *just* tab (confirmed live: a sink with no device.form_factor reporting
# "pci\t\tSpeaker" for bus/formfactor/porttype came back through `read` as
# bus=pci formfactor=Speaker porttype=<empty>, silently shifted left by
# one). \x1f is never IFS-whitespace, so empty fields survive. `device.bus`
# and `device.form_factor` live in the Properties section (`key =
# "value"` lines); the active port's type lives in the Ports section
# (`portkey: label (type: Type, ...)`), resolved via the later `Active
# Port: portkey` line -- Ports always comes before Active Port in pactl's
# output, hence buffering type_of[] and resolving it only once Active
# Port is seen.
device_props() {
    local pactl_kind="$1"
    # US (not OFS) carries the \x1f join: OFS itself must stay the awk
    # default (space) -- the Description handler below rebuilds $0 via
    # `$1=""; ...; desc=$0` to strip the label while keeping the rest of
    # the line, and THAT rebuild joins with OFS too. Overriding OFS to
    # \x1f (tried first) silently turned every space inside the
    # description into a field separator instead.
    pactl list "$pactl_kind" | awk -v US=$'\x1f' '
        function flush() {
            if (name != "") {
                printf "%s%s%s%s%s%s%s%s%s\n", name, US, desc, US, bus, US, formfactor, US, porttype
            }
            name=""; desc=""; bus=""; formfactor=""; porttype=""; active_port=""; in_ports=0
            delete type_of
        }
        /^Sink #/ || /^Source #/ { flush(); next }
        $1=="Name:"        { name=$2; next }
        $1=="Description:" { $1=""; sub(/^ /,""); desc=$0; next }
        /^\tProperties:/   { in_ports=0; next }
        /^\tPorts:/        { in_ports=1; next }
        in_ports && /\(type: / {
            key=$1; sub(/:$/,"",key)
            match($0, /\(type: [A-Za-z-]+/)
            type_of[key]=substr($0, RSTART+7, RLENGTH-7)
            next
        }
        $1=="Active" && $2=="Port:"        { active_port=$3; porttype=type_of[active_port]; next }
        /^\t\tdevice\.bus = /          { gsub(/"/,"",$3); bus=$3; next }
        /^\t\tdevice\.form_factor = / { gsub(/"/,"",$3); formfactor=$3; next }
        END { flush() }
    '
}

# Fills ROWS/NAME_OF/DESC_OF/BUS_OF/FORMFACTOR_OF/PORTTYPE_OF/DEFAULT_NAME
# as global variables instead of returning a result via $(...): see
# wifi.sh for why (a subshell would lose the associative arrays populated
# inside it).
build_rows() {
    local pactl_kind="$1" default_cmd="$2" kind="$3"
    ROWS=()
    NAME_OF=()
    DESC_OF=()
    BUS_OF=()
    FORMFACTOR_OF=()
    PORTTYPE_OF=()

    local name desc bus formfactor porttype mark row
    DEFAULT_NAME=$(pactl "$default_cmd")

    while IFS=$'\x1f' read -r name desc bus formfactor porttype; do
        [[ -z "$name" ]] && continue
        # ".monitor" sources are the loopback of each audio output, not real
        # mics -- without this filter they'd clutter the input picker.
        [[ "$kind" == "input" && "$name" == *.monitor ]] && continue
        [[ -z "$desc" ]] && desc="$name"

        mark="  "
        [[ "$name" == "$DEFAULT_NAME" ]] && mark=" "

        row="${mark}$(icon_for "$desc")  ${desc}"
        ROWS+=("$row")
        NAME_OF["$row"]="$name"
        DESC_OF["$row"]="$desc"
        BUS_OF["$row"]="$bus"
        FORMFACTOR_OF["$row"]="$formfactor"
        PORTTYPE_OF["$row"]="$porttype"
    done < <(device_props "$pactl_kind")
}

cmd_menu() {
    local kind="$1" pactl_kind default_cmd set_cmd title
    case "$kind" in
        output)
            pactl_kind="sinks"; default_cmd="get-default-sink"
            set_cmd="set-default-sink"; title="Audio output"
            ;;
        input)
            pactl_kind="sources"; default_cmd="get-default-source"
            set_cmd="set-default-source"; title="Audio input"
            ;;
    esac

    build_rows "$pactl_kind" "$default_cmd" "$kind"

    if [[ ${#ROWS[@]} -eq 0 ]]; then
        notify-send "$title" "No device detected"
        exit 0
    fi

    local choice name
    choice=$(printf '%s\n' "${ROWS[@]}" \
        | rofi -dmenu -theme "$RASI" -mesg "$title" -no-custom -format s -i)

    [[ -z "$choice" ]] && exit 0

    name="${NAME_OF[$choice]:-}"
    if [[ -n "$name" ]]; then
        if pactl "$set_cmd" "$name" >/dev/null 2>&1; then
            notify-send "$title" "Default device changed"
        else
            notify-send "$title" "Failed to change device"
        fi
    fi
}

# The state (which sink is default) comes from pipewire-pulse, not a file
# frozen in the repo -- so this TOML has no versioned static copy, it gets
# rewritten on every trigger, like wheels/display.toml (see
# display-layout.sh::cmd_roue_gen) and wheels/powerprofile.toml (see
# performance.sh::cmd_roue_gen). `active = true` on the current default
# sink's sector shows the state band on the wheel (see roue-src/src/wheel.rs).
# Each sector's action calls pactl directly (no wrapper subcommand needed
# here, same as powerprofile.toml's `powerprofilesctl set ...`).
cmd_roue_gen() {
    build_rows "sinks" "get-default-sink" "output"

    if [[ ${#ROWS[@]} -eq 0 ]]; then
        notify-send "Audio output" "No device detected"
        exit 1
    fi

    local dir="$HOME/.config/roue/wheels"
    mkdir -p "$dir"

    {
        echo 'title = "Audio output"'
        local row name desc icon esc active
        for row in "${ROWS[@]}"; do
            name="${NAME_OF[$row]}"
            desc="${DESC_OF[$row]}"
            icon=$(icon_svg_for "$desc" "${BUS_OF[$row]}" "${FORMFACTOR_OF[$row]}" "${PORTTYPE_OF[$row]}")
            # Minimal TOML escaping -- descriptions come from PipeWire/ALSA
            # metadata, never user input, but a literal quote would still
            # break parsing without this (see display-layout.sh roue-gen).
            esc="${desc//\"/\\\"}"
            active=""
            [[ "$name" == "$DEFAULT_NAME" ]] && active="active = true"

            printf '\n[[segment]]\nicon = "%s"\nlabel = "%s"\naction = "pactl set-default-sink '\''%s'\''"\n%s\n' \
                "$icon" "$esc" "$name" "$active"
        done
    } > "$dir/audio-output.toml"
}

case "${1:-output}" in
    output|input) cmd_menu "$1" ;;
    roue-gen)      cmd_roue_gen ;;
    *)             echo "usage: $0 {output|input|roue-gen}" >&2; exit 1 ;;
esac
