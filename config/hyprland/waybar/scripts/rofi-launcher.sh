#!/usr/bin/env bash
# rofi-launcher.sh — ouvre le lanceur d'applications Rofi (mode drun)

RASI="$HOME/.config/rofi/theme.rasi"

rofi -show drun \
     -i \
     -p "Launch" \
     -theme "$RASI"
