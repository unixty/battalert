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
VOLUME=70
INHIBIT_SLEEP_ON_AC=1
BOOST_SYSTEM_VOLUME_ON_ALERT=0
LOGFILE="/tmp/battalert.log"
CONFIG_FILE="/etc/default/battalert"
INHIBIT_PID=""
PW_CAT_BIN=""
WPCTL_BIN=""

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
    VOLUME="${VOLUME:-70}"
    INHIBIT_SLEEP_ON_AC="${INHIBIT_SLEEP_ON_AC:-1}"
    BOOST_SYSTEM_VOLUME_ON_ALERT="${BOOST_SYSTEM_VOLUME_ON_ALERT:-0}"

    if ! [[ "$LOWER" =~ ^[0-9]+$ ]]; then
        LOWER=40
    fi

    if ! [[ "$UPPER" =~ ^[0-9]+$ ]]; then
        UPPER=80
    fi

    if ! [[ "$VOLUME" =~ ^[0-9]+$ ]]; then
        VOLUME=70
    fi

    if [ "$VOLUME" -lt 0 ] || [ "$VOLUME" -gt 100 ]; then
        VOLUME=70
    fi

    case "$INHIBIT_SLEEP_ON_AC" in
        0|1) ;;
        *) INHIBIT_SLEEP_ON_AC=1 ;;
    esac

    case "$BOOST_SYSTEM_VOLUME_ON_ALERT" in
        0|1) ;;
        *) BOOST_SYSTEM_VOLUME_ON_ALERT=0 ;;
    esac

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

            # Consider any non-battery power supply with online=1 as AC power.
            if [ "$TYPE" != "Battery" ]; then
                if [ "$(cat "$SUPPLY/online" 2>/dev/null)" = "1" ]; then
                    return 0
                fi
            fi
        fi
    done

    return 1
}

start_sleep_inhibit() {
    if [ "$INHIBIT_SLEEP_ON_AC" -ne 1 ]; then
        return
    fi

    if [ -n "$INHIBIT_PID" ] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
        return
    fi

    systemd-inhibit \
        --what=sleep \
        --mode=block \
        --why="Battalert: AC power connected" \
        sleep infinity &
    INHIBIT_PID=$!
}

stop_sleep_inhibit() {
    if [ -n "$INHIBIT_PID" ] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
        kill "$INHIBIT_PID" 2>/dev/null || true
        wait "$INHIBIT_PID" 2>/dev/null || true
    fi
    INHIBIT_PID=""
}

resolve_pw_cat() {
    if command -v pw-cat >/dev/null 2>&1; then
        PW_CAT_BIN="pw-cat"
    else
        PW_CAT_BIN=""
    fi
}

resolve_wpctl() {
    if command -v wpctl >/dev/null 2>&1; then
        WPCTL_BIN="wpctl"
    else
        WPCTL_BIN=""
    fi
}

get_default_sink_volume() {
    sudo -u "$ACTIVE_USER" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        "$WPCTL_BIN" get-volume @DEFAULT_AUDIO_SINK@ 2>>"$LOGFILE"
}

compare_float_lt() {
    awk -v left="$1" -v right="$2" 'BEGIN { exit !(left < right) }'
}

set_default_sink_volume() {
    sudo -u "$ACTIVE_USER" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        "$WPCTL_BIN" set-volume @DEFAULT_AUDIO_SINK@ "$1" 2>>"$LOGFILE"
}

set_default_sink_mute() {
    sudo -u "$ACTIVE_USER" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        "$WPCTL_BIN" set-mute @DEFAULT_AUDIO_SINK@ "$1" 2>>"$LOGFILE"
}

