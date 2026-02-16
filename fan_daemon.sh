#!/bin/sh

IDRAC_IP="192.168.1.242"
IDRAC_USER="root"
IDRAC_PASS="$(pass show idrac/root)"

LOW=40
MED=50
HIGH=60
HYST=2

PWM_LOW="0x14"    # 20%
PWM_MED="0x1E"    # 30%
PWM_HIGH="0x28"   # 40%

STATE_FILE="/root/fan_state"

get_max_cpu_temp() {
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        sdr type temperature \
        | grep '0Eh\|0Fh' \
        | awk -F'|' '{print $5}' \
        | sed 's/[^0-9]//g' \
        | sort -nr \
        | head -n1
}

MAX_TEMP=$(get_max_cpu_temp)

if [ -z "$MAX_TEMP" ]; then
    echo "ERROR: could not read CPU temps"
    exit 1
fi

# Load previous PWM state
if [ -f "$STATE_FILE" ]; then
    LAST_PWM=$(cat "$STATE_FILE")
else
    LAST_PWM="$PWM_LOW"
fi

TARGET_PWM="$LAST_PWM"

# Decision logic with hysteresis
if [ "$MAX_TEMP" -ge "$HIGH" ]; then
    echo "CPU temp ${MAX_TEMP}°C >= ${HIGH}°C → returning to Dell auto"
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

# Apply only if changed
if [ "$TARGET_PWM" != "$LAST_PWM" ]; then
    echo "CPU temp ${MAX_TEMP}°C → setting manual PWM $TARGET_PWM"

    # enable manual mode
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        raw 0x30 0x30 0x01 0x00

    # set fan speed
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" \
        raw 0x30 0x30 0x02 0xff $TARGET_PWM

    echo "$TARGET_PWM" > "$STATE_FILE"
else
    echo "CPU temp ${MAX_TEMP}°C → PWM unchanged ($TARGET_PWM)"
fi
