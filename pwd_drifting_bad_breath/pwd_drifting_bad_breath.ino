#include <Wire.h>
#include <FS.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"
#include <bme68xLibrary.h>
#include "bsec_selectivity.h"
#include "diagnostics.h"

#define ENABLE_SERIAL_LOGS true
#define BATTERY_ADC_PIN 0
#define I2C_SDA 6
#define I2C_SCL 7

#define SERVICE_UUID "4fa215f0-0001-4b0e-b682-1a4c70f3a601"
#define CHARACTERISTIC_UUID "4fa215f0-0002-4b0e-b682-1a4c70f3a601"

constexpr const char *DEVICE_BASE_NAME = "Meso Nose";
String Device_Name;

const char *OFFLINE_FILE = "/offline_data.json";

// Storage & Watermark Constants
constexpr unsigned long FIVE_MINUTES_IN_MS = 300000UL;
constexpr size_t MAX_OFFLINE_FILE_SIZE_BYTES = 200000;

// Dynamic Advertising & Timing Constants
constexpr uint16_t BLE_ADV_FAST_MIN_INTERVAL_UNITS = 160;
constexpr uint16_t BLE_ADV_FAST_MAX_INTERVAL_UNITS = 320;
constexpr uint16_t BLE_ADV_ULP_MIN_INTERVAL_UNITS = 1600;
constexpr uint16_t BLE_ADV_ULP_MAX_INTERVAL_UNITS = 3200;
constexpr unsigned long FAST_ADV_BURST_WINDOW_MS = 30000UL;

// Hardware, Serial, Bus & Battery Constants
constexpr uint32_t SERIAL_BAUD_RATE = 115200;
constexpr uint32_t I2C_CLOCK_SPEED_HZ = 100000;
constexpr uint32_t I2C_BUS_TIMEOUT_MS = 1000;
constexpr float PRESSURE_HPA_DIVISOR = 1.0f;
constexpr uint32_t CPU_LOW_POWER_FREQ_MHZ = 80;

constexpr uint32_t SERIAL_INIT_DELAY_MS = 500;
constexpr uint32_t BLE_POST_INIT_DELAY_MS = 200;
constexpr uint32_t I2C_BUS_RESET_DELAY_MS = 50;
constexpr uint32_t I2C_BUS_SETTLE_DELAY_MS = 100;

constexpr uint8_t BATTERY_ADC_SAMPLES = 4;
constexpr uint8_t BATTERY_ADC_RESOLUTION_BITS = 12;
constexpr uint32_t BATTERY_SAMPLE_DELAY_MS = 5;
constexpr float BATTERY_MIN_VOLTS = 3.3f;
constexpr float BATTERY_MAX_VOLTS = 4.2f;
constexpr float BATTERY_VALID_LOWER_BOUND_VOLTS = 2.0f;
constexpr float BATTERY_VOLTAGE_DIVISER_FACTOR = 2.0f;

constexpr uint32_t BLE_FLUSH_DELAY_MS = 30;

// Operational Timing Constants
constexpr uint32_t NOTIFY_LP_INTERVAL_MS = 3000;
constexpr uint32_t NOTIFY_ULP_INTERVAL_MS = 300000;
constexpr uint32_t WARMUP_SHORT_DELAY_MS = 4000;
constexpr uint32_t WARMUP_LONG_DELAY_MS = 15000;
constexpr uint32_t SELECTIVITY_WARMUP_DELAY_MS = 4000;
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS = 30000;
constexpr uint32_t BREATH_SENSING_WINDOW_MS = 10000; // 10 seconds 
constexpr uint32_t LOOP_TICK_DELAY_MS = 20;
constexpr uint32_t POLL_TICK_DELAY_MS = 20;
constexpr uint32_t LOW_LEVEL_STEP_DELAY_MS = 150;

constexpr uint32_t DIAG_LOG_INTERVAL_MS = 3000;
constexpr uint32_t DIAG_HEARTBEAT_INTERVAL_MS = 2000;
constexpr uint32_t BSEC_PROFILE_SETTLE_DELAY_MS = 50;

// Physical Thresholds & Evaluation Constants
constexpr float BREATH_FRESH_MAX_DROP_PCT = 15.0f;
constexpr float BREATH_SIGNIFICANT_MAX_DROP_PCT = 45.0f;
constexpr float SELECTIVITY_RATIO_MALODOR_THRESHOLD = 0.5f;

constexpr float DRY_MOUTH_MAX_DELTA_RH_PCT = 2.5f;
constexpr float DRY_MOUTH_MIN_DELTA_CO2_PPM = 250.0f;

constexpr uint8_t BASELINE_TARGET_SAMPLE_COUNT = 10;
constexpr uint32_t BASELINE_CAPTURE_TIMEOUT_MS = 100000UL;

constexpr float HW_MIN_SENSOR_GAS_RES = 5000.0f;
constexpr float HW_MAX_SENSOR_GAS_RES = 1000000.0f;
constexpr float HW_MAX_TRANSIENT_GAS_RES = 100000000.0f;

constexpr float BASELINE_STABLE_MIN_GAS_RES = 5000.0f;
constexpr float BASELINE_STABLE_MAX_GAS_RES = 100000000.0f; // Expanded to 100 Mohm
constexpr uint8_t HEATER_STEP_200C_COOL_PLATE = 0; // Profile Step 0 (200°C - Low Temp / High Resistance)
constexpr uint8_t HEATER_STEP_400C_HOT_PLATE  = 5; // Profile Step 5 (400°C - High Temp / Low Resistance)

constexpr float BASELINE_MIN_VALID_CO2_PPM = 350.0f;
constexpr float BASELINE_MAX_VALID_CO2_PPM = 2000.0f;

constexpr float PARTIAL_EXHALATION_MIN_DELTA_RH_PCT = 0.8f;
constexpr float PARTIAL_EXHALATION_MIN_DELTA_CO2_PPM = 100.0f;

constexpr float EXHALATION_MIN_MOISTURE_DELTA_RH_PCT = 15.0f;
constexpr float EXHALATION_MIN_TEMP_DELTA_C = 0.5f;
constexpr float EXHALATION_MIN_CO2_DELTA_PPM = 100.0f;
constexpr float EXHALATION_MIN_GAS_DROP_PCT = 10.0f;
constexpr float EXHALATION_MAX_GAS_DROP_PCT = 95.0f;

constexpr float SELECTIVITY_MIN_VALID_GAS_RES = 5000.0f;
constexpr float SELECTIVITY_RATIO_MIN = 0.0f;
constexpr float SELECTIVITY_RATIO_MAX = 2.0f;