play_sound() {
    local SOUND="$1"
    local TARGET_SYSTEM_VOLUME
    local PW_CAT_VOLUME="1"
    local ORIGINAL_VOLUME_OUTPUT
    local ORIGINAL_VOLUME
    local ORIGINAL_MUTED
    local SHOULD_RESTORE=0

    if [ ! -f "$SOUND" ]; then
        return
    fi

    if [ -z "$PW_CAT_BIN" ]; then
        echo "$(date) - pw-cat not found; sound notification skipped" >> "$LOGFILE"
        return
    fi

    TARGET_SYSTEM_VOLUME=$(awk "BEGIN { printf \"%.2f\", $VOLUME / 100 }")

    if [ "$BOOST_SYSTEM_VOLUME_ON_ALERT" -eq 1 ] && [ -n "$WPCTL_BIN" ]; then
        ORIGINAL_VOLUME_OUTPUT=$(get_default_sink_volume)
        ORIGINAL_VOLUME=$(printf '%s\n' "$ORIGINAL_VOLUME_OUTPUT" | awk '/Volume:/ { print $2 }')
        ORIGINAL_MUTED=0

        if printf '%s\n' "$ORIGINAL_VOLUME_OUTPUT" | grep -q '\[MUTED\]'; then
            ORIGINAL_MUTED=1
        fi

        if [ "$ORIGINAL_MUTED" -eq 1 ]; then
            set_default_sink_mute 0
            SHOULD_RESTORE=1
        fi

        if [ -z "$ORIGINAL_VOLUME" ] || compare_float_lt "$ORIGINAL_VOLUME" "$TARGET_SYSTEM_VOLUME"; then
            set_default_sink_volume "$TARGET_SYSTEM_VOLUME"
            SHOULD_RESTORE=1
        fi

        sudo -u "$ACTIVE_USER" \
            XDG_RUNTIME_DIR="$XDG_DIR" \
            PIPEWIRE_RUNTIME_DIR="$XDG_DIR" \
            "$PW_CAT_BIN" --playback --volume="$PW_CAT_VOLUME" "$SOUND" \
            2>>"$LOGFILE"

        if [ "$SHOULD_RESTORE" -eq 1 ]; then
            if [ -n "$ORIGINAL_VOLUME" ]; then
                set_default_sink_volume "$ORIGINAL_VOLUME"
            fi
            set_default_sink_mute "$ORIGINAL_MUTED"
        fi
    else
        sudo -u "$ACTIVE_USER" \
            XDG_RUNTIME_DIR="$XDG_DIR" \
            PIPEWIRE_RUNTIME_DIR="$XDG_DIR" \
            "$PW_CAT_BIN" --playback --volume="$PW_CAT_VOLUME" "$SOUND" \
            2>>"$LOGFILE" &
    fi
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
            "$TITLE" "$BODY" \
            >>"$LOGFILE" 2>&1 \
        || echo "$(date) - notify-send failed for notification id $NOTIFY_ID" >> "$LOGFILE"

    play_sound "$SOUND"

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
            "$1" \
            >>"$LOGFILE" 2>&1 \
        || echo "$(date) - CloseNotification failed for notification id $1" >> "$LOGFILE"

    # Fallback method: replace notification with empty one for 1ms
    sudo -u "$ACTIVE_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        XDG_RUNTIME_DIR="$XDG_DIR" \
        notify-send \
            --replace-id="$1" \
            --expire-time=1 \
            " " " " \
            >>"$LOGFILE" 2>&1 \
        || echo "$(date) - notify-send fallback failed for notification id $1" >> "$LOGFILE"
}

should_repeat() {
    local NOW
    NOW=$(date +%s)
    local ELAPSED=$(( NOW - LAST_NOTIFY_TIME ))
    [ "$ELAPSED" -ge "$REPEAT_INTERVAL" ]
}

cleanup() {
    stop_sleep_inhibit
}

trap cleanup EXIT INT TERM

load_config
set_language_strings
resolve_pw_cat
resolve_wpctl

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

    if [ "$ON_AC" -eq 1 ]; then
        start_sleep_inhibit
    else
        stop_sleep_inhibit
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
