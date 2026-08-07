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
SOURCE="alsa_input.pci-0000_36_00.6.analog-stereo"
PORT="analog-input-headset-mic"

for _ in $(seq 1 20); do
    if pactl list short sources 2>/dev/null | grep -q "$SOURCE"; then
        pactl set-source-port "$SOURCE" "$PORT" 2>/dev/null || true
        exit 0
    fi
    sleep 0.5
done
