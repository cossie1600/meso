#include <Wire.h>
#include <FS.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"

#define ENABLE_SERIAL_LOGS true 
#define BATTERY_ADC_PIN 0
#define I2C_SDA 6
#define I2C_SCL 7

#define SERVICE_UUID        "4fa215f0-0001-4b0e-b682-1a4c70f3a601"
#define CHARACTERISTIC_UUID "4fa215f0-0002-4b0e-b682-1a4c70f3a601"

constexpr const char* DEVICE_BASE_NAME = "Meso Nose";
String Device_Name;

const char* OFFLINE_FILE = "/offline_data.json";


// -------------------------------------------------------------------
// Storage & Watermark Constants
// -------------------------------------------------------------------
constexpr unsigned long FIVE_MINUTES_IN_MS = 300000UL;
constexpr size_t MAX_OFFLINE_FILE_SIZE_BYTES = 200000; // ~200 KB cap (~7 days of data)

// -------------------------------------------------------------------
// Dynamic Advertising & Timing Constants
// -------------------------------------------------------------------
// BLE Spec Advertising Interval Units: 1 unit = 0.625 ms
constexpr uint16_t BLE_ADV_FAST_MIN_INTERVAL_UNITS = 160;  // 160 * 0.625ms = 100ms
constexpr uint16_t BLE_ADV_FAST_MAX_INTERVAL_UNITS = 320;  // 320 * 0.625ms = 200ms

constexpr uint16_t BLE_ADV_ULP_MIN_INTERVAL_UNITS  = 1600; // 1600 * 0.625ms = 1000ms (1.0 sec)
constexpr uint16_t BLE_ADV_ULP_MAX_INTERVAL_UNITS  = 3200; // 3200 * 0.625ms = 2000ms (2.0 sec)

constexpr unsigned long FAST_ADV_BURST_WINDOW_MS    = 30000UL; // 30 seconds

// -------------------------------------------------------------------
// Hardware, Serial & Clock Constants
// -------------------------------------------------------------------
constexpr uint32_t SERIAL_BAUD_RATE            = 115200; 
constexpr uint32_t I2C_CLOCK_SPEED_HZ          = 100000; 
constexpr float PRESSURE_HPA_DIVISOR           = 1.0f;   // Native hPa output (1.0f divisor)
constexpr uint32_t CPU_LOW_POWER_FREQ_MHZ      = 80;     

// Hardware Initialization Delays
constexpr uint32_t SERIAL_INIT_DELAY_MS        = 500;   // Serial startup stabilization delay
constexpr uint32_t BLE_POST_INIT_DELAY_MS      = 200;   // Delay after BLE stack launch
constexpr uint32_t I2C_BUS_RESET_DELAY_MS      = 50;    // I2C bus end/reset pulse delay
constexpr uint32_t I2C_BUS_SETTLE_DELAY_MS     = 100;   // I2C bus start/settle delay

// -------------------------------------------------------------------
// Operational Timing Constants (Millisecond Durations)
// -------------------------------------------------------------------
constexpr uint32_t NOTIFY_LP_INTERVAL_MS      = 3000;   // 3 seconds (LP mode)
constexpr uint32_t NOTIFY_ULP_INTERVAL_MS     = 300000; // 5 minutes (ULP mode)
constexpr uint32_t WARMUP_SHORT_DELAY_MS      = 4000;   // 4 seconds sensor thermal stabilization
constexpr uint32_t WARMUP_LONG_DELAY_MS       = 15000;  // 15 seconds sensor thermal stabilization
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS     = 10000;  // 10 seconds to wait for blow start
constexpr uint32_t BREATH_SENSING_WINDOW_MS   = 3500;   // 3.5 seconds to capture minimum VOC nadir
constexpr uint32_t LOOP_TICK_DELAY_MS         = 20;     
constexpr uint32_t POLL_TICK_DELAY_MS         = 20;     

// -------------------------------------------------------------------
// Physical Thresholds & Evaluation Constants
// -------------------------------------------------------------------
constexpr float BREATH_FRESH_MAX_DROP_PCT       = 15.0f;  
constexpr float BREATH_SIGNIFICANT_MAX_DROP_PCT = 45.0f; // Adjusted to match matrix (45%)
constexpr float SELECTIVITY_RATIO_MALODOR_THRESHOLD = 0.5f; // Boundary between aromatics (<0.5) and VSCs (>=0.5)

// Dry Mouth Evaluation Thresholds
constexpr float DRY_MOUTH_MAX_DELTA_RH_PCT      = 2.5f;   // Max moisture gain (%) to qualify as dry mouth
constexpr float DRY_MOUTH_MIN_DELTA_CO2_PPM     = 250.0f; // Min CO2 shift confirming a valid exhalation

// -------------------------------------------------------------------
// System & Sequence Status String Constants
// -------------------------------------------------------------------
constexpr const char* STATE_TRY_AGAIN_LATER        = "TRY_AGAIN_LATER";
constexpr const char* STATE_ROOM_AIR_DIRTY         = "ROOM_AIR_DIRTY_VENTILATE";
constexpr const char* STATE_READY_PLEASE_BLOW      = "READY_PLEASE_BLOW";
constexpr const char* STATE_TESTING_SENSING_BREATH = "TESTING_SENSING_BREATH";
constexpr const char* STATE_TIMEOUT                = "TIMEOUT";
constexpr const char* STATE_WARMING_UP             = "WARMING_UP";

