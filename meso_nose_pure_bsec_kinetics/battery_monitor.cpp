#include "battery_monitor.h"
#include "soc/usb_serial_jtag_struct.h"

namespace {
  uint8_t mapVoltageToPercentage(float cellVolts) {
    if (cellVolts >= BatteryConfig::LIPO_MAX_OPERATIONAL_VOLTS) {
      return BatteryConfig::USB_POWERED_FALLBACK_PERCENT;
    }
    if (cellVolts <= BatteryConfig::LIPO_MIN_OPERATIONAL_VOLTS) {
      return BatteryConfig::EMPTY_CELL_PERCENT;
    }

    constexpr float voltageRangeVolts =
      BatteryConfig::LIPO_MAX_OPERATIONAL_VOLTS - BatteryConfig::LIPO_MIN_OPERATIONAL_VOLTS;

    const float percentage = ((cellVolts - BatteryConfig::LIPO_MIN_OPERATIONAL_VOLTS) / voltageRangeVolts) *
                             BatteryConfig::PERCENTAGE_FULL_SCALE;

    return static_cast<uint8_t>(percentage);
  }
}

namespace BatteryMonitor {

  void init() {
    pinMode(BatteryConfig::BATTERY_ADC_PIN, INPUT);
    analogReadResolution(BatteryConfig::ADC_RESOLUTION_BITS);
    analogSetAttenuation(ADC_11db); // Full range 0 - 3.1V attenuation
  }

  bool isCharging() {
    if (static_cast<bool>(Serial)) {
      return true;
    }

    static uint32_t lastSofFrame = USB_SERIAL_JTAG.fram_num.val;
    static uint32_t lastUsbSofSeenMs = 0;
    static bool hasSampledOnce = false;

    if (!hasSampledOnce) {
      hasSampledOnce = true;
      delay(BatteryConfig::USB_SOF_PROBE_DELAY_MS);
    }

    const uint32_t nowMs = millis();
    const uint32_t currentSofFrame = USB_SERIAL_JTAG.fram_num.val;
    if (currentSofFrame != lastSofFrame) {
      lastSofFrame = currentSofFrame;
      lastUsbSofSeenMs = nowMs;
      return true;
    }

    return (lastUsbSofSeenMs > 0) && ((nowMs - lastUsbSofSeenMs) < BatteryConfig::USB_SOF_HOLD_MS);
  }

  uint8_t readPercentageAndVoltage(float &outVoltage) {
    static float s_filteredVoltage = BatteryConfig::UNINITIALIZED_VOLTAGE_SENTINEL;
    static uint8_t s_lastUntetheredPct = BatteryConfig::UNINITIALIZED_PERCENT_SENTINEL;

    uint32_t accumulatedMv = 0;
    for (uint8_t i = 0; i < BatteryConfig::ADC_OVERSAMPLE_COUNT; i++) {
      accumulatedMv += analogReadMilliVolts(BatteryConfig::BATTERY_ADC_PIN);
    }

    const float averagePinMv = static_cast<float>(accumulatedMv) /
                               static_cast<float>(BatteryConfig::ADC_OVERSAMPLE_COUNT);

    const float rawVoltage = (averagePinMv / BatteryConfig::MILLIVOLTS_PER_VOLT) *
                             BatteryConfig::VOLTAGE_DIVIDER_RATIO;

    // Below 1.50V implies batteryless USB VBUS operation
    if (rawVoltage < BatteryConfig::MIN_PHYSICAL_CELL_DETECT_VOLTS) {
      s_filteredVoltage = BatteryConfig::UNINITIALIZED_VOLTAGE_SENTINEL;
      s_lastUntetheredPct = BatteryConfig::UNINITIALIZED_PERCENT_SENTINEL;
      outVoltage = rawVoltage;
      return BatteryConfig::USB_POWERED_FALLBACK_PERCENT;
    }

    if (s_filteredVoltage < 0.0f) {
      s_filteredVoltage = rawVoltage;
    } else {
      s_filteredVoltage = (BatteryConfig::SOC_EMA_ALPHA * rawVoltage) +
                          ((1.0f - BatteryConfig::SOC_EMA_ALPHA) * s_filteredVoltage);
    }

    outVoltage = s_filteredVoltage;
    uint8_t computedPct = mapVoltageToPercentage(s_filteredVoltage);

    // Prevent upward SoC bounce when discharging on battery; allow rising SoC while charging
    if (!isCharging()) {
      if (s_lastUntetheredPct <= BatteryConfig::USB_POWERED_FALLBACK_PERCENT &&
          computedPct > s_lastUntetheredPct) {
        computedPct = s_lastUntetheredPct;
      }
      s_lastUntetheredPct = computedPct;
    } else {
      s_lastUntetheredPct = BatteryConfig::UNINITIALIZED_PERCENT_SENTINEL;
    }

    return computedPct;
  }

} // namespace BatteryMonitor