constexpr const char *STATE_EXHALATION_TOO_WEAK = "EXHALATION_TOO_WEAK";
constexpr const char *STATE_TRY_AGAIN_LATER = "TRY_AGAIN_LATER";
constexpr const char *STATE_ROOM_AIR_DIRTY = "ROOM_AIR_DIRTY_VENTILATE";
constexpr const char *STATE_READY_PLEASE_BLOW = "READY_PLEASE_BLOW";
constexpr const char *STATE_TESTING_SENSING_BREATH = "TESTING_SENSING_BREATH";
constexpr const char *STATE_TIMEOUT = "TIMEOUT";
constexpr const char *STATE_WARMING_UP = "WARMING_UP";

constexpr const char *STATUS_DRY_AIR_STARTED = "DRY_AIR_STARTED";
constexpr const char *STATUS_DRY_AIR_STOPPED = "DRY_AIR_STOPPED";
constexpr const char *STATUS_BREATH_TEST_STARTED = "BREATH_TEST_STARTED";
constexpr const char *STATUS_BREATH_TEST_COMPLETE = "BREATH_TEST_COMPLETE";
constexpr const char *STATE_DEVICE_INITIALIZING = "DEVICE_INITIALIZING";

bool systemReady = false;

constexpr const char *RESULT_NONE = "NONE";
constexpr const char *RESULT_DRY_MOUTH_HYDRATE = "DRY_MOUTH_HYDRATE";
constexpr const char *RESULT_DRY_MOUTH_VSC_BUILDUP = "DRY_MOUTH_VSC_BUILDUP";
constexpr const char *RESULT_SETTLE_BEVERAGE_FOOD_ODOR = "SETTLE_BEVERAGE_FOOD_ODOR";
constexpr const char *RESULT_BALANCED_BREATH = "BALANCED_BREATH";
constexpr const char *RESULT_SOME_BEVERAGE_FOOD_ODOR = "SOME_BEVERAGE_FOOD_ODOR";
constexpr const char *RESULT_NOTICEABLE_MALODOR = "NOTICEABLE_MALODOR";
constexpr const char *RESULT_STRONG_MALODOR = "STRONG_MALODOR";

float rGas_at_200C_CoolPlate = 0.0f; // High physical resistance at 200°C
float rGas_at_400C_HotPlate  = 0.0f; // Low physical resistance at 400°C

enum OperationMode { MODE_IDLE,
                     MODE_DRY_AIR_DETECTION,
                     MODE_BREATH_TEST };
enum BsecProfile { PROFILE_OFF,
                   PROFILE_ULP_300S,
                   PROFILE_LP_3S };

OperationMode currentMode = MODE_IDLE;
BsecProfile currentProfile = PROFILE_OFF;

bool dryAirActive = false;
bool deviceConnected = false;
bool bsecReady = false;
volatile bool newGasDataAvailable = false;
volatile bool pendingBreathCommand = false;
volatile bool pendingFlush = false;
uint8_t bmeI2cAddr = BME68X_I2C_ADDR_HIGH;
float selectivityRatio = 1.0f;
static uint8_t forcedStepIndex = 0;

unsigned long lastOfflineWriteTime = 0;
float accumTemp = 0.0f;
float accumHumidity = 0.0f;
float accumPressure = 0.0f;
float accumGasRes = 0.0f;
int accumCount = 0;
char pendingCmdBuf[32] = { 0 };
volatile bool hasPendingCommand = false;

struct SensorData {
  float currentTemp = 0.0f;
  float currentHumidity = 0.0f;
  float currentPressure = 0.0f;
  float currentGasRes = 0.0f;
  uint8_t currentHeaterStep = 0;
  float currentCO2 = 0.0f;
  uint8_t bsecAccuracy = 0;
  float deltaDrop = 0.0f;
  float selectivityRatio = 1.0f;
  long rBreathMin = 0;
  String ptcResult = RESULT_NONE;
  uint8_t batteryPct = 100;

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
    json += "\"breath_min\":" + String(rBreathMin) + ",";
    json += "\"ptc_result\":\"" + ptcResult + "\"";
    json += "}";
    return json;
  }
};

SensorData sensorData;

bsecSensor defaultSensorList[] = {
  BSEC_OUTPUT_RAW_GAS,
  BSEC_OUTPUT_RAW_TEMPERATURE,
  BSEC_OUTPUT_RAW_HUMIDITY,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
  BSEC_OUTPUT_RAW_PRESSURE,
  BSEC_OUTPUT_CO2_EQUIVALENT,
  BSEC_OUTPUT_IAQ
};
uint8_t numDefaultSensors = sizeof(defaultSensorList) / sizeof(bsecSensor);

Bsec2 *bsec = nullptr;
Bme68x bme; // Official Bosch C++ Driver Instance

NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

uint16_t bmeTempProf[10] = { 200, 240, 280, 320, 360, 400, 360, 320, 280, 240 };
uint16_t bmeDurProf[10]  = { 140, 140, 140, 140, 140, 140, 140, 140, 140, 140 };

// Forward Declarations
void dispatchData(String payload);
void logMessage(String msg);
void updateSelectivityRatio(float rawGasRes, uint8_t heaterStep);
bool validateBaselineQuality(float avgRes, float avgCO2);
static void processBreathTestResults(float baseRes, float minRes, float maxDeltaHumidity, float maxDeltaCO2);
static void clearI2CBus();
void setBsecProfile(BsecProfile profile);
void adjustAdvertisingPower(bool newlyDisconnected);
void saveOfflineData();
void flushOfflineData();
void performWarmup();
bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp, float &outBaseCO2);
bool waitAndCaptureBreath(float baseRes, float baseHumidity, float baseTemp, float baseCO2, float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2);
String evaluateBreathResult(float deltaDrop, float maxDeltaHumidity, float maxDeltaCO2, float selectivityRatio);
uint8_t readBatteryPercentage();
void runBreathSequence();
void printStoredFileToSerial();
void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsecInst);
void softResetBme688Sensor();
bool configureLowLevelParallelScan();
bool readLowLevelScanFrame(float &outGasRes, uint8_t &outStep);

void logMessage(String msg) {
#if ENABLE_SERIAL_LOGS
  Serial.println(msg);
  Serial.flush();
#endif
  if (deviceConnected && pCharacteristic) {
    String bleLog = "[LOG]: " + msg + "\n";
    pCharacteristic->setValue((uint8_t *)bleLog.c_str(), bleLog.length());
    pCharacteristic->notify();
  }
}

void reinitBsecInstance() {
  if (bsec != nullptr) {
    delete bsec;
    bsec = nullptr;
  }
  bsec = new Bsec2();
}

