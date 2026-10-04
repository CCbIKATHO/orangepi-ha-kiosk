#!/bin/bash
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-winner}"
CONF="/etc/orangepi-ha-kiosk.conf"
URL="${1:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./install.sh [HOME_ASSISTANT_URL]"
  exit 1
fi

if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  echo "User '$KIOSK_USER' does not exist."
  echo "Finish the Armbian first-login wizard and create user winner first."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  xserver-xorg xinit openbox firefox-esr x11-xserver-utils unclutter dbus-x11 ca-certificates

if [ -z "$URL" ] && [ -f "$CONF" ]; then
  URL="$(sed -n 's/^KIOSK_URL="\(.*\)"/\1/p' "$CONF" | head -n1)"
fi
URL="${URL:-http://192.168.55.1}"

cat > "$CONF" <<EOF
KIOSK_URL="$URL"
HDMI_OUTPUT="HDMI-1"
HDMI_MODE="1024x600"
ROTATION="right"
FRAMEBUFFER="600x1024"
DISABLE_OUTPUT="Composite-1"
EOF
chmod 644 "$CONF"

install -m 755 config/kiosk.sh /usr/local/bin/orangepi-ha-kiosk

HOME_DIR="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
install -d -o "$KIOSK_USER" -g "$KIOSK_USER" "$HOME_DIR/.config/openbox" "$HOME_DIR/.local/state"

cat > "$HOME_DIR/.xinitrc" <<'EOF'
#!/bin/sh
exec openbox-session
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.xinitrc"
chmod 755 "$HOME_DIR/.xinitrc"

cat > "$HOME_DIR/.config/openbox/autostart" <<'EOF'
/usr/local/bin/orangepi-ha-kiosk >> "$HOME/.local/state/orangepi-ha-kiosk.log" 2>&1 &
EOF
chown -R "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.config" "$HOME_DIR/.local"

# Start X automatically only on the local tty1 login.
START_MARKER='# orangepi-ha-kiosk'
touch "$HOME_DIR/.bash_profile"
if ! grep -Fq "$START_MARKER" "$HOME_DIR/.bash_profile"; then
cat >> "$HOME_DIR/.bash_profile" <<'EOF'

# orangepi-ha-kiosk
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx -- -nocursor
fi
EOF
fi
chown "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.bash_profile"

# systemd tty1 autologin override
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
Type=idle
EOF

systemctl daemon-reload
systemctl set-default multi-user.target

echo
echo "Installed Orange Pi HA kiosk."
echo "User: $KIOSK_USER"
echo "URL:  $URL"
echo "Reboot with: sudo reboot"