constexpr const char* STATUS_DRY_AIR_STARTED       = "DRY_AIR_STARTED";
constexpr const char* STATUS_DRY_AIR_STOPPED       = "DRY_AIR_STOPPED";
constexpr const char* STATUS_BREATH_TEST_STARTED   = "BREATH_TEST_STARTED";
constexpr const char* STATUS_BREATH_TEST_COMPLETE  = "BREATH_TEST_COMPLETE";
constexpr const char* STATE_DEVICE_INITIALIZING    = "DEVICE_INITIALIZING";

bool systemReady = false;

// -------------------------------------------------------------------
// Result Classification String Constants
// -------------------------------------------------------------------
constexpr const char* RESULT_NONE                        = "NONE";
constexpr const char* RESULT_DRY_MOUTH_HYDRATE           = "DRY_MOUTH_HYDRATE";          
constexpr const char* RESULT_DRY_MOUTH_VSC_BUILDUP       = "DRY_MOUTH_VSC_BUILDUP";      
constexpr const char* RESULT_SETTLE_BEVERAGE_FOOD_ODOR   = "SETTLE_BEVERAGE_FOOD_ODOR";  
constexpr const char* RESULT_BALANCED_BREATH             = "BALANCED_BREATH";             
constexpr const char* RESULT_SOME_BEVERAGE_FOOD_ODOR     = "SOME_BEVERAGE_FOOD_ODOR";    
constexpr const char* RESULT_NOTICEABLE_MALODOR          = "NOTICEABLE_MALODOR";          
constexpr const char* RESULT_STRONG_MALODOR              = "STRONG_MALODOR";
// -------------------------------------------------------------------
// Baseline Batch & Trimming Constants
// -------------------------------------------------------------------
constexpr uint8_t  BASELINE_TARGET_SAMPLE_COUNT    = 10;            // 10 samples for robust trimmed average
constexpr uint32_t BASELINE_CAPTURE_TIMEOUT_MS     = 100000UL;      // 100s window (3.3x headroom over 30s collection time)
constexpr uint8_t  MIN_SAMPLES_TO_TRIM_HIGH        = 3;             // Strips highest transient spike
constexpr uint8_t  MIN_SAMPLES_TO_TRIM_LOW         = 4;             // Strips lowest anomaly
constexpr float    MAX_VALID_BASELINE_GAS_RES      = 800000.0f;     // 800 k-Ohm ceiling (accepts resting ~130k-300k, rejects transients)
constexpr float    ROOM_AIR_MAX_CO2_PPM            = 1200.0f;       // Max ambient CO2 safety limit

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
float selectivityRatio = 1.0f;

// -------------------------------------------------------------------
// Offline Accumulation Variables (Rate Limited to 5 Minutes)
// -------------------------------------------------------------------
unsigned long lastOfflineWriteTime = 0;
float accumTemp = 0.0f;
float accumHumidity = 0.0f;
float accumPressure = 0.0f;
float accumGasRes = 0.0f;
int accumCount = 0;

char pendingCmdBuf[32] = {0};
volatile bool hasPendingCommand = false;

struct SensorData {
  float currentTemp = 0.0f;
  float currentHumidity = 0.0f;
  float currentPressure = 0.0f;
  float currentGasRes = 0.0f;
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

bsecSensor sensorList[] = {
  BSEC_OUTPUT_RAW_GAS,
  BSEC_OUTPUT_RAW_TEMPERATURE,
  BSEC_OUTPUT_RAW_HUMIDITY,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
  BSEC_OUTPUT_RAW_PRESSURE,
  BSEC_OUTPUT_CO2_EQUIVALENT,
  BSEC_OUTPUT_IAQ
};
uint8_t numSensors = sizeof(sensorList) / sizeof(bsecSensor);

Bsec2 bsec;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

/// Forward Declarations
static void clearI2CBus();
void setBsecProfile(BsecProfile profile);
void adjustAdvertisingPower(bool newlyDisconnected);
void saveOfflineData();
void flushOfflineData();
void enterLightSleep(uint64_t sleepTimeMs);
void performWarmup();
bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp, float &outBaseCO2);
bool waitAndCaptureBreath(float baseRes, float baseHumidity, float baseTemp, float baseCO2, float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2);
String evaluateBreathResult(float deltaDrop, float maxDeltaHumidity, float maxDeltaCO2, float selectivityRatio);
uint8_t readBatteryPercentage();
void runBreathSequence();
void printStoredFileToSerial();

void logMessage(String msg) {
#if ENABLE_SERIAL_LOGS
  Serial.println(msg);
  Serial.flush();
#endif
  if (deviceConnected && pCharacteristic) {
    String bleLog = "[LOG]: " + msg + "\n";
    pCharacteristic->setValue((uint8_t*)bleLog.c_str(), bleLog.length());
    pCharacteristic->notify();
  }
}

