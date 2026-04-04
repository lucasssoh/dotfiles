#!/usr/bin/env bash
# ============================================================
# DETECT-TEMP.SH — Find the right CPU temperature sensor
# Run once after install to configure Waybar's temperature module
# ============================================================

echo "[INFO] Temperature sensors found on this system:"
echo ""

for hwmon in /sys/class/hwmon/hwmon*/; do
    NAME_FILE="$hwmon/name"
    [ -f "$NAME_FILE" ] || continue
    NAME=$(cat "$NAME_FILE")
    echo "  [$NAME] → $hwmon"
    for temp in "$hwmon"temp*_input; do
        [ -f "$temp" ] || continue
        VAL=$(cat "$temp")
        CELSIUS=$(( VAL / 1000 ))
        LABEL_FILE="${temp/_input/_label}"
        LABEL=""
        [ -f "$LABEL_FILE" ] && LABEL=" ($(cat "$LABEL_FILE"))"
        echo "    $(basename $temp)$LABEL → ${CELSIUS}°C"
    done
done

echo ""
echo "[INFO] Recommended path for Waybar:"
echo "       Look for a sensor named 'coretemp' (Intel) or 'k10temp'/'zenpower' (AMD)"
echo "       then set the full path in ~/.config/waybar/config"
echo ""
echo "       Intel example:"
echo '       "hwmon-path": "/sys/class/hwmon/hwmon2/temp1_input"'
echo ""
echo "       AMD example:"
echo '       "hwmon-path": "/sys/class/hwmon/hwmon1/temp1_input"'
echo ""
echo "[INFO] Alternatively, leave Waybar to auto-detect by keeping"
echo "       only 'critical-threshold' in the temperature module config."
