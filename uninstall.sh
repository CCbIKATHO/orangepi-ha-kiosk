#!/bin/bash
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-winner}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустіть від root: sudo ./uninstall.sh"
    exit 1
fi

HOME_DIR="$(getent passwd "$KIOSK_USER" | cut -d: -f6 || true)"

systemctl disable --now jk-display.service 2>/dev/null || true
systemctl disable --now jk-power-monitor.service 2>/dev/null || true

rm -f /etc/systemd/system/jk-display.service
rm -f /etc/systemd/system/jk-power-monitor.service
rm -f /usr/local/bin/jk-dashboard-start
rm -f /etc/jk-kiosk.conf
rm -f /etc/chromium/policies/managed/jk-kiosk.json
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true

if [ -n "$HOME_DIR" ]; then
    rm -f "$HOME_DIR/.xinitrc"
    rm -f "$HOME_DIR/.config/openbox/autostart"
    if [ -f "$HOME_DIR/.bash_profile" ]; then
        sed -i '/# jk-bms-dashboard/,+3d' "$HOME_DIR/.bash_profile"
    fi
fi

systemctl daemon-reload

echo "Автозапуск JK-BMS Dashboard видалено."
echo "Дані /opt/jk-display та /etc/jk-display.conf залишено навмисно."
echo "Рекомендовано перезавантажити Orange Pi."
