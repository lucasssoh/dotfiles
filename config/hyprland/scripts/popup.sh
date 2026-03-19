#!/usr/bin/env bash
APP="$1"
CLASS="$2"

if hyprctl clients | grep -q "class: $CLASS"; then
    hyprctl dispatch closewindow "class:$CLASS"
else
    wezterm start \
        --class "$CLASS" \
        --always-new-process \
        -- $APP
fi