#include <Wire.h>
#include <SPIFFS.h>
#include <NimBLEDevice.h>
#include "bsec2.h"
#include "bsec_iaq.h"

// Hardware I2C Pins for ESP32-C6
#define I2C_SDA 6
#define I2C_SCL 7

// BLE Service & Characteristic UUIDs
#define SERVICE_UUID        "4FA215F0-0001-4B0E-B682-1A4C70F3A601"
#define CHARACTERISTIC_UUID "4FA215F0-0002-4B0E-B682-1A4C70F3A601"

// Device Name
String Device_Name = "Meso Nose";

// System State Machine
enum SystemState {
  STATE_IDLE,
  STATE_SAMPLING_BASELINE,
  STATE_WAITING_FOR_BREATH,
  STATE_RECORDING_BREATH
};

SystemState currentState = STATE_IDLE;
uint32_t stateTimer = 0;
float ambientBaseline = 0;
float minBreathResistance = 0;
int validBaselineSamples = 0;
float baselineSum = 0;

// Global Objects
Bsec2 bsec;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;

// System Flags & Volatiles
volatile bool startTestTriggered = false;
bool deviceConnected = false;
bool bsecReady = false;

// -------------------------------------------------------------------
// Helper / Logging Functions
// -------------------------------------------------------------------

void logMessage(String msg) {
  Serial.println(msg);
  Serial.flush();

  if (deviceConnected && pCharacteristic) {
    String bleLog = "[LOG]: " + msg;
    pCharacteristic->setValue((uint8_t*)bleLog.c_str(), bleLog.length());
    pCharacteristic->notify();
  }
}

void sendBleMessage(String msg) {
  logMessage("[BLE OUT]: " + msg);
  if (deviceConnected && pCharacteristic) {
    pCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
    pCharacteristic->notify();
  }
}

// -------------------------------------------------------------------
// BSEC Callback (Executed whenever BSEC has a fresh output frame)
// -------------------------------------------------------------------
void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsecObj) {
  float currentGas = 0.0;

  // Extract raw gas signal from BSEC outputs
  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    if (outputs.output[i].sensor_id == BSEC_OUTPUT_RAW_GAS) {
      currentGas = outputs.output[i].signal;
      break;
    }
  }

  // Fallback to raw struct if output array wasn't populated
  if (currentGas <= 0 && data.gas_resistance > 0) {
    currentGas = data.gas_resistance;
  }

  if (currentGas <= 0) return; // Skip if no valid gas reading this frame

  logMessage("Gas Reading: " + String(currentGas));

  // Process State Machine Transitions on Valid Sensor Data
  if (currentState == STATE_SAMPLING_BASELINE) {
    baselineSum += currentGas;
    validBaselineSamples++;
    logMessage("Sample " + String(validBaselineSamples) + " R_gas: " + String(currentGas));

    if (validBaselineSamples >= 2) {
      ambientBaseline = baselineSum / validBaselineSamples;
      logMessage("Baseline Established: " + String(ambientBaseline) + " Ohms");
      sendBleMessage("STATE:READY");
      logMessage("Waiting for breath input (10 sec window)...");
      currentState = STATE_WAITING_FOR_BREATH;
      stateTimer = millis();
    }
  } 
  else if (currentState == STATE_WAITING_FOR_BREATH) {
    if (currentGas < (ambientBaseline * 0.90)) { // 10% gas resistance drop threshold
      minBreathResistance = currentGas;
      sendBleMessage("STATE:TESTING");
      logMessage("Breath detected! Recording for 7 seconds...");
      currentState = STATE_RECORDING_BREATH;
      stateTimer = millis();
    }
  } 
  else if (currentState == STATE_RECORDING_BREATH) {
    if (currentGas < minBreathResistance) {
      minBreathResistance = currentGas;
    }
  }
}

// -------------------------------------------------------------------
// Safe BLE Callbacks (NimBLE v2.x Compatible)
// -------------------------------------------------------------------
class ServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) {
      deviceConnected = true;
      logMessage("iOS Connected!");
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) {
      deviceConnected = false;
      logMessage("iOS Disconnected!");
      NimBLEDevice::startAdvertising();
    }
};

class CharacteristicCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo& connInfo) {
      NimBLEAttValue val = pCharacteristic->getValue();
      if (val.length() > 0) {
        const uint8_t* data = val.data();
        if (data[0] == '1' || data[0] == 'S' || data[0] == 's' || data[0] == 0x01) {
          startTestTriggered = true;
        }
      }
    }
};

