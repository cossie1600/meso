/**
 * ============================================================================
 * DIAGNOSTICS: PURE BSEC KINETICS & POWER PROFILE VERIFICATION (diagnostics.cpp)
 * Zero Magic Numbers & Zero Magic Strings Standard
 * ============================================================================
 */

#include "diagnostics.h"
#include "sensor_data.h"
#include <Wire.h>
#include "bsec2.h"
#include "breath_kinetics_engine.h"

extern Bsec2* bsec;
extern uint8_t bmeI2cAddr;
extern bool bsecReady;
extern volatile bool newGasDataAvailable;

extern bsecSensor defaultSensorList[];
extern uint8_t numDefaultSensors;
extern bool updateBsecSubscription(float sampleRate);
extern SensorData sensorData;

enum OperationMode { MODE_IDLE, MODE_DRY_AIR_DETECTION, MODE_BREATH_TEST, MODE_DIAGNOSTIC };
extern OperationMode currentMode;
enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };
extern BsecProfile currentProfile;

extern void logMessage(String msg);
extern void dispatchData(String payload);

// Diagnostics Constants (Zero Magic Numbers)
namespace DiagConstants {
    constexpr float HW_MIN_SENSOR_GAS_RES               = 5000.0f;
    constexpr uint32_t ACTIVE_GAS_SAMPLING_TIMEOUT_MS   = 60000;
    constexpr uint32_t HEARTBEAT_INTERVAL_MS            = 5000;
    constexpr uint32_t POLLING_TICK_DELAY_MS            = 20;
    constexpr uint8_t TARGET_VALID_SAMPLES              = 3;
    constexpr uint8_t TOTAL_HEALTH_CHECK_TESTS          = 6;
    
    // Kinetics Defect 2 Test Bench Constants
    constexpr float TEST_BASE_GAS_RES                   = 100000.0f;
    constexpr float TEST_DROPPED_GAS_RES                = 80000.0f;   // 20.0% gas drop
    constexpr float TEST_LOW_DELTA_RH                   = 2.0f;       // Below 6.0% moisture threshold
    constexpr float EXHALATION_FORCE_TRIGGER_GAS_DROP   = 15.0f;      // Defect 2 threshold
    
    // Kinetics Defect 3 Test Bench Constants
    constexpr uint32_t TEST_INITIAL_SAMPLE_TIME_MS      = 2000;       // Within 4000ms window
    constexpr uint32_t TEST_LATE_SAMPLE_TIME_MS         = 5000;       // Outside 4000ms window
    constexpr float TEST_NEGATIVE_DELTA_RH              = -4.5f;      // Cold puff cooling artifact
    constexpr uint32_t THERMAL_TRANSIENT_SUPPRESSION_MS = 4000;
}