void setBsecProfile(BsecProfile profile) {
  if (bsec == nullptr) return;

  logMessage("[SET_PROFILE START]: Target Profile = " + String((int)profile) + " | Current Profile = " + String((int)currentProfile) + " | Initial status = " + String((int)bsec->status));

  if (currentProfile == profile) {
    logMessage("[SET_PROFILE SKIPPED]: Target profile matches current profile.");
    return;
  }

  newGasDataAvailable = false;

  if (profile == PROFILE_OFF) {
    logMessage("[SET_PROFILE OFF]: Step 1 - Unsubscribing BSEC...");
    bool subSuccess = bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_DISABLED);
    logMessage("[SET_PROFILE OFF]: Unsubscribe result = " + String(subSuccess ? "YES" : "NO") + " | status = " + String((int)bsec->status));

    currentProfile = profile;
    dispatchData("{\"state\":\"PROFILE_OFF\"}");
  } else if (profile == PROFILE_ULP_300S) {
    logMessage("[SET_PROFILE ULP]: Setting standard ULP 300s mode...");

    bool subSuccess = bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_ULP);
    bsec->attachCallback(newDataCallback);

    logMessage("[SET_PROFILE ULP]: Subscribe result = " + String(subSuccess ? "YES" : "NO") + " | status = " + String((int)bsec->status));

    currentProfile = profile;
    dispatchData("{\"state\":\"PROFILE_ULP\"}");
  } else if (profile == PROFILE_LP_3S) {
    logMessage("[SET_PROFILE LP]: Setting standard continuous 3s LP mode...");

    bool subSuccess = bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_LP);
    bsec->attachCallback(newDataCallback);

    logMessage("[SET_PROFILE LP]: LP Subscribe result = " + String(subSuccess ? "YES" : "NO") + " | status = " + String((int)bsec->status));

    currentProfile = profile;
    dispatchData("{\"state\":\"PROFILE_LP\"}");
  }

  logMessage("[SET_PROFILE COMPLETE]: Final status = " + String((int)bsec->status) + " | Active Profile = " + String((int)currentProfile));
  vTaskDelay(pdMS_TO_TICKS(BSEC_PROFILE_SETTLE_DELAY_MS));
}

void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsecInst) {
#if ENABLE_SERIAL_LOGS
  Serial.printf("[RAW CALLBACK FIRED @ %lu ms]: nOutputs = %d | BSEC Status = %d\n",
                millis(), outputs.nOutputs, (int)bsecInst.status);
#endif

  if (!outputs.nOutputs) {
    logMessage("[BSEC CALLBACK NULL @ " + String(millis()) + " ms]: Fired with 0 outputs!");
    return;
  }

  bool gasFound = false;

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
        sensorData.currentPressure = output.signal;
        break;

      case BSEC_OUTPUT_RAW_GAS:
      case BSEC_OUTPUT_GAS_ESTIMATE_1:
      case BSEC_OUTPUT_GAS_ESTIMATE_2:
      case BSEC_OUTPUT_GAS_ESTIMATE_3:
      case BSEC_OUTPUT_GAS_ESTIMATE_4:
        gasFound = true;
        sensorData.currentGasRes = (output.signal > 0.0f) ? output.signal : data.gas_resistance;
        sensorData.currentHeaterStep = data.gas_index;
        newGasDataAvailable = true;
        updateSelectivityRatio(sensorData.currentGasRes, data.gas_index);
        break;

      case BSEC_OUTPUT_RAW_GAS_INDEX:
        sensorData.currentHeaterStep = (uint8_t)output.signal;
        if (data.gas_resistance >= HW_MIN_SENSOR_GAS_RES) {
          gasFound = true;
          sensorData.currentGasRes = data.gas_resistance;
          newGasDataAvailable = true;
          updateSelectivityRatio(sensorData.currentGasRes, data.gas_index);
        }
        break;

      case BSEC_OUTPUT_CO2_EQUIVALENT:
        sensorData.currentCO2 = output.signal;
        sensorData.bsecAccuracy = output.accuracy;
        break;
      case BSEC_OUTPUT_IAQ:
        sensorData.bsecAccuracy = output.accuracy;
        break;
      default:
        break;
    }
  }
}

void updateSelectivityRatio(float rawGasRes, uint8_t currentHeaterStep) {
  // 1. Capture physical resistance at 200°C (Step 0)
  if (currentHeaterStep == HEATER_STEP_200C_COOL_PLATE) {
    rGas_at_200C_CoolPlate = rawGasRes;
  } 
  // 2. Capture physical resistance at 400°C (Step 5)
  else if (currentHeaterStep == HEATER_STEP_400C_HOT_PLATE) {
    rGas_at_400C_HotPlate = rawGasRes;
  }

  // 3. Compute Selectivity Ratio: R(200°C) / R(400°C)
  const bool hasValidCoolPlateReading = (rGas_at_200C_CoolPlate > SELECTIVITY_MIN_VALID_GAS_RES);
  const bool hasValidHotPlateReading  = (rGas_at_400C_HotPlate > SELECTIVITY_MIN_VALID_GAS_RES);

  if (hasValidCoolPlateReading && hasValidHotPlateReading) {
    float rawRatio = rGas_at_200C_CoolPlate / rGas_at_400C_HotPlate;

    // Clamp ratio within valid bounds
    if (rawRatio < SELECTIVITY_RATIO_MIN) rawRatio = SELECTIVITY_RATIO_MIN;
    if (rawRatio > SELECTIVITY_RATIO_MAX) rawRatio = SELECTIVITY_RATIO_MAX;

    selectivityRatio = rawRatio;

#if ENABLE_SERIAL_LOGS
    Serial.printf("[SELECTIVITY UPDATE]: Step=%d | R_200C=%.0f, R_400C=%.0f | Selectivity Ratio=%.2f\n",
                  currentHeaterStep, rGas_at_200C_CoolPlate, rGas_at_400C_HotPlate, selectivityRatio);
#endif
  }
}

// -------------------------------------------------------------------
// Official Bosch Bme68x Library Hardware Hand-Off
// -------------------------------------------------------------------
bool configureLowLevelParallelScan() {
  logMessage("[DRIVER HAND-OFF]: Initializing Bosch bme68x C++ Class Driver...");

  bme.begin(bmeI2cAddr, Wire);
  if (bme.checkStatus() < BME68X_OK) {
    logMessage("[ERROR]: bme.begin() failed with status: " + String(bme.checkStatus()));
    return false;
  }

  bme.setTPH(BME68X_OS_2X, BME68X_OS_1X, BME68X_OS_2X);
  bme.setFilter(BME68X_FILTER_OFF);

  forcedStepIndex = 0;
  logMessage("[DRIVER HAND-OFF PASS]: Bosch Bme68x Driver configured cleanly.");
  return true;
}

