#include <Wire.h>
#include <FS.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"

#define ENABLE_SERIAL_LOGS true 
#define BATTERY_ADC_PIN 1 // Set to your ESP32 battery sensing pin

#define I2C_SDA 6
#define I2C_SCL 7

#define SERVICE_UUID        "4fa215f0-0001-4b0e-b682-1a4c70f3a601"
#define CHARACTERISTIC_UUID "4fa215f0-0002-4b0e-b682-1a4c70f3a601"

String Device_Name = "Meso Nose";
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
// Physical Thresholds & Clinical Evaluation Constants
// -------------------------------------------------------------------
constexpr float BREATH_FRESH_MAX_DROP_PCT       = 15.0f;  
constexpr float BREATH_MILD_MAX_DROP_PCT        = 35.0f;  
constexpr float BREATH_SIGNIFICANT_MAX_DROP_PCT = 55.0f;  

enum OperationMode { MODE_IDLE, MODE_DRY_AIR_DETECTION, MODE_BREATH_TEST };
enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };

OperationMode currentMode = MODE_IDLE;
BsecProfile currentProfile = PROFILE_OFF;

bool dryAirActive = false;
bool deviceConnected = false;
bool bsecReady = false;
bool newGasDataAvailable = false;
volatile bool pendingBreathCommand = false; 
volatile bool pendingFlush = false;

// -------------------------------------------------------------------
// Offline Accumulation Variables (Rate Limited to 5 Minutes)
// -------------------------------------------------------------------
unsigned long lastOfflineWriteTime = 0;
float accumTemp = 0.0f;
float accumHumidity = 0.0f;
float accumPressure = 0.0f;
float accumGasRes = 0.0f;
int accumCount = 0;

struct SensorData {
  float currentTemp = 0.0f;
  float currentHumidity = 0.0f;
  float currentPressure = 0.0f;
  float currentGasRes = 0.0f;
  float deltaDrop = 0.0f;
  long rBreathMin = 0;
  String ptcResult = "NONE";
  uint8_t batteryPct = 100; // <--- Add Battery Percentage Field

  String toJsonString() const {
    String json = "{";
    json += "\"temp\":" + String(currentTemp, 1) + ",";
    json += "\"rh\":" + String(currentHumidity, 1) + ",";
    json += "\"press\":" + String(currentPressure, 1) + ",";
    json += "\"voc\":" + String((long)currentGasRes) + ",";
    json += "\"battery\":" + String(batteryPct) + ","; // <--- Included in JSON
    json += "\"breath_drop_delta\":" + String(deltaDrop, 1) + ",";
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
  BSEC_OUTPUT_RAW_PRESSURE
};
uint8_t numSensors = sizeof(sensorList) / sizeof(bsecSensor);

Bsec2 bsec;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

void adjustAdvertisingPower(bool newlyDisconnected);
void saveOfflineData();
void flushOfflineData();
void enterLightSleep(uint64_t sleepTimeMs);
void performWarmup();
bool waitAndCaptureBreath(float &outBaselineRes, float &outMinRes);
String eval_breath_result(float pctDrop);
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
    avgData.ptcResult = "NONE";

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

void setBsecProfile(BsecProfile profile) {
  if (currentProfile == profile) return;
  currentProfile = profile;

  if (profile == PROFILE_OFF) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_DISABLED);
    dispatchData("{\"state\":\"PROFILE_OFF\"}");
  } 
  else if (profile == PROFILE_ULP_300S) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_ULP);
    dispatchData("{\"state\":\"PROFILE_ULP\"}");
  } 
  else if (profile == PROFILE_LP_3S) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP);
    dispatchData("{\"state\":\"PROFILE_LP\"}");
  }
  vTaskDelay(pdMS_TO_TICKS(50));
}

void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsec) {
  if (!outputs.nOutputs) return;

  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    const bsecData output = outputs.output[i];
    switch (output.sensor_id) {
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
        if (output.signal > -40.0f && output.signal < 85.0f && output.signal != 0.0f) {
          sensorData.currentTemp = output.signal;
        }
        break;
      case BSEC_OUTPUT_RAW_HUMIDITY:
        sensorData.currentHumidity = output.signal;
        break;
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:
        if (sensorData.currentHumidity == 0.0f) {
          sensorData.currentHumidity = output.signal;
        }
        break;
      case BSEC_OUTPUT_RAW_PRESSURE:
        sensorData.currentPressure = output.signal;
        break;
      case BSEC_OUTPUT_RAW_GAS:
        sensorData.currentGasRes = output.signal;
        newGasDataAvailable = true;
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
    dispatchData("{\"status\":\"DRY_AIR_STARTED\"}");
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
    dispatchData("{\"status\":\"DRY_AIR_STOPPED\"}");
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

        if (rxValue == "3" || rxValue == "b" || rxValue == "breath" || rxValue.indexOf('b') != -1) {
          dryAirActive = false;
          currentMode = MODE_BREATH_TEST;
          pendingBreathCommand = true;
        } else {
          handleCommand(rxValue);
        }
      }
    }
};

