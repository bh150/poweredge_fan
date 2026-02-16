#!/bin/sh

# load credentials
. /root/.ipmi_credentials

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LOW=40
MED=50
HIGH=60
HYST=2

PWM_LOW="0x14"
PWM_MED="0x1E"
PWM_HIGH="0x28"

STATE_FILE="/root/fan_state"

get_max_cpu_temp() {
    ipmitool -I lanplus -H "$IPMI_IP" -U "$IPMI_USER" -P "$IPMI_PASS" \
        sdr type temperature | grep '0Eh\|0Fh' | awk -F'|' '{print $5}' | sed 's/[^0-9]//g' | sort -nr | head -n1
}

while true; do
    DEBUG_LINE="DEBUG: IP=$IPMI_IP USER=$IPMI_USER PASS=$IPMI_PASS"
    echo "$DEBUG_LINE"

    MAX_TEMP=$(get_max_cpu_temp)

    if [ -z "$MAX_TEMP" ]; then
        echo "ERROR: could not read CPU temps"
        sleep 10
        continue
    fi

    # Load previous PWM
    if [ -f "$STATE_FILE" ]; then
        LAST_PWM=$(cat "$STATE_FILE")
    else
        LAST_PWM="$PWM_LOW"
    fi

    TARGET_PWM="$LAST_PWM"

    # Hysteresis-based decision
    if [ "$MAX_TEMP" -ge "$HIGH" ]; then
        echo "CPU temp ${MAX_TEMP}°C >= ${HIGH}°C → returning to Dell auto"
        ipmitool -I lanplus -H "$IPMI_IP" -U "$IPMI_USER" -P "$IPMI_PASS" \
            raw 0x30 0x30 0x01 0x01
        sleep 10
        continue
    elif [ "$MAX_TEMP" -ge $(($MED + $HYST)) ]; then
        TARGET_PWM="$PWM_HIGH"
    elif [ "$MAX_TEMP" -ge $(($LOW + $HYST)) ]; then
        TARGET_PWM="$PWM_MED"
    elif [ "$MAX_TEMP" -le $(($LOW - $HYST)) ]; then
        TARGET_PWM="$PWM_LOW"
    fi

    if [ "$TARGET_PWM" != "$LAST_PWM" ]; then
        echo "CPU temp ${MAX_TEMP}°C → setting manual PWM $TARGET_PWM"

        # enable manual mode
        ipmitool -I lanplus -H "$IPMI_IP" -U "$IPMI_USER" -P "$IPMI_PASS" \
            raw 0x30 0x30 0x01 0x00

        # set fan speed
        ipmitool -I lanplus -H "$IPMI_IP" -U "$IPMI_USER" -P "$IPMI_PASS" \
            raw 0x30 0x30 0x02 0xff $TARGET_PWM

        echo "$TARGET_PWM" > "$STATE_FILE"
    else
        echo "CPU temp ${MAX_TEMP}°C → PWM unchanged ($TARGET_PWM)"
    fi

    # wait before checking again
    sleep 10
done