bool readLowLevelScanFrame(float &outGasRes, uint8_t &outStep) {
  uint16_t temp = bmeTempProf[forcedStepIndex];
  uint16_t dur = bmeDurProf[forcedStepIndex];

  // 1. Set heater temperature & duration for current step
  bme.setHeaterProf(&temp, &dur, 1);

  // 2. Trigger Forced Mode measurement
  bme.setOpMode(BME68X_FORCED_MODE);

  // 3. Wait exact measurement duration + 10ms margin for hardware completion
  uint32_t delPeriodUs = bme.getMeasDur(BME68X_FORCED_MODE);
  //vTaskDelay(pdMS_TO_TICKS((delPeriodUs / 1000) + 10));
  vTaskDelay(pdMS_TO_TICKS(LOW_LEVEL_STEP_DELAY_MS));

  // 4. Fetch data via bme instance
  bme68xData data;
  uint8_t nFields = bme.fetchData();

  if (nFields > 0) {
    bme.getData(data);
    // logMessage("   [STEP " + String(forcedStepIndex) + " DETAIL]: Temp=" + String(temp) 
    //            + "C | GasRes=" + String((long)data.gas_resistance) 
    //            + " Ohm | Status=0x" + String(data.status, HEX));
    sensorData.currentTemp = data.temperature;
    sensorData.currentHumidity = data.humidity;

    if ((data.status & BME68X_GASM_VALID_MSK) && (data.gas_resistance >= HW_MIN_SENSOR_GAS_RES)) {
      outGasRes = data.gas_resistance;
      outStep = forcedStepIndex;

      forcedStepIndex = (forcedStepIndex + 1) % 10;
      return true;
    }
  } else {
    logMessage("   [STEP " + String(forcedStepIndex) + " DETAIL]: No data returned (nFields = 0)");
  }

  forcedStepIndex = (forcedStepIndex + 1) % 10;
  return false;
}

static void executeBreathWarmup() {
  logMessage("[WARMUP EXECUTE]: Option B Driver Hand-Off Initiated...");

  if (bsec != nullptr) {
    bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_DISABLED);
  }
  vTaskDelay(pdMS_TO_TICKS(I2C_BUS_SETTLE_DELAY_MS));

  softResetBme688Sensor();
  vTaskDelay(pdMS_TO_TICKS(I2C_BUS_RESET_DELAY_MS));

  if (!configureLowLevelParallelScan()) {
    logMessage("[ERROR]: Failed to configure parallel scan heater matrix!");
    return;
  }

  currentProfile = PROFILE_LP_3S;

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_STARTED) + "\"}");
  dispatchData("{\"state\":\"" + String(STATE_WARMING_UP) + "\",\"seconds\":" + String(SELECTIVITY_WARMUP_DELAY_MS / 1000) + "}");

  uint32_t warmupStart = millis();
  while (millis() - warmupStart < SELECTIVITY_WARMUP_DELAY_MS) {
    float gasRes = 0.0f;
    uint8_t step = 0;
    if (readLowLevelScanFrame(gasRes, step)) {
      if (gasRes >= HW_MIN_SENSOR_GAS_RES) {
        sensorData.currentGasRes = gasRes;
        sensorData.currentHeaterStep = step;
        updateSelectivityRatio(gasRes, step);
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  logMessage("[WARMUP EXECUTE]: Option B Warmup complete.");
  newGasDataAvailable = false;
}

uint8_t collectBaselineSamples(float &sumRes, float &sumHumidity, float &sumTemp, float &sumCO2,
                               uint8_t targetCount, uint32_t timeoutMs) {
  uint8_t validCount = 0;
  uint32_t startMs = millis();
  uint32_t lastDiagLogMs = 0;

  logMessage("[BASELINE LOOP START]: Target Count = " + String(targetCount) + " | Timeout = " + String(timeoutMs) + " ms");

  while (validCount < targetCount && (millis() - startMs < timeoutMs)) {
    float rawRes = 0.0f;
    uint8_t step = 0;

    if (readLowLevelScanFrame(rawRes, step)) {
      bool isBusFaultTransient = (rawRes < HW_MIN_SENSOR_GAS_RES) || (rawRes > HW_MAX_TRANSIENT_GAS_RES);

      if (!isBusFaultTransient) {
        sensorData.currentGasRes = rawRes;
        sensorData.currentHeaterStep = step;
        updateSelectivityRatio(rawRes, step);

        sumRes += rawRes;
        sumHumidity += sensorData.currentHumidity;
        sumTemp += sensorData.currentTemp;
        sumCO2 += sensorData.currentCO2;
        validCount++;
        logMessage("[BASELINE SAMPLE ACCEPTED " + String(validCount) + "/" + String(targetCount) + "]: Step " + String(step) + " Gas = " + String((long)rawRes) + " Ohm");
      }
    }

    if (millis() - lastDiagLogMs >= DIAG_LOG_INTERVAL_MS) {
      lastDiagLogMs = millis();
      logMessage("[BASELINE LOOP TICK @ " + String(millis() - startMs) + " ms]: Valid Samples = " + String(validCount) + "/" + String(targetCount));
    }

    vTaskDelay(pdMS_TO_TICKS(LOW_LEVEL_STEP_DELAY_MS));
  }

  logMessage("[BASELINE LOOP EXIT]: Collected " + String(validCount) + " valid samples in " + String(millis() - startMs) + " ms");
  return validCount;
}

bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp, float &outBaseCO2) {
  logMessage("[PREPARE BASELINE]: Capturing " + String(BASELINE_TARGET_SAMPLE_COUNT) + " samples via low-level driver...");

  float sumRes = 0.0f, sumHumidity = 0.0f, sumTemp = 0.0f, sumCO2 = 0.0f;

  uint8_t count = collectBaselineSamples(sumRes, sumHumidity, sumTemp, sumCO2,
                                         BASELINE_TARGET_SAMPLE_COUNT,
                                         BASELINE_CAPTURE_TIMEOUT_MS);

  if (count == 0) {
    logMessage("[WARNING]: Baseline collection returned 0 samples!");
    dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
    return false;
  }

  outBaselineRes = sumRes / count;
  outBaseHumidity = sumHumidity / count;
  outBaseTemp = sumTemp / count;
  outBaseCO2 = sumCO2 / count;

  logMessage("[BASELINE SUCCESS]: R_base = " + String((long)outBaselineRes) + " Ohm | Temp = " + String(outBaseTemp, 1) + "C | RH = " + String(outBaseHumidity, 1) + "% across " + String(count) + " samples.");

  return validateBaselineQuality(outBaselineRes, outBaseCO2);
}

bool validateBaselineQuality(float avgRes, float avgCO2) {
  bool isResOutOfBounds = (avgRes < BASELINE_STABLE_MIN_GAS_RES) || (avgRes > BASELINE_STABLE_MAX_GAS_RES);
  
  // CO2 is only validated if BSEC is active and producing non-zero ppm readings
  bool isCO2OutOfBounds = (avgCO2 > 0.0f) && ((avgCO2 < BASELINE_MIN_VALID_CO2_PPM) || (avgCO2 > BASELINE_MAX_VALID_CO2_PPM));
  
  bool isBaselineInvalid = isResOutOfBounds || isCO2OutOfBounds;

  if (isBaselineInvalid) {
    if (isResOutOfBounds) {
      logMessage("[ERROR]: Averaged baseline resistance out of stable bounds: " + String(avgRes, 0) + " Ohm");
    }
    if (isCO2OutOfBounds) {
      logMessage("[ERROR]: Averaged baseline CO2 out of valid bounds: " + String(avgCO2, 0) + " ppm");
    }
    dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
    return false;
  }

  logMessage("[BASELINE LOCKED]: Avg Res = " + String(avgRes, 0) + " Ohm | Avg CO2 = " + String(avgCO2, 0) + " ppm");
  return true;
}

void resetToDefaultMode() {
  logMessage("[RESET MODE]: Restoring hardware and resuming BSEC ULP profile...");

  softResetBme688Sensor();
  reinitBsecInstance();

  if (bsec->begin(bmeI2cAddr, Wire)) {
    bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_ULP);
    bsec->attachCallback(newDataCallback);
  }

  currentProfile = PROFILE_ULP_300S;
  currentMode = MODE_DRY_AIR_DETECTION;
  dispatchData("{\"state\":\"PROFILE_ULP\"}");
}

