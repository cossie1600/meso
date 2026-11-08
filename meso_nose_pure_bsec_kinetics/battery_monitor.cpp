#include "battery_monitor.h"

void BatteryMonitor::init() {
  pinMode(BatteryConfig::ADC_PIN, INPUT);
  analogReadResolution(BatteryConfig::ADC_RESOLUTION_BITS);
  analogSetPinAttenuation(BatteryConfig::ADC_PIN, ADC_11db);
}

float BatteryMonitor::readCellVoltage() {
  using namespace BatteryConfig;
  uint32_t totalMilliVolts = 0;
  for (uint8_t i = 0; i < ADC_SAMPLE_COUNT; i++) {
    totalMilliVolts += analogReadMilliVolts(ADC_PIN);
    vTaskDelay(pdMS_TO_TICKS(ADC_SAMPLE_DELAY_MS));
  }
  const float rawPinVolts = (static_cast<float>(totalMilliVolts) / static_cast<float>(ADC_SAMPLE_COUNT)) / MV_TO_VOLTS_DIVISOR;
  return rawPinVolts * VOLTAGE_DIVIDER_RATIO;
}

float BatteryMonitor::getRawVoltage() {
  return readCellVoltage();
}

bool BatteryMonitor::isCharging() {
  return (readCellVoltage() >= BatteryConfig::CHARGER_CONNECTED_THRESHOLD_V);
}

float BatteryMonitor::interpolateStateOfCharge(float voltage) {
  using namespace BatteryConfig;
  if (voltage >= LIPO_OCV_TABLE[0].cellVolts) return 100.0f;
  if (voltage <= LIPO_OCV_TABLE[OCV_TABLE_SIZE - 1].cellVolts) return 0.0f;

  for (size_t i = 0; i < OCV_TABLE_SIZE - 1; i++) {
    const float vHigh = LIPO_OCV_TABLE[i].cellVolts;
    const float vLow  = LIPO_OCV_TABLE[i + 1].cellVolts;
    if (voltage <= vHigh && voltage >= vLow) {
      const float socHigh = LIPO_OCV_TABLE[i].stateOfChargePct;
      const float socLow  = LIPO_OCV_TABLE[i + 1].stateOfChargePct;
      const float ratio   = (voltage - vLow) / (vHigh - vLow);
      return socLow + ratio * (socHigh - socLow);
    }
  }
  return 0.0f;
}

uint8_t BatteryMonitor::readPercentage() {
  float dummyVoltage = 0.0f;
  return readPercentageAndVoltage(dummyVoltage);
}

uint8_t BatteryMonitor::readPercentageAndVoltage(float &outVoltage) {
  using namespace BatteryConfig;
  outVoltage = readCellVoltage();

  if (outVoltage < MIN_VALID_CELL_VOLTS || outVoltage <= LIPO_OCV_TABLE[OCV_TABLE_SIZE - 1].cellVolts) {
    return 0;
  }
  if (outVoltage >= CHARGER_CONNECTED_THRESHOLD_V) {
    return 100;
  }

  const float soc = interpolateStateOfCharge(outVoltage);
  return static_cast<uint8_t>(soc + 0.5f);
}