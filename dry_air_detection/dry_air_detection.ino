#include <Wire.h>
#include <SPIFFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"

// Set to false for battery production to disable USB CDC power drain
#define ENABLE_SERIAL_LOGS false 

#define I2C_SDA 6
#define I2C_SCL 7

#define SERVICE_UUID        "4FA215F0-0001-4B0E-B682-1A4C70F3A601"
#define CHARACTERISTIC_UUID "4FA215F0-0002-4B0E-B682-1A4C70F3A601"

String Device_Name = "Meso Nose";

// -------------------------------------------------------------------
// Hardware, Serial & Clock Constants
// -------------------------------------------------------------------
constexpr uint32_t SERIAL_BAUD_RATE            = 115200; // Serial UART speed
constexpr uint32_t I2C_CLOCK_SPEED_HZ          = 100000; // 100 kHz I2C Standard Mode
constexpr float PRESSURE_HPA_DIVISOR           = 100.0f; // Pascal to Hectopascal conversion
constexpr uint32_t CPU_LOW_POWER_FREQ_MHZ      = 80;     // Low power CPU scale rate

// -------------------------------------------------------------------
// Hardware Initialization Delays (Millisecond Durations)
// -------------------------------------------------------------------
constexpr uint32_t SERIAL_INIT_DELAY_MS        = 500;   // Serial startup stabilization delay
constexpr uint32_t BLE_POST_INIT_DELAY_MS      = 200;   // Delay after BLE stack launch
constexpr uint32_t I2C_BUS_RESET_DELAY_MS      = 50;    // I2C bus end/reset pulse delay
constexpr uint32_t I2C_BUS_SETTLE_DELAY_MS     = 100;   // I2C bus start/settle delay

// -------------------------------------------------------------------
// Operational Timing Constants (Millisecond Durations & BLE Intervals)
// -------------------------------------------------------------------
constexpr uint32_t NOTIFY_LP_INTERVAL_MS      = 3000;   // 3 seconds (LP mode)
constexpr uint32_t NOTIFY_ULP_INTERVAL_MS     = 300000; // 5 minutes (ULP mode)
constexpr uint32_t WARMUP_DELAY_MS            = 5000;   // 5 seconds sensor warmup
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS     = 10000;  // 10 seconds to wait for blow start
constexpr uint32_t BREATH_SENSING_WINDOW_MS   = 12000;  // 12 seconds to capture minimum VOC
constexpr uint32_t LOOP_TICK_DELAY_MS         = 20;     // Fast RTOS yield to keep BLE stack snappy
constexpr uint32_t POLL_TICK_DELAY_MS         = 20;     // Fast polling RTOS yield

// BLE Advertising Timing Units (0.625 ms per count)
constexpr uint16_t BLE_ADV_MIN_INTERVAL       = 160;    // 100 ms (160 * 0.625ms)
constexpr uint16_t BLE_ADV_MAX_INTERVAL       = 320;    // 200 ms (320 * 0.625ms)

// -------------------------------------------------------------------
// Physical Thresholds & Clinical Evaluation Constants
// -------------------------------------------------------------------
constexpr float BREATH_FRESH_MAX_DROP_PCT       = 15.0f;  // < 15.0% = FRESH
constexpr float BREATH_MILD_MAX_DROP_PCT        = 35.0f;  // 15.0% to 34.9% = MILD
constexpr float BREATH_SIGNIFICANT_MAX_DROP_PCT = 55.0f;  // 35.0% to 54.9% = SIGNIFICANT
                                                         // >= 55.0% = SEVERE

// System Operational Modes
enum OperationMode { MODE_IDLE, MODE_DRY_AIR_DETECTION, MODE_BREATH_TEST };
enum BsecProfile { PROFILE_OFF, PROFILE_ULP_300S, PROFILE_LP_3S };

OperationMode currentMode = MODE_IDLE;
BsecProfile currentProfile = PROFILE_OFF;

bool dryAirActive = false;
bool deviceConnected = false;
bool bsecReady = false;
bool newGasDataAvailable = false;
volatile bool pendingBreathCommand = false; // Flag to instantly break out of dry air mode

