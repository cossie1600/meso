#include "diagnostics.h"
#include <Wire.h>
#include "bsec2.h"
#include <bme68x/bme68x.h>

// -------------------------------------------------------------------
// External Global References (Defined in main sketch)
// -------------------------------------------------------------------
extern Bsec2* bsec;
extern uint8_t bmeI2cAddr;
extern bool bsecReady;

extern bsecSensor defaultSensorList[];
extern uint8_t numDefaultSensors;

struct SensorData {
  float currentTemp;
  float currentHumidity;
  float currentPressure;
  float currentGasRes;
  uint8_t currentHeaterStep;
  float currentCO2;
  uint8_t bsecAccuracy;
  float deltaDrop;
  float selectivityRatio;
  long rBreathMin;
  String ptcResult;
  uint8_t batteryPct;
};
extern SensorData sensorData;

enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };
extern BsecProfile currentProfile;

extern void logMessage(String msg);
extern void dispatchData(String payload);
extern void softResetBme688Sensor();
extern void resetToDefaultMode();
extern bool configureLowLevelParallelScan();
extern bool readLowLevelScanFrame(float &outGasRes, uint8_t &outStep);

constexpr uint32_t I2C_BUS_SETTLE_DELAY_MS = 100;
constexpr float DIAG_HW_MIN_SENSOR_GAS_RES = 5000.0f;

bool runSelectivityDiagnosticTest() {
  logMessage("\n==================================================");
  logMessage("[DIAG TEST START]: Running Option B Low-Level Suite");
  logMessage("==================================================");

  bool t1_pass = false;
  bool t2_pass = false;
  bool t3_pass = false;
  bool t4_pass = false;
  bool t5_pass = false;

  // -------------------------------------------------------------------
  // Test 1: Physical I2C Bus Soft Reset (0xB6)
  // -------------------------------------------------------------------
  logMessage("[DIAG 1/5]: Teardown ULP and sending 0xB6 Soft Reset over I2C...");
  if (bsec != nullptr) {
    bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_DISABLED);
  }
  vTaskDelay(pdMS_TO_TICKS(I2C_BUS_SETTLE_DELAY_MS));

  softResetBme688Sensor();

  Wire.beginTransmission(bmeI2cAddr);
  if (Wire.endTransmission() == 0) {
    logMessage("[DIAG 1/5 PASS]: BME688 hardware acknowledged soft reset on I2C.");
    t1_pass = true;
  } else {
    logMessage("[DIAG 1/5 FAIL]: Sensor did not respond on I2C after soft reset!");
  }

  // -------------------------------------------------------------------
  // Test 2: Verify BSEC Safe Pause (Freezing Subscription)
  // -------------------------------------------------------------------
  logMessage("[DIAG 2/5]: Verifying BSEC subscription pause...");
  if (bsec != nullptr && bsec->status == BSEC_OK) {
    logMessage("[DIAG 2/5 PASS]: BSEC background subscriptions paused cleanly.");
    t2_pass = true;
  } else {
    logMessage("[DIAG 2/5 FAIL]: BSEC object invalid or in fault state!");
  }

  // -------------------------------------------------------------------
  // Test 3: Configure bme68x Parallel Heater Matrix (200-400 C)
  // -------------------------------------------------------------------
  logMessage("[DIAG 3/5]: Configuring bme68x parallel scan heater matrix...");
  if (configureLowLevelParallelScan()) {
    logMessage("[DIAG 3/5 PASS]: Low-level 10-step parallel scan profile loaded.");
    t3_pass = true;
  } else {
    logMessage("[DIAG 3/5 FAIL]: bme68x_set_heatr_conf failed!");
  }

  // -------------------------------------------------------------------
  // Test 4: Capture Physical Gas Resistance (Filtering Non-Zero Values)
  // -------------------------------------------------------------------
  logMessage("[DIAG 4/5]: Sampling raw physical gas resistance (10s window)...");
  uint32_t capturedSamples = 0;
  unsigned long startMs = millis();
  unsigned long lastHeartbeatMs = 0;

  while (millis() - startMs < 10000) {
    float rawGasRes = 0.0f;
    uint8_t step = 0;

    if (readLowLevelScanFrame(rawGasRes, step)) {
      if (rawGasRes >= DIAG_HW_MIN_SENSOR_GAS_RES) {
        capturedSamples++;
        sensorData.currentGasRes = rawGasRes;
        sensorData.currentHeaterStep = step;
        logMessage("   -> [PHYSICAL GAS FRAME #" + String(capturedSamples) + "]: Step = " 
                   + String(step) + " | Gas Res = " + String((long)rawGasRes) + " Ohm");
      }
    }

    if (millis() - lastHeartbeatMs >= 2000) {
      lastHeartbeatMs = millis();
      logMessage("   ... [POLLING]: Elapsed = " + String(millis() - startMs) 
                 + " ms | Valid Hardware Samples = " + String(capturedSamples));
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }

  if (capturedSamples > 0) {
    logMessage("[DIAG 4/5 PASS]: Captured " + String(capturedSamples) + " valid physical gas samples!");
    t4_pass = true;
  } else {
    logMessage("[DIAG 4/5 FAIL]: Captured 0 valid physical gas samples.");
  }

  // -------------------------------------------------------------------
  // Test 5: Clean Recovery Back to BSEC ULP 300s Mode
  // -------------------------------------------------------------------
  logMessage("[DIAG 5/5]: Restoring hardware and resuming BSEC ULP profile...");
  resetToDefaultMode();

  if (currentProfile == PROFILE_ULP_300S && bsec != nullptr && bsec->status == BSEC_OK) {
    logMessage("[DIAG 5/5 PASS]: Restored BSEC PROFILE_ULP_300S cleanly.");
    t5_pass = true;
  } else {
    logMessage("[DIAG 5/5 FAIL]: Recovery to BSEC ULP profile failed!");
  }

  // -------------------------------------------------------------------
  // Summary & Score Calculation
  // -------------------------------------------------------------------
  uint32_t passCount = (t1_pass ? 1 : 0) + (t2_pass ? 1 : 0) + 
                       (t3_pass ? 1 : 0) + (t4_pass ? 1 : 0) + 
                       (t5_pass ? 1 : 0);

  logMessage("\n==================================================");
  logMessage("[DIAG TEST SUMMARY]: " + String(passCount) + "/5 TESTS PASSED!");
  logMessage("  - Test 1 (I2C Soft Reset):      " + String(t1_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 2 (BSEC Pause):          " + String(t2_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 3 (Parallel Scan Load):  " + String(t3_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 4 (Raw Gas Sampling):    " + String(t4_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 5 (BSEC ULP Resume):     " + String(t5_pass ? "PASS" : "FAIL"));
  logMessage("==================================================\n");

  dispatchData("{\"diag_test\":\"COMPLETE\",\"passed_tests\":" + String(passCount) + ",\"total_tests\":5}");
  return (passCount == 5);
}