void saveOfflineData() {
  // 1. Watermark Guard: Immediate exit if log file hit capacity
  if (LittleFS.exists(OFFLINE_FILE)) {
    File fileCheck = LittleFS.open(OFFLINE_FILE, FILE_READ);
    if (fileCheck) {
      size_t currentSize = fileCheck.size();
      fileCheck.close();
      if (currentSize >= MAX_OFFLINE_FILE_SIZE_BYTES) {
        return; // Early return prevents dead sample accumulation
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

  // 2. Rate-limited 5-minute write interval
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

    // Reset accumulators
    accumTemp = 0.0f; accumHumidity = 0.0f; accumPressure = 0.0f; accumGasRes = 0.0f;
    accumCount = 0;
    lastOfflineWriteTime = now;
  }
}

void dispatchData(String payload) {
  Serial.println(payload);
  if (deviceConnected && pCharacteristic) {
    String formattedMsg = payload + "\n";
    pCharacteristic->setValue((uint8_t*)formattedMsg.c_str(), formattedMsg.length());
    pCharacteristic->notify();
  } else {
    // Only accumulate periodic sensor measurements when offline
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
      pCharacteristic->setValue((uint8_t*)formattedMsg.c_str(), formattedMsg.length());
      pCharacteristic->notify();
      vTaskDelay(pdMS_TO_TICKS(30)); // Avoid congestion on BLE ringbuffer
    }
  }
  file.close();

  // Clear offline flash file after successful transmission
  LittleFS.remove(OFFLINE_FILE);
}

void enterLightSleep(uint64_t sleepTimeMs) {
  if (sleepTimeMs == 0) return;
  
  // Keep CPU peripherals awake enough for BLE stack/radio events
  esp_sleep_enable_timer_wakeup(sleepTimeMs * 1000ULL);
  esp_light_sleep_start();
}

void performWarmup() {
  setBsecProfile(PROFILE_LP_3S);
  uint32_t warmupStart = millis();
  while (millis() - warmupStart < WARMUP_SHORT_DELAY_MS) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}

static void softResetBme688Sensor() {
  Wire.beginTransmission(bmeI2cAddr);
  Wire.write(0xE0); // BME68X_REG_RESET
  Wire.write(0xB6); // BME68X_SOFT_RESET_CMD
  Wire.endTransmission();
  vTaskDelay(pdMS_TO_TICKS(10)); // Allow ASIC to reboot
}

void setBsecProfile(BsecProfile profile) {
  if (currentProfile == profile) return;

  newGasDataAvailable = false;
  softResetBme688Sensor();

  if (profile == PROFILE_OFF) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_DISABLED);
    currentProfile = profile;
    dispatchData("{\"state\":\"PROFILE_OFF\"}");
  } 
  else if (profile == PROFILE_ULP_300S) {
    bsecReady = bsec.begin(bmeI2cAddr, Wire);
    if (bsecReady) {
      bsec.attachCallback(newDataCallback);
      bsec.setTemperatureOffset(0.0f);
      bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_ULP);
      currentProfile = profile;
      dispatchData("{\"state\":\"PROFILE_ULP\"}");
    }
  } 
  else if (profile == PROFILE_LP_3S) {
    bsecReady = bsec.begin(bmeI2cAddr, Wire);
    if (bsecReady) {
      bsec.attachCallback(newDataCallback);
      bsec.setTemperatureOffset(0.0f);
      bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP);
      currentProfile = profile;
      dispatchData("{\"state\":\"PROFILE_LP\"}");
    }
  }

  vTaskDelay(pdMS_TO_TICKS(100));
}

void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsec) {
  if (!outputs.nOutputs) return;

#if ENABLE_SERIAL_LOGS
  Serial.printf("[DIAG CALLBACK @ %lu ms] Received %d outputs | Raw Gas: %.0f Ohm\n", 
                millis(), outputs.nOutputs, data.gas_resistance);
#endif

  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    const bsecData output = outputs.output[i];
    switch (output.sensor_id) {
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
        if (output.signal > -40.0f && output.signal < 85.0f && output.signal != 0.0f) {
          sensorData.currentTemp = output.signal;
        }
        break;
      case BSEC_OUTPUT_RAW_HUMIDITY:
      if (sensorData.currentHumidity == 0.0f) {
        sensorData.currentHumidity = output.signal;
      }
        break;
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:        
        sensorData.currentHumidity = output.signal;        
        break;
      case BSEC_OUTPUT_RAW_PRESSURE:
        sensorData.currentPressure = output.signal;
        break;
      case BSEC_OUTPUT_RAW_GAS:
        sensorData.currentGasRes = output.signal;
        newGasDataAvailable = true;
#if ENABLE_SERIAL_LOGS
        Serial.printf("[BSEC TRACE]: Raw Gas Sample = %.0f Ohm | Accuracy = %d\n", output.signal, output.accuracy);
#endif
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
  }
  else if (command == "set_ultra_low_sampling_mode" || command == "set_ulp") {
    if (currentMode == MODE_IDLE) performWarmup();
    setBsecProfile(PROFILE_ULP_300S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
  }
  else if (command == "set_active_sampling_mode" || command == "set_lp") {
    if (currentMode == MODE_IDLE) performWarmup();
    setBsecProfile(PROFILE_LP_3S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
  }
  else if (command == "2" || command == "s" || command == "stop") {
    setBsecProfile(PROFILE_OFF);
    dryAirActive = false;
    currentMode = MODE_IDLE;
    dispatchData("{\"status\":\"" + String(STATUS_DRY_AIR_STOPPED) + "\"}");
  }
  else if (command == "10" || command == "status") {
    String statusResp = "{\"dry_air_active\":" + String(dryAirActive ? "true" : "false") + 
                        ",\"profile\":" + String((int)currentProfile) + "}";
    dispatchData(statusResp);
  }
}

class ServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) {
      deviceConnected = true;
      pendingFlush = true; // Signal flush to loop() asynchronously
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) {
      deviceConnected = false;
      setBsecProfile(PROFILE_ULP_300S);
      currentMode = MODE_DRY_AIR_DETECTION;
      dryAirActive = true;
      pendingBreathCommand = false;
      
      // Reset timer and re-launch fast advertising burst
      adjustAdvertisingPower(true);
    }
};

class CharacteristicCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo& connInfo) {
      NimBLEAttValue val = pCharacteristic->getValue();
      if (val.length() > 0) {
        String rxValue = String((char*)val.data()).substring(0, val.length());
        rxValue.trim();
        rxValue.toLowerCase();

        logMessage("BLE Received Command: " + rxValue);

        if (rxValue == "3" || rxValue == "b" || rxValue == "breath") {
          // 1. Device is still running setup() or BSEC startup
          if (!systemReady || !bsecReady) {
            logMessage("[WARNING]: Command rejected — device still initializing.");
            dispatchData("{\"state\":\"" + String(STATE_DEVICE_INITIALIZING) + "\"}");
            return;
          }

          // 2. A breath test sequence is already actively running
          if (currentMode == MODE_BREATH_TEST) {
            logMessage("[WARNING]: Command rejected — breath test already in progress.");
            dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
            return;
          }

          // 3. Command accepted
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
///////////////////////////////// Initialize Bluetooth //////////////////////////////////////////////////////////////////
// 1. Append MAC address suffix to existing Device_Name
static void generateDeviceName() {
  uint64_t mac = ESP.getEfuseMac();
  char macSuffix[6];
  snprintf(macSuffix, sizeof(macSuffix), "%02X%02X", 
           (uint8_t)(mac >> 40), (uint8_t)(mac >> 32));
  
  Device_Name = String(DEVICE_BASE_NAME) + " " + String(macSuffix);
  Serial.println("[BLE] Device Name: " + Device_Name);
}

// 2. Initialize GATT Server, Service, and Characteristics
static void setupBLEServiceAndCharacteristics() {
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE |
                      NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::NOTIFY
                    );

  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start();
}

// 3. Configure split-payload advertising (Main Advert + Scan Response)
static void configureBLEAdvertising() {
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  // Packet 1: Flags + Service UUID
  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN);
  advData.setCompleteServices(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advData);

  // Packet 2: Scan Response Device Name
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

///////////////// setup ////////////////////////////////////////////////////////////////////
static void initPowerAndADC() {
  pinMode(BATTERY_ADC_PIN, INPUT);
  analogReadResolution(12);
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
  Wire.setTimeOut(1000);

  bmeI2cAddr = BME68X_I2C_ADDR_HIGH;
  Wire.beginTransmission(bmeI2cAddr);
  if (Wire.endTransmission() != 0) {
    bmeI2cAddr = BME68X_I2C_ADDR_LOW;
  }

  Serial.print("Connecting to BSEC at address: 0x");
  Serial.println(bmeI2cAddr, HEX);

  if (bsec.begin(bmeI2cAddr, Wire)) {
    bsecReady = true;
    Serial.println("[SETUP] BSEC started successfully!");
    
    setBsecProfile(PROFILE_ULP_300S);
  } else {
    Serial.println("[SETUP] BSEC failed to start!");
    bsecReady = false;
  }
}

void setup() {
  #if defined(CONFIG_ARDUINO_LOOP_STACK_SIZE)
  // Ensures BSEC2 math engine has sufficient headroom
  #endif
  delay(2000); 

  initPowerAndADC();
  initSerialLogs();
  initStorage();

  Serial.println("[SETUP] Initializing BLE...");
  initBLE();
#if ENABLE_SERIAL_LOGS
  Serial.printf("Free Heap after BLE: %d bytes\n", ESP.getFreeHeap());
#endif

  initI2CAndBsec();

  // Mark system ready for commands as the final step of setup
  systemReady = true;
  Serial.println("[SETUP] Setup complete — System ready!");

#if ENABLE_SERIAL_LOGS
  printStoredFileToSerial();
#endif
}

//////////////////////////////////////////////////////////////////////////////////////////
void loop() {
  adjustAdvertisingPower(false);

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

  if (bsecReady && bsec.status >= BSEC_OK && (currentProfile == PROFILE_LP_3S || currentProfile == PROFILE_ULP_300S)) {
    bsec.run();

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
  } else if (bsecReady && bsec.status < BSEC_OK) {
    logMessage("[ERROR]: BSEC entered fault state: " + String(bsec.status));
    vTaskDelay(pdMS_TO_TICKS(500));
  }
  vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));  
}