void initBLE() {
  Serial.println("[BLE] Starting NimBLE initialization...");
  
  // Get chip MAC address suffix (e.g., "Meso Nose A1B2")
  uint64_t mac = ESP.getEfuseMac();
  char macSuffix[6];
  snprintf(macSuffix, sizeof(macSuffix), "%02X%02X", 
           (uint8_t)(mac >> 40), (uint8_t)(mac >> 32));
  
  Device_Name = "Meso Nose " + String(macSuffix);

  Serial.println("[BLE] Device Name: " + Device_Name);
  NimBLEDevice::init(Device_Name.c_str());

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

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  // Packet 1: Main Advert (Flags + UUID) - Fits under 31 bytes
  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN);
  advData.setCompleteServices(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advData);

  // Packet 2: Scan Response (Device Name)
  NimBLEAdvertisementData scanData;
  scanData.setName(Device_Name.c_str());
  pAdvertising->setScanResponseData(scanData);

  pAdvertising->enableScanResponse(true);

  adjustAdvertisingPower(true);
  Serial.println("[BLE] Advertising active with split payload!");
}

void setup() {
  delay(2000); 

#if ENABLE_SERIAL_LOGS
  Serial.begin(SERIAL_BAUD_RATE);
  delay(SERIAL_INIT_DELAY_MS);
  Serial.println("Booting Meso Nose with Storage & Light Sleep Support...");
  Serial.printf("Free Heap at startup: %d bytes\n", ESP.getFreeHeap());
#endif

  if (!LittleFS.begin(true, "/littlefs", 10, "spiffs")) {
   Serial.println("LittleFS Mount Failed and Auto-Format Failed!");
  } else {
   Serial.println("[STORAGE]: LittleFS mounted successfully!");
  }

  Serial.println("[SETUP] Initializing BLE...");
  initBLE();
  Serial.printf("Free Heap after BLE: %d bytes\n", ESP.getFreeHeap());

  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(I2C_CLOCK_SPEED_HZ);
  Wire.setTimeOut(1000);

  uint8_t sensorAddr = BME68X_I2C_ADDR_HIGH;
  Wire.beginTransmission(sensorAddr);
  if (Wire.endTransmission() != 0) {
    sensorAddr = BME68X_I2C_ADDR_LOW;
  }

  Serial.print("Connecting to BSEC at address: 0x");
  Serial.println(sensorAddr, HEX);

  if (bsec.begin(sensorAddr, Wire)) {
    bsec.attachCallback(newDataCallback);
    bsec.setTemperatureOffset(0.0f);
    setBsecProfile(PROFILE_ULP_300S);
    bsecReady = true;
    Serial.println("[SETUP] BSEC started successfully!");
  } else {
    Serial.println("[SETUP] BSEC failed to start!");
    bsecReady = false;
  }
  
  Serial.println("[SETUP] Setup complete!");

#if ENABLE_SERIAL_LOGS
  printStoredFileToSerial();
#endif
}

