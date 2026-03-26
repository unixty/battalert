#!/bin/bash
# ------------------------------------------------------------------
# Battery monitoring: notifications + sound on charge thresholds.
# Repeats notification every REPEAT_INTERVAL seconds until charger
# state changes. Status is checked every 2 seconds in active alert
# mode and every 60 seconds in normal mode.
# ------------------------------------------------------------------

LOWER=40
UPPER=80
LANG_CODE="en"
LOGFILE="/tmp/battalert.log"
CONFIG_FILE="/etc/default/battalert"

# Notification repeat interval (seconds)
REPEAT_INTERVAL=30

# Polling intervals (seconds)
SLEEP_NORMAL=60    # normal mode
SLEEP_ALERT=2      # active threshold mode - waiting for charger state change

SOUND_HIGH="/usr/share/sounds/freedesktop/stereo/power-unplug.oga"
SOUND_LOW="/usr/share/sounds/freedesktop/stereo/power-plug.oga"

NOTIFY_ID_HIGH=9901
NOTIFY_ID_LOW=9902

NOTIFIED_UPPER=0
NOTIFIED_LOWER=0
LAST_NOTIFY_TIME=0

TITLE_HIGH_FMT=""
BODY_HIGH_FMT=""
TITLE_LOW_FMT=""
BODY_LOW_FMT=""
LOG_STATUS_CHANGED=""

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi

    LOWER="${LOWER:-40}"
    UPPER="${UPPER:-80}"
    LANG_CODE="${LANG_CODE:-en}"

    if ! [[ "$LOWER" =~ ^[0-9]+$ ]]; then
        LOWER=40
    fi

    if ! [[ "$UPPER" =~ ^[0-9]+$ ]]; then
        UPPER=80
    fi

    if [ "$LOWER" -ge "$UPPER" ]; then
        LOWER=40
        UPPER=80
    fi

    case "$LANG_CODE" in
        en|ru) ;;
        *) LANG_CODE="en" ;;
    esac
}

set_language_strings() {
    if [ "$LANG_CODE" = "ru" ]; then
        TITLE_HIGH_FMT="🔋 Батарея %s%% — ОТКЛЮЧИ ЗАРЯДКУ"
        BODY_HIGH_FMT="Верхний порог %s%% достигнут. Отключи кабель!"
        TITLE_LOW_FMT="🪫 Батарея %s%% — ПОДКЛЮЧИ ЗАРЯДКУ"
        BODY_LOW_FMT="Нижний порог %s%% достигнут. Подключи кабель!"
        LOG_STATUS_CHANGED="Status changed, notification closed"
    else
        TITLE_HIGH_FMT="🔋 Battery %s%% — UNPLUG CHARGER"
        BODY_HIGH_FMT="Upper threshold %s%% reached. Unplug the cable!"
        TITLE_LOW_FMT="🪫 Battery %s%% — PLUG IN CHARGER"
        BODY_LOW_FMT="Lower threshold %s%% reached. Plug in the cable!"
        LOG_STATUS_CHANGED="Status changed, notification closed"
    fi
}

get_user_env() {
    ACTIVE_USER=$(who | awk 'NR==1{print $1}')
    USER_ID=$(id -u "$ACTIVE_USER" 2>/dev/null)
    DBUS_ADDR="unix:path=/run/user/${USER_ID}/bus"
    XDG_DIR="/run/user/${USER_ID}"
    PULSE_SERVER="unix:${XDG_DIR}/pulse/native"
}

