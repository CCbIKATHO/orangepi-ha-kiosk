# WT32-ETH01 + JK-BMS + ESPHome

Ця інструкція описує підготовку WT32-ETH01 для локальної панелі Orange Pi.

## 1. Архітектура

```text
JK-BMS
  |
  | UART TTL 115200
  v
WT32-ETH01
  |
  | Ethernet / TCP 6053 / ESPHome Native API
  +------> Orange Pi
  |
  +------> Home Assistant (опційно)
```

Orange Pi не читає Home Assistant. Він підключається безпосередньо до ESPHome Native API.

## 2. UART між JK-BMS та WT32

Перевірена схема:

```text
JK-BMS RX   <--- GPIO4  WT32 TX
JK-BMS TX   ---> GPIO35 WT32 RX
JK-BMS GND  ----- GND   WT32
```

Налаштування:

```text
baud: 115200
RX buffer: 384
```

В ESPHome:

```yaml
uart:
  - id: uart_bms
    baud_rate: 115200
    rx_buffer_size: 384
    tx_pin: GPIO4
    rx_pin: GPIO35
```

### Важливо

Розпіновка фізичного роз'єму JK-BMS залежить від моделі та ревізії.

Перед підключенням:

1. знайдіть GND;
2. перевірте TX JK-BMS;
3. перевірте RX JK-BMS;
4. не підключайте лінії навмання за кольором кабелю;
5. не подавайте напругу батареї на WT32.

## 3. Ethernet WT32-ETH01

```yaml
ethernet:
  type: LAN8720
  mdc_pin: GPIO23
  mdio_pin: GPIO18
  clk:
    pin: GPIO0
    mode: CLK_EXT_IN
  phy_addr: 1
  power_pin: GPIO16
```

Ці GPIO зайняті Ethernet і не повинні використовуватися для BMS:

```text
GPIO0
GPIO16
GPIO18
GPIO23
```

## 4. Native API

Згенеруйте ключ:

```bash
openssl rand -base64 32
```

Створіть `secrets.yaml` поруч з YAML:

```yaml
api_encryption_key: "ВАШ_BASE64_KEY"
```

У конфігурації:

```yaml
api:
  encryption:
    key: !secret api_encryption_key
```

Пізніше цей самий ключ потрібно вказати на Orange Pi у `BMS24_KEY` або `BMS48_KEY`.

## 5. Підготовка YAML

Скопіюйте шаблон:

```bash
cp esphome/wt32-jk-bms.yaml /config/jk-bms-24v.yaml
```

Для 24V:

```yaml
substitutions:
  device_name: jk-bms-24v
  friendly_name: "JK BMS 24V"
```

Для другого WT32 / 48V:

```yaml
substitutions:
  device_name: jk-bms-48v
  friendly_name: "JK BMS 48V"
```

Кожен WT32 повинен мати унікальне `device_name`.

## 6. Перша прошивка WT32 через USB-TTL

Для першої прошивки Ethernet/OTA ще не доступні.

USB-TTL:

```text
USB-TTL TX  -> WT32 RX0 / GPIO3
USB-TTL RX  <- WT32 TX0 / GPIO1
USB-TTL GND -> WT32 GND
```

Для входу в bootloader:

```text
GPIO0 -> GND
```

Після цього подайте живлення або натисніть reset.

Сигнальні рівні UART USB-TTL повинні бути **3.3 V**. Не подавайте RS-232 рівні на ESP32 і не подавайте напругу акумуляторної збірки на WT32.

## 7. Компіляція ESPHome

Звичайна установка ESPHome:

```bash
esphome config jk-bms-24v.yaml
esphome compile jk-bms-24v.yaml
```

Якщо ESPHome працює у Docker:

```bash
docker exec -it esphome esphome config /config/jk-bms-24v.yaml
docker exec -it esphome esphome compile /config/jk-bms-24v.yaml
```

Для першої прошивки потрібен factory image. Типовий шлях:

```text
/config/.esphome/build/jk-bms-24v/.pioenvs/jk-bms-24v/firmware.factory.bin
```

Після першої прошивки наступні оновлення можна виконувати OTA.

## 8. Після прошивки

1. від'єднайте GPIO0 від GND;
2. перезавантажте WT32;
3. підключіть Ethernet;
4. знайдіть IP у DHCP;
5. перевірте порт 6053;
6. переконайтеся, що ESPHome бачить JK-BMS.

У логах повинні з'являтися значення:

```text
Battery Voltage
Battery Current
Battery Power
State of Charge
Cell Voltage Delta
Battery Temperature 1
MOS Temperature
BMS Online
Errors
```

Саме ці назви використовує dashboard.

## 9. Підключення Orange Pi

Відредагуйте:

```bash
sudo nano /etc/jk-display.conf
```

Наприклад:

```bash
BMS24_HOST=192.168.1.204
BMS24_PORT=6053
BMS24_KEY=ВАШ_API_KEY

BMS48_HOST=
BMS48_PORT=6053
BMS48_KEY=
```

Перезапустіть:

```bash
sudo systemctl restart jk-display
```

Перевірте:

```bash
curl -s http://127.0.0.1:8080/api/state
```

Для підключеного BMS очікується `configured: true` і `connected: true`.

## 10. Home Assistant

ESPHome Native API підтримує паралельне підключення, тому один WT32 може одночасно використовуватися Orange Pi dashboard та Home Assistant.

## 11. Якщо дані BMS не з'являються

Спочатку перевірте Ethernet/API:

```bash
ping IP_WT32
nc -vz IP_WT32 6053
```

Якщо API доступний, але немає Battery Voltage / Current / Cells:

- перевірте TX/RX;
- TX і RX повинні бути перехресними;
- перевірте спільний GND;
- перевірте 115200 baud;
- перевірте, що використовується UART/GPS порт JK-BMS;
- перевірте, що BMS реально бачить потрібну кількість комірок.

Якщо BMS показує лише частину комірок, це вже не проблема Orange Pi або Native API — перевіряйте балансувальний шлейф та налаштування самого JK-BMS.
