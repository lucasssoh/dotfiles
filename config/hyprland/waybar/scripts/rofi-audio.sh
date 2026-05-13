#!/usr/bin/env bash
# rofi-audio.sh — Contrôle audio via pactl/wpctl avec rofi

RASI="$HOME/.config/rofi/theme.rasi"

# --- Détection backend audio ---
if command -v wpctl &>/dev/null; then
    BACKEND="pipewire"
elif command -v pactl &>/dev/null; then
    BACKEND="pulseaudio"
else
    notify-send "rofi-audio" "Aucun backend audio (wpctl/pactl)"
    exit 1
fi

# --- Helpers ---
_get_volume() {
    if [[ "$BACKEND" == "pipewire" ]]; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null \
            | awk '{printf "%d", $2 * 100}'
    else
        pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
            | grep -oP '\d+(?=%)' | head -1
    fi
}

_is_muted() {
    if [[ "$BACKEND" == "pipewire" ]]; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q "MUTED"
    else
        pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q "yes"
    fi
}

_set_volume() {
    local vol="$1"
    if [[ "$BACKEND" == "pipewire" ]]; then
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "${vol}%"
    else
        pactl set-sink-volume @DEFAULT_SINK@ "${vol}%"
    fi
}

_toggle_mute() {
    if [[ "$BACKEND" == "pipewire" ]]; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    else
        pactl set-sink-mute @DEFAULT_SINK@ toggle
    fi
}

# --- Sinks disponibles ---
_list_sinks() {
    if [[ "$BACKEND" == "pipewire" ]]; then
        wpctl status 2>/dev/null | awk '/Audio/,/Video/' \
            | grep "Sinks" -A 20 \
            | grep -E "^\s+[0-9]" \
            | sed 's/^\s*//' \
            | awk '{
                active = ($1 == "*") ? " ●" : ""
                # retire le * en début si présent
                sub(/^\* /, "")
                id = $1
                sub(/^[0-9]+\. /, "")
                name = $0
                printf "󰓃  %s%s|%s\n", name, active, id
              }'
    else
        pactl list sinks 2>/dev/null | awk '
            /^Sink #/       { id=substr($2,2) }
            /Name:/         { name=$2 }
            /Active Port:/  { port=$3 }
            /State:/        { if ($2=="RUNNING") active=" ●"; else active="" }
            /Description:/  {
                desc=substr($0, index($0,$2))
                printf "󰓃  %s%s|%s\n", desc, active, id
            }'
    fi
}

_set_default_sink() {
    local id="$1"
    if [[ "$BACKEND" == "pipewire" ]]; then
        wpctl set-default "$id"
    else
        pactl set-default-sink "$id"
    fi
}

# --- Volume courant ---
VOL=$(_get_volume)
_is_muted && MUTE_LABEL="󰕾  Activer le son (muet)" || MUTE_LABEL="󰖁  Muet"

# --- Options de volume ---
VOL_OPTIONS=$(printf \
    "󰕿  10%%\n󰕿  20%%\n󰖀  30%%\n󰖀  40%%\n󰖀  50%%\n󰕾  60%%\n󰕾  70%%\n󰕾  80%%\n󰕾  90%%\n󰕾  100%%")

# --- Sinks ---
SINKS_RAW=$(_list_sinks)
SINKS_DISPLAY=$(echo "$SINKS_RAW" | cut -d'|' -f1)

MENU=$(printf "󰒩  Volume actuel : %s%%\n%s\n── Sorties ──\n%s\n── Volume ──\n%s" \
    "$VOL" "$MUTE_LABEL" "$SINKS_DISPLAY" "$VOL_OPTIONS")

CHOICE=$(echo "$MENU" | rofi -dmenu -i \
    -p "󰕾  Audio" \
    -theme "$RASI" \
    -no-custom \
    -selected-row 1)

[[ -z "$CHOICE" ]] && exit 0

case "$CHOICE" in
    *"Muet"*|*"Activer le son"*)
        _toggle_mute
        ;;
    *"Volume actuel"*|"── "*)
        # headers, rien
        ;;
    *"%"*)
        # Lignes de volume : extraire le nombre
        PCT=$(echo "$CHOICE" | grep -oP '\d+(?=%)' | head -1)
        [[ -n "$PCT" ]] && _set_volume "$PCT" && \
            notify-send "Audio" "Volume : ${PCT}%"
        ;;
    *)
        # Sink sélectionné
        SINK_ID=$(echo "$SINKS_RAW" | grep -F "${CHOICE%% ●}" | head -1 | cut -d'|' -f2)
        [[ -n "$SINK_ID" ]] && _set_default_sink "$SINK_ID" && \
            notify-send "Audio" "Sortie changée"
        ;;
esac
