/**
 * ============================================================================
 * FIRMWARE 2: PURE BSEC KINETICS ARCHITECTURE
 * ============================================================================
 */

#include <Wire.h>
#include <FS.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>

#include "esp_sleep.h"
#include "bsec2.h"
#include "sensor_data.h"
#include "diagnostics.h"
#include "bsec_iaq.h"
#include "breath_kinetics_engine.h"
#include "battery_monitor.h"

#include "hal/usb_serial_jtag_ll.h"
#include "esp_private/usb_console.h"

const uint8_t bsec_config_iaq[] = {
#include "./bsec_selectivity.txt"
};

#define ENABLE_SERIAL_LOGS true
#define ENABLE_VERBOSE_DEBUG false

#define VERBOSE_LOG(x) do { \
  if (ENABLE_VERBOSE_DEBUG) { \
    logMessage(x); \
  } \
} while(0)

// Hardware Pin Assignments
#define I2C_SDA 6
#define I2C_SCL 7
#define SERVICE_UUID "4fa215f0-0001-4b0e-b682-1a4c70f3a601"
#define CHARACTERISTIC_UUID "4fa215f0-0002-4b0e-b682-1a4c70f3a601"

constexpr const char *DEVICE_BASE_NAME = "Meso Nose";
String Device_Name = String(DEVICE_BASE_NAME);

constexpr const char *OFFLINE_FILE_PATH = "/offline_data.json";
constexpr const char *LITTLEFS_MOUNT_POINT = "/littlefs";

constexpr unsigned long FIVE_MINUTES_IN_MS = 300000UL;
constexpr size_t MAX_OFFLINE_FILE_SIZE_BYTES = 200000;
constexpr uint32_t SERIAL_BAUD_RATE = 115200;
constexpr uint32_t I2C_CLOCK_SPEED_HZ = 100000;
constexpr uint32_t I2C_BUS_TIMEOUT_MS = 1000;
constexpr uint32_t SERIAL_AUTO_FLUSH_TIMEOUT_MS = 250UL;

constexpr uint16_t BLE_ADV_FAST_MIN_INTERVAL_UNITS = 160;
constexpr uint16_t BLE_ADV_FAST_MAX_INTERVAL_UNITS = 320;
constexpr uint16_t BLE_ADV_ULP_MIN_INTERVAL_UNITS = 1600;
constexpr uint16_t BLE_ADV_ULP_MAX_INTERVAL_UNITS = 3200;
constexpr unsigned long FAST_ADV_BURST_WINDOW_MS = 30000UL;
constexpr uint32_t BLE_FLUSH_DELAY_MS = 30;

constexpr uint32_t NOTIFY_ULP_INTERVAL_MS = 300000;
constexpr uint32_t NOTIFY_LP_INTERVAL_MS  = 3000;
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS = 30000;
constexpr uint32_t BREATH_SENSING_WINDOW_MS = 10000; 
constexpr uint32_t RECOVERY_SENSING_WINDOW_MS = 15000; 
constexpr uint32_t POLL_TICK_DELAY_MS = 20;

constexpr uint8_t BASELINE_TARGET_SAMPLE_COUNT = 3; 
constexpr uint32_t BASELINE_CAPTURE_TIMEOUT_MS = 15000UL;
constexpr float HW_MIN_SENSOR_GAS_RES = 5000.0f;

constexpr float PARTIAL_EXHALATION_MIN_DELTA_RH_PCT = 0.8f;
constexpr float EXHALATION_MIN_MOISTURE_DELTA_RH_PCT = 6.0f;
constexpr float EXHALATION_MIN_GAS_DROP_PCT          = 5.0f;
constexpr float EXHALATION_FORCE_TRIGGER_GAS_DROP_PCT = 15.0f;
constexpr uint32_t THERMAL_TRANSIENT_SUPPRESSION_MS   = 4000;

constexpr float T50_CALCULATION_FACTOR = 0.5f;
constexpr float HIGH_BASELINE_HUMIDITY_THRESHOLD_PCT = 80.0f;
constexpr float MILLISECONDS_TO_SECONDS_CONVERSION = 1000.0f;

constexpr const char *STATE_EXHALATION_TOO_WEAK = "EXHALATION_TOO_WEAK";
constexpr const char *STATE_TRY_AGAIN_LATER = "TRY_AGAIN_LATER";
constexpr const char *STATE_READY_PLEASE_BLOW = "READY_PLEASE_BLOW";
constexpr const char *STATE_TESTING_SENSING_BREATH = "TESTING_SENSING_BREATH";
constexpr const char *STATE_TIMEOUT = "TIMEOUT";
constexpr const char *STATUS_BREATH_TEST_STARTED = "BREATH_TEST_STARTED";
constexpr const char *STATUS_BREATH_TEST_COMPLETE = "BREATH_TEST_COMPLETE";

constexpr const char *RESULT_NONE = "NONE";

constexpr const char *CMD_BREATH_SHORT = "3";
constexpr const char *CMD_BREATH_CHAR = "b";
constexpr const char *CMD_BREATH_FULL = "breath";
constexpr const char *CMD_DIAG_POWER_KINETICS = "test_power_kinetics";
constexpr const char *CMD_DIAG_POWER_NUMERIC  = "98";
constexpr const char *CMD_DIAG_SELECTIVITY = "test_selectivity";
constexpr const char *CMD_DIAG_NUMERIC = "99";

