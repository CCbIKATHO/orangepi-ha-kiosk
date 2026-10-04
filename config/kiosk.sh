#!/bin/bash
set -u

CONF="/etc/orangepi-ha-kiosk.conf"
[ -r "$CONF" ] && . "$CONF"

KIOSK_URL="${KIOSK_URL:-http://192.168.55.1}"
HDMI_OUTPUT="${HDMI_OUTPUT:-HDMI-1}"
HDMI_MODE="${HDMI_MODE:-1024x600}"
ROTATION="${ROTATION:-right}"
FRAMEBUFFER="${FRAMEBUFFER:-600x1024}"
DISABLE_OUTPUT="${DISABLE_OUTPUT:-Composite-1}"

# Give X a moment to enumerate outputs.
sleep 2

xrandr --output "$HDMI_OUTPUT" \
  --mode "$HDMI_MODE" \
  --rotate "$ROTATION" \
  --primary \
  --fb "$FRAMEBUFFER" \
  --output "$DISABLE_OUTPUT" --off

xset s off
xset -dpms
xset s noblank

unclutter -idle 0.5 -root &

# Keep Firefox alive. If it exits, restart it after a short delay.
while true; do
  firefox-esr --kiosk "$KIOSK_URL"
  echo "$(date -Is) Firefox exited; restarting in 2 seconds"
  sleep 2
done
