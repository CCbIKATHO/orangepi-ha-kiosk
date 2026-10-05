#!/bin/bash
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-winner}"
APP_DIR="/opt/jk-display"
BMS_CONF="/etc/jk-display.conf"
KIOSK_CONF="/etc/jk-kiosk.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустіть від root: sudo ./install.sh"
    exit 1
fi

if ! id "$KIOSK_USER" >/dev/null 2>&1; then
    echo "Користувача '$KIOSK_USER' не знайдено."
    echo "Спочатку завершіть початкове налаштування Armbian і створіть користувача winner."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    xserver-xorg xinit openbox chromium x11-xserver-utils wmctrl \
    unclutter dbus-x11 ca-certificates \
    python3 python3-venv python3-dev build-essential libffi-dev pkg-config

install -d -m 755 "$APP_DIR"
install -m 644 "$SCRIPT_DIR/app/app.py" "$APP_DIR/app.py"
install -m 644 "$SCRIPT_DIR/app/index.html" "$APP_DIR/index.html"

if [ ! -d "$APP_DIR/venv" ]; then
    python3 -m venv "$APP_DIR/venv"
fi

"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install --upgrade aiohttp aioesphomeapi

if [ ! -f "$BMS_CONF" ]; then
    install -m 600 "$SCRIPT_DIR/config/jk-display.conf.example" "$BMS_CONF"
    echo
    echo "Створено $BMS_CONF."
    echo "Вкажіть IP та API key ваших WT32-ETH01 перед підключенням BMS."
else
    chmod 600 "$BMS_CONF"
    echo "Збережено наявний $BMS_CONF."
fi

install -m 644 "$SCRIPT_DIR/config/jk-display.service" /etc/systemd/system/jk-display.service
install -m 755 "$SCRIPT_DIR/config/kiosk.sh" /usr/local/bin/jk-dashboard-start

cat > "$KIOSK_CONF" <<'EOF'
KIOSK_URL="http://127.0.0.1:8080"
HDMI_OUTPUT="HDMI-1-1"
HDMI_MODE="1024x600"
ROTATION="right"
WINDOW_WIDTH="600"
WINDOW_HEIGHT="1024"
EOF
chmod 644 "$KIOSK_CONF"

install -d -o "$KIOSK_USER" -g "$KIOSK_USER" \
    "$HOME_DIR/.config/openbox" \
    "$HOME_DIR/.config/jk-chromium" \
    "$HOME_DIR/.local/state"

cat > "$HOME_DIR/.xinitrc" <<'EOF'
#!/bin/sh
exec openbox-session
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.xinitrc"
chmod 755 "$HOME_DIR/.xinitrc"

cat > "$HOME_DIR/.config/openbox/autostart" <<'EOF'
/usr/local/bin/jk-dashboard-start >> "$HOME/.local/state/jk-dashboard-start.log" 2>&1 &
EOF
chown -R "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.config" "$HOME_DIR/.local"

START_MARKER='# jk-bms-dashboard'
touch "$HOME_DIR/.bash_profile"
if ! grep -Fq "$START_MARKER" "$HOME_DIR/.bash_profile"; then
cat >> "$HOME_DIR/.bash_profile" <<'EOF'

# jk-bms-dashboard
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx -- -nocursor
fi
EOF
fi
chown "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.bash_profile"

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
Type=idle
EOF

mkdir -p /etc/chromium/policies/managed
cat > /etc/chromium/policies/managed/jk-kiosk.json <<'EOF'
{
  "TranslateEnabled": false
}
EOF

systemctl daemon-reload
systemctl enable --now jk-display.service
systemctl set-default multi-user.target

echo
echo "JK-BMS Dashboard встановлено."
echo "Користувач: $KIOSK_USER"
echo "Веб-інтерфейс: http://127.0.0.1:8080"
echo "BMS конфіг: $BMS_CONF"
echo
echo "Після налаштування BMS виконайте:"
echo "  sudo systemctl restart jk-display"
echo "  sudo reboot"