is_on_ac_power() {
    local SUPPLY
    for SUPPLY in /sys/class/power_supply/*; do
        [ -d "$SUPPLY" ] || continue

        if [ -f "$SUPPLY/type" ] && [ -f "$SUPPLY/online" ]; then
            local TYPE
            TYPE=$(cat "$SUPPLY/type" 2>/dev/null)

            if [ "$TYPE" = "Mains" ] || [ "$TYPE" = "USB" ]; then
                if [ "$(cat "$SUPPLY/online" 2>/dev/null)" = "1" ]; then
                    return 0
                fi
            fi
        fi
    done

    return 1
}

send_notification() {
    local TITLE="$1"
    local BODY="$2"
    local URGENCY="$3"
    local NOTIFY_ID="$4"
    local SOUND="$5"

    sudo -u "$ACTIVE_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        notify-send \
            --urgency="$URGENCY" \
            --expire-time=0 \
            --replace-id="$NOTIFY_ID" \
            "$TITLE" "$BODY"

    if [ -f "$SOUND" ]; then
        sudo -u "$ACTIVE_USER" \
            XDG_RUNTIME_DIR="$XDG_DIR" \
            PULSE_SERVER="$PULSE_SERVER" \
            paplay "$SOUND" &
    fi

    LAST_NOTIFY_TIME=$(date +%s)
    echo "$(date) - $TITLE | $BODY" >> "$LOGFILE"
}

close_notification() {
    sudo -u "$ACTIVE_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        gdbus call \
            --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification \
            "$1" 2>/dev/null

    # Fallback method: replace notification with empty one for 1ms
    sudo -u "$ACTIVE_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        notify-send \
            --replace-id="$1" \
            --expire-time=1 \
            " " " " 2>/dev/null
}

should_repeat() {
    local NOW
    NOW=$(date +%s)
    local ELAPSED=$(( NOW - LAST_NOTIFY_TIME ))
    [ "$ELAPSED" -ge "$REPEAT_INTERVAL" ]
}

load_config
set_language_strings

# --- Main loop ---
while true; do
    get_user_env

    LEVEL=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null \
         || cat /sys/class/power_supply/CMB0/capacity 2>/dev/null \
         || acpi -b | grep -oP '[0-9]+(?=%)' | head -1)

    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null \
          || cat /sys/class/power_supply/CMB0/status 2>/dev/null)

    ON_AC=0
    if is_on_ac_power; then
        ON_AC=1
    fi

    if [[ "$LEVEL" =~ ^[0-9]+$ ]]; then

        # --- Upper threshold ---
        if [ "$LEVEL" -ge "$UPPER" ] && { [ "$STATUS" = "Charging" ] || [ "$STATUS" = "Full" ] || [ "$ON_AC" -eq 1 ]; }; then
            if [ "$NOTIFIED_UPPER" -eq 0 ] || should_repeat; then
                printf -v title_high "$TITLE_HIGH_FMT" "$LEVEL"
                printf -v body_high "$BODY_HIGH_FMT" "$UPPER"
                send_notification \
                    "$title_high" \
                    "$body_high" \
                    "critical" \
                    "$NOTIFY_ID_HIGH" \
                    "$SOUND_HIGH"
                NOTIFIED_UPPER=1
                NOTIFIED_LOWER=0
            fi
            sleep "$SLEEP_ALERT"
            continue

        # --- Lower threshold ---
        elif [ "$LEVEL" -le "$LOWER" ] && [ "$STATUS" = "Discharging" ]; then
            if [ "$NOTIFIED_LOWER" -eq 0 ] || should_repeat; then
                printf -v title_low "$TITLE_LOW_FMT" "$LEVEL"
                printf -v body_low "$BODY_LOW_FMT" "$LOWER"
                send_notification \
                    "$title_low" \
                    "$body_low" \
                    "critical" \
                    "$NOTIFY_ID_LOW" \
                    "$SOUND_LOW"
                NOTIFIED_LOWER=1
                NOTIFIED_UPPER=0
            fi
            sleep "$SLEEP_ALERT"
            continue

        # --- Status changed ---
        else
            if [ "$NOTIFIED_UPPER" -eq 1 ] || [ "$NOTIFIED_LOWER" -eq 1 ]; then
                close_notification "$NOTIFY_ID_HIGH"
                close_notification "$NOTIFY_ID_LOW"
                NOTIFIED_UPPER=0
                NOTIFIED_LOWER=0
                LAST_NOTIFY_TIME=0
                echo "$(date) - $LOG_STATUS_CHANGED" >> "$LOGFILE"
            fi
        fi
    fi

    sleep "$SLEEP_NORMAL"
done
