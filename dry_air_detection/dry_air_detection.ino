#include <Wire.h>
#include <SPIFFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"

// Set to false for battery production to disable USB CDC power drain
#define ENABLE_SERIAL_LOGS true 

#define I2C_SDA 6
#define I2C_SCL 7

#define SERVICE_UUID        "4FA215F0-0001-4B0E-B682-1A4C70F3A601"
#define CHARACTERISTIC_UUID "4FA215F0-0002-4B0E-B682-1A4C70F3A601"

String Device_Name = "Meso Nose";

// -------------------------------------------------------------------
// Hardware, Serial & Clock Constants
// -------------------------------------------------------------------
constexpr uint32_t SERIAL_BAUD_RATE            = 115200; 
constexpr uint32_t I2C_CLOCK_SPEED_HZ          = 100000; 
constexpr float PRESSURE_HPA_DIVISOR           = 100.0f; 
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
constexpr uint32_t WARMUP_DELAY_MS            = 4000;   // 4 seconds sensor thermal stabilization
constexpr uint32_t BREATH_WAIT_TIMEOUT_MS     = 10000;  // 10 seconds to wait for blow start
constexpr uint32_t BREATH_SENSING_WINDOW_MS   = 3500;   // 3.5 seconds to capture minimum VOC nadir
constexpr uint32_t LOOP_TICK_DELAY_MS         = 20;     
constexpr uint32_t POLL_TICK_DELAY_MS         = 50;     

// BLE Advertising Timing Units
constexpr uint16_t BLE_ADV_MIN_INTERVAL       = 160;    
constexpr uint16_t BLE_ADV_MAX_INTERVAL       = 320;    

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
    json += "\"temp\":" + String(currentTemp, 1) + ",";
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

bool waitAndCaptureBreath(float &outBaselineRes, float &outMinRes);
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
    sendBleMessage("{\"state\":\"PROFILE_OFF\"}");
  } 
  else if (profile == PROFILE_ULP_300S) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_ULP);
    sendBleMessage("{\"state\":\"PROFILE_ULP\"}");
  } 
  else if (profile == PROFILE_LP_3S) {
    bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP);
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

        logMessage("BLE Received Command: " + rxValue);

        if (rxValue == "3" || rxValue == "b" || rxValue == "breath" || rxValue.indexOf('b') != -1) {
          dryAirActive = false;               // Force ambient mode to stop
          currentMode = MODE_BREATH_TEST;    // Lock mode immediately
          pendingBreathCommand = true;       // Trigger sequence on next pass
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
  delay(2000); 

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
  sendBleMessage("{\"state\":\"WARMING_UP\",\"seconds\":4}");
  
  setBsecProfile(PROFILE_LP_3S);

  // Warmup BSEC heater for 4 seconds with RTOS yield
  uint32_t warmupStart = millis();
  while (millis() - warmupStart < WARMUP_DELAY_MS) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(100));
  }

  float baseRes = 0.0f;
  float minRes = 0.0f;
  
  bool userBreathTaken = waitAndCaptureBreath(baseRes, minRes);

  if (!userBreathTaken) {
    sendBleMessage("{\"state\":\"TIMEOUT\"}");
  } else {
    float deltaDrop = 0.0f;
    if (baseRes > 0.0f) {
      deltaDrop = ((baseRes - minRes) / baseRes) * 100.0f;
      if (deltaDrop < 0.0f) deltaDrop = 0.0f;
    }

    sensorData.deltaDrop = deltaDrop;
    sensorData.rBreathMin = (long)minRes;
    sensorData.ptcResult = eval_breath_result(deltaDrop);
    
    sendBleMessage(sensorData.toJsonString());
  }

  setBsecProfile(PROFILE_ULP_300S);
  currentMode = MODE_IDLE;
}

void loop() {
  // Check breath trigger FIRST before touching BSEC
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

      sendBleMessage(sensorData.toJsonString());
    }
  }

  vTaskDelay(pdMS_TO_TICKS(LOOP_TICK_DELAY_MS));
}

bool waitAndCaptureBreath(float &outBaselineRes, float &outMinRes) {
  if (!bsecReady) return false;

  // 1. Force BSEC execution until fresh sample updates sensorData
  newGasDataAvailable = false;
  uint32_t baselineTimeout = millis();
  while (!newGasDataAvailable && (millis() - baselineTimeout < 3500UL)) {
    bsec.run();
    vTaskDelay(pdMS_TO_TICKS(20));
  }

  // 2. Capture baseline snapshot AFTER fresh reading
  float baseHumidity = sensorData.currentHumidity;
  float baseGasRes   = sensorData.currentGasRes;
  outBaselineRes     = baseGasRes;

  sendBleMessage("{\"state\":\"READY_PLEASE_BLOW\"}");

  uint32_t startMs = millis();
  uint32_t lastPrint = 0;
  bool detected = false;

  newGasDataAvailable = false;

  // 3. 10-Second Wait Window for Blow Start
  while ((millis() - startMs) < BREATH_WAIT_TIMEOUT_MS) {
    bsec.run();

    float deltaHumidity = sensorData.currentHumidity - baseHumidity;
    float gasDropPct = 0.0f;
    
    if (baseGasRes > 0.0f && sensorData.currentGasRes > 0.0f) {
      gasDropPct = ((baseGasRes - sensorData.currentGasRes) / baseGasRes) * 100.0f;
    }

    // Stream status update every 1 second
    if (millis() - lastPrint >= 1000UL) {
      lastPrint = millis();
      String debugMsg = "{\"dH\":" + String(deltaHumidity, 1) + 
                        ",\"gDrop\":" + String(gasDropPct, 1) + "}";
      sendBleMessage(debugMsg);
    }

    // Trigger condition: Human breath moisture spike (+0.3% RH) or Gas resistance drop (+0.8%)
    if (deltaHumidity >= 0.3f || gasDropPct >= 0.8f) {
      detected = true;
      outMinRes = sensorData.currentGasRes;
      break;
    }

    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  if (!detected) {
    return false;
  }

  // 4. Blow detected! Transition UI to processing and capture VOC nadir
  sendBleMessage("{\"state\":\"TESTING_SENSING_BREATH\"}");

  uint32_t blowWindowStart = millis();
  newGasDataAvailable = false;

  while (millis() - blowWindowStart < BREATH_SENSING_WINDOW_MS) {
    bsec.run();
    if (newGasDataAvailable) {
      if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < outMinRes) {
        outMinRes = sensorData.currentGasRes; 
      }
      newGasDataAvailable = false;
    }
    vTaskDelay(pdMS_TO_TICKS(POLL_TICK_DELAY_MS));
  }

  return true;
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