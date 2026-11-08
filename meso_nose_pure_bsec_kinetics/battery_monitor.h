#ifndef BATTERY_MONITOR_H
#define BATTERY_MONITOR_H

#include <Arduino.h>

namespace BatteryConfig {
  constexpr uint8_t ADC_PIN                     = 2;
  constexpr uint8_t ADC_RESOLUTION_BITS         = 12;
  constexpr uint8_t ADC_SAMPLE_COUNT            = 16;
  constexpr uint32_t ADC_SAMPLE_DELAY_MS        = 1;
  constexpr float VOLTAGE_DIVIDER_RATIO         = 2.0f;
  constexpr float MV_TO_VOLTS_DIVISOR           = 1000.0f;

  constexpr float MIN_VALID_CELL_VOLTS          = 2.50f;
  constexpr float CHARGER_CONNECTED_THRESHOLD_V = 4.22f;

  struct OcvPoint {
    float cellVolts;
    float stateOfChargePct;
  };

  constexpr size_t OCV_TABLE_SIZE = 11;
  constexpr OcvPoint LIPO_OCV_TABLE[OCV_TABLE_SIZE] = {
    { 4.20f, 100.0f },
    { 4.10f,  90.0f },
    { 4.00f,  80.0f },
    { 3.90f,  70.0f },
    { 3.82f,  60.0f },
    { 3.78f,  50.0f },
    { 3.74f,  40.0f },
    { 3.70f,  30.0f },
    { 3.65f,  20.0f },
    { 3.55f,  10.0f },
    { 3.30f,   0.0f }
  };
}

class BatteryMonitor {
public:
  static void init();
  static uint8_t readPercentage();
  static uint8_t readPercentageAndVoltage(float &outVoltage);
  static bool isCharging();
  static float getRawVoltage();

private:
  static float readCellVoltage();
  static float interpolateStateOfCharge(float voltage);
};

#endif // BATTERY_MONITOR_H