// -------------------------------------------------------------------
// BLE Setup
// -------------------------------------------------------------------
void initBLE() {
  NimBLEDevice::init(Device_Name.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_N3); 

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      NIMBLE_PROPERTY::READ |
                      NIMBLE_PROPERTY::WRITE |
                      NIMBLE_PROPERTY::WRITE_NR |
                      NIMBLE_PROPERTY::NOTIFY
                    );

  pCharacteristic->setCallbacks(new CharacteristicCallbacks());

  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->enableScanResponse(true); 
  pAdvertising->start();

  logMessage("BLE initialized & advertising as " + Device_Name);
}

// -------------------------------------------------------------------
// Setup & Loop
// -------------------------------------------------------------------
void setup() {
  Serial.begin(115200);

  uint32_t usbStart = millis();
  while (!Serial && (millis() - usbStart < 3000)) {
    delay(10);
  }
  delay(500);

  logMessage("\n\n====================================");
  logMessage(">>> SYSTEM BOOT: MESO NOSE ESP32-C6 <<<");
  logMessage("====================================");

  // Step 1: Initialize BLE Stack
  initBLE();
  delay(200);
  
  // Step 2: Reset and Initialize I2C Bus cleanly
  Wire.end(); 
  delay(50);

  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);
  delay(100);

  // Hardware I2C Ping Test
  uint8_t sensorAddr = BME68X_I2C_ADDR_HIGH; // 0x77

  Wire.beginTransmission(sensorAddr);
  if (Wire.endTransmission() != 0) {
    sensorAddr = BME68X_I2C_ADDR_LOW; // 0x76
    Wire.beginTransmission(sensorAddr);
    if (Wire.endTransmission() != 0) {
      logMessage("ERROR: No I2C response from BME688 on 0x76 or 0x77!");
      logMessage("Check physical connections (SDA=GPIO6, SCL=GPIO7) & Power!");
      return; 
    }
  }

  logMessage("BME688 detected hardware response on address 0x" + String(sensorAddr, HEX));

  // Step 3: Initialize BSEC2 cleanly with discovered address
  if (!bsec.begin(sensorAddr, Wire)) {
    logMessage("ERROR: BSEC2 software initialization failed!");
    return;
  }
  logMessage("BSEC2 initialized successfully!");

  if (!bsec.setConfig(bsec_config_iaq)) {
    logMessage("ERROR: Failed to load BSEC configuration!");
    return;
  }

  bsec.attachCallback(newDataCallback);

  // Full BSEC Subscription Set (Ensures IAQ and Humidity Compensation run)
  bsecSensor sensorList[] = {
    BSEC_OUTPUT_RAW_GAS,
    BSEC_OUTPUT_RAW_TEMPERATURE,
    BSEC_OUTPUT_RAW_HUMIDITY,
    BSEC_OUTPUT_STATIC_IAQ,
    BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
    BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY
  };

  uint8_t numSensors = sizeof(sensorList) / sizeof(bsecSensor);

  if (!bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP)) {
    logMessage("ERROR: BSEC subscription failed!");
    return;
  }

  bsecReady = true;
  logMessage("BSEC Ready & Subscribed. System Idle!");
}

void loop() {
  // 1. Keep BSEC internal state machine running continuously
  if (bsecReady) {
    bsec.run();
  }

  // 2. Process BLE Triggers
  if (startTestTriggered) {
    startTestTriggered = false;
    logMessage("Trigger received! Starting Breath Test...");
    sendBleMessage("STATE:SAMPLING");
    
    // Reset sampling variables for fresh baseline run
    currentState = STATE_SAMPLING_BASELINE;
    validBaselineSamples = 0;
    baselineSum = 0;
    stateTimer = millis();
  }

  // 3. Non-Blocking State Machine Timeouts
  if (currentState == STATE_SAMPLING_BASELINE) {
    if (millis() - stateTimer > 25000) { // 25s baseline timeout
      sendBleMessage("ERROR:SAMPLING_TIMEOUT");
      logMessage("Test complete. Returning to standby...");
      currentState = STATE_IDLE;
    }
  } 
  else if (currentState == STATE_WAITING_FOR_BREATH) {
    if (millis() - stateTimer > 10000) { // 10s window to receive breath
      sendBleMessage("STATE:TIMEOUT");
      logMessage("No breath detected within 10 seconds.");
      currentState = STATE_IDLE;
    }
  } 
  else if (currentState == STATE_RECORDING_BREATH) {
    if (millis() - stateTimer > 7000) { // 7s active recording window
      float dropPercent = ((ambientBaseline - minBreathResistance) / ambientBaseline) * 100.0;
      String resultString = "DROP:" + String(dropPercent, 1) +
                            ",AMB:" + String((long)ambientBaseline) +
                            ",BREATH:" + String((long)minBreathResistance);
      sendBleMessage(resultString);
      logMessage("Test complete. Returning to standby...");
      currentState = STATE_IDLE;
    }
  }

  delay(5); // Small delay to yield to FreeRTOS watchdog
}