void runBreathSequence() {
  logMessage("[SEQUENCE START]: Breath test sequence initiated.");
  
  // 1. Snapshot ambient CO2, Temp, and RH from BSEC BEFORE pausing BSEC
  float ambientCO2 = sensorData.currentCO2;
  float ambientTemp = sensorData.currentTemp;
  float ambientRH = sensorData.currentHumidity;
  
  logMessage("[BSEC SNAPSHOT]: Ambient CO2 = " + String(ambientCO2) + " ppm | RH = " + String(ambientRH) + "%");

  dryAirActive = false;
  currentMode = MODE_BREATH_TEST;

  executeBreathWarmup();

  float baseRes = 0.0f, baseHumidity = ambientRH, baseTemp = ambientTemp, baseCO2 = ambientCO2;
  float maxDeltaRH = 0.0f, maxDeltaCO2 = 0.0f;

  if (!prepareAndCaptureBaseline(baseRes, baseHumidity, baseTemp, baseCO2)) {
    logMessage("[SEQUENCE ABORTED]: Baseline capture failed.");
    resetToDefaultMode();
    return;
  }

  float minRes = baseRes;

  bool breathDetected = waitAndCaptureBreath(baseRes, baseHumidity, baseTemp, baseCO2,
                                             minRes, maxDeltaRH, maxDeltaCO2);

  if (!breathDetected) {
    bool isPartialExhalation = (maxDeltaRH >= PARTIAL_EXHALATION_MIN_DELTA_RH_PCT) || (maxDeltaCO2 >= PARTIAL_EXHALATION_MIN_DELTA_CO2_PPM);
    if (isPartialExhalation) {
      logMessage("[SEQUENCE TIMEOUT]: Partial exhalation detected below threshold.");
      dispatchData("{\"state\":\"" + String(STATE_EXHALATION_TOO_WEAK) + "\"}");
    } else {
      dispatchData("{\"state\":\"" + String(STATE_TIMEOUT) + "\"}");
      vTaskDelay(pdMS_TO_TICKS(I2C_BUS_SETTLE_DELAY_MS));
    }
  } else {
    processBreathTestResults(baseRes, minRes, maxDeltaRH, maxDeltaCO2);
  }
  resetToDefaultMode();
}

static bool evaluateExhalationFrame(float baseGasRes, float baseHumidity, float baseTemp, float baseCO2,
                                    float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  float currentGasRes = 0.0f;
  uint8_t step = 0;

  if (!readLowLevelScanFrame(currentGasRes, step)) return false;

  sensorData.currentGasRes = currentGasRes;
  sensorData.currentHeaterStep = step;
  updateSelectivityRatio(currentGasRes, step);

  float deltaHumidity = sensorData.currentHumidity - baseHumidity;
  float deltaTemp = sensorData.currentTemp - baseTemp;
  float deltaCO2 = sensorData.currentCO2 - baseCO2;

  float gasDropPct = (baseGasRes > 0.0f && currentGasRes > 0.0f) ? ((baseGasRes - currentGasRes) / baseGasRes) * 100.0f : 0.0f;

  if (currentGasRes > 0.0f && currentGasRes < outMinRes) {
    outMinRes = currentGasRes;
  }

  if (deltaHumidity > outMaxDeltaRH) outMaxDeltaRH = deltaHumidity;
  if (deltaCO2 > outMaxDeltaCO2) outMaxDeltaCO2 = deltaCO2;

  dispatchData("{\"dH\":" + String(deltaHumidity, 1) + ",\"dT\":" + String(deltaTemp, 1) + ",\"dCO2\":" + String(deltaCO2, 0) + ",\"gDrop\":" + String(gasDropPct, 1) + "}");

  bool isMoistSpike = (deltaHumidity >= EXHALATION_MIN_MOISTURE_DELTA_RH_PCT);
  bool isWarming = (deltaTemp >= EXHALATION_MIN_TEMP_DELTA_C);
  bool isCO2Spike = (deltaCO2 >= EXHALATION_MIN_CO2_DELTA_PPM);
  bool isGasDrop = (gasDropPct >= EXHALATION_MIN_GAS_DROP_PCT && gasDropPct <= EXHALATION_MAX_GAS_DROP_PCT);

  return isMoistSpike && (isWarming || isGasDrop || isCO2Spike);
}

bool waitForBreathExhalation(float baseGasRes, float baseHumidity, float baseTemp, float baseCO2,
                             float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  dispatchData("{\"state\":\"" + String(STATE_READY_PLEASE_BLOW) + "\"}");
  vTaskDelay(pdMS_TO_TICKS(I2C_BUS_RESET_DELAY_MS));

  uint32_t startMs = millis();

  outMaxDeltaRH = 0.0f;
  outMaxDeltaCO2 = 0.0f;

  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    if (evaluateExhalationFrame(baseGasRes, baseHumidity, baseTemp, baseCO2,
                                outMinRes, outMaxDeltaRH, outMaxDeltaCO2)) {
      return true;
    }

    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  return false;
}

static bool isFrameValidExhalation(float currentGasRes, float deltaRH, float gasDropPct) {
  const bool isSensorReadingValid = (currentGasRes > HW_MIN_SENSOR_GAS_RES);
  const bool hasMoistureSpike = (deltaRH >= DRY_MOUTH_MAX_DELTA_RH_PCT);
  const bool hasGasDropSpike = (gasDropPct >= BREATH_FRESH_MAX_DROP_PCT);
  const bool isExhalationActive = (hasMoistureSpike || hasGasDropSpike);

  return isSensorReadingValid && isExhalationActive;
}

