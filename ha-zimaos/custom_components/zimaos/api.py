"""Small, endpoint-discovering client for ZimaOS."""
from __future__ import annotations
import aiohttp
from homeassistant.core import HomeAssistant

class ZimaOSApi:
    def __init__(self, hass: HomeAssistant, host: str, token: str | None) -> None:
        self._session = aiohttp.ClientSession()
        self._base = host.rstrip("/") if host.startswith("http") else f"http://{host}"
        self._headers = {"Authorization": f"Bearer {token}"} if token else {}

    async def async_status(self) -> dict:
        """Probe stable CasaOS/ZimaOS system endpoints; retain raw data for entities."""
        errors: list[str] = []
        for path in ("/v1/sys/info", "/v1/sys/health", "/v2/system/info"):
            try:
                async with self._session.get(self._base + path, headers=self._headers, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json(content_type=None)
                        return {"endpoint": path, "data": data}
                    errors.append(f"{path}: HTTP {response.status}")
            except aiohttp.ClientError as err:
                errors.append(f"{path}: {err}")
        raise RuntimeError("ZimaOS API unavailable; " + "; ".join(errors))
