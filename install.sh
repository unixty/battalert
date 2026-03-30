#!/bin/bash

set -e

SCRIPT_SOURCE="$(dirname "$0")/battalert.sh"
SERVICE_SOURCE="$(dirname "$0")/battalert.service"

SCRIPT_TARGET="/usr/local/bin/battalert.sh"
SERVICE_TARGET="/etc/systemd/system/battalert.service"
CONFIG_TARGET="/etc/default/battalert"

DEFAULT_LOWER=40
DEFAULT_UPPER=80
DEFAULT_LANG="en"
DEFAULT_VOLUME=80
DEFAULT_INHIBIT_SLEEP_ON_AC=1
DEFAULT_BOOST_SYSTEM_VOLUME_ON_ALERT=0

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash install.sh"
    exit 1
fi

if [ ! -f "$SCRIPT_SOURCE" ] || [ ! -f "$SERVICE_SOURCE" ]; then
    echo "Error: battalert.sh or battalert.service not found next to install.sh"
    exit 1
fi

REQUIRED_BINS=(systemctl notify-send gdbus systemd-inhibit sudo)
for BIN in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$BIN" >/dev/null 2>&1; then
        echo "Error: required dependency '$BIN' is not installed"
        exit 1
    fi
done

if command -v pw-cat >/dev/null 2>&1; then
    SOUND_BIN="pw-cat"
else
    echo "Error: required dependency 'pw-cat' is not installed"
    echo "Install package: pipewire-audio-client-libraries, pipewire-bin, or pipewire"
    exit 1
fi

if ! command -v acpi >/dev/null 2>&1; then
    echo "Warning: 'acpi' is not installed; fallback battery detection may be limited"
fi

echo "Using sound player: $SOUND_BIN"

read -r -p "Lower threshold percent [${DEFAULT_LOWER}]: " INPUT_LOWER
LOWER="${INPUT_LOWER:-$DEFAULT_LOWER}"

read -r -p "Upper threshold percent [${DEFAULT_UPPER}]: " INPUT_UPPER
UPPER="${INPUT_UPPER:-$DEFAULT_UPPER}"

read -r -p "Language (en/ru) [${DEFAULT_LANG}]: " INPUT_LANG
LANG_CODE="${INPUT_LANG:-$DEFAULT_LANG}"

read -r -p "Inhibit sleep while charging? (1=yes, 0=no) [${DEFAULT_INHIBIT_SLEEP_ON_AC}]: " INPUT_INHIBIT_SLEEP_ON_AC
INHIBIT_SLEEP_ON_AC="${INPUT_INHIBIT_SLEEP_ON_AC:-$DEFAULT_INHIBIT_SLEEP_ON_AC}"

read -r -p "Temporarily boost system volume for alert? (1=yes, 0=no) [${DEFAULT_BOOST_SYSTEM_VOLUME_ON_ALERT}]: " INPUT_BOOST_SYSTEM_VOLUME_ON_ALERT
BOOST_SYSTEM_VOLUME_ON_ALERT="${INPUT_BOOST_SYSTEM_VOLUME_ON_ALERT:-$DEFAULT_BOOST_SYSTEM_VOLUME_ON_ALERT}"

if [ "$BOOST_SYSTEM_VOLUME_ON_ALERT" -eq 1 ]; then
    read -r -p "Alert target volume percent (0-100) [${DEFAULT_VOLUME}]: " INPUT_VOLUME
    VOLUME="${INPUT_VOLUME:-$DEFAULT_VOLUME}"
else
    VOLUME="$DEFAULT_VOLUME"
fi

if ! [[ "$LOWER" =~ ^[0-9]+$ ]]; then
    echo "Error: lower threshold must be a number"
    exit 1
fi

if ! [[ "$UPPER" =~ ^[0-9]+$ ]]; then
    echo "Error: upper threshold must be a number"
    exit 1
fi

if [ "$LOWER" -lt 1 ] || [ "$LOWER" -gt 99 ]; then
    echo "Error: lower threshold must be between 1 and 99"
    exit 1
fi

if [ "$UPPER" -lt 1 ] || [ "$UPPER" -gt 99 ]; then
    echo "Error: upper threshold must be between 1 and 99"
    exit 1
fi

if [ "$LOWER" -ge "$UPPER" ]; then
    echo "Error: lower threshold must be less than upper threshold"
    exit 1
fi

case "$LANG_CODE" in
    en|ru) ;;
    *)
        echo "Error: language must be en or ru"
        exit 1
        ;;
esac

if ! [[ "$VOLUME" =~ ^[0-9]+$ ]]; then
    echo "Error: volume must be a number"
    exit 1
fi

if [ "$VOLUME" -lt 0 ] || [ "$VOLUME" -gt 100 ]; then
    echo "Error: volume must be between 0 and 100"
    exit 1
fi

case "$INHIBIT_SLEEP_ON_AC" in
    0|1) ;;
    *)
        echo "Error: inhibit sleep value must be 0 or 1"
        exit 1
        ;;
esac

case "$BOOST_SYSTEM_VOLUME_ON_ALERT" in
    0|1) ;;
    *)
        echo "Error: boost system volume value must be 0 or 1"
        exit 1
        ;;
esac

if [ "$BOOST_SYSTEM_VOLUME_ON_ALERT" -eq 1 ] && ! command -v wpctl >/dev/null 2>&1; then
    echo "Error: 'wpctl' is required when temporary system volume boost is enabled"
    exit 1
fi

install -m 0755 "$SCRIPT_SOURCE" "$SCRIPT_TARGET"
install -m 0644 "$SERVICE_SOURCE" "$SERVICE_TARGET"

cat > "$CONFIG_TARGET" <<EOF
LOWER=$LOWER
UPPER=$UPPER
LANG_CODE="$LANG_CODE"
VOLUME=$VOLUME
INHIBIT_SLEEP_ON_AC=$INHIBIT_SLEEP_ON_AC
BOOST_SYSTEM_VOLUME_ON_ALERT=$BOOST_SYSTEM_VOLUME_ON_ALERT
EOF

systemctl daemon-reload
systemctl enable battalert.service
systemctl restart battalert.service

echo "Installed successfully."
echo "Config: LOWER=$LOWER, UPPER=$UPPER, LANG_CODE=$LANG_CODE, VOLUME=$VOLUME, INHIBIT_SLEEP_ON_AC=$INHIBIT_SLEEP_ON_AC, BOOST_SYSTEM_VOLUME_ON_ALERT=$BOOST_SYSTEM_VOLUME_ON_ALERT"
echo "Service status: systemctl status battalert.service"
