from homeassistant.components.sensor import SensorEntity
from homeassistant.helpers.update_coordinator import CoordinatorEntity
from .const import DOMAIN

async def async_setup_entry(hass, entry, async_add_entities):
    coordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([ZimaOSEndpointSensor(coordinator, entry.data["host"])])

class ZimaOSEndpointSensor(CoordinatorEntity, SensorEntity):
    _attr_name = "ZimaOS API"
    _attr_icon = "mdi:server"
    def __init__(self, coordinator, host):
        super().__init__(coordinator)
        self._attr_unique_id = f"zimaos_{host}_api"
    @property
    def native_value(self):
        return "connected"
    @property
    def extra_state_attributes(self):
        return self.coordinator.data
