#!/bin/bash

set -e

SERVICE_NAME="battalert.service"
SCRIPT_TARGET="/usr/local/bin/battalert.sh"
SERVICE_TARGET="/etc/systemd/system/battalert.service"
CONFIG_TARGET="/etc/default/battalert"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash uninstall.sh"
    exit 1
fi

if systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | grep -Fxq "$SERVICE_NAME"; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
fi

rm -f "$SCRIPT_TARGET"
rm -f "$SERVICE_TARGET"

systemctl daemon-reload

read -r -p "Remove config file ${CONFIG_TARGET}? (y/N): " REMOVE_CONFIG
case "$REMOVE_CONFIG" in
    y|Y|yes|YES)
        rm -f "$CONFIG_TARGET"
        echo "Config removed: $CONFIG_TARGET"
        ;;
    *)
        echo "Config kept: $CONFIG_TARGET"
        ;;
esac

echo "BattAlert uninstalled."
echo "Check service status: systemctl status ${SERVICE_NAME}"
