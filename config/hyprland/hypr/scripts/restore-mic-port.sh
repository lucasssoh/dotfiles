#!/usr/bin/env bash
set -euo pipefail

# restore-mic-port.sh — forces the front combo jack's active input port to
# the headset mic on every login.
#
# The "Ryzen HD Audio Controller" analog-stereo source is a single pactl
# Source object with two mutually exclusive Ports: analog-input-internal-
# mic (priority 8900) and analog-input-headset-mic (priority 8800, see
# `pactl list sources`). Neither reports jack-sensing ("availability
# unknown" on both), so wireplumber/alsa-card-profile never auto-switches
# between them when a headset is plugged in -- it just activates the
# higher-priority port (internal mic) every time the profile comes up,
# i.e. on every boot. Symptom that led here: people on a call reported
# hearing nothing when tapping the headset mic -- the OS was still
# listening to the laptop's own internal mic instead.
#
# Not solvable from the audio-input roue wheel / rofi picker (audio.sh):
# those switch between *devices* (pactl set-default-source), not between
# *ports* of the same device -- this is the one place that calls
# `pactl set-source-port`.
#
# Small retry loop, not a bare one-shot call: this runs from Hyprland's
# exec-once block, which can fire before pipewire-pulse has finished
# enumerating ALSA cards on a cold login.
PORT="analog-input-headset-mic"

# Generic discovery instead of a fixed PCI-address source name: any
# alsa_input.*.analog-stereo source that exposes BOTH
# analog-input-internal-mic and analog-input-headset-mic ports is the same
# "combo jack without jack-sensing" signature described above, regardless
# of which sound card/PCI address it lives on. If no source matches the
# machine simply doesn't have this quirk -- the retry loop below then finds
# nothing and exits without effect, same as before.
find_combo_jack_source() {
    pactl list sources 2>/dev/null | awk '
        /^Source #/ { name=""; has_internal=0; has_headset=0 }
        /^[[:space:]]*Name:/ { name=$2 }
        /analog-input-internal-mic/ { has_internal=1 }
        /analog-input-headset-mic/ { has_headset=1 }
        name ~ /^alsa_input\..*\.analog-stereo$/ && has_internal && has_headset {
            print name; exit
        }
    '
}

for _ in $(seq 1 20); do
    SOURCE="$(find_combo_jack_source)"
    if [ -n "$SOURCE" ]; then
        pactl set-source-port "$SOURCE" "$PORT" 2>/dev/null || true
        exit 0
    fi
    sleep 0.5
done