constexpr const char *CMD_SET_ACTIVE_SAMPLING = "set_active_sampling_mode";
constexpr const char *CMD_SET_ULP_SAMPLING    = "set_ultra_low_sampling_mode";
constexpr const char *STATE_PROFILE_LP        = "PROFILE_LP";
constexpr const char *STATE_PROFILE_ULP       = "PROFILE_ULP";



namespace MesoPowerConfig {
  constexpr int8_t BSEC_STATUS_CONFIG_FAIL = 14;
  constexpr uint32_t CPU_LOW_POWER_FREQ_MHZ = 80; // Stable APB clock for NimBLE radio
  constexpr int CPU_FREQ_MAX_MHZ = 80;
  constexpr int CPU_FREQ_MIN_MHZ = 10;
  constexpr bool ENABLE_AUTOMATIC_LIGHT_SLEEP = true;
  
  // Timed light sleep duration during idle (20ms) 
  constexpr uint64_t IDLE_LIGHT_SLEEP_DURATION_US = 20000ULL; // 20 
  constexpr uint32_t BOOT_STABILIZATION_GRACE_MS    = 5000UL;   // 5s grace window
  constexpr uint32_t BLE_HANDSHAKE_STABILIZATION_MS = 5000UL;   // 5s window for GATT discovery
}

namespace MesoPowerLogs {
  constexpr const char *PM_LIGHT_SLEEP_ACTIVE = "[PM]: Automatic Light Sleep & DFS initialized successfully.";
  constexpr const char *PM_INIT_SUCCESS       = "[PM]: Dynamic frequency scaling active (80MHz/10MHz).";
  constexpr const char *PM_INIT_FAILED        = "[PM ERROR]: esp_pm_configure failed.";
  constexpr const char *BSEC_CLEAN_ULP_INIT   = "[BSEC]: Default config active for ULP (300s) mode.";
  constexpr const char *BSEC_CUSTOM_LP_INIT   = "[BSEC]: Custom selectivity config active for LP (3s) mode.";
  constexpr const char *BSEC_SUB_FAIL         = "[BSEC ERROR]: updateSubscription failed: ";
  constexpr const char *CPU_FREQ_CONFIG_SUCCESS = "[POWER]: CPU clock scaled down to 80 MHz (Low Power Mode).";
  constexpr const char *CPU_FREQ_CONFIG_FAIL    = "[POWER ERROR]: Failed to adjust CPU clock frequency.";
  constexpr const char *LIGHT_SLEEP_ENGINE_ACTIVE = "[POWER]: Explicit Timed Light Sleep active (20ms ticks).";
}

namespace BleConnParams {
  // Apple Accessory Design Guidelines Compliant Intervals (units of 1.25ms and 10ms)
  constexpr uint16_t BLE_CONN_MIN_INTERVAL_UNITS         = 400; // 500 ms (400 * 1.25 ms)
  constexpr uint16_t BLE_CONN_MAX_INTERVAL_UNITS         = 800; // 1000 ms (800 * 1.25 ms)
  constexpr uint16_t BLE_CONN_SLAVE_LATENCY              = 4;   // Skip up to 4 intervals when idle
  constexpr uint16_t BLE_CONN_SUPERVISION_TIMEOUT_UNITS  = 600; // 6000 ms (600 * 10 ms)
}

namespace MesoLogStrings {
  constexpr const char *LOG_BLE_CONN_UPDATE_REQ   = "[BLE CONNECT]: Central connected. Negotiated 500-1000ms low-power interval.";
  constexpr const char *LOG_BLE_RESTORE_ULP       = "[BLE CONNECT]: Connection established. Maintained ULP mode.";
  constexpr const char *LOG_BSEC_INIT_BOOT_ULP   = "[BSEC INIT]: Engine Initialized & Booted Cleanly into ULP (300s) Mode.";
  constexpr const char *LOG_BSEC_CONFIG_WARN      = "[BSEC WARN]: Custom setConfig failed (Code: ";
  constexpr const char *LOG_BSEC_INIT_SUCCESS     = "[BSEC INIT]: Engine Initialized & Resting in ULP Mode.";
  constexpr const char *LOG_BSEC_INIT_FAIL        = "[BSEC ERROR]: BSEC Initialization Failed!";
}

unsigned long connectionEstablishedTimeMs = 0;
bool connectionParamsUpdated = false;

bool systemReady = false;
enum OperationMode { MODE_IDLE, MODE_BREATH_TEST, MODE_DIAGNOSTIC };
enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };

OperationMode currentMode = MODE_IDLE;
BsecProfile currentProfile = PROFILE_OFF;

bool dryAirActive = false;
bool deviceConnected = false;
bool bsecReady = false;
volatile bool newGasDataAvailable = false;
volatile bool pendingBreathCommand = false;
volatile bool pendingDiagCommand = false;
volatile bool pendingFlush = false;
uint8_t bmeI2cAddr = BME68X_I2C_ADDR_HIGH;

unsigned long lastOfflineWriteTime = 0;
float accumTemp = 0.0f, accumHumidity = 0.0f, accumPressure = 0.0f, accumGasRes = 0.0f;
int accumCount = 0;
constexpr size_t CMD_BUF_SIZE = 32;
char pendingCmdBuf[CMD_BUF_SIZE] = { 0 };
volatile bool hasPendingCommand = false;