// -------------------------------------------------------------------
// Dynamic Power Adjustment Function
// -------------------------------------------------------------------
void adjustAdvertisingPower(bool newlyDisconnected) {
  static unsigned long disconnectTime = 0;
  static bool isInLowPowerAdvertising = false;

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  if (newlyDisconnected) {
    disconnectTime = millis();
    isInLowPowerAdvertising = false;

    // Trigger fast-reconnect window
    pAdvertising->setMinInterval(BLE_ADV_FAST_MIN_INTERVAL_UNITS);
    pAdvertising->setMaxInterval(BLE_ADV_FAST_MAX_INTERVAL_UNITS);
    pAdvertising->start();
    
#if ENABLE_SERIAL_LOGS
    Serial.println("[BLE]: Entered fast advertising mode (100ms - 200ms).");
#endif
  } 
  else if (!deviceConnected && !isInLowPowerAdvertising && (millis() - disconnectTime > FAST_ADV_BURST_WINDOW_MS)) {
    isInLowPowerAdvertising = true;

    // Transition to ultra-low power advertising interval
    pAdvertising->stop();
    pAdvertising->setMinInterval(BLE_ADV_ULP_MIN_INTERVAL_UNITS);
    pAdvertising->setMaxInterval(BLE_ADV_ULP_MAX_INTERVAL_UNITS);
    pAdvertising->start();

#if ENABLE_SERIAL_LOGS
    Serial.println("[BLE]: Fast window expired. Transitioned to ULP advertising (1.0s - 2.0s).");
#endif
  }
}

// ===================================================================
// BSEC BASELINE & BREATH CAPTURE HELPERS (WIND-RESISTANT FUSION)
// ===================================================================

struct SampleFrame {
  float gasRes;
  float humidity;
  float temp;
  float co2;
};

// 1. Helper: Polls sensor and collects raw sample frames until target or timeout
static std::vector<SampleFrame> fetchRawBaselineSamples(uint8_t targetSamples, uint32_t timeoutMs) {
  std::vector<SampleFrame> samples;
  samples.reserve(targetSamples);

  uint32_t startMs = millis();
  uint32_t lastDiagMs = millis();
  uint32_t runCalls = 0;
  newGasDataAvailable = false;

  logMessage("[BASELINE TRACE @ " + String(startMs) + "ms]: Starting batch fetch for " + String(targetSamples) + " samples...");

  while (samples.size() < targetSamples && (millis() - startMs) < timeoutMs) {
    if (bsecReady) {
      runCalls++;
      bsec.run();

      // Auto-recover if I2C bus fails (sensor.status < 0, e.g. -2)
      if (bsec.sensor.status < 0) {
        logMessage("[ERROR]: I2C bus error detected (sensor.status=" + String(bsec.sensor.status) + "). Recovering bus...");
        Wire.end();
        clearI2CBus();
        vTaskDelay(pdMS_TO_TICKS(20));
        Wire.begin(I2C_SDA, I2C_SCL);
        Wire.setClock(I2C_CLOCK_SPEED_HZ);
        bsec.begin(bmeI2cAddr, Wire);
        bsec.attachCallback(newDataCallback);
        bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP);
      }
    }

    if (newGasDataAvailable) {
      newGasDataAvailable = false;

      if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes <= MAX_VALID_BASELINE_GAS_RES) {
        samples.push_back({
          sensorData.currentGasRes,
          sensorData.currentHumidity,
          sensorData.currentTemp,
          sensorData.currentCO2
        });

        logMessage("[BASELINE TRACE]: Valid Sample " + String(samples.size()) + "/" + String(targetSamples) + 
                   " = " + String(sensorData.currentGasRes, 0) + " Ohm (t=" + String(millis() - startMs) + "ms)");
      } 
      else if (sensorData.currentGasRes > MAX_VALID_BASELINE_GAS_RES) {
        logMessage("[BASELINE TRACE]: Discarded transient reading: " + 
                   String(sensorData.currentGasRes, 0) + " Ohm (exceeds " + String((long)MAX_VALID_BASELINE_GAS_RES) + " Ohm)");
      }
    }

    if (millis() - lastDiagMs >= 1000UL) {
      lastDiagMs = millis();
      logMessage("[DIAG BASELINE @ " + String(millis() - startMs) + "ms]" +
                 " samples: " + String(samples.size()) + "/" + String(targetSamples) +
                 " | run() calls: " + String(runCalls) + 
                 " | bsec.status: " + String(bsec.status) + 
                 " | sensor.status: " + String(bsec.sensor.status));
    }

    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  return samples;
}