struct SensorData {
  float currentTemp = 0.0f;
  float currentHumidity = 0.0f;
  float currentPressure = 0.0f;
  float currentGasRes = 0.0f;
  float deltaDrop = 0.0f;
  long rBreathMin = 0;
  String ptcResult = "NONE";

  String toJsonString() const {
    String json = "{";
    json += "\"rt\":" + String(currentTemp, 1) + ",";
    json += "\"rh\":" + String(currentHumidity, 1) + ",";
    json += "\"press\":" + String(currentPressure, 1) + ",";
    json += "\"voc\":" + String((long)currentGasRes) + ",";
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
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
  BSEC_OUTPUT_RAW_PRESSURE
};
uint8_t numSensors = sizeof(sensorList) / sizeof(bsecSensor);

Bsec2 bsec;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

bool wait10SecForBreathBlow();
float getBreathMinIndex(const float r_ambient);
String eval_breath_result(float pctDrop);
void setBsecProfile(BsecProfile profile);
void runBreathSequence();

void logMessage(String msg) {
#if ENABLE_SERIAL_LOGS
  Serial.println(msg);
  Serial.flush();
#endif
  if (deviceConnected && pCharacteristic) {
    String bleLog = "[LOG]: " + msg;
    pCharacteristic->setValue((uint8_t*)bleLog.c_str(), bleLog.length());
    pCharacteristic->notify();
  }
}

void sendBleMessage(String msg) {
#if ENABLE_SERIAL_LOGS
  Serial.println("[BLE OUT]: " + msg);
  Serial.flush();
#endif
  if (deviceConnected && pCharacteristic) {
    pCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
    pCharacteristic->notify();
  }
}

void setBsecProfile(BsecProfile profile) {
  if (currentProfile == profile) return;
  currentProfile = profile;

  if (profile == PROFILE_OFF) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_DISABLED);
    logMessage("BSEC Profile: OFF");
    sendBleMessage("{\"state\":\"PROFILE_OFF\"}");
  } 
  else if (profile == PROFILE_ULP_300S) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_ULP);
    logMessage("BSEC Profile: ULP (5-min)");
    sendBleMessage("{\"state\":\"PROFILE_ULP\"}");
  } 
  else if (profile == PROFILE_LP_3S) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP);
    logMessage("BSEC Profile: LP (3-sec)");
    sendBleMessage("{\"state\":\"PROFILE_LP\"}");
  }
}

void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsec) {
  if (!outputs.nOutputs) return;

  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    const bsecData output = outputs.output[i];
    switch (output.sensor_id) {
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
        sensorData.currentTemp = output.signal;        
        break;
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:
        sensorData.currentHumidity = output.signal;        
        break;
      case BSEC_OUTPUT_RAW_PRESSURE:
        sensorData.currentPressure = output.signal / PRESSURE_HPA_DIVISOR;
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

  sendBleMessage("{\"rx_cmd\":\"" + command + "\"}");

  if (command == "1" || command == "r" || command == "run") {
    setBsecProfile(PROFILE_LP_3S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
    sendBleMessage("{\"status\":\"DRY_AIR_STARTED\"}");
  }
  else if (command == "set_ultra_low_sampling_mode" || command == "set_ulp") {
    setBsecProfile(PROFILE_ULP_300S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
  }
  else if (command == "set_active_sampling_mode" || command == "set_lp") {
    setBsecProfile(PROFILE_LP_3S);
    dryAirActive = true;
    currentMode = MODE_DRY_AIR_DETECTION;
  }
  else if (command == "2" || command == "s" || command == "stop") {
    setBsecProfile(PROFILE_OFF);
    dryAirActive = false;
    currentMode = MODE_IDLE;
    sendBleMessage("{\"status\":\"DRY_AIR_STOPPED\"}");
  }
  else if (command == "10" || command == "status") {
    String statusResp = "{\"dry_air_active\":" + String(dryAirActive ? "true" : "false") + 
                        ",\"profile\":" + String((int)currentProfile) + "}";
    sendBleMessage(statusResp);
  }
}

class ServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) {
      deviceConnected = true;
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) {
      deviceConnected = false;
      setBsecProfile(PROFILE_ULP_300S);
      currentMode = MODE_IDLE;
      dryAirActive = false;
      pendingBreathCommand = false;
      NimBLEDevice::startAdvertising();
    }
};

class CharacteristicCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo& connInfo) {
      NimBLEAttValue val = pCharacteristic->getValue();
      if (val.length() > 0) {
        String rxValue = String((char*)val.data()).substring(0, val.length());
        rxValue.trim();
        rxValue.toLowerCase();

        // Direct check for breath test trigger
        if (rxValue == "3" || rxValue == "b" || rxValue == "breath" || rxValue.indexOf('b') != -1) {
          dryAirActive = false;
          pendingBreathCommand = true; // Interrupt loop on next pass
        } else {
          handleCommand(rxValue);
        }
      }
    }
};

