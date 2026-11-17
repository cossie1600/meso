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
#include "breath_kinetics_engine.h"
#include "battery_monitor.h"

#define ENABLE_SERIAL_LOGS true
#define ENABLE_VERBOSE_DEBUG false

#define VERBOSE_LOG(x) \
  do { \
    if (ENABLE_VERBOSE_DEBUG) { \
      logMessage(x); \
    } \
  } while (0)

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

constexpr uint32_t SERIAL_BAUD_RATE = 115200;
constexpr uint32_t I2C_CLOCK_SPEED_HZ = 100000;
constexpr uint32_t I2C_BUS_TIMEOUT_MS = 1000;
constexpr uint32_t SERIAL_AUTO_FLUSH_TIMEOUT_MS = 250UL;

constexpr uint16_t BLE_ADV_FAST_MIN_INTERVAL_UNITS = 96;      // 60 ms (96 * 0.625 ms) - instant lock on boot/disconnect
constexpr uint16_t BLE_ADV_FAST_MAX_INTERVAL_UNITS = 160;     // 100 ms (160 * 0.625 ms)
constexpr uint16_t BLE_ADV_ULP_MIN_INTERVAL_UNITS  = 320;     // 200 ms (320 * 0.625 ms) - fast iOS discovery during ULP sleep
constexpr uint16_t BLE_ADV_ULP_MAX_INTERVAL_UNITS  = 480;     // 300 ms (480 * 0.625 ms)
constexpr unsigned long FAST_ADV_BURST_WINDOW_MS = 300000UL;  // Full 5-minute pairing window
constexpr uint32_t BLE_FLUSH_DELAY_MS = 30;


constexpr uint32_t NOTIFY_ULP_INTERVAL_MS = 300000;
constexpr uint32_t NOTIFY_LP_INTERVAL_MS = 3000;
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS = 30000;
constexpr uint32_t BREATH_SENSING_WINDOW_MS = 10000;
constexpr uint32_t RECOVERY_SENSING_WINDOW_MS = 15000;
constexpr uint32_t POLL_TICK_DELAY_MS = 20;

constexpr uint8_t BASELINE_TARGET_SAMPLE_COUNT = 3;
constexpr uint32_t BASELINE_CAPTURE_TIMEOUT_MS = 15000UL;
constexpr float HW_MIN_SENSOR_GAS_RES = 5000.0f;

constexpr float PARTIAL_EXHALATION_MIN_DELTA_RH_PCT = 0.8f;
constexpr float EXHALATION_MIN_MOISTURE_DELTA_RH_PCT = SensorConstants::DRY_MOUTH_MAX_DELTA_RH_PCT;
constexpr float EXHALATION_MIN_GAS_DROP_PCT = 5.0f;
constexpr float EXHALATION_FORCE_TRIGGER_GAS_DROP_PCT = 15.0f;
constexpr uint32_t THERMAL_TRANSIENT_SUPPRESSION_MS = 4000;

constexpr float T50_CALCULATION_FACTOR = 0.5f;
constexpr float HIGH_BASELINE_HUMIDITY_THRESHOLD_PCT = 80.0f;
constexpr float MILLISECONDS_TO_SECONDS_CONVERSION = 1000.0f;

constexpr const char *STATE_EXHALATION_TOO_WEAK = "EXHALATION_TOO_WEAK";
constexpr const char *STATE_READY_PLEASE_BLOW = "READY_PLEASE_BLOW";
constexpr const char *STATE_TESTING_SENSING_BREATH = "TESTING_SENSING_BREATH";
constexpr const char *STATE_TIMEOUT = "TIMEOUT";
constexpr const char *STATUS_BREATH_TEST_COMPLETE = "BREATH_TEST_COMPLETE";

constexpr const char *RESULT_NONE = "NONE";

constexpr const char *CMD_BREATH_SHORT = "3";
constexpr const char *CMD_BREATH_CHAR = "b";
constexpr const char *CMD_BREATH_FULL = "breath";
constexpr const char *CMD_DIAG_POWER_KINETICS = "test_power_kinetics";
constexpr const char *CMD_DIAG_POWER_NUMERIC = "98";
constexpr const char *CMD_DIAG_SELECTIVITY = "test_selectivity";
constexpr const char *CMD_DIAG_NUMERIC = "99";

constexpr const char *CMD_SET_ACTIVE_SAMPLING = "set_active_sampling_mode";
constexpr const char *CMD_SET_ULP_SAMPLING = "set_ultra_low_sampling_mode";
constexpr const char *CMD_STATUS              = "status";
constexpr const char *CMD_HELP                = "help";
constexpr const char *CMD_HELP_SHORT          = "?";

constexpr float        PA_TO_HPA_DIVISOR      = 100.0f;
constexpr float        BME688_MIN_VALID_TEMP_C = -40.0f;
constexpr float        BME688_MAX_VALID_TEMP_C = 85.0f;
constexpr unsigned int DURATION_FLOAT_PRECISION = 2U;
constexpr unsigned int VOLTAGE_FLOAT_PRECISION  = 3U;
constexpr const char  *LITTLEFS_PARTITION_LABEL = "spiffs";