// 2. Main: Trims transient anomalies and computes baseline averages
static uint8_t collectBaselineSamples(float &outSumRes, float &outSumHumidity, float &outSumTemp, float &outSumCO2, 
                                       uint8_t targetSamples, uint32_t timeoutMs) {
  logMessage("[BASELINE TRACE]: Gathering batch for statistical baseline filtering...");

  // Step 1: Collect raw sample batch
  std::vector<SampleFrame> samples = fetchRawBaselineSamples(targetSamples, timeoutMs);

  if (samples.empty()) {
    logMessage("[BASELINE TRACE]: Collection timed out with 0 samples.");
    return 0;
  }

  // Step 2: Sort samples ascending by gas resistance
  std::sort(samples.begin(), samples.end(), [](const SampleFrame &a, const SampleFrame &b) {
    return a.gasRes < b.gasRes;
  });

  // Step 3: Determine index bounds to trim high/low transient spikes
  size_t startIdx = 0;
  size_t endIdx = samples.size();

  if (samples.size() >= MIN_SAMPLES_TO_TRIM_HIGH) {
    endIdx--; // Drop highest transient hotplate spike
    logMessage("[BASELINE TRACE]: Discarded high transient (" + String(samples.back().gasRes, 0) + " Ohm)");
  }
  if (samples.size() >= MIN_SAMPLES_TO_TRIM_LOW) {
    startIdx++; // Drop lowest anomaly
    logMessage("[BASELINE TRACE]: Discarded low anomaly (" + String(samples.front().gasRes, 0) + " Ohm)");
  }

  // Step 4: Accumulate remaining clean samples
  outSumRes = 0.0f; 
  outSumHumidity = 0.0f; 
  outSumTemp = 0.0f; 
  outSumCO2 = 0.0f;
  
  uint8_t validCount = 0;
  for (size_t i = startIdx; i < endIdx; i++) {
    outSumRes      += samples[i].gasRes;
    outSumHumidity += samples[i].humidity;
    outSumTemp     += samples[i].temp;
    outSumCO2      += samples[i].co2;
    validCount++;
  }

  logMessage("[BASELINE TRACE]: Averaged " + String(validCount) + " clean samples (Clean Baseline = " + 
             String(outSumRes / validCount, 0) + " Ohm)");

  return validCount;
}


// Validate baseline data quality and environmental safety bounds
static bool validateBaselineQuality(float baselineRes, float baseCO2) {
  if (baselineRes <= 0.0f) {
    logMessage("[WARNING]: Baseline aborted — invalid gas resistance acquired.");
    dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
    return false;
  }

  if (baseCO2 > ROOM_AIR_MAX_CO2_PPM) {
    logMessage("[WARNING]: Baseline aborted due to high background VOC/CO2 levels.");
    dispatchData("{\"state\":\"" + String(STATE_ROOM_AIR_DIRTY) + "\"}");
    return false;
  }

  return true;
}

bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp, float &outBaseCO2) {
  if (!bsecReady) {
    logMessage("[ERROR]: prepareAndCaptureBaseline aborted — bsecReady is false!");
    dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
    return false;
  }

  logMessage("[BASELINE]: Capturing " + String(BASELINE_TARGET_SAMPLE_COUNT) + 
             " samples for adaptive baseline filtering...");

  float sumRes = 0.0f, sumHumidity = 0.0f, sumTemp = 0.0f, sumCO2 = 0.0f;

  uint8_t count = collectBaselineSamples(sumRes, sumHumidity, sumTemp, sumCO2, 
                                         BASELINE_TARGET_SAMPLE_COUNT, 
                                         BASELINE_CAPTURE_TIMEOUT_MS);

  if (count == 0) {
    logMessage("[WARNING]: Baseline collection failed to yield valid samples.");
    dispatchData("{\"state\":\"" + String(STATE_TRY_AGAIN_LATER) + "\"}");
    return false;
  }

  outBaselineRes  = sumRes / count;
  outBaseHumidity = sumHumidity / count;
  outBaseTemp     = sumTemp / count;
  outBaseCO2      = sumCO2 / count;

  return validateBaselineQuality(outBaselineRes, outBaseCO2);
}

static bool evaluateExhalationFrame(float baseGasRes, float baseHumidity, float baseTemp, float baseCO2, 
                                   float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  if (!newGasDataAvailable) return false;
  newGasDataAvailable = false;

  float deltaHumidity = sensorData.currentHumidity - baseHumidity;
  float deltaTemp     = sensorData.currentTemp - baseTemp;
  float deltaCO2      = sensorData.currentCO2 - baseCO2;
  float gasDropPct    = (baseGasRes > 0.0f && sensorData.currentGasRes > 0.0f) ?
                        ((baseGasRes - sensorData.currentGasRes) / baseGasRes) * 100.0f : 0.0f;

  // Track minimum gas resistance (peak drop)
  if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < outMinRes) {
    outMinRes = sensorData.currentGasRes;
  }

  // Record peak deltas for final classification in evaluateBreathResult()
  if (deltaHumidity > outMaxDeltaRH) outMaxDeltaRH = deltaHumidity;
  if (deltaCO2 > outMaxDeltaCO2)     outMaxDeltaCO2 = deltaCO2;

  dispatchData("{\"dH\":" + String(deltaHumidity, 1) + 
               ",\"dT\":" + String(deltaTemp, 1) + 
               ",\"dCO2\":" + String(deltaCO2, 0) + 
               ",\"gDrop\":" + String(gasDropPct, 1) + "}");

  bool isMoistSpike = (deltaHumidity >= 2.5f);
  bool isWarming    = (deltaTemp >= 0.10f);
  bool isCO2Spike   = (deltaCO2 >= 250.0f);
  bool isGasDrop    = (gasDropPct >= 1.5f);

  bool hasPrimaryAnchor   = (isMoistSpike || isCO2Spike);
  bool hasSecondarySignal = (isWarming || isGasDrop || (isMoistSpike && isCO2Spike));

  return hasPrimaryAnchor && hasSecondarySignal;
}

