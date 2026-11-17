#ifndef BATTERY_MONITOR_H
#define BATTERY_MONITOR_H

#include <Arduino.h>

namespace BatteryConfig {
  // Hardware Pin Assignment
  constexpr uint8_t BATTERY_ADC_PIN                  = 1; // GPIO 1 / ADC1 Channel 0

  // eFuse-Calibrated ADC & Divider Constants
  constexpr uint8_t ADC_RESOLUTION_BITS              = 12;
  constexpr uint8_t ADC_OVERSAMPLE_COUNT             = 4;
  constexpr float   MILLIVOLTS_PER_VOLT              = 1000.0f;
  constexpr float   VOLTAGE_DIVIDER_RATIO            = 2.0f;    // 100k / 100k divider network
  constexpr float   PERCENTAGE_FULL_SCALE            = 100.0f;

  // Physical Cell & Operational Voltage Boundaries
  constexpr float   MIN_PHYSICAL_CELL_DETECT_VOLTS   = 1.50f;   // Below 1.5V implies batteryless USB VBUS power
  constexpr float   LIPO_MIN_OPERATIONAL_VOLTS       = 3.20f;   // Empty cutoff floor
  constexpr float   LIPO_MAX_OPERATIONAL_VOLTS       = 4.20f;   // Full charge ceiling

  // State-of-Charge Smoothing & Sentinel Constants (Zero Magic Numbers)
  constexpr uint8_t USB_POWERED_FALLBACK_PERCENT     = 100;
  constexpr uint8_t EMPTY_CELL_PERCENT               = 0;
  constexpr uint8_t UNINITIALIZED_PERCENT_SENTINEL   = 255;
  constexpr float   UNINITIALIZED_VOLTAGE_SENTINEL   = -1.0f;
  constexpr float   SOC_EMA_ALPHA                    = 0.25f;   // Smooths ADC ripple without lag

  // USB Hardware Start-of-Frame (SOF) Host Detection Constants (1 ms USB SOF cadence)
  constexpr uint32_t USB_SOF_PROBE_DELAY_MS          = 3UL;     // Captures >= 2 hardware SOF ticks
  constexpr uint32_t USB_SOF_HOLD_MS                 = 100UL;   // Holds tethered state across loop ticks
}

namespace BatteryMonitor {
  void init();
  bool isCharging();
  uint8_t readPercentageAndVoltage(float &outVoltage);
}

#endif // BATTERY_MONITOR_H