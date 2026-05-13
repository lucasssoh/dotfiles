#!/usr/bin/env bash
# rofi-launcher.sh

RASI="$HOME/.config/rofi/theme.rasi"

rofi -show drun \
     -i \
     -p "Launch" \
     -theme "$RASI"