bool waitForBreathExhalation(float baseGasRes, float baseHumidity, float baseTemp, float baseCO2, 
                             float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  dispatchData("{\"state\":\"" + String(STATE_READY_PLEASE_BLOW) + "\"}");
  vTaskDelay(pdMS_TO_TICKS(50));

  uint32_t startMs = millis();
  newGasDataAvailable = false;

  // Initialize peak tracking variables
  outMaxDeltaRH  = 0.0f;
  outMaxDeltaCO2 = 0.0f;

  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    bsec.run();

    if (evaluateExhalationFrame(baseGasRes, baseHumidity, baseTemp, baseCO2, 
                                outMinRes, outMaxDeltaRH, outMaxDeltaCO2)) {
      return true;
    }

    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  return false;
}

void captureBreathSensingWindow(float baseHumidity, float baseCO2, float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  dispatchData("{\"state\":\"" + String(STATE_TESTING_SENSING_BREATH) + "\"}");
  vTaskDelay(pdMS_TO_TICKS(50));

  uint32_t blowWindowStart = millis();
  newGasDataAvailable = false;

  while ((millis() - blowWindowStart) < BREATH_SENSING_WINDOW_MS) {
    bsec.run();

    if (newGasDataAvailable) {
      newGasDataAvailable = false;

      if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < outMinRes) {
        outMinRes = sensorData.currentGasRes;
      }

      float dRH = sensorData.currentHumidity - baseHumidity;
      float dCO2 = sensorData.currentCO2 - baseCO2;

      if (dRH > outMaxDeltaRH) outMaxDeltaRH = dRH;
      if (dCO2 > outMaxDeltaCO2) outMaxDeltaCO2 = dCO2;
    }

    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}

bool waitAndCaptureBreath(float baseRes, float baseHumidity, float baseTemp, float baseCO2, 
                          float &outMinRes, float &outMaxDeltaRH, float &outMaxDeltaCO2) {
  outMinRes = baseRes;

  // Updated call passes all 7 required arguments
  if (!waitForBreathExhalation(baseRes, baseHumidity, baseTemp, baseCO2, 
                               outMinRes, outMaxDeltaRH, outMaxDeltaCO2)) {
    setBsecProfile(PROFILE_LP_3S);
    return false;
  }

  captureBreathSensingWindow(baseHumidity, baseCO2, outMinRes, outMaxDeltaRH, outMaxDeltaCO2);

  setBsecProfile(PROFILE_LP_3S);
  return true;
}

// ===================================================================
// MODULAR BREATH SEQUENCE EXECUTION ENGINE
// ===================================================================

static void executeBreathWarmup() {
  uint32_t warmTime = (currentProfile == PROFILE_LP_3S) ? WARMUP_SHORT_DELAY_MS : WARMUP_LONG_DELAY_MS;
  setBsecProfile(PROFILE_LP_3S);

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_STARTED) + "\"}");
  dispatchData("{\"state\":\"" + String(STATE_WARMING_UP) + "\",\"seconds\":" + String(warmTime / 1000) + "}");
  vTaskDelay(pdMS_TO_TICKS(100));

  uint32_t warmupStart = millis();
  while (millis() - warmupStart < warmTime) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }
}

static void processBreathTestResults(float baseRes, float minRes, float maxDeltaHumidity, float maxDeltaCO2) {
  float deltaDrop = 0.0f;
  if (baseRes > 0.0f) {
    deltaDrop = ((baseRes - minRes) / baseRes) * 100.0f;
    if (deltaDrop < 0.0f) deltaDrop = 0.0f;
  }

  sensorData.deltaDrop = deltaDrop;
  sensorData.rBreathMin = (long)minRes;
  sensorData.selectivityRatio = selectivityRatio;
  
  sensorData.ptcResult = evaluateBreathResult(deltaDrop, maxDeltaHumidity, maxDeltaCO2, selectivityRatio);

  dispatchData("{\"status\":\"" + String(STATUS_BREATH_TEST_COMPLETE) + "\"}");
  dispatchData(sensorData.toJsonString());
  vTaskDelay(pdMS_TO_TICKS(100));
}

static void resetToDefaultMode() {
  setBsecProfile(PROFILE_ULP_300S);
  currentMode = MODE_DRY_AIR_DETECTION;
}

