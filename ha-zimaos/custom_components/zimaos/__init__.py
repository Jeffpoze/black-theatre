"""ZimaOS Home Assistant integration."""
from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator

from .api import ZimaOSApi
from .const import CONF_HOST, CONF_TOKEN, DOMAIN, PLATFORMS

async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    api = ZimaOSApi(hass, entry.data[CONF_HOST], entry.data.get(CONF_TOKEN))
    coordinator = DataUpdateCoordinator(hass, __name__, update_method=api.async_status)
    await coordinator.async_config_entry_first_refresh()
    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True

async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
