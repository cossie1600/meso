/**
 * ============================================================================
 * FIRMWARE 2: PURE BSEC KINETICS ARCHITECTURE
 * ============================================================================
 */

#include <Wire.h>
#include <FS.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"
#include "sensor_data.h"
#include "diagnostics.h"
#include "bsec_iaq.h"

const uint8_t bsec_config_iaq[] = {
#include "./bsec_selectivity.txt"
};

#define ENABLE_SERIAL_LOGS true
#define ENABLE_VERBOSE_DEBUG false

#define VERBOSE_LOG(x) do { \
  if (ENABLE_VERBOSE_DEBUG) { \
    Serial.println(String("[TRACE @ ") + millis() + "ms]: " + String(x)); \
  } \
} while(0)

#define BATTERY_ADC_PIN 0
#define I2C_SDA 6
#define I2C_SCL 7
#define SERVICE_UUID "4fa215f0-0001-4b0e-b682-1a4c70f3a601"
#define CHARACTERISTIC_UUID "4fa215f0-0002-4b0e-b682-1a4c70f3a601"

constexpr const char *DEVICE_BASE_NAME = "Meso Nose";
String Device_Name;

const char *OFFLINE_FILE = "/offline_data.json";

constexpr unsigned long FIVE_MINUTES_IN_MS = 300000UL;
constexpr size_t MAX_OFFLINE_FILE_SIZE_BYTES = 200000;
constexpr uint32_t SERIAL_BAUD_RATE = 115200;
constexpr uint32_t I2C_CLOCK_SPEED_HZ = 100000;
constexpr uint32_t I2C_BUS_TIMEOUT_MS = 1000;

constexpr uint16_t BLE_ADV_FAST_MIN_INTERVAL_UNITS = 160;
constexpr uint16_t BLE_ADV_FAST_MAX_INTERVAL_UNITS = 320;
constexpr uint16_t BLE_ADV_ULP_MIN_INTERVAL_UNITS = 1600;
constexpr uint16_t BLE_ADV_ULP_MAX_INTERVAL_UNITS = 3200;
constexpr unsigned long FAST_ADV_BURST_WINDOW_MS = 30000UL;

constexpr uint8_t BATTERY_ADC_SAMPLES = 4;
constexpr uint8_t BATTERY_ADC_RESOLUTION_BITS = 12;
constexpr uint32_t BATTERY_SAMPLE_DELAY_MS = 5;
constexpr float BATTERY_MIN_VOLTS = 3.3f;
constexpr float BATTERY_MAX_VOLTS = 4.2f;
constexpr float BATTERY_VALID_LOWER_BOUND_VOLTS = 2.0f;
constexpr float BATTERY_VOLTAGE_DIVISER_FACTOR = 2.0f;
constexpr uint32_t BLE_FLUSH_DELAY_MS = 30;

constexpr uint32_t NOTIFY_ULP_INTERVAL_MS = 300000;
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS = 30000;
constexpr uint32_t BREATH_SENSING_WINDOW_MS = 10000; 
constexpr uint32_t RECOVERY_SENSING_WINDOW_MS = 15000; 
constexpr uint32_t POLL_TICK_DELAY_MS = 20;

constexpr float BREATH_FRESH_MAX_DROP_PCT = 15.0f;
constexpr float BREATH_SIGNIFICANT_MAX_DROP_PCT = 45.0f;
constexpr float DRY_MOUTH_MAX_DELTA_RH_PCT = 2.5f;
constexpr float DRY_MOUTH_MIN_DELTA_CO2_PPM = 250.0f;
constexpr float RECOVERY_LAG_MALODOR_THRESHOLD = 3.5f; 

constexpr uint8_t BASELINE_TARGET_SAMPLE_COUNT = 3; 
constexpr uint32_t BASELINE_CAPTURE_TIMEOUT_MS = 15000UL;
constexpr float HW_MIN_SENSOR_GAS_RES = 5000.0f;

constexpr float PARTIAL_EXHALATION_MIN_DELTA_RH_PCT = 0.8f;
constexpr float PARTIAL_EXHALATION_MIN_DELTA_CO2_PPM = 100.0f;
constexpr float EXHALATION_MIN_MOISTURE_DELTA_RH_PCT = 20.0f;
constexpr float EXHALATION_MIN_GAS_DROP_PCT          = 5.0f;