constexpr const char *STATE_PROFILE_LP = "PROFILE_LP";
constexpr const char *STATE_PROFILE_ULP = "PROFILE_ULP";

constexpr uint32_t MS_PER_SECOND              = 1000UL;
constexpr float    PERCENTAGE_SCALE_FACTOR    = 100.0f;
constexpr unsigned int TELEMETRY_FLOAT_PRECISION = 1U;

namespace MesoPowerConfig {
constexpr uint32_t CPU_LOW_POWER_FREQ_MHZ             = 80;  // Stable APB clock for NimBLE radio

// Timed light sleep duration during idle (100ms cuts wakeup overhead by 5x for ~2.5-day runtime)
constexpr uint64_t IDLE_LIGHT_SLEEP_DURATION_US       = 100000ULL;   // 100 ms
constexpr uint32_t BOOT_STABILIZATION_GRACE_MS        = 5000UL;      // 5s grace window
constexpr uint32_t BLE_HANDSHAKE_STABILIZATION_MS     = 5000UL;      // 5s GATT discovery window

// Battery Supervision Safety Thresholds (Zero Magic Numbers)
constexpr float CRITICAL_LOW_BATTERY_SHUTDOWN_VOLTS   = 3.10f;
constexpr uint32_t BATT_SUPERVISION_INTERVAL_MS       = 10000UL;     // 10s check cadence
constexpr uint32_t BLE_SHUTDOWN_DRAIN_DELAY_MS        = 1100UL;      // >1000ms max BLE connection interval
constexpr uint64_t EMERGENCY_SLEEP_WAKEUP_US          = 60000000ULL; // 60s recovery wakeup timer
constexpr uint8_t CRITICAL_BATTERY_CONSECUTIVE_SAMPLES = 3;

// Serial & Boot Initialization Constants (Zero Magic Numbers)
constexpr uint32_t SERIAL_RX_WAKE_HOLD_MS             = 30000UL;     // Keep USB PHY awake 30s after Serial RX
constexpr uint32_t USB_CDC_TX_TIMEOUT_MS              = 50UL;
constexpr uint32_t SERIAL_BOOT_SETTLE_MS              = 500UL;
constexpr uint32_t USB_ENUM_TIMEOUT_MS                = 2500UL;
constexpr uint32_t USB_POLL_STEP_MS                   = 10UL;
constexpr uint32_t USB_TERMINAL_SETTLE_MS             = 200UL;
constexpr uint8_t  LITTLEFS_MAX_OPEN_FILES            = 10;
}

namespace MesoPowerLogs {
constexpr const char *BSEC_CLEAN_ULP_INIT     = "[BSEC]: Default config active for ULP (300s) mode.";
constexpr const char *BSEC_CUSTOM_LP_INIT     = "[BSEC]: Custom selectivity config active for LP (3s) mode.";
constexpr const char *BSEC_SUB_SKIPPED        = "[SET_PROFILE SKIPPED]: Target profile matches current healthy profile.";
constexpr const char *BSEC_SUB_FAIL           = "[BSEC ERROR]: updateSubscription failed: ";
constexpr const char *CPU_FREQ_CONFIG_SUCCESS = "[POWER]: CPU clock scaled down to 80 MHz (Low Power Mode).";
constexpr const char *CPU_FREQ_CONFIG_FAIL    = "[POWER ERROR]: Failed to adjust CPU clock frequency.";
constexpr const char *LIGHT_SLEEP_ENGINE_ACTIVE = "[POWER]: Explicit Timed Light Sleep active (100ms ticks).";
}

namespace BleConnParams {
// Apple Accessory Design Guidelines Compliant Idle Intervals (units of 1.25ms and 10ms)
constexpr uint16_t BLE_CONN_MIN_INTERVAL_UNITS        = 120;  // 150 ms (120 * 1.25 ms)
constexpr uint16_t BLE_CONN_MAX_INTERVAL_UNITS        = 240;  // 300 ms (240 * 1.25 ms)
constexpr uint16_t BLE_CONN_SLAVE_LATENCY             = 1;    // Skip at most 1 interval (max 600ms latency)
constexpr uint16_t BLE_CONN_SUPERVISION_TIMEOUT_UNITS = 600;  // 6000 ms (600 * 10 ms)
// Active Breath Test Intervals (Zero-Lag UI State Delivery)
constexpr uint16_t BLE_ACTIVE_MIN_INTERVAL_UNITS      = 24;   // 30 ms (24 * 1.25 ms)
constexpr uint16_t BLE_ACTIVE_MAX_INTERVAL_UNITS      = 48;   // 60 ms (48 * 1.25 ms)
constexpr uint16_t BLE_ACTIVE_SLAVE_LATENCY           = 0;    // Every interval serviced immediately
constexpr uint16_t BLE_ACTIVE_SUPERVISION_TIMEOUT     = 400;  // 4000 ms (400 * 10 ms)
}