SensorData sensorData;

bsecSensor defaultSensorList[] = {
  BSEC_OUTPUT_RAW_TEMPERATURE,
  BSEC_OUTPUT_RAW_HUMIDITY,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
  BSEC_OUTPUT_RAW_PRESSURE
};
uint8_t numDefaultSensors = sizeof(defaultSensorList) / sizeof(bsecSensor);

Bsec2 *bsec = nullptr;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

void dispatchData(String payload);
void logMessage(String msg);
uint8_t readBatteryPercentage();
void softResetBme688Sensor();
void resetToDefaultMode();

void logMessage(String msg) {
#if ENABLE_SERIAL_LOGS
  Serial.println(msg);
#endif
  if (deviceConnected && pCharacteristic) {
    String bleLog = "[LOG]: " + msg + "\n";
    pCharacteristic->setValue((uint8_t *)bleLog.c_str(), bleLog.length());
    pCharacteristic->notify();
  }
}

bool updateBsecSubscription(float sampleRate) {
  if (!bsecReady || bsec == nullptr) return false;

  // 1. Non-destructively clear existing scheduler entries without deleting the object
  bsec->updateSubscription(nullptr, 0, 0.0f);

  if (sampleRate == BSEC_SAMPLE_RATE_LP) {
    // Apply custom selectivity configuration for 3s active sensing
    bsec->setConfig(bsec_config_iaq);
    bool success = bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_LP);
    if (success) {
      currentProfile = PROFILE_LP_3S;
      logMessage(String(MesoPowerLogs::BSEC_CUSTOM_LP_INIT));
    } else {
      logMessage(String(MesoPowerLogs::BSEC_SUB_FAIL) + String(bsec->status));
    }
    return success;
  }

  if (sampleRate == BSEC_SAMPLE_RATE_ULP) {
    // Re-initialize driver state cleanly without destroying the C++ instance
    bsec->begin(bmeI2cAddr, Wire);
    bsec->attachCallback(newDataCallback);
    bool success = bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_ULP);
    if (success) {
      currentProfile = PROFILE_ULP_300S;
      logMessage(String(MesoPowerLogs::BSEC_CLEAN_ULP_INIT));
    } else {
      logMessage(String(MesoPowerLogs::BSEC_SUB_FAIL) + String(bsec->status));
    }
    return success;
  }

  return bsec->updateSubscription(defaultSensorList, numDefaultSensors, sampleRate);
}

void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsecInst) {
  if ((data.status & BME68X_GASM_VALID_MSK) && data.gas_resistance > 0.0f) {
    sensorData.currentGasRes = data.gas_resistance;
    newGasDataAvailable = true;
  }

  if (!outputs.nOutputs) return;

  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    const bsecData output = outputs.output[i];
    switch (output.sensor_id) {
      case BSEC_OUTPUT_RAW_TEMPERATURE:
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
        if (output.signal > -40.0f && output.signal < 85.0f && output.signal != 0.0f) {
          sensorData.currentTemp = output.signal;
        }
        break;
      case BSEC_OUTPUT_RAW_HUMIDITY:
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:
        sensorData.currentHumidity = output.signal;
        break;
      case BSEC_OUTPUT_RAW_PRESSURE:
        sensorData.currentPressure = output.signal / 100.0f; // Pa to hPa
        break;
    }
  }
}

bool readLowLevelScanFrame(float &outGasRes, uint8_t &outStep) {
  if (bsecReady && bsec) bsec->run();
  if (newGasDataAvailable) {
    newGasDataAvailable = false;
    outGasRes = sensorData.currentGasRes;
    outStep = 0;
    return true;
  }
  return false;
}

bool readBsecFrame(float &outGasRes) {
  if (bsecReady && bsec) bsec->run();
  if (newGasDataAvailable) {
    newGasDataAvailable = false;
    outGasRes = sensorData.currentGasRes;
    return true;
  }
  return false;
}

bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp) {
  logMessage("[PREPARE BASELINE]: Capturing baseline samples in BSEC LP Mode...");
  if (currentProfile != PROFILE_LP_3S) {
    if (!updateBsecSubscription(BSEC_SAMPLE_RATE_LP)) {
      logMessage("[PREPARE BASELINE ERROR]: Failed to transition to LP Mode!");
      return false;
    }
    currentProfile = PROFILE_LP_3S;
  }
  
  float sumRes = 0.0f, sumHumidity = 0.0f, sumTemp = 0.0f;
  uint8_t validCount = 0;
  uint32_t startMs = millis();

  while (validCount < BASELINE_TARGET_SAMPLE_COUNT && ((millis() - startMs) < BASELINE_CAPTURE_TIMEOUT_MS)) {
    float rawRes = 0.0f;
    if (readBsecFrame(rawRes)) {
      if (rawRes >= HW_MIN_SENSOR_GAS_RES) {
        sumRes += rawRes; 
        sumHumidity += sensorData.currentHumidity;
        sumTemp += sensorData.currentTemp; 
        validCount++;
        VERBOSE_LOG("[BASELINE SAMPLE #" + String(validCount) + "]: GasRes=" + String((long)rawRes) + 
                    " Ohm | RH=" + String(sensorData.currentHumidity, 1) + 
                    "% | Temp=" + String(sensorData.currentTemp, 1) + "C");
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  if (validCount == 0) {
    logMessage("[PREPARE BASELINE ERROR]: Zero valid samples collected during baseline window!");
    return false;
  }

  outBaselineRes = sumRes / validCount;
  outBaseHumidity = sumHumidity / validCount;
  outBaseTemp = sumTemp / validCount;

  logMessage("[BASELINE CAPTURED]: R_base=" + String((long)outBaselineRes) + 
              " Ohm | Base_RH=" + String(outBaseHumidity, 1) + 
              "% | Base_Temp=" + String(outBaseTemp, 1) + "C");
  return true;
}

bool waitForBreathExhalation(float baseGasRes, float baseHumidity, float baseTemp,
                             float &outMinRes, float &outMaxDeltaRH) {
  dispatchData("{\"state\":\"" + String(STATE_READY_PLEASE_BLOW) + "\"}");
  logMessage("[WAIT EXHALATION]: Waiting for breath exhalation blow (Timeout: " + String(BREATH_WAIT_TIMEOUT_MS / 1000) + "s)...");
  
  uint32_t startMs = millis();
  outMaxDeltaRH = 0.0f; 

  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    float currentGasRes = 0.0f;
    if (readBsecFrame(currentGasRes)) {
      float rawDeltaRH = sensorData.currentHumidity - baseHumidity;
      float gasDropPct = (baseGasRes > 0.0f) ? (((baseGasRes - currentGasRes) / baseGasRes) * 100.0f) : 0.0f;

      // Defect 3 Fix: Suppress initial negative cooling transient within the first 4 seconds
      const bool isInsideThermalTransientWindow = ((millis() - startMs) < THERMAL_TRANSIENT_SUPPRESSION_MS);
      float effectiveDeltaRH = (isInsideThermalTransientWindow && rawDeltaRH < 0.0f) ? 0.0f : rawDeltaRH;

      if (currentGasRes < outMinRes) outMinRes = currentGasRes;
      if (effectiveDeltaRH > outMaxDeltaRH) outMaxDeltaRH = effectiveDeltaRH;

      // Telemetry dispatch
      dispatchData("{\"dH\":" + String(rawDeltaRH, 1) + ",\"gDrop\":" + String(gasDropPct, 1) + "}");

      VERBOSE_LOG("[BLOW MONITOR]: GasRes=" + String((long)currentGasRes) + 
                  " Ohm | gDrop=" + String(gasDropPct, 1) + 
                  "% | dH=" + String(rawDeltaRH, 1) + "%");

      // Condition A: Standard balanced breath (Moderate VOC drop + realistic moisture spike)
      const bool isStandardBreath = (effectiveDeltaRH >= EXHALATION_MIN_MOISTURE_DELTA_RH_PCT) && 
                                    (gasDropPct >= EXHALATION_MIN_GAS_DROP_PCT);

      // Condition B: High ambient background humidity (Room RH > 80%)
      const bool isHighAmbientHum = (baseHumidity >= HIGH_BASELINE_HUMIDITY_THRESHOLD_PCT) && 
                                    (gasDropPct >= EXHALATION_MIN_GAS_DROP_PCT);

      // Defect 2 Fix: Absolute VOC magnitude latch
      // If VOCs drop heavily (>= 15%), it is unmistakably an exhalation directly into the sensor
      const bool isStrongVocLatch = (gasDropPct >= EXHALATION_FORCE_TRIGGER_GAS_DROP_PCT);

      if (isStrongVocLatch) {
        logMessage("[BLOW TRIGGERED]: Absolute VOC drop latch met (" + String(gasDropPct, 1) + "% >= " + 
                   String(EXHALATION_FORCE_TRIGGER_GAS_DROP_PCT, 1) + "%)!");
        return true;
      }

      if (isStandardBreath) {
        logMessage("[BLOW TRIGGERED]: Valid moisture spike and gas drop detected!");
        return true;
      }

      if (isHighAmbientHum) {
        logMessage("[BLOW TRIGGERED]: High ambient humidity blow condition detected!");
        return true;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  logMessage("[BLOW TIMEOUT]: Exhalation wait window expired without blow detection.");
  return false;
}

void captureBreathSensingWindow(float baseRes, float baseHumidity,
                                float &outMinRes, float &outMaxDeltaRH) {
  dispatchData("{\"state\":\"" + String(STATE_TESTING_SENSING_BREATH) + "\"}");
  logMessage("[SENSING WINDOW]: Sampling breath kinetics window (" + String(BREATH_SENSING_WINDOW_MS / 1000) + "s)...");
  
  uint32_t windowStartMs = millis();
  outMinRes = baseRes;

  while ((millis() - windowStartMs) < BREATH_SENSING_WINDOW_MS) {
    float currentGasRes = 0.0f;
    if (readBsecFrame(currentGasRes)) {
      float deltaRH = sensorData.currentHumidity - baseHumidity;
      if (currentGasRes > HW_MIN_SENSOR_GAS_RES && currentGasRes < outMinRes) outMinRes = currentGasRes;
      if (deltaRH > outMaxDeltaRH) outMaxDeltaRH = deltaRH;

      VERBOSE_LOG("[SENSING FRAME]: Current R=" + String((long)currentGasRes) + 
                  " Ohm | R_min=" + String((long)outMinRes) + 
                  " Ohm | Peak dH=" + String(outMaxDeltaRH, 1) + "%");
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
  logMessage("[SENSING COMPLETE]: Final R_min=" + String((long)outMinRes) + " Ohm");
}

void captureRecoveryWindow(float minRes, float baseRes, float &outRecoveryLag) {
  dispatchData("{\"state\":\"RECOVERING_CALCULATING_T50\"}");
  
  float target50 = minRes + T50_CALCULATION_FACTOR * (baseRes - minRes);
  outRecoveryLag = SensorConstants::RECOVERY_LAG_TIMEOUT_SEC; 
  
  logMessage("[KINETICS T50 START]: R_base=" + String((long)baseRes) + 
              " Ohm | R_min=" + String((long)minRes) + 
              " Ohm | Target R_50%=" + String((long)target50) + " Ohm");
  
  uint32_t startMs = millis();
  while ((millis() - startMs) < RECOVERY_SENSING_WINDOW_MS) {
    float rGas = 0.0f;
    if (readBsecFrame(rGas)) {
      VERBOSE_LOG("[T50 RECOVERY PURGE]: R_current=" + String((long)rGas) + 
                  " Ohm | Target R_50%=" + String((long)target50) + " Ohm");
      if (rGas >= target50) {
        outRecoveryLag = (millis() - startMs) / MILLISECONDS_TO_SECONDS_CONVERSION;
        logMessage("[T50 RECOVERY TARGET MET]: Reached 50% baseline recovery at " + String(outRecoveryLag, 2) + "s!");
        break;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
  if (outRecoveryLag >= SensorConstants::RECOVERY_LAG_TIMEOUT_SEC) {
    logMessage("[T50 RECOVERY TIMEOUT]: Gas sensor failed to reach 50% recovery target within window. Defaulting lag to " + String(outRecoveryLag, 1) + "s.");
  }
}

String evaluateBreathResultWrapper(float deltaDrop, float maxDeltaHumidity, float recoveryLagSec) {
  BreathResult result = evaluateBreathResult(deltaDrop, maxDeltaHumidity, recoveryLagSec);
  String resultStr = String(breathResultToString(result));
  
  logMessage("[EVALUATE KINETICS RESULT]: DeltaDrop=" + String(deltaDrop, 1) + 
              "% | Max_dRH=" + String(maxDeltaHumidity, 1) + 
              "% | T50_Lag=" + String(recoveryLagSec, 2) + 
              "s => PTC Result: " + resultStr);
  return resultStr;
}

void resetTestEvaluationData() {
  sensorData.deltaDrop = 0.0f;
  sensorData.recoveryLagSec = 0.0f;
  sensorData.rBreathMin = 0;
  sensorData.ptcResult = RESULT_NONE;
}

void processBreathTestResults(float baseRes, float minRes, float maxDeltaHumidity, float recoveryLag) {
  float deltaDrop = (baseRes > 0.0f) ? (((baseRes - minRes) / baseRes) * 100.0f) : 0.0f;
  if (deltaDrop < 0.0f) deltaDrop = 0.0f;

  sensorData.currentGasRes = minRes;
  sensorData.deltaDrop = deltaDrop;
  sensorData.rBreathMin = (long)minRes;
  sensorData.recoveryLagSec = recoveryLag;
  sensorData.ptcResult = evaluateBreathResultWrapper(deltaDrop, maxDeltaHumidity, recoveryLag);

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_COMPLETE) + "\"}");
  dispatchData(sensorData.toJsonString());
  resetTestEvaluationData();
}

void resetToULP() {
  updateBsecSubscription(BSEC_SAMPLE_RATE_ULP);
  currentProfile = PROFILE_ULP_300S;
}

void runBreathSequence() {
  logMessage("[SEQUENCE START]: Breath test sequence initiated (Pure BSEC LP).");

  resetTestEvaluationData();

  float ambientTemp = sensorData.currentTemp;
  float ambientRH = sensorData.currentHumidity;
  dryAirActive = false; 
  currentMode = MODE_BREATH_TEST;

  float baseRes = 0.0f, baseHumidity = ambientRH, baseTemp = ambientTemp;
  float maxDeltaRH = 0.0f;
  float recoveryLag = 0.0f;

  if (!prepareAndCaptureBaseline(baseRes, baseHumidity, baseTemp)) {
    logMessage("[SEQUENCE ABORTED]: Baseline capture failed!");
    resetToULP();
    currentMode = MODE_IDLE; // Added clean state reset
    return;
  }

  float minRes = baseRes;
  if (waitForBreathExhalation(baseRes, baseHumidity, baseTemp, minRes, maxDeltaRH)) {
    captureBreathSensingWindow(baseRes, baseHumidity, minRes, maxDeltaRH);
    captureRecoveryWindow(minRes, baseRes, recoveryLag);
    processBreathTestResults(baseRes, minRes, maxDeltaRH, recoveryLag);
  } else {
    const bool isWeakExhalationDetected = (maxDeltaRH >= PARTIAL_EXHALATION_MIN_DELTA_RH_PCT);

    if (isWeakExhalationDetected) {
      logMessage("[SEQUENCE RESULT]: Exhalation too weak detected.");
      dispatchData("{\"state\":\"" + String(STATE_EXHALATION_TOO_WEAK) + "\"}");
    } else {
      logMessage("[SEQUENCE RESULT]: Exhalation wait timed out.");
      dispatchData("{\"state\":\"" + String(STATE_TIMEOUT) + "\"}");
    }
  }
  
  resetToULP();
  currentMode = MODE_IDLE;
  logMessage("[SEQUENCE END]: Breath test complete. Restored BSEC LP mode.");
}

void executeDiagnosticSequence() {
  logMessage("[DIAG START]: Command 99 processed. Triggering Selectivity Self-Test...");
  currentMode = MODE_DIAGNOSTIC;
  runSelectivityDiagnosticTest();
  currentMode = MODE_IDLE;
  logMessage("[DIAG COMPLETE]: Self-test sequence finished.");
}

void saveOfflineData() {
  accumTemp += sensorData.currentTemp; 
  accumHumidity += sensorData.currentHumidity;
  accumPressure += sensorData.currentPressure; 
  accumGasRes += sensorData.currentGasRes;
  accumCount++;

  unsigned long now = millis();
  if (lastOfflineWriteTime == 0) lastOfflineWriteTime = now;

  if ((now - lastOfflineWriteTime >= FIVE_MINUTES_IN_MS) && (accumCount > 0)) {
    SensorData avgData;
    avgData.currentTemp = accumTemp / accumCount; 
    avgData.currentHumidity = accumHumidity / accumCount;
    avgData.currentPressure = accumPressure / accumCount; 
    avgData.currentGasRes = accumGasRes / accumCount;
    
    File file = LittleFS.open(OFFLINE_FILE_PATH, FILE_APPEND);
    if (file) { 
      file.println(avgData.toJsonString()); 
      file.close(); 
    }
    accumTemp = 0.0f; 
    accumHumidity = 0.0f; 
    accumPressure = 0.0f; 
    accumGasRes = 0.0f; 
    accumCount = 0;
    lastOfflineWriteTime = now;
  }
}

void dispatchData(String payload) {
  Serial.println(payload);
  if (deviceConnected && pCharacteristic) {
    String formattedMsg = payload + "\n";
    pCharacteristic->setValue((uint8_t *)formattedMsg.c_str(), formattedMsg.length());
    pCharacteristic->notify();
  } else if (payload.startsWith("{\"temp\":")) {
    saveOfflineData();
  }
}

void flushOfflineData() {
  if (!LittleFS.exists(OFFLINE_FILE_PATH)) return;
  File file = LittleFS.open(OFFLINE_FILE_PATH, FILE_READ);
  if (!file) return;
  while (file.available() && deviceConnected) {
    String line = file.readStringUntil('\n'); 
    line.trim();
    if (line.length() > 0) {
      String formattedMsg = line + "\n";
      pCharacteristic->setValue((uint8_t *)formattedMsg.c_str(), formattedMsg.length());
      pCharacteristic->notify();
      vTaskDelay(pdMS_TO_TICKS(BLE_FLUSH_DELAY_MS));
    }
  }
  file.close(); 
  LittleFS.remove(OFFLINE_FILE_PATH);
}

void softResetBme688Sensor() {
  Wire.beginTransmission(bmeI2cAddr); 
  Wire.write(0xE0); 
  Wire.write(0xB6); 
  Wire.endTransmission();
  vTaskDelay(pdMS_TO_TICKS(10));
}

void resetToDefaultMode() {
  softResetBme688Sensor();
}

void handleCommand(String command) {
  command.trim(); 
  command.toLowerCase();
  logMessage("[CMD RX]: Received command: '" + command + "'");
  dispatchData("{\"rx_cmd\":\"" + command + "\"}");
  
  if (command == CMD_BREATH_SHORT || command == CMD_BREATH_CHAR || command == CMD_BREATH_FULL) {
    if (!systemReady || !bsecReady || currentMode == MODE_BREATH_TEST) return;
    dryAirActive = false; 
    currentMode = MODE_BREATH_TEST; 
    pendingBreathCommand = true;
  }   
  else if (command == CMD_SET_ACTIVE_SAMPLING) {
    if (currentProfile != PROFILE_LP_3S) {
      updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
      currentProfile = PROFILE_LP_3S;
      dispatchData("{\"state\":\"" + String(STATE_PROFILE_LP) + "\"}");
      logMessage("[POWER]: Transitioned to BSEC LP (3s) Mode.");
    }
  } 
  else if (command == CMD_SET_ULP_SAMPLING) {
    if (currentProfile != PROFILE_ULP_300S && currentMode != MODE_BREATH_TEST) {
      resetToULP();
      dispatchData("{\"state\":\"" + String(STATE_PROFILE_ULP) + "\"}");
      logMessage("[POWER]: Transitioned to BSEC ULP (300s) Mode.");
    }
  }
  else if (command == CMD_DIAG_SELECTIVITY || command == CMD_DIAG_NUMERIC) {
    pendingDiagCommand = true;
  }
  else if (command == CMD_DIAG_POWER_KINETICS || command == CMD_DIAG_POWER_NUMERIC) {
    logMessage("[DIAG START]: Processing Command 98 (Power & Kinetics Suite)...");
    currentMode = MODE_DIAGNOSTIC;
    runPowerAndKineticsDiagnosticTest();
    currentMode = MODE_IDLE;
    logMessage("[DIAG COMPLETE]: Power & Kinetics suite completed.");
  }
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo) override { 
    deviceConnected = true; 
    pendingFlush = true; 
    connectionEstablishedTimeMs = millis();
    connectionParamsUpdated = false;

    logMessage(F("[BLE CONNECT]: Central connected. Fast GATT discovery window active."));
    
    if (bsec != nullptr && currentMode != MODE_BREATH_TEST) {
      resetToULP();
      logMessage(String(MesoLogStrings::LOG_BLE_RESTORE_ULP));
      
      if (sensorData.currentGasRes > 0.0f || sensorData.currentTemp != 0.0f) {
        float measuredVoltage = 0.0f;
        sensorData.batteryPct = BatteryMonitor::readPercentageAndVoltage(measuredVoltage);
        dispatchData(sensorData.toJsonString());
      }
    }
  }

  void onDisconnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo, int reason) override { 
    deviceConnected = false; 
    connectionEstablishedTimeMs = 0;
    connectionParamsUpdated = false;
    adjustAdvertisingPower(true);
  }
};

class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo &connInfo) {
    NimBLEAttValue val = pCharacteristic->getValue();
    if (val.length() > 0) {
      String rxValue = String((char *)val.data()).substring(0, val.length());
      snprintf(pendingCmdBuf, sizeof(pendingCmdBuf), "%s", rxValue.c_str());
      hasPendingCommand = true;
    }
  }
};

void adjustAdvertisingPower(bool newlyDisconnected) {
  static unsigned long disconnectTime = millis();
  static bool isInLowPowerAdvertising = false;
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  if (newlyDisconnected) {
    disconnectTime = millis();
    isInLowPowerAdvertising = false;
    pAdvertising->stop();
    pAdvertising->setMinInterval(BLE_ADV_FAST_MIN_INTERVAL_UNITS);
    pAdvertising->setMaxInterval(BLE_ADV_FAST_MAX_INTERVAL_UNITS);
    pAdvertising->start();
    logMessage(F("[BLE ADV]: Fast Advertising Started (30s window)."));
  } else if (!deviceConnected) {
    if (!isInLowPowerAdvertising && ((millis() - disconnectTime) > FAST_ADV_BURST_WINDOW_MS)) {
      isInLowPowerAdvertising = true;
      pAdvertising->stop();
      pAdvertising->setMinInterval(BLE_ADV_ULP_MIN_INTERVAL_UNITS);
      pAdvertising->setMaxInterval(BLE_ADV_ULP_MAX_INTERVAL_UNITS);
      pAdvertising->start();
      logMessage(F("[BLE ADV]: Transitioned to Low Power Advertising."));
    } else if (!pAdvertising->isAdvertising()) {
      pAdvertising->start();
    }
  }
}

void processSerialInput() {
  static String serialBuffer = "";
  static unsigned long lastCharTime = 0;

  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    lastCharTime = millis();
    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        handleCommand(serialBuffer);
        serialBuffer = "";
      }
    } else {
      serialBuffer += c;
    }
  }

  if (serialBuffer.length() > 0 && (millis() - lastCharTime >= SERIAL_AUTO_FLUSH_TIMEOUT_MS)) {
    handleCommand(serialBuffer);
    serialBuffer = "";
  }
}

void setup() {
  Serial.begin(SERIAL_BAUD_RATE);
  
  // Wait up to 2500ms for USB host to enumerate endpoints
  const uint32_t usbStartMs = millis();
  while (!usb_serial_jtag_ll_txfifo_writable() && ((millis() - usbStartMs) < 2500UL)) {
    delay(10);
  }
  delay(200); // Terminal visual settle

  logMessage(F("[SYS INIT]: Firmware Booting (Meso Nose Pure BSEC Kinetics)"));

  BatteryMonitor::init();

  if (!LittleFS.begin(true, LITTLEFS_MOUNT_POINT, 10, "spiffs")) {
    logMessage(F("[LITTLEFS WARN]: Mount failed. Formatting LittleFS partition..."));
    LittleFS.format();
    LittleFS.begin(true, LITTLEFS_MOUNT_POINT, 10, "spiffs");
  }

  // Initialize NimBLE Radio at full bus speed
  NimBLEDevice::init(Device_Name.c_str());
  pServer = NimBLEDevice::createServer(); 
  pServer->setCallbacks(new ServerCallbacks());
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID, 
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start(); 
  
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  // Primary Advertisement Data: Flags & 128-bit Service UUID
  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.setCompleteServices(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advData);

  // Scan Response Data: Complete Local Name (guarantees iOS discovery on scan)
  NimBLEAdvertisementData scanRespData;
  scanRespData.setName(Device_Name.c_str());
  pAdvertising->setScanResponseData(scanRespData);

  pAdvertising->setMinInterval(BLE_ADV_FAST_MIN_INTERVAL_UNITS);
  pAdvertising->setMaxInterval(BLE_ADV_FAST_MAX_INTERVAL_UNITS);
  pAdvertising->start();

  logMessage("[BLE ADV]: Active BLE Advertising Broadcast under name: " + Device_Name);

  // Initialize I2C and BSEC at full bus speed
  Wire.begin(I2C_SDA, I2C_SCL); 
  Wire.setClock(I2C_CLOCK_SPEED_HZ); 
  Wire.setTimeOut(I2C_BUS_TIMEOUT_MS);
  
  bsec = new Bsec2();
  if (bsec->begin(bmeI2cAddr, Wire)) {
    if (!bsec->setConfig(bsec_config_iaq)) {
      logMessage(String(MesoLogStrings::LOG_BSEC_CONFIG_WARN) + String(bsec->status) + ")");
    }
    bsecReady = true; 
    bsec->attachCallback(newDataCallback);
    resetToULP();
    logMessage(String(MesoLogStrings::LOG_BSEC_INIT_BOOT_ULP));
  } else {
    logMessage(String(MesoLogStrings::LOG_BSEC_INIT_FAIL));
  }

  // Scale down CPU clock only when untethered from USB
  const bool isUsbConnected = usb_serial_jtag_ll_txfifo_writable() || BatteryMonitor::isCharging();
  if (!isUsbConnected) {
    if (setCpuFrequencyMhz(MesoPowerConfig::CPU_LOW_POWER_FREQ_MHZ)) {
      logMessage(String(MesoPowerLogs::CPU_FREQ_CONFIG_SUCCESS));
    } else {
      logMessage(String(MesoPowerLogs::CPU_FREQ_CONFIG_FAIL));
    }
  } else {
    logMessage(F("[POWER]: USB-CDC Active. Maintaining 160 MHz for diagnostics."));
  }

  logMessage(String(MesoPowerLogs::LIGHT_SLEEP_ENGINE_ACTIVE));
  systemReady = true;
  logMessage(F("[SYS READY]: System Ready. Listening for BLE/Serial commands..."));
}

void loop() {
  adjustAdvertisingPower(false);

  processSerialInput();

  if (hasPendingCommand) { hasPendingCommand = false; handleCommand(String(pendingCmdBuf)); }
  if (pendingFlush && deviceConnected) { pendingFlush = false; flushOfflineData(); }
  if (pendingDiagCommand) { pendingDiagCommand = false; executeDiagnosticSequence(); return; }
  if (pendingBreathCommand) { pendingBreathCommand = false; runBreathSequence(); return; }

  // 1. Deferred Low-Power Connection Parameter Negotiation
  if (deviceConnected && !connectionParamsUpdated && 
      ((millis() - connectionEstablishedTimeMs) >= MesoPowerConfig::BLE_HANDSHAKE_STABILIZATION_MS)) {
    connectionParamsUpdated = true;
    NimBLEConnInfo connInfo = pServer->getPeerInfo(0);
    pServer->updateConnParams(
      connInfo.getConnHandle(),
      BleConnParams::BLE_CONN_MIN_INTERVAL_UNITS,
      BleConnParams::BLE_CONN_MAX_INTERVAL_UNITS,
      BleConnParams::BLE_CONN_SLAVE_LATENCY,
      BleConnParams::BLE_CONN_SUPERVISION_TIMEOUT_UNITS
    );
    logMessage(String(MesoLogStrings::LOG_BLE_CONN_UPDATE_REQ));
  }

  // Protected BSEC execution block
  if (bsecReady && bsec != nullptr && bsec->status >= BSEC_OK && currentProfile != PROFILE_OFF && currentMode == MODE_IDLE) {
    bsec->run();
    
    static unsigned long lastNotifyTime = 0;
    const uint32_t activeNotifyInterval = (currentProfile == PROFILE_LP_3S) 
                                          ? NOTIFY_LP_INTERVAL_MS 
                                          : NOTIFY_ULP_INTERVAL_MS;

    if ((millis() - lastNotifyTime) >= activeNotifyInterval) {
      lastNotifyTime = millis();
      if (sensorData.currentGasRes > 0.0f || sensorData.currentTemp != 0.0f) {
        float measuredVoltage = 0.0f;
        sensorData.batteryPct = BatteryMonitor::readPercentageAndVoltage(measuredVoltage);

        logMessage("[BATT DIAG]: Measured Cell Voltage: " + String(measuredVoltage, 3) + 
                   " V | SoC: " + String(sensorData.batteryPct) + " %");
        dispatchData(sensorData.toJsonString());
      }
    }
  }
  
  const bool isBootGraceActive = (millis() < MesoPowerConfig::BOOT_STABILIZATION_GRACE_MS);
  
  // Hardware-level USB Connection Detection:
  // Detects physical USB cable connection regardless of battery charge state or Mac DTR status
  const bool isUsbTethered = usb_serial_jtag_ll_txfifo_writable() || 
                             BatteryMonitor::isCharging() || 
                             (bool)Serial;

  // Guard GATT discovery during the initial 5-second handshake window
  const bool isBleHandshaking = deviceConnected && 
    ((millis() - connectionEstablishedTimeMs) < MesoPowerConfig::BLE_HANDSHAKE_STABILIZATION_MS);

  // True Low Power: Engages untethered on battery outside active sensing/handshake windows
  if (!isBootGraceActive && !isUsbTethered && !isBleHandshaking &&
      currentMode == MODE_IDLE && !hasPendingCommand && !pendingBreathCommand && !pendingDiagCommand) {
    
    esp_err_t timerErr = esp_sleep_enable_timer_wakeup(MesoPowerConfig::IDLE_LIGHT_SLEEP_DURATION_US);
    
    if (timerErr == ESP_OK) {
      esp_err_t sleepErr = esp_light_sleep_start();
      if (sleepErr != ESP_OK) {
        vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
      }
    } else {
      vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
    }
  } else {
    // Keep FreeRTOS scheduler servicing USB-CDC and BLE when tethered or during handshakes
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}