constexpr const char *STATE_EXHALATION_TOO_WEAK = "EXHALATION_TOO_WEAK";
constexpr const char *STATE_TRY_AGAIN_LATER = "TRY_AGAIN_LATER";
constexpr const char *STATE_READY_PLEASE_BLOW = "READY_PLEASE_BLOW";
constexpr const char *STATE_TESTING_SENSING_BREATH = "TESTING_SENSING_BREATH";
constexpr const char *STATE_TIMEOUT = "TIMEOUT";
constexpr const char *STATUS_BREATH_TEST_STARTED = "BREATH_TEST_STARTED";
constexpr const char *STATUS_BREATH_TEST_COMPLETE = "BREATH_TEST_COMPLETE";

constexpr const char *RESULT_NONE = "NONE";
constexpr const char *RESULT_DRY_MOUTH_HYDRATE = "DRY_MOUTH_HYDRATE";
constexpr const char *RESULT_DRY_MOUTH_VSC_BUILDUP = "DRY_MOUTH_VSC_BUILDUP";
constexpr const char *RESULT_SETTLE_BEVERAGE_FOOD_ODOR = "SETTLE_BEVERAGE_FOOD_ODOR";
constexpr const char *RESULT_BALANCED_BREATH = "BALANCED_BREATH";
constexpr const char *RESULT_SOME_BEVERAGE_FOOD_ODOR = "SOME_BEVERAGE_FOOD_ODOR";
constexpr const char *RESULT_NOTICEABLE_MALODOR = "NOTICEABLE_MALODOR";
constexpr const char *RESULT_STRONG_MALODOR = "STRONG_MALODOR";

bool systemReady = false;
enum OperationMode { MODE_IDLE, MODE_DRY_AIR_DETECTION, MODE_BREATH_TEST };
enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };

OperationMode currentMode = MODE_IDLE;
BsecProfile currentProfile = PROFILE_OFF;

bool dryAirActive = false;
bool deviceConnected = false;
bool bsecReady = false;
volatile bool newGasDataAvailable = false;
volatile bool pendingBreathCommand = false;
volatile bool pendingFlush = false;
uint8_t bmeI2cAddr = BME68X_I2C_ADDR_HIGH;

unsigned long lastOfflineWriteTime = 0;
float accumTemp = 0.0f, accumHumidity = 0.0f, accumPressure = 0.0f, accumGasRes = 0.0f;
int accumCount = 0;
char pendingCmdBuf[32] = { 0 };
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
  if (!bsec) return false;
  return bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_LP);
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
      case BSEC_OUTPUT_CO2_EQUIVALENT:
        sensorData.currentCO2 = output.signal;
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

bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp, float &outBaseCO2) {
  logMessage("[PREPARE BASELINE]: Capturing samples from BSEC LP Mode...");
  
  if (!updateBsecSubscription(BSEC_SAMPLE_RATE_LP)) {
    logMessage("[PREPARE BASELINE ERROR]: Failed to transition to LP Mode!");
    return false;
  }
  currentProfile = PROFILE_LP_3S;
  
  float sumRes = 0.0f, sumHumidity = 0.0f, sumTemp = 0.0f, sumCO2 = 0.0f;
  uint8_t validCount = 0;
  uint32_t startMs = millis();

  while (validCount < BASELINE_TARGET_SAMPLE_COUNT && ((millis() - startMs) < BASELINE_CAPTURE_TIMEOUT_MS)) {
    float rawRes = 0.0f;
    if (readBsecFrame(rawRes)) {
      if (rawRes >= HW_MIN_SENSOR_GAS_RES) {
        sumRes += rawRes; 
        sumHumidity += sensorData.currentHumidity;
        sumTemp += sensorData.currentTemp; 
        sumCO2 += sensorData.currentCO2;
        validCount++;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  if (validCount == 0) return false;

  outBaselineRes = sumRes / validCount;
  outBaseHumidity = sumHumidity / validCount;
  outBaseTemp = sumTemp / validCount;
  outBaseCO2 = sumCO2 / validCount;
  return true;
}

bool waitForBreathExhalation(float baseGasRes, float baseHumidity, float baseTemp, float baseCO2,
                             float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  dispatchData("{\"state\":\"" + String(STATE_READY_PLEASE_BLOW) + "\"}");
  uint32_t startMs = millis();
  outMaxDeltaRH = 0.0f; 
  outMaxDeltaCO2 = 0.0f;

  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    float currentGasRes = 0.0f;
    if (readBsecFrame(currentGasRes)) {
      float deltaHumidity = sensorData.currentHumidity - baseHumidity;
      float deltaCO2      = sensorData.currentCO2 - baseCO2;
      float gasDropPct    = (baseGasRes > 0.0f) ? (((baseGasRes - currentGasRes) / baseGasRes) * 100.0f) : 0.0f;

      if (currentGasRes < outMinRes) outMinRes = currentGasRes;
      if (deltaHumidity > outMaxDeltaRH) outMaxDeltaRH = deltaHumidity;
      if (deltaCO2 > outMaxDeltaCO2) outMaxDeltaCO2 = deltaCO2;

      dispatchData("{\"dH\":" + String(deltaHumidity, 1) + ",\"dCO2\":" + String(deltaCO2, 0) + ",\"gDrop\":" + String(gasDropPct, 1) + "}");

      bool isMoistSpike = (deltaHumidity >= EXHALATION_MIN_MOISTURE_DELTA_RH_PCT);
      bool isGasDrop = (gasDropPct >= EXHALATION_MIN_GAS_DROP_PCT);
      if (baseHumidity >= 80.0f && isGasDrop) return true;
      if (isMoistSpike && isGasDrop) return true;
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
  return false;
}

void captureBreathSensingWindow(float baseRes, float baseHumidity, float baseCO2,
                                float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  dispatchData("{\"state\":\"" + String(STATE_TESTING_SENSING_BREATH) + "\"}");
  uint32_t windowStartMs = millis();
  outMinRes = baseRes;

  while ((millis() - windowStartMs) < BREATH_SENSING_WINDOW_MS) {
    float currentGasRes = 0.0f;
    if (readBsecFrame(currentGasRes)) {
      float deltaRH = sensorData.currentHumidity - baseHumidity;
      float deltaCO2 = sensorData.currentCO2 - baseCO2;
      if (currentGasRes > HW_MIN_SENSOR_GAS_RES && currentGasRes < outMinRes) outMinRes = currentGasRes;
      if (deltaRH > outMaxDeltaRH) outMaxDeltaRH = deltaRH;
      if (deltaCO2 > outMaxDeltaCO2) outMaxDeltaCO2 = deltaCO2;
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}

void captureRecoveryWindow(float minRes, float baseRes, float &outRecoveryLag) {
  dispatchData("{\"state\":\"RECOVERING_CALCULATING_T50\"}");
  uint32_t startMs = millis();
  float target50 = minRes + 0.5f * (baseRes - minRes);
  outRecoveryLag = 10.0f; 
  
  while ((millis() - startMs) < RECOVERY_SENSING_WINDOW_MS) {
    float rGas = 0.0f;
    if (readBsecFrame(rGas)) {
      if (rGas >= target50) {
        outRecoveryLag = (millis() - startMs) / 1000.0f;
        break;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
  logMessage("[KINETICS]: T50 Recovery Lag = " + String(outRecoveryLag) + "s");
}

String evaluateBreathResult(float deltaDrop, float maxDeltaHumidity, float maxDeltaCO2, float recoveryLagSec) {
  const bool isDryMouth = (maxDeltaHumidity < DRY_MOUTH_MAX_DELTA_RH_PCT) && 
                          (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT || maxDeltaCO2 >= DRY_MOUTH_MIN_DELTA_CO2_PPM);
  const bool validMoisture = (maxDeltaHumidity >= DRY_MOUTH_MAX_DELTA_RH_PCT);

  const bool isSlowRecovery = (recoveryLagSec >= RECOVERY_LAG_MALODOR_THRESHOLD); // >= 3.5s
  const bool isFastRecovery = (recoveryLagSec < RECOVERY_LAG_MALODOR_THRESHOLD);   // < 3.5s

  const bool isSubThresholdDrop = (deltaDrop < BREATH_FRESH_MAX_DROP_PCT); // < 15%
  const bool isSlightDrop = (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT);
  const bool isModerateDrop = (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT) && (deltaDrop < BREATH_SIGNIFICANT_MAX_DROP_PCT);
  const bool isSevereDrop = (deltaDrop >= BREATH_SIGNIFICANT_MAX_DROP_PCT);

  // Dry mouth conditions
  if (isDryMouth && isFastRecovery) return RESULT_DRY_MOUTH_HYDRATE;
  if (isDryMouth && isSlowRecovery) return RESULT_DRY_MOUTH_VSC_BUILDUP;

  // Sub-threshold drop (< 15%) conditions
  if (validMoisture && isSubThresholdDrop && isFastRecovery) return RESULT_BALANCED_BREATH;
  if (validMoisture && isSubThresholdDrop && isSlowRecovery) return RESULT_SETTLE_BEVERAGE_FOOD_ODOR;

  // Significant drop (>= 15%) conditions
  if (validMoisture && isSlightDrop && isFastRecovery) return RESULT_SOME_BEVERAGE_FOOD_ODOR;
  if (validMoisture && isModerateDrop && isSlowRecovery) return RESULT_NOTICEABLE_MALODOR;
  if (validMoisture && isSevereDrop && isSlowRecovery) return RESULT_STRONG_MALODOR;

  return RESULT_NONE;
}

void processBreathTestResults(float baseRes, float minRes, float maxDeltaHumidity, float maxDeltaCO2, float recoveryLag) {
  float deltaDrop = (baseRes > 0.0f) ? (((baseRes - minRes) / baseRes) * 100.0f) : 0.0f;
  if (deltaDrop < 0.0f) deltaDrop = 0.0f;

  sensorData.currentGasRes = minRes;
  sensorData.deltaDrop = deltaDrop;
  sensorData.rBreathMin = (long)minRes;
  sensorData.recoveryLagSec = recoveryLag;
  sensorData.ptcResult = evaluateBreathResult(deltaDrop, maxDeltaHumidity, maxDeltaCO2, recoveryLag);

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_COMPLETE) + "\"}");
  dispatchData(sensorData.toJsonString());
}

void runBreathSequence() {
  logMessage("[SEQUENCE START]: Breath test sequence initiated (Pure BSEC LP).");

  // Clear stale metrics from previous tests
  sensorData.deltaDrop = 0.0f;
  sensorData.recoveryLagSec = 0.0f;
  sensorData.rBreathMin = 0;
  sensorData.ptcResult = RESULT_NONE;

  float ambientCO2 = sensorData.currentCO2;
  float ambientTemp = sensorData.currentTemp;
  float ambientRH = sensorData.currentHumidity;
  dryAirActive = false; 
  currentMode = MODE_BREATH_TEST;

  float baseRes = 0.0f, baseHumidity = ambientRH, baseTemp = ambientTemp, baseCO2 = ambientCO2;
  float maxDeltaRH = 0.0f, maxDeltaCO2 = 0.0f;
  float recoveryLag = 0.0f;

  if (!prepareAndCaptureBaseline(baseRes, baseHumidity, baseTemp, baseCO2)) {
    updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
    currentProfile = PROFILE_LP_3S;
    return;
  }

  float minRes = baseRes;
  if (waitForBreathExhalation(baseRes, baseHumidity, baseTemp, baseCO2, minRes, maxDeltaRH, maxDeltaCO2)) {
    captureBreathSensingWindow(baseRes, baseHumidity, baseCO2, minRes, maxDeltaRH, maxDeltaCO2);
    captureRecoveryWindow(minRes, baseRes, recoveryLag);
    processBreathTestResults(baseRes, minRes, maxDeltaRH, maxDeltaCO2, recoveryLag);
  } else {
    const bool isWeakExhalationDetected = (maxDeltaRH >= PARTIAL_EXHALATION_MIN_DELTA_RH_PCT);

    if (isWeakExhalationDetected) {
      dispatchData("{\"state\":\"" + String(STATE_EXHALATION_TOO_WEAK) + "\"}");
    } else {
      dispatchData("{\"state\":\"" + String(STATE_TIMEOUT) + "\"}");
    }
  }
  
  updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
  currentProfile = PROFILE_LP_3S;
  currentMode = MODE_DRY_AIR_DETECTION;
}

uint8_t readBatteryPercentage() {
  uint32_t totalMv = 0;
  for (int i = 0; i < BATTERY_ADC_SAMPLES; i++) {
    totalMv += analogReadMilliVolts(BATTERY_ADC_PIN);
    vTaskDelay(pdMS_TO_TICKS(BATTERY_SAMPLE_DELAY_MS));
  }
  float voltage = (((float)totalMv / BATTERY_ADC_SAMPLES) / 1000.0f) * BATTERY_VOLTAGE_DIVISER_FACTOR;
  if (voltage < BATTERY_VALID_LOWER_BOUND_VOLTS || voltage >= BATTERY_MAX_VOLTS) return 100;
  if (voltage <= BATTERY_MIN_VOLTS) return 0;
  return (uint8_t)(((voltage - BATTERY_MIN_VOLTS) / (BATTERY_MAX_VOLTS - BATTERY_MIN_VOLTS)) * 100.0f);
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
    
    File file = LittleFS.open(OFFLINE_FILE, FILE_APPEND);
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
  if (!LittleFS.exists(OFFLINE_FILE)) return;
  File file = LittleFS.open(OFFLINE_FILE, FILE_READ);
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
  LittleFS.remove(OFFLINE_FILE);
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
  dispatchData("{\"rx_cmd\":\"" + command + "\"}");
  if (command == "3" || command == "b" || command == "breath") {
    if (!systemReady || !bsecReady || currentMode == MODE_BREATH_TEST) return;
    dryAirActive = false; 
    currentMode = MODE_BREATH_TEST; 
    pendingBreathCommand = true;
  } else if (command == "test_selectivity" || command == "99") {
    logMessage("[CMD RX]: Launching Selectivity Diagnostic Self-Test...");
    runSelectivityDiagnosticTest();
  }
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo) { 
    deviceConnected = true; 
    pendingFlush = true; 
    
    if (bsec != nullptr && currentMode != MODE_BREATH_TEST) {
      updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
      currentProfile = PROFILE_LP_3S;
      logMessage("[BLE CONNECT]: Maintained BSEC LP 3s Mode.");
    }
  }
  void onDisconnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo, int reason) { 
    deviceConnected = false; 
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
  static unsigned long disconnectTime = 0;
  static bool isInLowPowerAdvertising = false;
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  if (newlyDisconnected) {
    disconnectTime = millis();
    isInLowPowerAdvertising = false;
    pAdvertising->setMinInterval(BLE_ADV_FAST_MIN_INTERVAL_UNITS);
    pAdvertising->setMaxInterval(BLE_ADV_FAST_MAX_INTERVAL_UNITS);
    pAdvertising->start();
  } else if (!deviceConnected && !isInLowPowerAdvertising && ((millis() - disconnectTime) > FAST_ADV_BURST_WINDOW_MS)) {
    isInLowPowerAdvertising = true;
    pAdvertising->stop();
    pAdvertising->setMinInterval(BLE_ADV_ULP_MIN_INTERVAL_UNITS);
    pAdvertising->setMaxInterval(BLE_ADV_ULP_MAX_INTERVAL_UNITS);
    pAdvertising->start();
  }
}

void setup() {
  Serial.begin(SERIAL_BAUD_RATE); 
  delay(2000);
  pinMode(BATTERY_ADC_PIN, INPUT); 
  analogReadResolution(BATTERY_ADC_RESOLUTION_BITS); 
  analogSetPinAttenuation(BATTERY_ADC_PIN, ADC_11db);
  LittleFS.begin(true, "/littlefs", 10, "spiffs");

  NimBLEDevice::init(Device_Name.c_str());
  pServer = NimBLEDevice::createServer(); 
  pServer->setCallbacks(new ServerCallbacks());
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY);
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start(); 
  NimBLEDevice::getAdvertising()->start();

  Wire.begin(I2C_SDA, I2C_SCL); 
  Wire.setClock(I2C_CLOCK_SPEED_HZ); 
  Wire.setTimeOut(I2C_BUS_TIMEOUT_MS);
  
  bsec = new Bsec2();
  if (bsec->begin(bmeI2cAddr, Wire)) {
    if (!bsec->setConfig(bsec_config_iaq)) {
      logMessage("[BSEC WARN]: Custom setConfig failed (Code: " + String(bsec->status) + ")");
    }
    
    bsecReady = true; 
    currentProfile = PROFILE_LP_3S;
    updateBsecSubscription(BSEC_SAMPLE_RATE_LP);
    bsec->attachCallback(newDataCallback);
  }
  systemReady = true;
}

void loop() {
  adjustAdvertisingPower(false);

  if (Serial.available() > 0) handleCommand(Serial.readStringUntil('\n'));
  if (hasPendingCommand) { hasPendingCommand = false; handleCommand(String(pendingCmdBuf)); }
  if (pendingFlush && deviceConnected) { pendingFlush = false; flushOfflineData(); }
  if (pendingBreathCommand) { pendingBreathCommand = false; runBreathSequence(); return; }

  if (bsecReady && bsec != nullptr && bsec->status >= BSEC_OK && currentProfile != PROFILE_OFF) {
    bsec->run();
    static unsigned long lastNotifyTime = 0;
    if ((millis() - lastNotifyTime) >= NOTIFY_ULP_INTERVAL_MS) {
      lastNotifyTime = millis();
      if (sensorData.currentGasRes > 0.0f) {
        sensorData.batteryPct = readBatteryPercentage();
        dispatchData(sensorData.toJsonString());
      }
    }
  }
  vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
}