void initBLE() {
  NimBLEDevice::init(Device_Name.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); 

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
  
  NimBLEAdvertisementData advData;
  advData.setName(Device_Name.c_str());
  advData.setCompleteServices(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advData);

  NimBLEAdvertisementData scanData;
  scanData.setName(Device_Name.c_str());
  pAdvertising->setScanResponseData(scanData);

  pAdvertising->setMinInterval(BLE_ADV_MIN_INTERVAL);
  pAdvertising->setMaxInterval(BLE_ADV_MAX_INTERVAL);
  pAdvertising->start();
}

void setup() {
  delay(2000); // Allow USB CDC / power rails to stabilize

#if ENABLE_SERIAL_LOGS
  Serial.begin(SERIAL_BAUD_RATE);
  delay(SERIAL_INIT_DELAY_MS);
#endif

  initBLE();

  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(I2C_CLOCK_SPEED_HZ);

  uint8_t sensorAddr = BME68X_I2C_ADDR_HIGH;
  Wire.beginTransmission(sensorAddr);
  if (Wire.endTransmission() != 0) {
    sensorAddr = BME68X_I2C_ADDR_LOW;
  }

  if (bsec.begin(sensorAddr, Wire)) {
    bsec.attachCallback(newDataCallback);
    setBsecProfile(PROFILE_ULP_300S);
    bsecReady = true;
  } else {
    bsecReady = false;
  }

  setCpuFrequencyMhz(CPU_LOW_POWER_FREQ_MHZ);
}

void runBreathSequence() {
  dryAirActive = false;
  currentMode = MODE_BREATH_TEST;

  sendBleMessage("{\"status\":\"BREATH_TEST_STARTED\"}");
  sendBleMessage("{\"state\":\"WARMING_UP\",\"seconds\":5}");
  
  setBsecProfile(PROFILE_LP_3S);

  // Warmup BSEC heater for 5 seconds
  uint32_t warmupStart = millis();
  while (millis() - warmupStart < WARMUP_DELAY_MS) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  // Run breath detection loop
  bool userBreathTaken = wait10SecForBreathBlow();

  if (!userBreathTaken) {
    sendBleMessage("{\"state\":\"TIMEOUT\"}");
  } else {
    float r_breath_min = getBreathMinIndex(sensorData.currentGasRes);
    float deltaDrop = (1.0f - (r_breath_min / sensorData.currentGasRes)) * 100.0f; 

    sensorData.deltaDrop = deltaDrop;
    sensorData.rBreathMin = (long)r_breath_min;
    sensorData.ptcResult = eval_breath_result(deltaDrop);
    sendBleMessage(sensorData.toJsonString());
  }

  setBsecProfile(PROFILE_ULP_300S);
  currentMode = MODE_IDLE;
}