void loop() {
  adjustAdvertisingPower(false);

  if (pendingFlush && deviceConnected) {
    pendingFlush = false;
    flushOfflineData();
  }

  if (pendingBreathCommand) {
    pendingBreathCommand = false;
    runBreathSequence();
    return;
  }

  if (bsecReady && dryAirActive) {
    bsec.run();

    static unsigned long lastNotifyTime = 0;
    unsigned long notifyInterval = (currentProfile == PROFILE_LP_3S) ? NOTIFY_LP_INTERVAL_MS : NOTIFY_ULP_INTERVAL_MS;

    if (millis() - lastNotifyTime >= notifyInterval) {
      lastNotifyTime = millis();
      sensorData.deltaDrop = 0.0f;
      sensorData.rBreathMin = 0;
      sensorData.ptcResult = "NONE";

      sensorData.batteryPct = readBatteryPercentage();
      dispatchData(sensorData.toJsonString());
    }
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

void runBreathSequence() {
  dryAirActive = false;
  currentMode = MODE_BREATH_TEST;

  uint32_t warmTime = (currentProfile == PROFILE_LP_3S) ? WARMUP_SHORT_DELAY_MS : WARMUP_LONG_DELAY_MS;
  setBsecProfile(PROFILE_LP_3S);

  dispatchData("{\"status\":\"BREATH_TEST_STARTED\"}");
  dispatchData("{\"state\":\"WARMING_UP\",\"seconds\":" + String(warmTime / 1000) + "}");
  vTaskDelay(pdMS_TO_TICKS(100));
    
  uint32_t warmupStart = millis();
  while (millis() - warmupStart < warmTime) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  float baseRes = 0.0f, minRes = 0.0f;
  bool userBreathTaken = waitAndCaptureBreath(baseRes, minRes);

  if (!userBreathTaken) {
    dispatchData("{\"state\":\"TIMEOUT\"}");
    vTaskDelay(pdMS_TO_TICKS(100));
  } else {
    float deltaDrop = 0.0f;
    if (baseRes > 0.0f) {
      deltaDrop = ((baseRes - minRes) / baseRes) * 100.0f;
      if (deltaDrop < 0.0f) deltaDrop = 0.0f;
    }

    sensorData.deltaDrop = deltaDrop;
    sensorData.rBreathMin = (long)minRes;
    sensorData.ptcResult = eval_breath_result(deltaDrop);
    sensorData.batteryPct = readBatteryPercentage();
    
    dispatchData("{\"status\":\"BREATH_TEST_COMPLETE\"}");
    dispatchData(sensorData.toJsonString());
    vTaskDelay(pdMS_TO_TICKS(100));
  }

  setBsecProfile(PROFILE_ULP_300S);
  currentMode = MODE_DRY_AIR_DETECTION;
}

bool waitAndCaptureBreath(float &outBaselineRes, float &outMinRes) {
  if (!bsecReady) return false;

  newGasDataAvailable = false;
  uint32_t baselineTimeout = millis();
  while (!newGasDataAvailable && (millis() - baselineTimeout < 4000UL)) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  float baseHumidity = sensorData.currentHumidity;
  float baseGasRes   = sensorData.currentGasRes;
  outBaselineRes     = baseGasRes;
  outMinRes          = baseGasRes;

  dispatchData("{\"state\":\"READY_PLEASE_BLOW\"}");
  vTaskDelay(pdMS_TO_TICKS(100)); 

  uint32_t startMs = millis();
  bool detected = false;
  
  newGasDataAvailable = false;

  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    bsec.run();

    if (newGasDataAvailable) {
      newGasDataAvailable = false;

      float deltaHumidity = sensorData.currentHumidity - baseHumidity;
      float gasDropPct = (baseGasRes > 0.0f && sensorData.currentGasRes > 0.0f) ? 
                         ((baseGasRes - sensorData.currentGasRes) / baseGasRes) * 100.0f : 0.0f;

      if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < outMinRes) {
        outMinRes = sensorData.currentGasRes;
      }

      dispatchData("{\"dH\":" + String(deltaHumidity, 1) + ",\"gDrop\":" + String(gasDropPct, 1) + "}");

      if (deltaHumidity >= 0.3f || gasDropPct >= 0.8f) {
        detected = true;
        break;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  if (!detected) return false;

  dispatchData("{\"state\":\"TESTING_SENSING_BREATH\"}");
  vTaskDelay(pdMS_TO_TICKS(50));

  uint32_t blowWindowStart = millis();
  newGasDataAvailable = false;

  while (millis() - blowWindowStart < BREATH_SENSING_WINDOW_MS) {
    bsec.run();
    if (newGasDataAvailable) {
      newGasDataAvailable = false;
      if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < outMinRes) {
        outMinRes = sensorData.currentGasRes; 
      }
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  return true;
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

String eval_breath_result(float pctDrop) {
  if (pctDrop < BREATH_FRESH_MAX_DROP_PCT) return "FRESH";
  if (pctDrop < BREATH_MILD_MAX_DROP_PCT) return "MILD";
  if (pctDrop < BREATH_SIGNIFICANT_MAX_DROP_PCT) return "SIGNIFICANT";
  return "SEVERE";
}

uint8_t readBatteryPercentage() {
  // Read raw ADC (ESP32 12-bit ADC: 0 - 4095)
  uint32_t raw = analogRead(BATTERY_ADC_PIN);
  
  // Convert ADC reading to actual battery voltage (adjust multiplier for your resistor divider)
  float voltage = (raw / 4095.0f) * 3.3f * 2.0f; // Multiplied by 2 for 1:1 voltage divider
  
  // LiPo battery voltage range: 4.2V (100%) to 3.3V (0%)
  if (voltage >= 4.2f) return 100;
  if (voltage <= 3.3f) return 0;
  
  uint8_t pct = (uint8_t)(((voltage - 3.3f) / (4.2f - 3.3f)) * 100.0f);
  return pct;
}