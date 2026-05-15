#!/usr/bin/env bash

FAN_PATH=$(find /sys/class/hwmon/hwmon*/fan1_input 2>/dev/null | head -n 1)

if [ -f "$FAN_PATH" ]; then
    RPM=$(cat "$FAN_PATH")

    formatted_rpm=$(printf "%4d" "$RPM")
    echo "󰈐 ${formatted_rpm} RPM"
else
    echo "󰈐 N/A"
fi
