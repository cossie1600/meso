#ifndef SENSOR_DATA_H
#define SENSOR_DATA_H

#include <Arduino.h>

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
  String ptcResult = "NONE";

  String toJsonString() const {
    String json = "{";
    json += "\"temp\":" + String(currentTemp, 1) + ",";
    json += "\"rh\":" + String(currentHumidity, 1) + ",";
    json += "\"press\":" + String(currentPressure, 1) + ",";
    json += "\"voc\":" + String((long)currentGasRes) + ",";
    json += "\"co2\":" + String((int)currentCO2) + ",";
    json += "\"battery\":" + String(batteryPct) + ",";
    json += "\"breath_drop_delta\":" + String(deltaDrop, 1) + ",";
    json += "\"selectivity_ratio\":" + String(selectivityRatio, 2) + ",";
    json += "\"recovery_lag_sec\":" + String(recoveryLagSec, 2) + ",";
    json += "\"breath_min\":" + String(rBreathMin) + ",";
    json += "\"ptc_result\":\"" + ptcResult + "\"";
    json += "}";
    return json;
  }
};

#endif // SENSOR_DATA_H