void runBreathSequence() {
  dryAirActive = false;
  currentMode = MODE_BREATH_TEST;

  executeBreathWarmup();

  float baseRes = 0.0f, baseHumidity = 0.0f, baseTemp = 0.0f, baseCO2 = 0.0f;
  float maxDeltaRH = 0.0f, maxDeltaCO2 = 0.0f;

  if (!prepareAndCaptureBaseline(baseRes, baseHumidity, baseTemp, baseCO2)) {
    resetToDefaultMode();
    return;
  }

  float minRes = baseRes;

  bool breathDetected = waitAndCaptureBreath(baseRes, baseHumidity, baseTemp, baseCO2, 
                                            minRes, maxDeltaRH, maxDeltaCO2);

  if (!breathDetected) {
    dispatchData("{\"state\":\"" + String(STATE_TIMEOUT) + "\"}");
    vTaskDelay(pdMS_TO_TICKS(100));
  } else {
    processBreathTestResults(baseRes, minRes, maxDeltaRH, maxDeltaCO2);
  }

  resetToDefaultMode();
}

////////////////////////////////////////////////////////////////////////

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
  // 1. Moisture Condition Variables
  const bool isDryMouth = (maxDeltaHumidity < DRY_MOUTH_MAX_DELTA_RH_PCT) && 
                          (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT || maxDeltaCO2 >= DRY_MOUTH_MIN_DELTA_CO2_PPM);
  const bool validMoisture = (maxDeltaHumidity >= DRY_MOUTH_MAX_DELTA_RH_PCT);

  // 2. Selectivity Ratio Variables
  const bool isMalodorRatio = (selectivityRatio >= SELECTIVITY_RATIO_MALODOR_THRESHOLD);       // Ratio >= 0.5 (Sulfur / VSCs)
  const bool isBeverageFoodRatio = (selectivityRatio < SELECTIVITY_RATIO_MALODOR_THRESHOLD);  // Ratio < 0.5  (Aromatics)

  // 3. Gas Resistance Drop Threshold Variables
  const bool isSubThresholdDrop = (deltaDrop < BREATH_FRESH_MAX_DROP_PCT);                      // ΔDrop < 15%
  const bool isSlightDrop = (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT);                          // ΔDrop >= 15%
  const bool isModerateDrop = (deltaDrop >= BREATH_FRESH_MAX_DROP_PCT) && 
                              (deltaDrop < BREATH_SIGNIFICANT_MAX_DROP_PCT);                    // 15% <= ΔDrop < 45%
  const bool isSevereDrop = (deltaDrop >= BREATH_SIGNIFICANT_MAX_DROP_PCT);                    // ΔDrop >= 45%

  // --- ROW 1: DRY MOUTH (LOW VSCs) ---
  if (isDryMouth && isBeverageFoodRatio) {
    return RESULT_DRY_MOUTH_HYDRATE;
  }

  // --- ROW 2: DRY MOUTH (ACTIVE VSC BUILDUP) ---
  if (isDryMouth && isMalodorRatio) {
    return RESULT_DRY_MOUTH_VSC_BUILDUP;
  }

  // --- ROW 3: LINGERING/SETTLING BEVERAGE/FOOD (ΔRH >= 2.5%, ΔDROP < 15%, RATIO < 0.5) ---
  if (validMoisture && isSubThresholdDrop && isBeverageFoodRatio) {
    return RESULT_SETTLE_BEVERAGE_FOOD_ODOR;
  }

  // --- ROW 4: BALANCED BREATH (ΔRH >= 2.5%, ΔDROP < 15%) ---
  if (validMoisture && isSubThresholdDrop) {
    return RESULT_BALANCED_BREATH;
  }

  // --- ROW 5: SOME BEVERAGE / FOOD ODOR (ΔRH >= 2.5%, ΔDROP >= 15%, RATIO < 0.5) ---
  if (validMoisture && isSlightDrop && isBeverageFoodRatio) {
    return RESULT_SOME_BEVERAGE_FOOD_ODOR;
  }

  // --- ROW 6: NOTICEABLE MALODOR (ΔRH >= 2.5%, 15% <= ΔDROP < 45%, RATIO >= 0.5) ---
  if (validMoisture && isModerateDrop && isMalodorRatio) {
    return RESULT_NOTICEABLE_MALODOR;
  }

  // --- ROW 7: STRONG MALODOR (ΔRH >= 2.5%, ΔDROP >= 45%, RATIO >= 0.5) ---
  if (validMoisture && isSevereDrop && isMalodorRatio) {
    return RESULT_STRONG_MALODOR;
  }

  // --- SAFEGUARD FALLBACK ---
  return RESULT_NONE;
}

uint8_t readBatteryPercentage() {
  uint32_t totalMv = 0;
  for (int i = 0; i < 4; i++) {
    totalMv += analogReadMilliVolts(BATTERY_ADC_PIN);
    vTaskDelay(pdMS_TO_TICKS(5)); // Safe now because it only runs once every 30s in loop()
  }
  uint32_t rawMv = totalMv / 4;
  float voltage = (rawMv / 1000.0f) * 2.0f;
  
  if (voltage < 2.0f) return 100; // Tethered to USB
  if (voltage >= 4.2f) return 100;
  if (voltage <= 3.3f) return 0;
  
  return (uint8_t)(((voltage - 3.3f) / (4.2f - 3.3f)) * 100.0f);
}