static void processExhalationFrame(float baseRes, float baseHumidity, float baseCO2,
                                   float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  float currentGasRes = 0.0f;
  uint8_t step = 0;

  if (readLowLevelScanFrame(currentGasRes, step)) {
    sensorData.currentGasRes = currentGasRes;
    sensorData.currentHeaterStep = step;
    updateSelectivityRatio(currentGasRes, step);

    const float deltaRH = sensorData.currentHumidity - baseHumidity;
    const float deltaCO2 = sensorData.currentCO2 - baseCO2;
    const float gasDropPct = (baseRes > 0.0f) ? ((baseRes - currentGasRes) / baseRes) * 100.0f : 0.0f;

    const bool isValidExhalation = isFrameValidExhalation(currentGasRes, deltaRH, gasDropPct);

    if (isValidExhalation) {
      if (currentGasRes < outMinRes) {
        outMinRes = currentGasRes;
        logMessage("[NEW BREATH MINIMUM]: " + String(outMinRes, 0) + " Ohm | dRH: " + String(deltaRH, 1) + "%");
      }
    }

    if (deltaRH > outMaxDeltaRH) outMaxDeltaRH = deltaRH;
    if (deltaCO2 > outMaxDeltaCO2) outMaxDeltaCO2 = deltaCO2;
  }
}

void captureBreathSensingWindow(float baseRes, float baseHumidity, float baseCO2,
                                float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  dispatchData("{\"state\":\"" + String(STATE_TESTING_SENSING_BREATH) + "\"}");
  vTaskDelay(pdMS_TO_TICKS(I2C_BUS_RESET_DELAY_MS));

  const uint32_t windowStartMs = millis();
  outMinRes = baseRes;

  while ((millis() - windowStartMs) < BREATH_SENSING_WINDOW_MS) {
    processExhalationFrame(baseRes, baseHumidity, baseCO2, outMinRes, outMaxDeltaRH, outMaxDeltaCO2);
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  logMessage("[SENSING COMPLETE]: Lowest Breath Resistance = " + String(outMinRes, 0) + " Ohm");
}

bool waitAndCaptureBreath(float baseRes, float baseHumidity, float baseTemp, float baseCO2,
                          float &outAvgRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  float tempMinRes = baseRes;

  const bool isExhalationDetected = waitForBreathExhalation(baseRes, baseHumidity, baseTemp, baseCO2,
                                                            tempMinRes, outMaxDeltaRH, outMaxDeltaCO2);

  if (!isExhalationDetected) {
    logMessage("[BREATH]: Exhalation timeout — returning to ULP mode.");
    resetToDefaultMode();
    return false;
  }

  logMessage("[BREATH]: Exhalation detected! Sampling exhalation window...");

  captureBreathSensingWindow(baseRes, baseHumidity, baseCO2, outAvgRes, outMaxDeltaRH, outMaxDeltaCO2);

  resetToDefaultMode();
  return true;
}

static void processBreathTestResults(float baseRes, float minRes, float maxDeltaHumidity, float maxDeltaCO2) {
  float deltaDrop = 0.0f;
  if (baseRes > 0.0f) {
    deltaDrop = ((baseRes - minRes) / baseRes) * 100.0f;
    if (deltaDrop < 0.0f) deltaDrop = 0.0f;
  }

  logMessage("[SELECTIVITY EVAL]: Base Res = " + String(baseRes, 0) + " Ohm | Min Breath Res = " + String(minRes, 0) + " Ohm | Ratio = " + String(selectivityRatio, 2));

  sensorData.currentGasRes = minRes;
  sensorData.deltaDrop = deltaDrop;
  sensorData.rBreathMin = (long)minRes;
  sensorData.selectivityRatio = selectivityRatio;

  sensorData.ptcResult = evaluateBreathResult(deltaDrop, maxDeltaHumidity, maxDeltaCO2, selectivityRatio);

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_COMPLETE) + "\"}");
  dispatchData(sensorData.toJsonString());
  vTaskDelay(pdMS_TO_TICKS(I2C_BUS_SETTLE_DELAY_MS));
}

void printStoredFileToSerial() {
  if (!LittleFS.exists(OFFLINE_FILE)) {
    Serial.println("[STORAGE CHECK]: No offline file found on LittleFS.");
    return;
  }

  File file = LittleFS.open(OFFLINE_FILE, FILE_READ);
  if (!file) {
    Serial.println("[STORAGE CHECK]: Failed to open offline file.");
    return;
  }

  Serial.printf("--- READING %s (Size: %d bytes) ---\n", OFFLINE_FILE, file.size());
  while (file.available()) {
    String line = file.readStringUntil('\n');
    Serial.println(line);
  }
  Serial.println("--- END OF FILE ---");
  file.close();
}

String evaluateBreathResult(float deltaDrop, float maxDeltaHumidity, float maxDeltaCO2, float selectivityRatio) {
  const bool isDryMouth = (maxDeltaHumidity < DRY_MOUTH_MAX_DELTA_RH_PCT) && (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT || maxDeltaCO2 >= DRY_MOUTH_MIN_DELTA_CO2_PPM);
  const bool validMoisture = (maxDeltaHumidity >= DRY_MOUTH_MAX_DELTA_RH_PCT);

  const bool isMalodorRatio = (selectivityRatio >= SELECTIVITY_RATIO_MALODOR_THRESHOLD);
  const bool isBeverageFoodRatio = (selectivityRatio < SELECTIVITY_RATIO_MALODOR_THRESHOLD);

  const bool isSubThresholdDrop = (deltaDrop < BREATH_FRESH_MAX_DROP_PCT);
  const bool isSlightDrop = (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT);
  const bool isModerateDrop = (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT) && (deltaDrop < BREATH_SIGNIFICANT_MAX_DROP_PCT);
  const bool isSevereDrop = (deltaDrop >= BREATH_SIGNIFICANT_MAX_DROP_PCT);

  if (isDryMouth && isBeverageFoodRatio) {
    return RESULT_DRY_MOUTH_HYDRATE;
  }

  if (isDryMouth && isMalodorRatio) {
    return RESULT_DRY_MOUTH_VSC_BUILDUP;
  }

  if (validMoisture && isSubThresholdDrop && isBeverageFoodRatio) {
    return RESULT_SETTLE_BEVERAGE_FOOD_ODOR;
  }

  if (validMoisture && isSubThresholdDrop) {
    return RESULT_BALANCED_BREATH;
  }

  if (validMoisture && isSlightDrop && isBeverageFoodRatio) {
    return RESULT_SOME_BEVERAGE_FOOD_ODOR;
  }

  if (validMoisture && isModerateDrop && isMalodorRatio) {
    return RESULT_NOTICEABLE_MALODOR;
  }

  if (validMoisture && isSevereDrop && isMalodorRatio) {
    return RESULT_STRONG_MALODOR;
  }

  return RESULT_NONE;
}

