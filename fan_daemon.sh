#!/bin/sh

IDRAC_IP="192.xxx.x.xxx"
IDRAC_USER="root"
IDRAC_PASS="$(pass show idrac/root)"

# Define thresholds and PWM values
LOW=40
MED=50
HIGH=60
HYST=2   # degrees hysteresis buffer

PWM_LOW="0x14"   # 20%
PWM_MED="0x1E"   # 30%
PWM_HIGH="0x28"  # 40%

# File to store last applied PWM
STATE_FILE="/root/fan_state"

# Get max CPU temp from iDRAC sensors
get_max_cpu_temp() {
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        sdr type temperature \
        | grep -E '^Temp[[:space:]]+\| 0[EF]h' \
        | awk '{print $10}' \
        | sort -nr \
        | head -n1
}

MAX_TEMP=$(get_max_cpu_temp)
if [ -z "$MAX_TEMP" ]; then
    echo "ERROR: Could not read CPU temps"
    exit 1
fi

# Load last PWM (default to LOW)
if [ -f "$STATE_FILE" ]; then
    LAST_PWM=$(cat "$STATE_FILE")
else
    LAST_PWM="$PWM_LOW"
fi

# Determine target PWM with hysteresis
TARGET_PWM="$LAST_PWM"

if [ "$MAX_TEMP" -ge "$HIGH" ]; then
    # Above HIGH threshold → hand back to auto
    echo "CPU temp $MAX_TEMP°C >= $HIGH°C → returning to Dell auto"
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        raw 0x30 0x30 0x01 0x01
    exit 0
elif [ "$MAX_TEMP" -ge $(($MED + $HYST)) ]; then
    TARGET_PWM="$PWM_HIGH"
elif [ "$MAX_TEMP" -ge $(($LOW + $HYST)) ]; then
    TARGET_PWM="$PWM_MED"
elif [ "$MAX_TEMP" -le $(($LOW - $HYST)) ]; then
    TARGET_PWM="$PWM_LOW"
fi

# Only apply PWM if it changed
if [ "$TARGET_PWM" != "$LAST_PWM" ]; then
    echo "CPU temp $MAX_TEMP°C → setting manual PWM $TARGET_PWM"
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        raw 0x30 0x30 0x02 0xff $TARGET_PWM
    echo "$TARGET_PWM" > "$STATE_FILE"
else
    echo "CPU temp $MAX_TEMP°C → PWM unchanged ($TARGET_PWM)"
fi
