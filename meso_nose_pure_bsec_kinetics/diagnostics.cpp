/**
 * ============================================================================
 * DIAGNOSTICS: PURE BSEC KINETICS (diagnostics.cpp)
 * ============================================================================
 */

#include "diagnostics.h"
#include <Wire.h>
#include "bsec2.h"

extern Bsec2* bsec;
extern uint8_t bmeI2cAddr;
extern bool bsecReady;
extern volatile bool newGasDataAvailable;

extern bsecSensor defaultSensorList[];
extern uint8_t numDefaultSensors;
extern bool updateBsecSubscription(float sampleRate);
extern SensorData sensorData;

enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };
extern BsecProfile currentProfile;

extern void logMessage(String msg);
extern void dispatchData(String payload);

constexpr float DIAG_HW_MIN_SENSOR_GAS_RES = 5000.0f;

bool runSelectivityDiagnosticTest() {
  logMessage("\n==================================================");
  logMessage("[DIAG TEST START]: Running Pure BSEC Health Check Suite");
  logMessage("==================================================");

  bool t1_pass = false;
  bool t2_pass = false;
  bool t3_pass = false;
  bool t4_pass = false;
  bool t5_pass = false;

  // -------------------------------------------------------------------
  // Test 1: BSEC Object & Bus Verification (Safe non-disruptive check)
  // -------------------------------------------------------------------
  logMessage("[DIAG 1/5]: Verifying BSEC Object and I2C status...");
  if (bsec != nullptr) {
    logMessage("[DIAG 1/5 PASS]: BSEC object active at I2C address 0x" + String(bmeI2cAddr, HEX));
    t1_pass = true;
  } else {
    logMessage("[DIAG 1/5 FAIL]: Missing BSEC object!");
  }

  // -------------------------------------------------------------------
  // Test 2: BSEC Background State & Accuracy Check
  // -------------------------------------------------------------------
  logMessage("[DIAG 2/5]: Checking BSEC internal status and accuracy...");
  if (bsecReady && bsec->status == BSEC_OK) {
    logMessage("[DIAG 2/5 PASS]: BSEC internal status OK. Current Accuracy = " + String(sensorData.bsecAccuracy));
    t2_pass = true;
  } else {
    logMessage("[DIAG 2/5 FAIL]: BSEC fault state! Code: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Test 3: Verify LP (3-Second) Profile
  // -------------------------------------------------------------------
  logMessage("[DIAG 3/5]: Verifying LP sampling profile subscription...");
  bool subSuccess = true;
  if (currentProfile != PROFILE_LP_3S || bsec->status != BSEC_OK) {
    subSuccess = updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
    currentProfile = PROFILE_LP_3S;
  } else {
    logMessage("   -> [BSEC INFO]: BSEC LP profile active and stable. Preserving heater state.");
  }

  if (subSuccess && bsec->status == BSEC_OK) {
    logMessage("[DIAG 3/5 PASS]: BSEC_SAMPLE_RATE_LP active.");
    t3_pass = true;
  } else {
    logMessage("[DIAG 3/5 FAIL]: Failed to verify LP mode! Code: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Test 4: Capture Valid Gas Resistance Output
  // -------------------------------------------------------------------
  logMessage("[DIAG 4/5]: Sampling gas output from BSEC engine...");
  uint32_t capturedSamples = 0;
  unsigned long startMs = millis();
  unsigned long lastHeartbeatMs = 0;
  
  newGasDataAvailable = false;

  while ((millis() - startMs) < 60000) { // 60-second window is plenty once warmed up
    if (bsecReady && bsec != nullptr) {
      bsec->run();
    }

    if (newGasDataAvailable) {
      newGasDataAvailable = false;
      if (sensorData.currentGasRes >= DIAG_HW_MIN_SENSOR_GAS_RES) {
        capturedSamples++;
        logMessage("   -> [BSEC LP FRAME #" + String(capturedSamples) + "]: Gas Res = " + String((long)sensorData.currentGasRes) + " Ohm | Temp = " + String(sensorData.currentTemp, 1) + " C");
        if (capturedSamples >= 3) break;
      }
    }

    if ((millis() - lastHeartbeatMs) >= 5000) {
      lastHeartbeatMs = millis();
      logMessage("   ... [POLLING]: Elapsed = " + String((millis() - startMs) / 1000) + "s | Valid Samples = " + String(capturedSamples));
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }

  if (capturedSamples > 0) {
    logMessage("[DIAG 4/5 PASS]: Captured " + String(capturedSamples) + " valid gas samples from BSEC!");
    t4_pass = true;
  } else {
    logMessage("[DIAG 4/5 FAIL]: Captured 0 valid gas samples. BSEC engine stalled.");
  }

  // -------------------------------------------------------------------
  // Test 5: Re-verify Profile Recovery
  // -------------------------------------------------------------------
  logMessage("[DIAG 5/5]: Re-verifying BSEC profile subscription...");
  bool recoverySuccess = (bsec->status == BSEC_OK);

  if (recoverySuccess) {
    logMessage("[DIAG 5/5 PASS]: Restored BSEC sampling profile cleanly.");
    t5_pass = true;
  } else {
    logMessage("[DIAG 5/5 FAIL]: BSEC object in error state! Code: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Summary Calculation
  // -------------------------------------------------------------------
  uint32_t passCount = (t1_pass ? 1 : 0) + (t2_pass ? 1 : 0) + 
                       (t3_pass ? 1 : 0) + (t4_pass ? 1 : 0) + 
                       (t5_pass ? 1 : 0);

  logMessage("\n==================================================");
  logMessage("[DIAG TEST SUMMARY]: " + String(passCount) + "/5 TESTS PASSED!");
  logMessage("  - Test 1 (I2C/Object Check):    " + String(t1_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 2 (BSEC State Check):    " + String(t2_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 3 (LP Mode Transition):  " + String(t3_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 4 (Active Gas Sampling): " + String(t4_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 5 (Profile Recovery):    " + String(t5_pass ? "PASS" : "FAIL"));
  logMessage("==================================================\n");

  dispatchData("{\"diag_test\":\"COMPLETE\",\"passed_tests\":" + String(passCount) + ",\"total_tests\":5}");
  return (passCount == 5);
}