# Orange Pi JK-BMS Dashboard

Локальна панель моніторингу двох акумуляторів JK-BMS на **Orange Pi PC Plus**.

Проєкт працює **без Home Assistant**: Orange Pi напряму підключається до кожного WT32-ETH01 через **ESPHome Native API**. Home Assistant можна підключити паралельно до тих самих ESPHome-пристроїв.

Поточна схема:

```text
JK-BMS 24V -> UART -> WT32-ETH01 #1 -> Ethernet -> Orange Pi Dashboard
                                      \-> Home Assistant (опційно)

JK-BMS 48V -> UART -> WT32-ETH01 #2 -> Ethernet -> Orange Pi Dashboard
                                      \-> Home Assistant (опційно)
```

## Що показує панель

Для кожного акумулятора:

- SOC, %
- заряд / розряд / очікування
- напруга
- струм
- потужність
- різниця напруг між комірками
- температура АКБ
- температура MOSFET
- статус BMS
- помилки BMS

Інтерфейс оптимізований під вертикальний HDMI-дисплей **600×1024**.

## Перевірена конфігурація

Orange Pi:

- Orange Pi PC Plus / Allwinner H3
- Armbian Community
- Ubuntu 26.04 Resolute
- Xorg + Openbox
- Chromium у `--app` режимі
- фізичний HDMI: 1024×600
- поворот: right
- робоче вікно: 600×1024
- користувач: `winner`

ESP:

- WT32-ETH01
- LAN8720 Ethernet
- ESPHome
- `syssi/esphome-jk-bms`
- JK-BMS через UART 115200
- ESPHome Native API з encryption key

## Структура репозиторію

```text
app/
  app.py                  backend: ESPHome Native API -> JSON
  index.html              локальний український HUD

config/
  kiosk.sh                Chromium watchdog + HDMI + DPMS
  jk-display.service      systemd backend
  jk-display.conf.example приклад конфігурації двох BMS

esphome/
  wt32-jk-bms.yaml        готовий шаблон WT32-ETH01
  secrets.yaml.example    приклад API encryption key

docs/
  WT32-ESPHOME-UA.md      підключення та перша прошивка ESP

install.sh
uninstall.sh
```

## Встановлення Orange Pi

На свіжому Armbian створіть користувача `winner`, потім:

```bash
sudo apt update
sudo apt install -y git

git clone https://github.com/CCbIKATHO/orangepi-ha-kiosk.git
cd orangepi-ha-kiosk

sudo ./install.sh
```

Інсталятор:

1. встановлює Xorg, Openbox, Chromium та утиліти;
2. встановлює Python backend у `/opt/jk-display`;
3. створює venv і ставить `aioesphomeapi` + `aiohttp`;
4. створює `jk-display.service`;
5. налаштовує autologin `winner`;
6. запускає Openbox;
7. запускає Chromium у режимі застосунку;
8. примусово тримає вікно 600×1024;
9. вимикає DPMS/screensaver;
10. автоматично перезапускає Chromium після падіння.

## Налаштування BMS на Orange Pi

Конфіг:

```text
/etc/jk-display.conf
```

Приклад:

```bash
BMS24_HOST=192.168.1.204
BMS24_PORT=6053
BMS24_KEY=YOUR_ESPHOME_API_KEY

BMS48_HOST=
BMS48_PORT=6053
BMS48_KEY=YOUR_ESPHOME_API_KEY
```

Якщо другого BMS ще немає, залиште `BMS48_HOST=` порожнім.

Після зміни:

```bash
sudo systemctl restart jk-display
```

Перевірка:

```bash
systemctl status jk-display --no-pager
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/api/state
```

## ESPHome / WT32-ETH01

Повна інструкція:

[docs/WT32-ESPHOME-UA.md](docs/WT32-ESPHOME-UA.md)

Шаблон:

```text
esphome/wt32-jk-bms.yaml
```

Для 48V другого модуля достатньо змінити:

```yaml
substitutions:
  device_name: jk-bms-48v
  friendly_name: "JK BMS 48V"
```

та використати окремий API encryption key або той самий ключ, якщо це свідомо потрібно у вашій мережі.

## Підключення WT32 до JK-BMS

У перевіреній схемі використовується GPS/UART порт JK-BMS:

```text
WT32 GPIO4  (TX) -> JK-BMS RX
WT32 GPIO35 (RX) <- JK-BMS TX
WT32 GND          -> JK-BMS GND
```

UART:

```text
115200 baud
```

Ethernet WT32-ETH01:

```text
MDC       GPIO23
MDIO      GPIO18
CLK       GPIO0 / CLK_EXT_IN
PHY addr  1
POWER     GPIO16
```

> У різних ревізій JK-BMS роз'єм і порядок контактів можуть відрізнятися. Не орієнтуйтеся лише на колір дроту: перед підключенням перевірте TX/RX/GND саме для своєї моделі.

**Не подавайте напругу акумуляторної збірки безпосередньо на WT32-ETH01.**

## Home Assistant

Home Assistant не потрібен для роботи дисплея.

За бажанням WT32 можна одночасно додати в HA через інтеграцію ESPHome, використавши IP WT32 та Native API encryption key.

Orange Pi та Home Assistant можуть читати один ESPHome-пристрій паралельно.

## Діагностика

Backend:

```bash
systemctl status jk-display --no-pager -l
journalctl -u jk-display -f
```

API:

```bash
curl -s http://127.0.0.1:8080/api/state
```

Chromium:

```bash
ps -ef | grep chromium | grep -v grep
wmctrl -lG
```

Очікуване вікно: **600×1024**.

Kiosk log:

```bash
tail -f /home/winner/.local/state/jk-chromium.log
```

X/HDMI:

```bash
sudo -u winner env DISPLAY=:0 XAUTHORITY=/home/winner/.Xauthority xrandr --query
```

DPMS:

```bash
sudo -u winner env DISPLAY=:0 XAUTHORITY=/home/winner/.Xauthority xset q
```

Екран не повинен автоматично гаснути.

## Оновлення

```bash
cd orangepi-ha-kiosk
git pull
sudo ./install.sh
sudo reboot
```

Інсталятор **не перезаписує** вже наявний `/etc/jk-display.conf`, тому IP та ключі BMS зберігаються.

## Видалення автозапуску

```bash
sudo ./uninstall.sh
sudo reboot
```

`/opt/jk-display` і `/etc/jk-display.conf` навмисно не видаляються, щоб не втратити робочий конфіг.

## Безпека

Не комітьте реальні ESPHome API encryption keys у GitHub.

Згенерувати ключ:

```bash
openssl rand -base64 32
```

Один і той самий ключ із YAML ESPHome потрібно вказати у відповідному `BMS24_KEY` або `BMS48_KEY` на Orange Pi.
