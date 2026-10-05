#!/usr/bin/env python3
import asyncio
import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path

import aiohttp

STATE_FILE = Path("/run/jk-power-state.json")
GPIO_CHIP = os.getenv("POWER_GPIO_CHIP", "gpiochip0").strip()
GPIO_LINE = os.getenv("POWER_GPIO_LINE", "1").strip()
PRESENT_VALUE = os.getenv("POWER_PRESENT_VALUE", "0").strip()
POLL_SECONDS = float(os.getenv("POWER_POLL_SECONDS", "1"))
DEBOUNCE_SECONDS = float(os.getenv("POWER_DEBOUNCE_SECONDS", "3"))

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "").strip()
DASHBOARD_API = os.getenv("DASHBOARD_API", "http://127.0.0.1:8080/api/state").strip()

last_stable = None
candidate = None
candidate_since = 0.0
outage_started_wall = None
telegram_offset = 0


def read_gpio() -> str:
    commands = [
        ["gpioget", "-c", GPIO_CHIP, GPIO_LINE],
        ["gpioget", GPIO_CHIP, GPIO_LINE],
    ]
    last_error = ""
    for cmd in commands:
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=2, check=False
            )
            if result.returncode == 0:
                raw = result.stdout.strip().lower()
                if raw in {"0", "1"}:
                    return raw
                if raw.endswith("=0"):
                    return "0"
                if raw.endswith("=1"):
                    return "1"
            last_error = (result.stderr or result.stdout).strip()
        except Exception as exc:
            last_error = str(exc)
    raise RuntimeError(last_error or "gpioget failed")


def write_state(present, raw=None, error="", changed_at=None):
    payload = {
        "configured": True,
        "present": present,
        "raw": raw,
        "error": error,
        "changed_at": changed_at,
        "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "outage_started_at": outage_started_wall,
    }
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    tmp.replace(STATE_FILE)


async def telegram_send(session: aiohttp.ClientSession, text: str):
    if not BOT_TOKEN or not CHAT_ID:
        return
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        async with session.post(
            url,
            json={"chat_id": CHAT_ID, "text": text},
            timeout=aiohttp.ClientTimeout(total=10),
        ) as response:
            if response.status >= 300:
                body = await response.text()
                print(f"[telegram] HTTP {response.status}: {body}", flush=True)
    except Exception as exc:
        print(f"[telegram] send failed: {exc}", flush=True)


def fmt_duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h} год {m} хв {s} с"
    if m:
        return f"{m} хв {s} с"
    return f"{s} с"


async def fetch_dashboard(session: aiohttp.ClientSession):
    try:
        async with session.get(
            DASHBOARD_API, timeout=aiohttp.ClientTimeout(total=3)
        ) as response:
            if response.status == 200:
                return await response.json()
    except Exception:
        pass
    return {}


def battery_line(label: str, data: dict) -> str:
    if not data or not data.get("configured"):
        return f"🔋 {label}: не налаштовано"
    if not data.get("connected"):
        return f"🔋 {label}: не в мережі"
    values = data.get("values") or {}
    soc = values.get("State of Charge")
    voltage = values.get("Battery Voltage")
    current = values.get("Battery Current")

    def n(v, digits=1):
        try:
            return f"{float(v):.{digits}f}"
        except Exception:
            return "--"

    soc_text = "--"
    try:
        soc_text = str(round(float(soc)))
    except Exception:
        pass

    return (
        f"🔋 {label}: {soc_text}% · "
        f"{n(voltage)} V · {n(current)} A"
    )


async def status_text(session: aiohttp.ClientSession) -> str:
    state = {}
    try:
        state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception:
        pass

    present = state.get("present")
    if present is True:
        power = "🟢 220V: є живлення"
    elif present is False:
        power = "🔴 220V: немає живлення"
    else:
        power = "⚪ 220V: стан невідомий"

    dashboard = await fetch_dashboard(session)
    return "\n".join([
        power,
        "",
        battery_line("АКБ 24V", dashboard.get("24v", {})),
        battery_line("АКБ 48V", dashboard.get("48v", {})),
    ])


async def telegram_poll(session: aiohttp.ClientSession):
    global telegram_offset
    if not BOT_TOKEN:
        return

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/getUpdates"
    params = {"timeout": 1}
    if telegram_offset:
        params["offset"] = telegram_offset

    try:
        async with session.get(
            url, params=params, timeout=aiohttp.ClientTimeout(total=5)
        ) as response:
            if response.status != 200:
                return
            body = await response.json()
    except Exception:
        return

    for update in body.get("result", []):
        telegram_offset = max(telegram_offset, int(update["update_id"]) + 1)
        msg = update.get("message") or {}
        chat = msg.get("chat") or {}
        if CHAT_ID and str(chat.get("id")) != CHAT_ID:
            continue

        text = (msg.get("text") or "").strip().split("@", 1)[0]
        if text in {"/status", "/power", "/start"}:
            if text == "/power":
                try:
                    state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
                    present = state.get("present")
                    reply = (
                        "🟢 220V: є живлення"
                        if present is True else
                        "🔴 220V: немає живлення"
                        if present is False else
                        "⚪ 220V: стан невідомий"
                    )
                except Exception:
                    reply = "⚪ 220V: стан невідомий"
            else:
                reply = await status_text(session)

            if not CHAT_ID:
                continue
            await telegram_send(session, reply)


async def main():
    global last_stable, candidate, candidate_since, outage_started_wall

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)

    async with aiohttp.ClientSession() as session:
        while True:
            now = time.monotonic()
            changed_at = None
            try:
                raw = read_gpio()
                present = raw == PRESENT_VALUE

                if candidate != present:
                    candidate = present
                    candidate_since = now

                if last_stable is None:
                    if now - candidate_since >= DEBOUNCE_SECONDS:
                        last_stable = candidate
                        changed_at = datetime.now().astimezone().isoformat(timespec="seconds")
                        if last_stable is False:
                            outage_started_wall = time.time()
                        write_state(last_stable, raw=raw, changed_at=changed_at)
                        print(f"[power] initial present={last_stable} raw={raw}", flush=True)

                elif candidate != last_stable and now - candidate_since >= DEBOUNCE_SECONDS:
                    previous = last_stable
                    last_stable = candidate
                    changed_at = datetime.now().astimezone().isoformat(timespec="seconds")

                    if last_stable is False:
                        outage_started_wall = time.time()
                        await telegram_send(
                            session,
                            "🔴 Зникло живлення 220В\n"
                            + datetime.now().astimezone().strftime("%d.%m.%Y %H:%M:%S"),
                        )
                    else:
                        duration = ""
                        if outage_started_wall is not None:
                            duration = "\nБез мережі: " + fmt_duration(time.time() - outage_started_wall)
                        outage_started_wall = None
                        await telegram_send(
                            session,
                            "🟢 Живлення 220В відновлено\n"
                            + datetime.now().astimezone().strftime("%d.%m.%Y %H:%M:%S")
                            + duration,
                        )

                    write_state(last_stable, raw=raw, changed_at=changed_at)
                    print(
                        f"[power] changed {previous} -> {last_stable}, raw={raw}",
                        flush=True,
                    )
                else:
                    write_state(last_stable, raw=raw)

            except Exception as exc:
                write_state(last_stable, error=str(exc))
                print(f"[power] read error: {exc}", flush=True)

            await telegram_poll(session)
            await asyncio.sleep(POLL_SECONDS)


if __name__ == "__main__":
    asyncio.run(main())
