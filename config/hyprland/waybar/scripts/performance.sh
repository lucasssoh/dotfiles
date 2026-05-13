#!/bin/bash
ARG=$(powerprofilesctl get)
case $ARG in
    performance) ICON="󰓅" ;;
    balanced)    ICON="󰾅" ;;
    power-saver) ICON="󰾆" ;;
esac
echo "{\"text\": \"$ICON\", \"tooltip\": \"Mode: $ARG\"}"
