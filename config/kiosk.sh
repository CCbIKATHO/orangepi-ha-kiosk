#!/bin/bash
set -u

CONF="/etc/jk-kiosk.conf"
[ -r "$CONF" ] && . "$CONF"

KIOSK_URL="${KIOSK_URL:-http://127.0.0.1:8080}"
HDMI_OUTPUT="${HDMI_OUTPUT:-HDMI-1-1}"
HDMI_MODE="${HDMI_MODE:-1024x600}"
ROTATION="${ROTATION:-right}"
WINDOW_WIDTH="${WINDOW_WIDTH:-600}"
WINDOW_HEIGHT="${WINDOW_HEIGHT:-1024}"
BROWSER_RESTART_SECONDS="${BROWSER_RESTART_SECONDS:-3600}"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

cd "$HOME" || exit 1
mkdir -p "$HOME/.local/state" "$HOME/.config/jk-chromium"

for _ in $(seq 1 60); do
    if xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

xrandr \
  --output "$HDMI_OUTPUT" \
  --mode "$HDMI_MODE" \
  --rotate "$ROTATION" \
  --pos 0x0 \
  --primary \
  --fb "${WINDOW_WIDTH}x${WINDOW_HEIGHT}" \
  2>/dev/null || \
xrandr \
  --output "$HDMI_OUTPUT" \
  --mode "$HDMI_MODE" \
  --rotate "$ROTATION" \
  --pos 0x0 \
  --primary

xset s off
xset -dpms
xset s noblank

pkill -u "$USER" -f '[u]nclutter' 2>/dev/null || true
unclutter -idle 0.5 -root >/dev/null 2>&1 &

while true; do
    chromium \
      --app="$KIOSK_URL" \
      --window-position=0,0 \
      --window-size="${WINDOW_WIDTH},${WINDOW_HEIGHT}" \
      --no-first-run \
      --disable-gpu \
      --disable-gpu-compositing \
      --disable-background-networking \
      --disable-component-update \
      --disable-sync \
      --ozone-platform=x11 \
      --disable-session-crashed-bubble \
      --disable-features=Translate,TranslateUI \
      --user-data-dir="$HOME/.config/jk-chromium" \
      >>"$HOME/.local/state/jk-chromium.log" 2>&1 &

    CHROMIUM_PID=$!
    CHROMIUM_STARTED="$(date +%s)"

    while kill -0 "$CHROMIUM_PID" 2>/dev/null; do
        NOW="$(date +%s)"
        if [ "$BROWSER_RESTART_SECONDS" -gt 0 ] &&
           [ $((NOW - CHROMIUM_STARTED)) -ge "$BROWSER_RESTART_SECONDS" ]; then
            echo "$(date -Is) Плановий перезапуск Chromium після ${BROWSER_RESTART_SECONDS} с" \
              >>"$HOME/.local/state/jk-chromium.log"
            kill "$CHROMIUM_PID" 2>/dev/null || true
            break
        fi
        WIN="$(
          wmctrl -lx 2>/dev/null |
          awk 'tolower($3) ~ /chromium/ {print $1; exit}'
        )"

        if [ -n "$WIN" ]; then
            wmctrl -ir "$WIN" -b remove,fullscreen,maximized_vert,maximized_horz
            wmctrl -ir "$WIN" -e "0,0,0,${WINDOW_WIDTH},${WINDOW_HEIGHT}"
        fi

        sleep 1
    done

    wait "$CHROMIUM_PID" 2>/dev/null || true
    echo "$(date -Is) Chromium зупинився, перезапуск через 2 секунди" \
      >>"$HOME/.local/state/jk-chromium.log"
    sleep 2
done
