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

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash install.sh"
    exit 1
fi

if [ ! -f "$SCRIPT_SOURCE" ] || [ ! -f "$SERVICE_SOURCE" ]; then
    echo "Error: battalert.sh or battalert.service not found next to install.sh"
    exit 1
fi

read -r -p "Lower threshold percent [${DEFAULT_LOWER}]: " INPUT_LOWER
LOWER="${INPUT_LOWER:-$DEFAULT_LOWER}"

read -r -p "Upper threshold percent [${DEFAULT_UPPER}]: " INPUT_UPPER
UPPER="${INPUT_UPPER:-$DEFAULT_UPPER}"

read -r -p "Language (en/ru) [${DEFAULT_LANG}]: " INPUT_LANG
LANG_CODE="${INPUT_LANG:-$DEFAULT_LANG}"

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

install -m 0755 "$SCRIPT_SOURCE" "$SCRIPT_TARGET"
install -m 0644 "$SERVICE_SOURCE" "$SERVICE_TARGET"

cat > "$CONFIG_TARGET" <<EOF
LOWER=$LOWER
UPPER=$UPPER
LANG_CODE="$LANG_CODE"
EOF

systemctl daemon-reload
systemctl enable battalert.service
systemctl restart battalert.service

echo "Installed successfully."
echo "Config: LOWER=$LOWER, UPPER=$UPPER, LANG_CODE=$LANG_CODE"
echo "Service status: systemctl status battalert.service"