uint8_t readBatteryPercentage() {
  uint32_t totalMv = 0;
  for (int i = 0; i < BATTERY_ADC_SAMPLES; i++) {
    totalMv += analogReadMilliVolts(BATTERY_ADC_PIN);
    vTaskDelay(pdMS_TO_TICKS(BATTERY_SAMPLE_DELAY_MS));
  }
  uint32_t rawMv = totalMv / BATTERY_ADC_SAMPLES;
  float voltage = (rawMv / 1000.0f) * BATTERY_VOLTAGE_DIVISER_FACTOR;

  if (voltage < BATTERY_VALID_LOWER_BOUND_VOLTS) return 100;
  if (voltage >= BATTERY_MAX_VOLTS) return 100;
  if (voltage <= BATTERY_MIN_VOLTS) return 0;

  return (uint8_t)(((voltage - BATTERY_MIN_VOLTS) / (BATTERY_MAX_VOLTS - BATTERY_MIN_VOLTS)) * 100.0f);
}

void saveOfflineData() {
  if (LittleFS.exists(OFFLINE_FILE)) {
    File fileCheck = LittleFS.open(OFFLINE_FILE, FILE_READ);
    if (fileCheck) {
      size_t currentSize = fileCheck.size();
      fileCheck.close();
      if (currentSize >= MAX_OFFLINE_FILE_SIZE_BYTES) {
        return;
      }
    }
  }

  accumTemp += sensorData.currentTemp;
  accumHumidity += sensorData.currentHumidity;
  accumPressure += sensorData.currentPressure;
  accumGasRes += sensorData.currentGasRes;
  accumCount++;

  unsigned long now = millis();
  if (lastOfflineWriteTime == 0) {
    lastOfflineWriteTime = now;
  }

  if ((now - lastOfflineWriteTime >= FIVE_MINUTES_IN_MS) && (accumCount > 0)) {
    SensorData avgData;
    avgData.currentTemp = accumTemp / accumCount;
    avgData.currentHumidity = accumHumidity / accumCount;
    avgData.currentPressure = accumPressure / accumCount;
    avgData.currentGasRes = accumGasRes / accumCount;
    avgData.deltaDrop = 0.0f;
    avgData.rBreathMin = 0;
    avgData.ptcResult = RESULT_NONE;

    File file = LittleFS.open(OFFLINE_FILE, FILE_APPEND);
    if (file) {
      file.println(avgData.toJsonString());
      file.close();
#if ENABLE_SERIAL_LOGS
      Serial.println("[STORAGE]: 5-minute averaged sample cached locally.");
#endif
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
  } else {
    if (payload.startsWith("{\"temp\":")) {
      saveOfflineData();
    }
  }
}

void flushOfflineData() {
  if (!LittleFS.exists(OFFLINE_FILE)) return;

  File file = LittleFS.open(OFFLINE_FILE, FILE_READ);
  if (!file) return;

#if ENABLE_SERIAL_LOGS
  Serial.println("[STORAGE]: Flushing stored offline samples over BLE...");
#endif

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

void enterLightSleep(uint64_t sleepTimeMs) {
  if (sleepTimeMs == 0) return;
  esp_sleep_enable_timer_wakeup(sleepTimeMs * 1000ULL);
  esp_light_sleep_start();
}

void performWarmup() {
  setBsecProfile(PROFILE_LP_3S);
  uint32_t warmupStart = millis();
  while (millis() - warmupStart < WARMUP_SHORT_DELAY_MS) {
    if (bsecReady && bsec != nullptr) {
      bsec->run();
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}

void softResetBme688Sensor() {
  Wire.beginTransmission(bmeI2cAddr);
  Wire.write(0xE0);
  Wire.write(0xB6);
  Wire.endTransmission();
  vTaskDelay(pdMS_TO_TICKS(10));
}

void handleCommand(String command) {
  command.trim();
  command.toLowerCase();

  dispatchData("{\"rx_cmd\":\"" + command + "\"}");

  if (command == "1" || command == "r" || command == "run") {
    if (currentMode == MODE_IDLE) performWarmup();
    setBsecProfile(PROFILE_LP_3S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
    dispatchData("{\"status\":\"" + String(STATUS_DRY_AIR_STARTED) + "\"}");
  } else if (command == "set_ultra_low_sampling_mode" || command == "set_ulp") {
    if (currentMode == MODE_IDLE) performWarmup();
    setBsecProfile(PROFILE_ULP_300S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
  } else if (command == "set_active_sampling_mode" || command == "set_lp") {
    if (currentMode == MODE_IDLE) performWarmup();
    setBsecProfile(PROFILE_LP_3S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
  } else if (command == "2" || command == "s" || command == "stop") {
    setBsecProfile(PROFILE_OFF);
    dryAirActive = false;
    currentMode = MODE_IDLE;
    dispatchData("{\"status\":\"" + String(STATUS_DRY_AIR_STOPPED) + "\"}");
  } else if (command == "10" || command == "status") {
    String statusResp = "{\"dry_air_active\":" + String(dryAirActive ? "true" : "false") + ",\"profile\":" + String((int)currentProfile) + "}";
    dispatchData(statusResp);
  } else if (command == "test_selectivity" || command == "99") {
    logMessage("[CMD RX]: Launching Selectivity Diagnostic Self-Test...");
    runSelectivityDiagnosticTest();
  }
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo) {
    deviceConnected = true;
    pendingFlush = true;

    logMessage("[BLE CONNECT]: Smartphone connected. Remaining in low-power ULP mode.");
  }

  void onDisconnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo, int reason) {
    deviceConnected = false;
    setBsecProfile(PROFILE_ULP_300S);
    currentMode = MODE_DRY_AIR_DETECTION;
    dryAirActive = true;
    pendingBreathCommand = false;

    adjustAdvertisingPower(true);
  }
};

class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo &connInfo) {
    NimBLEAttValue val = pCharacteristic->getValue();
    if (val.length() > 0) {
      String rxValue = String((char *)val.data()).substring(0, val.length());
      rxValue.trim();
      rxValue.toLowerCase();

      logMessage("BLE Received Command: " + rxValue);

      if (rxValue == "3" || rxValue == "b" || rxValue == "breath") {
        logMessage("[BLE RX]: Command '3' accepted at " + String(millis()) + " ms | currentMode = " + String(currentMode) + " | status = " + String((int)(bsec != nullptr ? bsec->status : -1)));

        if (!systemReady || !bsecReady) {
          logMessage("[WARNING]: Command rejected — systemReady=" + String(systemReady) + " bsecReady=" + String(bsecReady));
          dispatchData("{\"state\":\"" + String(STATE_DEVICE_INITIALIZING) + "\"}");
          return;
        }

        if (currentMode == MODE_BREATH_TEST) {
          logMessage("[WARNING]: Command rejected — breath test already in progress.");
          dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
          return;
        }

        dryAirActive = false;
        currentMode = MODE_BREATH_TEST;
        pendingBreathCommand = true;
      } else {
        snprintf(pendingCmdBuf, sizeof(pendingCmdBuf), "%s", rxValue.c_str());
        hasPendingCommand = true;
      }
    }
  }
};

static void generateDeviceName() {
  uint64_t mac = ESP.getEfuseMac();
  char macSuffix[6];
  snprintf(macSuffix, sizeof(macSuffix), "%02X%02X",
           (uint8_t)(mac >> 40), (uint8_t)(mac >> 32));

  Device_Name = String(DEVICE_BASE_NAME) + " " + String(macSuffix);
  Serial.println("[BLE] Device Name: " + Device_Name);
}

static void setupBLEServiceAndCharacteristics() {
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::NOTIFY);

  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start();
}

static void configureBLEAdvertising() {
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN);
  advData.setCompleteServices(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advData);

  NimBLEAdvertisementData scanData;
  scanData.setName(Device_Name.c_str());
  pAdvertising->setScanResponseData(scanData);

  pAdvertising->enableScanResponse(true);

  adjustAdvertisingPower(true);
}

void initBLE() {
  Serial.println("[BLE] Starting NimBLE initialization...");

  generateDeviceName();
  NimBLEDevice::init(Device_Name.c_str());

  setupBLEServiceAndCharacteristics();
  configureBLEAdvertising();

  Serial.println("[BLE] Advertising active with split payload!");
}

static void initPowerAndADC() {
  pinMode(BATTERY_ADC_PIN, INPUT);
  analogReadResolution(BATTERY_ADC_RESOLUTION_BITS);
  analogSetPinAttenuation(BATTERY_ADC_PIN, ADC_11db);
  sensorData.batteryPct = readBatteryPercentage();
}

static void initSerialLogs() {
#if ENABLE_SERIAL_LOGS
  Serial.begin(SERIAL_BAUD_RATE);
  delay(SERIAL_INIT_DELAY_MS);
  Serial.println("Booting Meso Nose with Storage & Light Sleep Support...");
  Serial.printf("Free Heap at startup: %d bytes\n", ESP.getFreeHeap());
#endif
}

static void initStorage() {
  if (!LittleFS.begin(true, "/littlefs", 10, "spiffs")) {
    Serial.println("LittleFS Mount Failed and Auto-Format Failed!");
  } else {
    Serial.println("[STORAGE]: LittleFS mounted successfully!");
  }
}

static void clearI2CBus() {
  pinMode(I2C_SDA, INPUT_PULLUP);
  pinMode(I2C_SCL, OUTPUT);
  for (int i = 0; i < 9; i++) {
    digitalWrite(I2C_SCL, LOW);
    delayMicroseconds(5);
    digitalWrite(I2C_SCL, HIGH);
    delayMicroseconds(5);
  }
  pinMode(I2C_SCL, INPUT_PULLUP);
}

static void initI2CAndBsec() {
  clearI2CBus();
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(I2C_CLOCK_SPEED_HZ);
  Wire.setTimeOut(I2C_BUS_TIMEOUT_MS);

  bmeI2cAddr = BME68X_I2C_ADDR_HIGH;
  Wire.beginTransmission(bmeI2cAddr);
  if (Wire.endTransmission() != 0) {
    bmeI2cAddr = BME68X_I2C_ADDR_LOW;
  }

  Serial.print("Connecting to BSEC at address: 0x");
  Serial.println(bmeI2cAddr, HEX);

  reinitBsecInstance();
  if (bsec->begin(bmeI2cAddr, Wire)) {
    bsecReady = true;
    bsec->updateSubscription(defaultSensorList, numDefaultSensors, BSEC_SAMPLE_RATE_ULP);
    bsec->attachCallback(newDataCallback);
    bsec->setTemperatureOffset(0.0f);

    Serial.println("[SETUP] BSEC and official Bme68x driver initialized successfully!");

    currentProfile = PROFILE_ULP_300S;
  } else {
    Serial.println("[SETUP] BSEC failed to start!");
    bsecReady = false;
  }
}

void setup() {
  delay(2000);

  initPowerAndADC();
  initSerialLogs();
  initStorage();

  Serial.println("[SETUP] Initializing BLE...");
  initBLE();

  initI2CAndBsec();

  systemReady = true;
  Serial.println("[SETUP] Setup complete — System ready!");

#if ENABLE_SERIAL_LOGS
  printStoredFileToSerial();
#endif
}

void loop() {
  adjustAdvertisingPower(false);

  // --- READ SERIAL MONITOR INPUT ---
  if (Serial.available() > 0) {
    String serialCmd = Serial.readStringUntil('\n');
    serialCmd.trim();
    if (serialCmd.length() > 0) {
      logMessage("[SERIAL RX]: Received command via Serial Monitor: " + serialCmd);
      handleCommand(serialCmd);
    }
  }

  if (hasPendingCommand) {
    hasPendingCommand = false;
    handleCommand(String(pendingCmdBuf));
  }

  if (pendingFlush && deviceConnected) {
    pendingFlush = false;
    flushOfflineData();
  }

  if (pendingBreathCommand) {
    pendingBreathCommand = false;
    runBreathSequence();
    return;
  }

  if (bsecReady && bsec != nullptr && bsec->status >= BSEC_OK && (currentProfile == PROFILE_LP_3S || currentProfile == PROFILE_ULP_300S)) {
    bsec->run();

    static unsigned long lastNotifyTime = 0;
    unsigned long notifyInterval = (currentProfile == PROFILE_LP_3S) ? NOTIFY_LP_INTERVAL_MS : NOTIFY_ULP_INTERVAL_MS;

    if (millis() - lastNotifyTime >= notifyInterval) {
      lastNotifyTime = millis();

      if (sensorData.currentGasRes > 0.0f) {
        sensorData.deltaDrop = 0.0f;
        sensorData.rBreathMin = 0;
        sensorData.ptcResult = RESULT_NONE;

        sensorData.batteryPct = readBatteryPercentage();
        dispatchData(sensorData.toJsonString());
      }
    }
  } else if (bsecReady && bsec != nullptr && bsec->status < BSEC_OK) {
    logMessage("[ERROR]: BSEC entered fault state: " + String(bsec->status));
    vTaskDelay(pdMS_TO_TICKS(500));
  }
  vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
}

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

#if ENABLE_SERIAL_LOGS
    Serial.println("[BLE]: Entered fast advertising mode (100ms - 200ms).");
#endif
  } else if (!deviceConnected && !isInLowPowerAdvertising && (millis() - disconnectTime > FAST_ADV_BURST_WINDOW_MS)) {
    isInLowPowerAdvertising = true;

    pAdvertising->stop();
    pAdvertising->setMinInterval(BLE_ADV_ULP_MIN_INTERVAL_UNITS);
    pAdvertising->setMaxInterval(BLE_ADV_ULP_MAX_INTERVAL_UNITS);
    pAdvertising->start();

#if ENABLE_SERIAL_LOGS
    Serial.println("[BLE]: Fast window expired. Transitioned to ULP advertising (1.0s - 2.0s).");
#endif
  }
}