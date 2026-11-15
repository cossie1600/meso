#ifndef SENSOR_DATA_H
#define SENSOR_DATA_H

#include <Arduino.h>

enum OperationMode : uint8_t {
  MODE_IDLE = 0,
  MODE_BREATH_TEST = 1,
  MODE_DIAGNOSTIC = 2
};

enum BsecProfile : uint8_t {
  PROFILE_OFF = 0,
  PROFILE_ULP_300S = 1,
  PROFILE_LP_3S = 2
};

namespace SensorFormatConstants {
  constexpr unsigned int STANDARD_FLOAT_PRECISION = 1U;
  constexpr unsigned int HIGH_FLOAT_PRECISION     = 2U;
  constexpr const char  *DEFAULT_PTC_RESULT       = "NONE";
}

struct SensorData {
  float currentTemp = 0.0f;
  float currentHumidity = 0.0f;
  float currentPressure = 0.0f;
  float currentGasRes = 0.0f;
  float currentCO2 = 0.0f; // Intact
  uint8_t currentHeaterStep = 0;
  uint8_t bsecAccuracy = 0;
  uint8_t batteryPct = 100;
  float deltaDrop = 0.0f;
  float selectivityRatio = 1.0f;
  float recoveryLagSec = 0.0f;
  long rBreathMin = 0;
  String ptcResult = SensorFormatConstants::DEFAULT_PTC_RESULT;

  String toJsonString() const {
    String json = "{";
    json += "\"temp\":" + String(currentTemp, SensorFormatConstants::STANDARD_FLOAT_PRECISION) + ",";
    json += "\"rh\":" + String(currentHumidity, SensorFormatConstants::STANDARD_FLOAT_PRECISION) + ",";
    json += "\"press\":" + String(currentPressure, SensorFormatConstants::STANDARD_FLOAT_PRECISION) + ",";
    json += "\"voc\":" + String((long)currentGasRes) + ",";
    json += "\"co2\":" + String((int)currentCO2) + ",";
    json += "\"battery\":" + String(batteryPct) + ",";
    json += "\"breath_drop_delta\":" + String(deltaDrop, SensorFormatConstants::STANDARD_FLOAT_PRECISION) + ",";
    json += "\"selectivity_ratio\":" + String(selectivityRatio, SensorFormatConstants::HIGH_FLOAT_PRECISION) + ",";
    json += "\"recovery_lag_sec\":" + String(recoveryLagSec, SensorFormatConstants::HIGH_FLOAT_PRECISION) + ",";
    json += "\"breath_min\":" + String(rBreathMin) + ",";
    json += "\"ptc_result\":\"" + ptcResult + "\"";
    json += "}";
    return json;
  }
};

#endif // SENSOR_DATA_H