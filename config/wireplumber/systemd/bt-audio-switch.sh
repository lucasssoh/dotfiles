#!/usr/bin/env bash
BT_MAC="38_D5_18_97_68_63"
CARD="bluez_card.${BT_MAC}"

switch_profile() {
    local profile=$1
    local current
    current=$(pactl list cards | grep -A2 "bluez_card" | grep "Profil actif" | awk '{print $NF}')
    [ "$current" != "$profile" ] && pactl set-card-profile "$CARD" "$profile" && echo "[bt-switch] -> $profile"
}

declare -A capture_ids

pw-dump --monitor --no-colors 2>/dev/null | while IFS= read -r line; do
    # Detect a new ID
    if [[ "$line" =~ ^[[:space:]]*\"id\":[[:space:]]*([0-9]+) ]]; then
        current_id="${BASH_REMATCH[1]}"
    fi

    # If this block contains Stream/Input/Audio (not Internal)
    if [[ "$line" =~ \"Stream/Input/Audio\" ]] && [[ ! "$line" =~ Internal ]]; then
        capture_ids[$current_id]=1
        switch_profile "headset-head-unit"
    fi

    # If a known ID receives "info": null → stream ended
    if [[ "$line" =~ \"info\":[[:space:]]*null ]] && [[ -n "${capture_ids[$current_id]}" ]]; then
        unset "capture_ids[$current_id]"
        if [ "${#capture_ids[@]}" -eq 0 ]; then
            switch_profile "a2dp-sink"
        fi
    fi
done