namespace MesoLogStrings {
constexpr const char *LOG_BLE_CONN_UPDATE_REQ   = "[BLE CONNECT]: Central connected. Negotiated 150-300ms low-power interval.";
constexpr const char *LOG_BLE_RESTORE_ULP       = "[BLE CONNECT]: Connection established. Maintained ULP mode.";
constexpr const char *LOG_BLE_ADV_FAST_START    = "[BLE ADV]: Fast Advertising Started (5m window).";
constexpr const char *LOG_BLE_ADV_ULP_START     = "[BLE ADV]: Transitioned to Low Power Advertising.";
constexpr const char *LOG_BSEC_INIT_BOOT_ULP    = "[BSEC INIT]: Engine Initialized & Booted Cleanly into ULP (300s) Mode.";
constexpr const char *LOG_BSEC_INIT_FAIL        = "[BSEC ERROR]: BSEC Initialization Failed!";
constexpr const char *LOG_BATT_CRITICAL_CUTOFF  = "[POWER ERROR]: Battery depleted below cutoff threshold. Entering deep sleep.";
constexpr const char *LOG_HEATER_TRANSIENT_SKIP = "[BLOW MONITOR]: Ignored transient heater frame below minimum gas floor.";
constexpr const char *LOG_CMD_UNRECOGNIZED      = "[CMD WARN]: Unrecognized command: '";
constexpr const char *LOG_HELP_COMMANDS         = "[SYS HELP]: Commands -> 98 (power/kinetics), 99 (BSEC health), breath (test), status";
constexpr const char *LOG_USB_CONSOLE_ATTACHED  = "[USB]: Serial console active. Commands: status, 98, 99, breath";
}

unsigned long connectionEstablishedTimeMs = 0;
unsigned long lastAdvBurstStartMs = 0;
unsigned long lastSerialActivityMs = 0;
bool connectionParamsUpdated = false;

bool systemReady = false;
OperationMode currentMode = MODE_IDLE;
BsecProfile currentProfile = PROFILE_OFF;

bool deviceConnected = false;
bool bsecReady = false;
volatile bool newGasDataAvailable = false;
volatile bool pendingBreathCommand = false;
volatile bool pendingDiagCommand = false;
volatile bool pendingPowerDiagCommand = false;
volatile bool pendingFlush = false;
volatile bool pendingFastAdvRestart   = false;
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
  BSEC_OUTPUT_RAW_PRESSURE,
  BSEC_OUTPUT_RAW_GAS
};
uint8_t numDefaultSensors = sizeof(defaultSensorList) / sizeof(bsecSensor);

Bsec2 *bsec = nullptr;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

void dispatchData(String payload);
void logMessage(String msg);
void softResetBme688Sensor();

void setBleConnectionSpeed(bool isHighSpeed);
void startBleAdvertisingWithInterval(uint16_t minIntervalUnits, uint16_t maxIntervalUnits);

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

  const bool isAlreadyTargetProfile =
    ((sampleRate == BSEC_SAMPLE_RATE_LP)  && (currentProfile == PROFILE_LP_3S)) ||
    ((sampleRate == BSEC_SAMPLE_RATE_ULP) && (currentProfile == PROFILE_ULP_300S));

  if (isAlreadyTargetProfile && (bsec->status >= BSEC_OK)) {
    VERBOSE_LOG(String(MesoPowerLogs::BSEC_SUB_SKIPPED));
    return true;
  }

  delete bsec;
  bsec = new Bsec2();
  if (!bsec->begin(bmeI2cAddr, Wire)) {
    logMessage(String(MesoPowerLogs::BSEC_SUB_FAIL) + String(bsec->status));
    bsecReady = false;
    currentProfile = PROFILE_OFF;
    return false;
  }
  bsec->attachCallback(newDataCallback);

  const bool subOk = bsec->updateSubscription(defaultSensorList, numDefaultSensors, sampleRate);
  const bool isSubscriptionActive = subOk || (bsec->status >= BSEC_OK);

  if (isSubscriptionActive) {
    if (sampleRate == BSEC_SAMPLE_RATE_LP) {
      currentProfile = PROFILE_LP_3S;
      logMessage(String(MesoPowerLogs::BSEC_CUSTOM_LP_INIT));
    } else if (sampleRate == BSEC_SAMPLE_RATE_ULP) {
      currentProfile = PROFILE_ULP_300S;
      logMessage(String(MesoPowerLogs::BSEC_CLEAN_ULP_INIT));
    }
    return true;
  }

  logMessage(String(MesoPowerLogs::BSEC_SUB_FAIL) + String(bsec->status));
  return false;
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
        sensorData.currentPressure = output.signal / 100.0f;  // Pa to hPa
        break;
    }
  }
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
        VERBOSE_LOG("[BASELINE SAMPLE #" + String(validCount) + "]: GasRes=" + String((long)rawRes) + " Ohm | RH=" + String(sensorData.currentHumidity, 1) + "% | Temp=" + String(sensorData.currentTemp, 1) + "C");
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

  logMessage("[BASELINE CAPTURED]: R_base=" + String((long)outBaselineRes) + " Ohm | Base_RH=" + String(outBaseHumidity, 1) + "% | Base_Temp=" + String(outBaseTemp, 1) + "C");
  return true;
}

