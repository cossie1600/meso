#include "battery_monitor.h"
#include "soc/usb_serial_jtag_struct.h"

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
    uint32_t accumulatedMv = 0;
    for (uint8_t i = 0; i < BatteryConfig::ADC_OVERSAMPLE_COUNT; i++) {
      accumulatedMv += analogReadMilliVolts(BatteryConfig::BATTERY_ADC_PIN);
    }

    const float averagePinMv = static_cast<float>(accumulatedMv) /
                               static_cast<float>(BatteryConfig::ADC_OVERSAMPLE_COUNT);

    outVoltage = (averagePinMv / BatteryConfig::MILLIVOLTS_PER_VOLT) *
                 BatteryConfig::VOLTAGE_DIVIDER_RATIO;

    // If the MCU is running while cell voltage reads below 1.50V, it is powered
    // via USB VBUS with no physical LiPo attached (including dumb USB wall chargers)
    if (outVoltage < BatteryConfig::MIN_PHYSICAL_CELL_DETECT_VOLTS) {
      return BatteryConfig::USB_POWERED_FALLBACK_PERCENT;
    }

    // Upper and lower operational clamping
    if (outVoltage >= BatteryConfig::LIPO_MAX_OPERATIONAL_VOLTS) {
      return BatteryConfig::USB_POWERED_FALLBACK_PERCENT;
    }
    if (outVoltage <= BatteryConfig::LIPO_MIN_OPERATIONAL_VOLTS) {
      return BatteryConfig::EMPTY_CELL_PERCENT;
    }

    // Linear interpolation across operational voltage span
    constexpr float voltageRangeVolts =
      BatteryConfig::LIPO_MAX_OPERATIONAL_VOLTS - BatteryConfig::LIPO_MIN_OPERATIONAL_VOLTS;

    const float percentage = ((outVoltage - BatteryConfig::LIPO_MIN_OPERATIONAL_VOLTS) / voltageRangeVolts) *
                             BatteryConfig::PERCENTAGE_FULL_SCALE;

    return static_cast<uint8_t>(percentage);
  }

} // namespace BatteryMonitor