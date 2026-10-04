#!/bin/bash
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-winner}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./uninstall.sh"
  exit 1
fi

HOME_DIR="$(getent passwd "$KIOSK_USER" | cut -d: -f6 || true)"

rm -f /usr/local/bin/orangepi-ha-kiosk
rm -f /etc/orangepi-ha-kiosk.conf
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true

if [ -n "$HOME_DIR" ]; then
  rm -f "$HOME_DIR/.xinitrc"
  rm -f "$HOME_DIR/.config/openbox/autostart"
  if [ -f "$HOME_DIR/.bash_profile" ]; then
    sed -i '/# orangepi-ha-kiosk/,+3d' "$HOME_DIR/.bash_profile"
  fi
fi

systemctl daemon-reload
echo "Kiosk startup configuration removed. Reboot recommended."