void loop() {
  // 1. Immediate priority check for incoming breath command
  if (pendingBreathCommand) {
    pendingBreathCommand = false;
    runBreathSequence();
    return;
  }

  if (bsecReady) {
    bsec.run();

    if (currentMode == MODE_DRY_AIR_DETECTION && dryAirActive) {
      static unsigned long lastNotifyTime = 0;
      unsigned long notifyInterval = (currentProfile == PROFILE_LP_3S) ? NOTIFY_LP_INTERVAL_MS : NOTIFY_ULP_INTERVAL_MS;

      if (millis() - lastNotifyTime >= notifyInterval) {
        lastNotifyTime = millis();
        sensorData.deltaDrop = 0.0f;
        sensorData.rBreathMin = 0;
        sensorData.ptcResult = "NONE";

        sendBleMessage(sensorData.toJsonString());
      }
    } 
  }
  else {
    if (currentMode != MODE_IDLE) {
      sendBleMessage("{\"error\":\"HARDWARE_FAULT_BME688_NOT_FOUND\"}");
      currentMode = MODE_IDLE;
    }
  }

  vTaskDelay(pdMS_TO_TICKS(LOOP_TICK_DELAY_MS));
}

bool wait10SecForBreathBlow() {
  if (!bsecReady) return false;

  // 1. Force a baseline snapshot
  bsec.run();
  float baseHumidity = sensorData.currentHumidity;
  float baseTemp     = sensorData.currentTemp;
  float basePressure = sensorData.currentPressure;
  float baseGasRes   = sensorData.currentGasRes;

  sendBleMessage("{\"state\":\"READY_PLEASE_BLOW\"}");
  vTaskDelay(pdMS_TO_TICKS(300));

  uint32_t startMs = millis();
  uint32_t lastPrint = 0;
  bool detected = false;

  // HARD 10-SECOND LOCK
  while ((millis() - startMs) < 10000UL) {
    bsec.run(); // Pump BSEC to trigger newDataCallback

    // Calculate deltas against initial snapshot
    float deltaHumidity = fabs(sensorData.currentHumidity - baseHumidity);
    float deltaTemp     = fabs(sensorData.currentTemp - baseTemp);
    float deltaPressure = fabs(sensorData.currentPressure - basePressure);
    
    float gasDropPct = 0.0f;
    if (baseGasRes > 0.0f && sensorData.currentGasRes > 0.0f) {
      gasDropPct = ((baseGasRes - sensorData.currentGasRes) / baseGasRes) * 100.0f;
    }

    // Stream status every 1 second
    if (millis() - lastPrint >= 1000UL) {
      lastPrint = millis();
      String debugMsg = "{\"dH\":" + String(deltaHumidity, 1) + 
                        ",\"dP\":" + String(deltaPressure, 2) + 
                        ",\"gDrop\":" + String(gasDropPct, 1) + "}";
      sendBleMessage(debugMsg);
    }

    // Trigger condition
    if (deltaHumidity >= 0.2f || deltaPressure >= 0.01f || gasDropPct >= 0.5f) {
      detected = true;
      break;
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }

  return detected;
}

float getBreathMinIndex(const float r_ambient) {
  if (!bsecReady) return r_ambient;

  sendBleMessage("{\"state\":\"TESTING_SENSING_BREATH\"}");

  float r_breath_min = (r_ambient > 0.0f) ? r_ambient : sensorData.currentGasRes; 
  uint32_t blowStart = millis();
  newGasDataAvailable = false;

  while (millis() - blowStart < BREATH_SENSING_WINDOW_MS) {
    bsec.run();
    
    if (newGasDataAvailable) {
      if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < r_breath_min) {
        r_breath_min = sensorData.currentGasRes; 
      }
      newGasDataAvailable = false;
    }
    
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  return r_breath_min;
}

String eval_breath_result(float pctDrop) {
  if (pctDrop < BREATH_FRESH_MAX_DROP_PCT) {
    return "FRESH";
  }
  else if (pctDrop < BREATH_MILD_MAX_DROP_PCT) {
    return "MILD";
  }
  else if (pctDrop < BREATH_SIGNIFICANT_MAX_DROP_PCT) {
    return "SIGNIFICANT";
  }
  else {
    return "SEVERE";
  }
}