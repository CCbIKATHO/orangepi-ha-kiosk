#!/usr/bin/env python3
import asyncio
import math
import os
import time
from pathlib import Path

import aioesphomeapi
from aiohttp import web

BASE_DIR = Path("/opt/jk-display")
INDEX_FILE = BASE_DIR / "index.html"
POWER_STATE_FILE = Path("/run/jk-power-state.json")


class BatteryClient:
    def __init__(self, env_prefix: str, label: str) -> None:
        self.env_prefix = env_prefix
        self.label = label
        self.host = os.getenv(f"{env_prefix}_HOST", "").strip()
        self.port = int(os.getenv(f"{env_prefix}_PORT", "6053"))
        self.key = os.getenv(f"{env_prefix}_KEY", "").strip()
        self.configured = bool(self.host)
        self.connected = False
        self.error = ""
        self.values: dict[str, object] = {}
        self.last_update: float | None = None
        self._client: aioesphomeapi.APIClient | None = None

    def snapshot(self) -> dict[str, object]:
        age = None
        if self.last_update is not None:
            age = round(max(0.0, time.monotonic() - self.last_update), 1)

        return {
            "configured": self.configured,
            "connected": self.connected,
            "age": age,
            "error": self.error,
            "values": self.values,
        }

    async def run(self) -> None:
        if not self.configured:
            print(f"[{self.label}] host is not configured", flush=True)
            return

        while True:
            stopped = asyncio.Event()
            client: aioesphomeapi.APIClient | None = None

            async def on_stop(expected_disconnect: bool) -> None:
                self.connected = False
                stopped.set()

            try:
                print(f"[{self.label}] connecting to {self.host}:{self.port}", flush=True)
                kwargs = {}
                if self.key:
                    kwargs["noise_psk"] = self.key

                client = aioesphomeapi.APIClient(self.host, self.port, **kwargs)
                self._client = client

                await client.connect(on_stop=on_stop, login=True)
                entities, _services = await client.list_entities_services()
                names = {entity.key: entity.name for entity in entities}

                self.connected = True
                self.error = ""
                print(f"[{self.label}] connected, {len(names)} entities", flush=True)

                def on_state(state: object) -> None:
                    key = getattr(state, "key", None)
                    name = names.get(key)
                    if not name:
                        return

                    value = getattr(state, "state", None)
                    if isinstance(value, float) and math.isnan(value):
                        value = None

                    self.values[name] = value
                    self.last_update = time.monotonic()

                client.subscribe_states(on_state)
                await stopped.wait()

                if not self.error:
                    self.error = "connection closed"

            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.connected = False
                self.error = str(exc)
                print(f"[{self.label}] {type(exc).__name__}: {exc}", flush=True)
            finally:
                if client is not None:
                    try:
                        client.force_disconnect()
                    except Exception:
                        pass
                self._client = None

            await asyncio.sleep(5)


BATTERIES = {
    "24v": BatteryClient("BMS24", "24v"),
    "48v": BatteryClient("BMS48", "48v"),
}


async def index(_request: web.Request) -> web.StreamResponse:
    return web.FileResponse(
        INDEX_FILE,
        headers={
            "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
            "Pragma": "no-cache",
            "Expires": "0",
        },
    )


def power_snapshot() -> dict[str, object]:
    try:
        import json
        data = json.loads(POWER_STATE_FILE.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {
        "configured": True,
        "present": None,
        "raw": None,
        "error": "power monitor has no data",
    }


async def api_state(_request: web.Request) -> web.Response:
    payload = {name: battery.snapshot() for name, battery in BATTERIES.items()}
    payload["mains"] = power_snapshot()
    return web.json_response(payload)


async def health(_request: web.Request) -> web.Response:
    return web.json_response({"ok": True})


async def on_startup(app: web.Application) -> None:
    app["bms_tasks"] = [
        asyncio.create_task(battery.run(), name=f"bms-{name}")
        for name, battery in BATTERIES.items()
    ]


async def on_cleanup(app: web.Application) -> None:
    tasks = app.get("bms_tasks", [])
    for task in tasks:
        task.cancel()
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)


def build_app() -> web.Application:
    app = web.Application()
    app.router.add_get("/", index)
    app.router.add_get("/api/state", api_state)
    app.router.add_get("/health", health)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    return app


if __name__ == "__main__":
    web.run_app(build_app(), host="127.0.0.1", port=8080)