bool waitForBreathExhalation(float baseGasRes, float baseHumidity, float baseTemp,
                             float &outMinRes, float &outMaxDeltaRH) {
  (void)baseTemp;
  dispatchData("{\"state\":\"" + String(STATE_READY_PLEASE_BLOW) + "\"}");
  logMessage("[WAIT EXHALATION]: Waiting for breath exhalation blow (Timeout: " + String(BREATH_WAIT_TIMEOUT_MS / MS_PER_SECOND) + "s)...");

  const uint32_t startMs = millis();
  outMaxDeltaRH = 0.0f;

  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    float currentGasRes = 0.0f;
    if (readBsecFrame(currentGasRes)) {
      if (currentGasRes <= HW_MIN_SENSOR_GAS_RES) {
        VERBOSE_LOG(String(MesoLogStrings::LOG_HEATER_TRANSIENT_SKIP));
        vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
        continue;
      }

      const float rawDeltaRH = sensorData.currentHumidity - baseHumidity;
      const float gasDropPct = (baseGasRes > 0.0f)
                                 ? (((baseGasRes - currentGasRes) / baseGasRes) * PERCENTAGE_SCALE_FACTOR)
                                 : 0.0f;

      // Defect 3 Fix: Suppress initial negative cooling transient within the first 4 seconds
      const bool isInsideThermalTransientWindow = ((millis() - startMs) < THERMAL_TRANSIENT_SUPPRESSION_MS);
      const float effectiveDeltaRH = (isInsideThermalTransientWindow && rawDeltaRH < 0.0f) ? 0.0f : rawDeltaRH;

      if (currentGasRes < outMinRes) outMinRes = currentGasRes;
      if (effectiveDeltaRH > outMaxDeltaRH) outMaxDeltaRH = effectiveDeltaRH;

      // Telemetry dispatch
      dispatchData("{\"dH\":" + String(rawDeltaRH, TELEMETRY_FLOAT_PRECISION) +
                   ",\"gDrop\":" + String(gasDropPct, TELEMETRY_FLOAT_PRECISION) + "}");

      VERBOSE_LOG("[BLOW MONITOR]: GasRes=" + String((long)currentGasRes) +
                  " Ohm | gDrop=" + String(gasDropPct, TELEMETRY_FLOAT_PRECISION) +
                  "% | dH=" + String(rawDeltaRH, TELEMETRY_FLOAT_PRECISION) + "%");

      // Condition A: Standard balanced breath (Moderate VOC drop + realistic moisture spike)
      const bool isStandardBreath = (effectiveDeltaRH >= EXHALATION_MIN_MOISTURE_DELTA_RH_PCT) &&
                                    (gasDropPct >= EXHALATION_MIN_GAS_DROP_PCT);

      // Condition B: High ambient background humidity (Room RH > 80%)
      const bool isHighAmbientHum = (baseHumidity >= HIGH_BASELINE_HUMIDITY_THRESHOLD_PCT) &&
                                    (gasDropPct >= EXHALATION_MIN_GAS_DROP_PCT);

      // Defect 2 Fix: Absolute VOC magnitude latch
      const bool isStrongVocLatch = (gasDropPct >= EXHALATION_FORCE_TRIGGER_GAS_DROP_PCT);

      if (isStrongVocLatch) {
        logMessage("[BLOW TRIGGERED]: Absolute VOC drop latch met (" +
                   String(gasDropPct, TELEMETRY_FLOAT_PRECISION) + "% >= " +
                   String(EXHALATION_FORCE_TRIGGER_GAS_DROP_PCT, TELEMETRY_FLOAT_PRECISION) + "%)!");
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

// ============================================================================
// DYNAMIC KINETICS & BREATH SEQUENCE PIPELINE
// ============================================================================

void captureUnifiedBreathKinetics(float baseRes, float baseHumidity,
                                  float &inOutMinRes, float &inOutMaxDeltaRH,
                                  float &outRecoveryLag) {
  dispatchData("{\"state\":\"" + String(STATE_TESTING_SENSING_BREATH) + "\"}");

  // Dynamic 50% target calculated from initial exhalation nadir
  float target50 = inOutMinRes + (T50_CALCULATION_FACTOR * (baseRes - inOutMinRes));
  outRecoveryLag = SensorConstants::RECOVERY_LAG_TIMEOUT_SEC;

  const uint32_t windowStartMs = millis();
  uint32_t nadirTimestampMs = millis();
  bool isAscending = false;

  while ((millis() - windowStartMs) < RECOVERY_SENSING_WINDOW_MS) {
    float currentGasRes = 0.0f;
    if (readBsecFrame(currentGasRes)) {
      const float deltaRH = sensorData.currentHumidity - baseHumidity;
      if (deltaRH > inOutMaxDeltaRH) {
        inOutMaxDeltaRH = deltaRH;
      }

      // Track deeper nadir if exhalation is continuing
      if (currentGasRes > HW_MIN_SENSOR_GAS_RES && currentGasRes < inOutMinRes) {
        inOutMinRes = currentGasRes;
        nadirTimestampMs = millis();
        target50 = inOutMinRes + (T50_CALCULATION_FACTOR * (baseRes - inOutMinRes));
      } else if (currentGasRes > inOutMinRes && !isAscending) {
        isAscending = true;
        dispatchData("{\"state\":\"RECOVERING_CALCULATING_T50\"}");
      }

      // T50 Desorption point reached
      if (isAscending && currentGasRes >= target50) {
        outRecoveryLag = static_cast<float>(millis() - nadirTimestampMs) / MILLISECONDS_TO_SECONDS_CONVERSION;
        logMessage("[T50 RECOVERY TARGET MET]: Reached 50% recovery in " + String(outRecoveryLag, 2) + "s");
        return;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  logMessage(F("[T50 TIMEOUT]: Sensor did not reach target50 within recovery window."));
}

String evaluateBreathResultWrapper(float deltaDrop, float maxDeltaHumidity, float recoveryLagSec) {
  BreathResult result = evaluateBreathResult(deltaDrop, maxDeltaHumidity, recoveryLagSec);
  String resultStr = String(breathResultToString(result));

  logMessage("[EVALUATE KINETICS RESULT]: DeltaDrop=" + String(deltaDrop, 1) + "% | Max_dRH=" + String(maxDeltaHumidity, 1) + "% | T50_Lag=" + String(recoveryLagSec, 2) + "s => PTC Result: " + resultStr);
  return resultStr;
}

void resetTestEvaluationData() {
  sensorData.deltaDrop = 0.0f;
  sensorData.recoveryLagSec = 0.0f;
  sensorData.rBreathMin = 0;
  sensorData.ptcResult = RESULT_NONE;
}

void processBreathTestResults(float baseRes, float minRes, float maxDeltaHumidity, float recoveryLag) {
  float deltaDrop = (baseRes > 0.0f) ? (((baseRes - minRes) / baseRes) * PERCENTAGE_SCALE_FACTOR) : 0.0f;
  if (deltaDrop < 0.0f) deltaDrop = 0.0f;

  // Reuse resting idle batteryPct (avoids ~30 mA heater + BLE voltage sag dip)
  sensorData.currentGasRes = minRes;
  sensorData.deltaDrop = deltaDrop;
  sensorData.rBreathMin = static_cast<long>(minRes);
  sensorData.recoveryLagSec = recoveryLag;
  sensorData.ptcResult = evaluateBreathResultWrapper(deltaDrop, maxDeltaHumidity, recoveryLag);

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_COMPLETE) + "\"}");
  dispatchData(sensorData.toJsonString());

  // Note: resetTestEvaluationData() only clears breath test transients, not battery
  resetTestEvaluationData();
}

void resetToULP() {
  updateBsecSubscription(BSEC_SAMPLE_RATE_ULP);
}

void runBreathSequence() {
  logMessage("[SEQUENCE START]: Breath test sequence initiated (Pure BSEC LP).");

  resetTestEvaluationData();

  float ambientTemp = sensorData.currentTemp;
  float ambientRH = sensorData.currentHumidity;
  currentMode = MODE_BREATH_TEST;
  setBleConnectionSpeed(true); // Switch to 30-60ms zero-lag BLE interval for real-time state updates

  float baseRes = 0.0f, baseHumidity = ambientRH, baseTemp = ambientTemp;
  float maxDeltaRH = 0.0f;
  float recoveryLag = 0.0f;

  if (!prepareAndCaptureBaseline(baseRes, baseHumidity, baseTemp)) {
    logMessage("[SEQUENCE ABORTED]: Baseline capture failed!");
    resetToULP();
    setBleConnectionSpeed(false); // Restore 500-1000ms low-power BLE interval
    currentMode = MODE_IDLE;  // Added clean state reset
    return;
  }

  float minRes = baseRes;
  if (waitForBreathExhalation(baseRes, baseHumidity, baseTemp, minRes, maxDeltaRH)) {
    // Single, clean dynamic kinetics pass (removes redundant captureRecoveryWindow call)
    captureUnifiedBreathKinetics(baseRes, baseHumidity, minRes, maxDeltaRH, recoveryLag);
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
  setBleConnectionSpeed(false); // Restore 500-1000ms low-power BLE interval
  currentMode = MODE_IDLE;
  logMessage("[SEQUENCE END]: Breath test complete. Restored BSEC ULP mode.");
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
    pCharacteristic->setValue(reinterpret_cast<const uint8_t *>(formattedMsg.c_str()), formattedMsg.length());
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

void handleCommand(String command) {
  command.trim();
  command.toLowerCase();
  logMessage("[CMD RX]: Received command: '" + command + "'");
  dispatchData("{\"rx_cmd\":\"" + command + "\"}");

  if (command == CMD_BREATH_SHORT || command == CMD_BREATH_CHAR || command == CMD_BREATH_FULL) {
    if (!systemReady || !bsecReady || currentMode == MODE_BREATH_TEST) return;
    currentMode = MODE_BREATH_TEST;
    pendingBreathCommand = true;
  } else if (command == CMD_SET_ACTIVE_SAMPLING) {
    if (currentProfile != PROFILE_LP_3S) {
      updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
      currentProfile = PROFILE_LP_3S;
      dispatchData("{\"state\":\"" + String(STATE_PROFILE_LP) + "\"}");
      logMessage("[POWER]: Transitioned to BSEC LP (3s) Mode.");
    }
  } else if (command == CMD_SET_ULP_SAMPLING) {
    if (currentProfile != PROFILE_ULP_300S && currentMode != MODE_BREATH_TEST) {
      resetToULP();
      dispatchData("{\"state\":\"" + String(STATE_PROFILE_ULP) + "\"}");
      logMessage("[POWER]: Transitioned to BSEC ULP (300s) Mode.");
    }
  } else if (command == CMD_DIAG_SELECTIVITY || command == CMD_DIAG_NUMERIC) {
    pendingDiagCommand = true;
  } else if (command == CMD_DIAG_POWER_KINETICS || command == CMD_DIAG_POWER_NUMERIC) {
    pendingPowerDiagCommand = true;
  } else if (command == CMD_STATUS) {
    printSystemStatus();
  } else if (command == CMD_HELP || command == CMD_HELP_SHORT) {
    logMessage(String(MesoLogStrings::LOG_HELP_COMMANDS));
  } else {
    logMessage(String(MesoLogStrings::LOG_CMD_UNRECOGNIZED) + command + "'");
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
    }
  }

  void onDisconnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo, int reason) override {
    deviceConnected = false;
    connectionEstablishedTimeMs = 0;
    connectionParamsUpdated = false;
    pendingFastAdvRestart = true;
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

  void onSubscribe(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo &connInfo, uint16_t subValue) override {
    if (subValue > 0 && currentMode != MODE_BREATH_TEST) {
      if (sensorData.currentGasRes > 0.0f || sensorData.currentTemp != 0.0f) {
        float measuredVoltage = 0.0f;
        sensorData.batteryPct = BatteryMonitor::readPercentageAndVoltage(measuredVoltage);
        dispatchData(sensorData.toJsonString());
      }
    }
  }
};

void adjustAdvertisingPower() {
  static bool isInLowPowerAdvertising = false;

  if (pendingFastAdvRestart) {
    pendingFastAdvRestart = false;
    lastAdvBurstStartMs = millis();
    isInLowPowerAdvertising = false;
    startBleAdvertisingWithInterval(BLE_ADV_FAST_MIN_INTERVAL_UNITS, BLE_ADV_FAST_MAX_INTERVAL_UNITS);
    logMessage(String(MesoLogStrings::LOG_BLE_ADV_FAST_START));
    return;
  }

  if (!deviceConnected) {
    NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
    if (!isInLowPowerAdvertising && ((millis() - lastAdvBurstStartMs) > FAST_ADV_BURST_WINDOW_MS)) {
      isInLowPowerAdvertising = true;
      startBleAdvertisingWithInterval(BLE_ADV_ULP_MIN_INTERVAL_UNITS, BLE_ADV_ULP_MAX_INTERVAL_UNITS);
      logMessage(String(MesoLogStrings::LOG_BLE_ADV_ULP_START));
    } else if (pAdvertising != nullptr && !pAdvertising->isAdvertising()) {
      const uint16_t minUnits = isInLowPowerAdvertising ? BLE_ADV_ULP_MIN_INTERVAL_UNITS : BLE_ADV_FAST_MIN_INTERVAL_UNITS;
      const uint16_t maxUnits = isInLowPowerAdvertising ? BLE_ADV_ULP_MAX_INTERVAL_UNITS : BLE_ADV_FAST_MAX_INTERVAL_UNITS;
      startBleAdvertisingWithInterval(minUnits, maxUnits);
    }
  }
}

void printSystemStatus() {
  float cellVoltage = 0.0f;
  const uint8_t soc = BatteryMonitor::readPercentageAndVoltage(cellVoltage);
  const char *profileLabel = (currentProfile == PROFILE_LP_3S)
                               ? STATE_PROFILE_LP
                               : ((currentProfile == PROFILE_ULP_300S) ? STATE_PROFILE_ULP : RESULT_NONE);

  logMessage("[SYS STATUS]: Ready=" + String(systemReady ? "YES" : "NO") +
             " | Profile=" + String(profileLabel) +
             " | Batt=" + String(cellVoltage, VOLTAGE_FLOAT_PRECISION) + "V (" + String(soc) + "%)" +
             " | BLE=" + String(deviceConnected ? "CONNECTED" : "ADVERTISING"));
}

void processSerialInput() {
  static String serialBuffer = "";
  static unsigned long lastCharTime = 0;

  while (Serial.available() > 0) {
    lastSerialActivityMs = millis();
    const char c = static_cast<char>(Serial.read());
    lastCharTime = millis();

    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        handleCommand(serialBuffer);
        serialBuffer = "";
      } else if (c == '\n') {
        printSystemStatus();
      }
    } else if (isPrintable(static_cast<unsigned char>(c))) {
      serialBuffer += c;
    }
  }

  if (serialBuffer.length() > 0 && (millis() - lastCharTime >= SERIAL_AUTO_FLUSH_TIMEOUT_MS)) {
    handleCommand(serialBuffer);
    serialBuffer = "";
  }
}

bool checkAndEnforceBatterySafety(bool isUsbTethered) {
  if (isUsbTethered) {
    return false;
  }

  static uint8_t consecutiveLowVoltageHits = 0;

  float cellVoltage = 0.0f;
  uint8_t soc = BatteryMonitor::readPercentageAndVoltage(cellVoltage);

  // Validate that voltage is in the genuine cell range and below critical cutoff
  if (cellVoltage >= BatteryConfig::MIN_PHYSICAL_CELL_DETECT_VOLTS && cellVoltage < MesoPowerConfig::CRITICAL_LOW_BATTERY_SHUTDOWN_VOLTS) {

    consecutiveLowVoltageHits++;

    // Debounce to ensure it is not a momentary transient from sensor heater or BLE TX
    if (consecutiveLowVoltageHits >= MesoPowerConfig::CRITICAL_BATTERY_CONSECUTIVE_SAMPLES) {
      logMessage(String(MesoLogStrings::LOG_BATT_CRITICAL_CUTOFF) + " (" + String(cellVoltage, 2) + " V | SoC: " + String(soc) + "%)");

      // Notify connected iOS Central
      dispatchData("{\"error\":\"BATTERY_CRITICALLY_LOW\",\"voltage\":" + String(cellVoltage, 2) + ",\"soc\":" + String(soc) + "}");

      // Allow radio link-layer buffers to drain across the 500-1000ms connection interval
      vTaskDelay(pdMS_TO_TICKS(MesoPowerConfig::BLE_SHUTDOWN_DRAIN_DELAY_MS));

      if (NimBLEDevice::isInitialized()) {
        NimBLEDevice::deinit(true);
      }

      // Configure timer or peripheral wake-up so plugging back into power revives the board
      esp_sleep_enable_timer_wakeup(MesoPowerConfig::EMERGENCY_SLEEP_WAKEUP_US); 
      esp_deep_sleep_start();
      return true;
    }
  } else {
    consecutiveLowVoltageHits = 0;
  }

  return false;
}

void setBleConnectionSpeed(bool isHighSpeed) {
  if (!deviceConnected || pServer == nullptr) return;

  NimBLEConnInfo connInfo = pServer->getPeerInfo(0);
  if (isHighSpeed) {
    pServer->updateConnParams(
      connInfo.getConnHandle(),
      BleConnParams::BLE_ACTIVE_MIN_INTERVAL_UNITS,
      BleConnParams::BLE_ACTIVE_MAX_INTERVAL_UNITS,
      BleConnParams::BLE_ACTIVE_SLAVE_LATENCY,
      BleConnParams::BLE_ACTIVE_SUPERVISION_TIMEOUT
    );
  } else {
    pServer->updateConnParams(
      connInfo.getConnHandle(),
      BleConnParams::BLE_CONN_MIN_INTERVAL_UNITS,
      BleConnParams::BLE_CONN_MAX_INTERVAL_UNITS,
      BleConnParams::BLE_CONN_SLAVE_LATENCY,
      BleConnParams::BLE_CONN_SUPERVISION_TIMEOUT_UNITS
    );
  }
}

void startBleAdvertisingWithInterval(uint16_t minIntervalUnits, uint16_t maxIntervalUnits) {
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  if (pAdvertising == nullptr) return;

  if (pAdvertising->isAdvertising()) {
    pAdvertising->stop();
  }

  pAdvertising->setName(Device_Name.c_str());
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->enableScanResponse(true);
  pAdvertising->setMinInterval(minIntervalUnits);
  pAdvertising->setMaxInterval(maxIntervalUnits);
  pAdvertising->refreshAdvertisingData();
  NimBLEDevice::startAdvertising();
}

void setup() {
  Serial.begin(SERIAL_BAUD_RATE);
  Serial.setTxTimeoutMs(MesoPowerConfig::USB_CDC_TX_TIMEOUT_MS);
  delay(MesoPowerConfig::SERIAL_BOOT_SETTLE_MS);

  BatteryMonitor::init();

  // When USB host is present, allow macOS/PC CDC port re-enumeration after upload/reset
  // to complete before printing boot logs; skip delay on battery to conserve energy
  const bool isUsbConnected = BatteryMonitor::isCharging();
  if (isUsbConnected) {
    delay(MesoPowerConfig::USB_ENUM_TIMEOUT_MS);
  }

  Serial.println(F("\n=== MESO NOSE BOOTING ==="));
  logMessage(F("[SYS INIT]: Firmware Booting (Meso Nose Pure BSEC Kinetics)"));

  float initialVoltage = 0.0f;
  sensorData.batteryPct = BatteryMonitor::readPercentageAndVoltage(initialVoltage);

  // Scale CPU clock BEFORE NimBLE and I2C initialize so RF PLL & bus dividers lock cleanly
  if (!isUsbConnected) {
    if (setCpuFrequencyMhz(MesoPowerConfig::CPU_LOW_POWER_FREQ_MHZ)) {
      logMessage(String(MesoPowerLogs::CPU_FREQ_CONFIG_SUCCESS));
    } else {
      logMessage(String(MesoPowerLogs::CPU_FREQ_CONFIG_FAIL));
    }
  } else {
    logMessage(F("[POWER]: USB-CDC Active. Maintaining 160 MHz for diagnostics."));
  }

  if (!LittleFS.begin(true, LITTLEFS_MOUNT_POINT, MesoPowerConfig::LITTLEFS_MAX_OPEN_FILES, "spiffs")) {
    logMessage(F("[LITTLEFS WARN]: Mount failed. Formatting LittleFS partition..."));
    LittleFS.format();
    LittleFS.begin(true, LITTLEFS_MOUNT_POINT, MesoPowerConfig::LITTLEFS_MAX_OPEN_FILES, "spiffs");
  }

  // Initialize NimBLE 2.x Radio on the stabilized clock
  NimBLEDevice::init(Device_Name.c_str());
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY);
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start();

  lastAdvBurstStartMs = millis();
  startBleAdvertisingWithInterval(BLE_ADV_FAST_MIN_INTERVAL_UNITS, BLE_ADV_FAST_MAX_INTERVAL_UNITS);
  logMessage("[BLE ADV]: Active BLE Advertising Broadcast under name: " + Device_Name);

  // Initialize I2C and BSEC
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(I2C_CLOCK_SPEED_HZ);
  Wire.setTimeOut(I2C_BUS_TIMEOUT_MS);

  bsec = new Bsec2();
  if (bsec->begin(bmeI2cAddr, Wire)) {
    bsecReady = true;
    bsec->attachCallback(newDataCallback);
    resetToULP();
    logMessage(String(MesoLogStrings::LOG_BSEC_INIT_BOOT_ULP));
  } else {
    logMessage(String(MesoLogStrings::LOG_BSEC_INIT_FAIL));
  }

  logMessage(String(MesoPowerLogs::LIGHT_SLEEP_ENGINE_ACTIVE));
  systemReady = true;
  logMessage(F("[SYS READY]: System Ready. Listening for BLE/Serial commands..."));
}

void loop() {
  adjustAdvertisingPower();

  processSerialInput();

  if (pendingPowerDiagCommand) {
    pendingPowerDiagCommand = false;
    logMessage("[DIAG START]: Processing Command 98 (Power & Kinetics Suite)...");
    currentMode = MODE_DIAGNOSTIC;
    runPowerAndKineticsDiagnosticTest();
    currentMode = MODE_IDLE;
    logMessage("[DIAG COMPLETE]: Power & Kinetics suite completed.");
    return;
  }
  if (hasPendingCommand) {
    hasPendingCommand = false;
    handleCommand(String(pendingCmdBuf));
  }
  if (pendingFlush && deviceConnected) {
    pendingFlush = false;
    flushOfflineData();
  }
  if (pendingDiagCommand) {
    pendingDiagCommand = false;
    executeDiagnosticSequence();
    return;
  }
  if (pendingBreathCommand) {
    pendingBreathCommand = false;
    runBreathSequence();
    return;
  }

  // 1. Deferred Low-Power Connection Parameter Negotiation
  if (deviceConnected && !connectionParamsUpdated && ((millis() - connectionEstablishedTimeMs) >= MesoPowerConfig::BLE_HANDSHAKE_STABILIZATION_MS)) {
    connectionParamsUpdated = true;
    NimBLEConnInfo connInfo = pServer->getPeerInfo(0);
    pServer->updateConnParams(
      connInfo.getConnHandle(),
      BleConnParams::BLE_CONN_MIN_INTERVAL_UNITS,
      BleConnParams::BLE_CONN_MAX_INTERVAL_UNITS,
      BleConnParams::BLE_CONN_SLAVE_LATENCY,
      BleConnParams::BLE_CONN_SUPERVISION_TIMEOUT_UNITS);
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

        logMessage("[BATT DIAG]: Measured Cell Voltage: " + String(measuredVoltage, 3) + " V | SoC: " + String(sensorData.batteryPct) + " %");
        dispatchData(sensorData.toJsonString());
      }
    }
  }

  const bool isBootGraceActive = (millis() < MesoPowerConfig::BOOT_STABILIZATION_GRACE_MS);

  // Hardware-level USB Connection Detection:
  // Detects physical USB cable connection regardless of battery charge state or Mac DTR status
  const bool isSerialSessionActive = (Serial.available() > 0) ||
  ((lastSerialActivityMs > 0) && ((millis() - lastSerialActivityMs) < MesoPowerConfig::SERIAL_RX_WAKE_HOLD_MS));

  const bool isUsbTethered = BatteryMonitor::isCharging() || isSerialSessionActive;

  static bool wasUsbTethered = true;
  if (isUsbTethered && !wasUsbTethered) {
    logMessage(String(MesoLogStrings::LOG_USB_CONSOLE_ATTACHED));
  }
  wasUsbTethered = isUsbTethered;

  // Periodic battery supervision: rate-limited to avoid bus/ADC thrashing
  static unsigned long lastBatteryCheckTimeMs = 0;
  if ((millis() - lastBatteryCheckTimeMs) >= MesoPowerConfig::BATT_SUPERVISION_INTERVAL_MS) {
    lastBatteryCheckTimeMs = millis();
    checkAndEnforceBatterySafety(isUsbTethered);
  }

  const bool isBleHandshaking = deviceConnected && ((millis() - connectionEstablishedTimeMs) < MesoPowerConfig::BLE_HANDSHAKE_STABILIZATION_MS);

  const bool isInFastPairingWindow = (!deviceConnected) && ((millis() - lastAdvBurstStartMs) < FAST_ADV_BURST_WINDOW_MS);
  if (!isBootGraceActive && !isUsbTethered && !deviceConnected && !isInFastPairingWindow &&
    !pendingFastAdvRestart && currentMode == MODE_IDLE && !hasPendingCommand &&
    !pendingBreathCommand && !pendingDiagCommand && !pendingPowerDiagCommand) {
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
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}