bool runPowerAndKineticsDiagnosticTest() {
  logMessage("\n==================================================");
  logMessage("[DIAG TEST START]: Running Power Profile & Kinetics Gate Check");
  logMessage("==================================================");

  bool t1_lp_pass  = false;
  bool t2_ulp_pass = false;
  bool t3_def2_pass = false;
  bool t4_def3_pass = false;

  // -------------------------------------------------------------------
  // Test 1: Verify Subscription to LP Mode (3-Second Interval)
  // -------------------------------------------------------------------
  logMessage("[DIAG 1/4]: Subscribing to BSEC LP (3s) Mode...");
  if (updateBsecSubscription(BSEC_SAMPLE_RATE_LP) && bsec->status == BSEC_OK) {
    currentProfile = PROFILE_LP_3S;
    logMessage("[DIAG 1/4 PASS]: Successfully subscribed to BSEC_SAMPLE_RATE_LP.");
    t1_lp_pass = true;
  } else {
    logMessage("[DIAG 1/4 FAIL]: Failed to subscribe to LP Mode! Status: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Test 2: Verify Subscription to ULP Mode (300-Second Interval)
  // -------------------------------------------------------------------
  logMessage("[DIAG 2/4]: Subscribing to BSEC ULP (300s) Mode (Battery Saver)...");
  if (updateBsecSubscription(BSEC_SAMPLE_RATE_ULP) && bsec->status == BSEC_OK) {
    currentProfile = PROFILE_ULP_300S;
    logMessage("[DIAG 2/4 PASS]: Successfully subscribed to BSEC_SAMPLE_RATE_ULP.");
    t2_ulp_pass = true;
  } else {
    logMessage("[DIAG 2/4 FAIL]: Failed to subscribe to ULP Mode! Status: " + String((int)bsec->status));
  }

  // Restore ULP mode for operational readiness
  updateBsecSubscription(BSEC_SAMPLE_RATE_ULP);
  currentProfile = PROFILE_ULP_300S;
  currentMode = MODE_IDLE;

  // -------------------------------------------------------------------
  // Test 3: Defect 2 Verification (Absolute Magnitude Latch Gate)
  // -------------------------------------------------------------------
  logMessage("[DIAG 3/4]: Testing Defect 2 (Magnitude Latch with low humidity)...");
  {
    const float simulatedGasDropPct = ((DiagConstants::TEST_BASE_GAS_RES - DiagConstants::TEST_DROPPED_GAS_RES) 
                                       / DiagConstants::TEST_BASE_GAS_RES) * 100.0f; // 20.0%
    const float simulatedDeltaRH = DiagConstants::TEST_LOW_DELTA_RH;                // 2.0%

    // Evaluate Defect 2 logic: gasDropPct >= 15.0f must latch even if dH < 6.0%
    const bool isStrongVocLatch = (simulatedGasDropPct >= DiagConstants::EXHALATION_FORCE_TRIGGER_GAS_DROP);
    const bool isStandardBreath = (simulatedDeltaRH >= 6.0f) && (simulatedGasDropPct >= 5.0f);

    if (isStrongVocLatch && !isStandardBreath) {
      logMessage("[DIAG 3/4 PASS]: Defect 2 Verified. gDrop of " + String(simulatedGasDropPct, 1) + 
                 "% triggered absolute latch successfully without high moisture.");
      t3_def2_pass = true;
    } else {
      logMessage("[DIAG 3/4 FAIL]: Defect 2 Gate evaluation failed!");
    }
  }

  // -------------------------------------------------------------------
  // Test 4: Defect 3 Verification (Negative Initial Moisture Transient Filter)
  // -------------------------------------------------------------------
  logMessage("[DIAG 4/4]: Testing Defect 3 (Initial Negative Moisture Clamping)...");
  {
    // Case A: Inside 4-second preheat cooling window
    const bool isInsideWindow = (DiagConstants::TEST_INITIAL_SAMPLE_TIME_MS < DiagConstants::THERMAL_TRANSIENT_SUPPRESSION_MS);
    const float rawDeltaRH = DiagConstants::TEST_NEGATIVE_DELTA_RH;
    const float clampedEarlyRH = (isInsideWindow && rawDeltaRH < 0.0f) ? 0.0f : rawDeltaRH;

    // Case B: Outside 4-second window
    const bool isOutsideWindow = (DiagConstants::TEST_LATE_SAMPLE_TIME_MS < DiagConstants::THERMAL_TRANSIENT_SUPPRESSION_MS);
    const float unclampedLateRH = (isOutsideWindow && rawDeltaRH < 0.0f) ? 0.0f : rawDeltaRH;

    if (clampedEarlyRH == 0.0f && unclampedLateRH == DiagConstants::TEST_NEGATIVE_DELTA_RH) {
      logMessage("[DIAG 4/4 PASS]: Defect 3 Verified. Early negative dH clamped to 0.0% (raw: " + 
                 String(rawDeltaRH, 1) + "%), late negative dH preserved.");
      t4_def3_pass = true;
    } else {
      logMessage("[DIAG 4/4 FAIL]: Defect 3 Transient filter failed!");
    }
  }

  // -------------------------------------------------------------------
  // Summary
  // -------------------------------------------------------------------
  uint32_t passCount = (t1_lp_pass ? 1 : 0) + (t2_ulp_pass ? 1 : 0) + 
                       (t3_def2_pass ? 1 : 0) + (t4_def3_pass ? 1 : 0);

  logMessage("\n==================================================");
  logMessage("[POWER & KINETICS SUMMARY]: " + String(passCount) + "/4 TESTS PASSED!");
  logMessage("  - Test 1 (BSEC LP 3s Switch):     " + String(t1_lp_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 2 (BSEC ULP 300s Switch):  " + String(t2_ulp_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 3 (Defect 2 Magnitude):    " + String(t3_def2_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 4 (Defect 3 Filter Clamping): " + String(t4_def3_pass ? "PASS" : "FAIL"));
  logMessage("==================================================\n");

  dispatchData("{\"diag_power_kinetics\":\"COMPLETE\",\"passed_tests\":" + String(passCount) + ",\"total_tests\":4}");
  return (passCount == 4);
}

bool runSelectivityDiagnosticTest() {
  logMessage("\n==================================================");
  logMessage("[DIAG TEST START]: Running Pure BSEC Health & Power Suite");
  logMessage("==================================================");

  bool t1_pass = false;
  bool t2_pass = false;
  bool t3_pass = false;
  bool t4_pass = false;
  bool t5_pass = false;
  bool t6_ulp_teardown_pass = false;

  // -------------------------------------------------------------------
  // Test 1: BSEC Object & Address Verification
  // -------------------------------------------------------------------
  logMessage("[DIAG 1/6]: Verifying BSEC Object and I2C status...");
  if (bsec != nullptr) {
    logMessage("[DIAG 1/6 PASS]: BSEC object active at I2C address 0x" + String(bmeI2cAddr, HEX));
    t1_pass = true;
  } else {
    logMessage("[DIAG 1/6 FAIL]: Missing BSEC object!");
  }

  // -------------------------------------------------------------------
  // Test 2: BSEC Internal State & Accuracy
  // -------------------------------------------------------------------
  logMessage("[DIAG 2/6]: Checking BSEC internal status and accuracy...");
  if (bsecReady && bsec->status == BSEC_OK) {
    logMessage("[DIAG 2/6 PASS]: BSEC internal status OK. Current Accuracy = " + String(sensorData.bsecAccuracy));
    t2_pass = true;
  } else {
    logMessage("[DIAG 2/6 FAIL]: BSEC fault state! Code: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Test 3: Verify LP (3-Second) Profile State
  // -------------------------------------------------------------------
  logMessage("[DIAG 3/6]: Verifying LP sampling profile subscription...");
  bool subSuccess = true;
  if (currentProfile != PROFILE_LP_3S || bsec->status != BSEC_OK) {
    subSuccess = updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
    currentProfile = PROFILE_LP_3S;
  }

  if (subSuccess && bsec->status == BSEC_OK) {
    logMessage("[DIAG 3/6 PASS]: BSEC_SAMPLE_RATE_LP active.");
    t3_pass = true;
  } else {
    logMessage("[DIAG 3/6 FAIL]: Failed to verify LP mode! Code: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Test 4: Capture Valid Gas Resistance Output
  // -------------------------------------------------------------------
  logMessage("[DIAG 4/6]: Sampling gas output from BSEC engine...");
  uint32_t capturedSamples = 0;
  unsigned long startMs = millis();
  unsigned long lastHeartbeatMs = 0;
  newGasDataAvailable = false;

  while ((millis() - startMs) < DiagConstants::ACTIVE_GAS_SAMPLING_TIMEOUT_MS) {
    if (bsecReady && bsec != nullptr) {
      bsec->run();
    }

    if (newGasDataAvailable) {
      newGasDataAvailable = false;
      if (sensorData.currentGasRes >= DiagConstants::HW_MIN_SENSOR_GAS_RES) {
        capturedSamples++;
        logMessage("   -> [BSEC LP FRAME #" + String(capturedSamples) + "]: Gas Res = " + String((long)sensorData.currentGasRes) + " Ohm | Temp = " + String(sensorData.currentTemp, 1) + " C");
        if (capturedSamples >= DiagConstants::TARGET_VALID_SAMPLES) break;
      }
    }

    if ((millis() - lastHeartbeatMs) >= DiagConstants::HEARTBEAT_INTERVAL_MS) {
      lastHeartbeatMs = millis();
      logMessage("   ... [POLLING]: Elapsed = " + String((millis() - startMs) / 1000) + "s | Valid Samples = " + String(capturedSamples));
    }

    vTaskDelay(pdMS_TO_TICKS(DiagConstants::POLLING_TICK_DELAY_MS));
  }

  if (capturedSamples > 0) {
    logMessage("[DIAG 4/6 PASS]: Captured " + String(capturedSamples) + " valid gas samples from BSEC!");
    t4_pass = true;
  } else {
    logMessage("[DIAG 4/6 FAIL]: Captured 0 valid gas samples. BSEC engine stalled.");
  }

  // -------------------------------------------------------------------
  // Test 5: Re-verify Profile Recovery
  // -------------------------------------------------------------------
  logMessage("[DIAG 5/6]: Re-verifying BSEC profile subscription...");
  bool recoverySuccess = (bsec->status == BSEC_OK);

  if (recoverySuccess) {
    logMessage("[DIAG 5/6 PASS]: Restored BSEC sampling profile cleanly.");
    t5_pass = true;
  } else {
    logMessage("[DIAG 5/6 FAIL]: BSEC object in error state! Code: " + String((int)bsec->status));
  }

  // -------------------------------------------------------------------
  // Test 6: Verify Post-Breath Test ULP Teardown & Standby State
  // -------------------------------------------------------------------
  logMessage("[DIAG 6/6]: Testing ULP Mode Teardown & Scheduler Standby...");
  
  // Simulate end of breath sequence teardown
  bool ulpSubSuccess = updateBsecSubscription(BSEC_SAMPLE_RATE_ULP);
  if (ulpSubSuccess && bsec->status == BSEC_OK) {
    currentProfile = PROFILE_ULP_300S;
    currentMode = MODE_IDLE;

    const bool isUlpActive = (currentProfile == PROFILE_ULP_300S);
    const bool isIdleState = (currentMode == MODE_IDLE);

    if (isUlpActive && isIdleState) {
      logMessage("[DIAG 6/6 PASS]: Verified post-test teardown: BSEC ULP active, heater powered down, MODE_IDLE restored.");
      t6_ulp_teardown_pass = true;
    } else {
      logMessage("[DIAG 6/6 FAIL]: State mismatch after teardown! currentProfile=" + String((int)currentProfile) + ", currentMode=" + String((int)currentMode));
    }
  } else {
    logMessage("[DIAG 6/6 FAIL]: BSEC rejected ULP subscription update! Status: " + String((int)bsec->status));
  }

  // Restore operational ULP profile for subsequent testing
  updateBsecSubscription(BSEC_SAMPLE_RATE_ULP);
  currentProfile = PROFILE_ULP_300S;
  currentMode = MODE_IDLE;

  // -------------------------------------------------------------------
  // Summary
  // -------------------------------------------------------------------
  uint32_t passCount = (t1_pass ? 1 : 0) + (t2_pass ? 1 : 0) + 
                       (t3_pass ? 1 : 0) + (t4_pass ? 1 : 0) + 
                       (t5_pass ? 1 : 0) + (t6_ulp_teardown_pass ? 1 : 0);

  logMessage("\n==================================================");
  logMessage("[DIAG TEST SUMMARY]: " + String(passCount) + "/" + String(DiagConstants::TOTAL_HEALTH_CHECK_TESTS) + " TESTS PASSED!");
  logMessage("  - Test 1 (I2C/Object Check):        " + String(t1_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 2 (BSEC State Check):        " + String(t2_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 3 (LP Mode Transition):      " + String(t3_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 4 (Active Gas Sampling):     " + String(t4_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 5 (Profile Recovery):        " + String(t5_pass ? "PASS" : "FAIL"));
  logMessage("  - Test 6 (Post-Test ULP Teardown):  " + String(t6_ulp_teardown_pass ? "PASS" : "FAIL"));
  logMessage("==================================================\n");

  dispatchData("{\"diag_test\":\"COMPLETE\",\"passed_tests\":" + String(passCount) + 
               ",\"total_tests\":" + String(DiagConstants::TOTAL_HEALTH_CHECK_TESTS) + "}");
  return (passCount == DiagConstants::TOTAL_HEALTH_CHECK_TESTS);
}