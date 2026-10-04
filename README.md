# Orange Pi Home Assistant Kiosk

Minimal Firefox kiosk for **Orange Pi PC Plus** running **Armbian / Debian 13 (Trixie)**.

Default display setup is tailored for a 1024x600 HDMI panel mounted vertically:

- HDMI mode: 1024x600
- rotation: right
- framebuffer: 600x1024
- Composite-1: disabled
- user: winner
- Firefox ESR kiosk mode
- no full desktop environment
- cursor auto-hide
- DPMS/screensaver disabled
- automatic graphical login and browser restart

## Fresh install

Start with a clean Armbian Debian 13 installation. Finish Armbian's first-login wizard and create the user `winner`.

Install git:

```bash
apt update
apt install -y git
```

Clone this repository:

```bash
git clone https://github.com/CCbIKATHO/orangepi-ha-kiosk.git
cd orangepi-ha-kiosk
```

Run the installer and provide your Home Assistant URL:

```bash
sudo ./install.sh http://192.168.55.1
```

Replace the URL with the actual Home Assistant dashboard URL if different.

Reboot:

```bash
sudo reboot
```

The expected boot path is:

```text
Armbian
  -> automatic login as winner on tty1
  -> startx
  -> Openbox
  -> display configuration
  -> Firefox ESR --kiosk
  -> Home Assistant
```

## Configuration

The installed configuration is stored in:

```text
/etc/orangepi-ha-kiosk.conf
```

Example:

```bash
KIOSK_URL="http://192.168.55.1"
HDMI_OUTPUT="HDMI-1"
HDMI_MODE="1024x600"
ROTATION="right"
FRAMEBUFFER="600x1024"
DISABLE_OUTPUT="Composite-1"
```

After changing it, restart the graphical session or reboot.

## Diagnostics

Check whether X is running:

```bash
pgrep -a Xorg
```

Check Firefox:

```bash
pgrep -a firefox
```

Check the display from SSH:

```bash
sudo -u winner DISPLAY=:0 xrandr
```

Expected important lines:

```text
Screen 0: ... current 600 x 1024
HDMI-1 connected primary 600x1024 ... right
Composite-1 connected ...
```

Composite may still be physically reported as connected, but it must not extend the framebuffer.

View the kiosk log:

```bash
cat /home/winner/.local/state/orangepi-ha-kiosk.log
```

Temporarily stop Firefox:

```bash
pkill -u winner firefox
```

The kiosk loop will start it again.

## Update

```bash
cd orangepi-ha-kiosk
git pull
sudo ./install.sh
sudo reboot
```

Running the installer without a URL preserves the URL already stored in `/etc/orangepi-ha-kiosk.conf`.

## Uninstall

```bash
sudo ./uninstall.sh
sudo reboot
```

This removes kiosk-specific autologin/startup configuration. It does not remove Firefox, Xorg or Openbox.

## Notes

This project deliberately avoids XFCE/LXDE and a display manager. On a small H3 board this keeps the kiosk simple and reduces RAM/CPU overhead.

If the SD card starts producing errors such as `Input/output error`, `EXT4-fs error` or `mmcblk0` I/O failures, stop troubleshooting the kiosk first and check/replace the storage.
