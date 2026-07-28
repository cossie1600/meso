#include <Wire.h>
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <FS.h>         
#include <SD.h>          
#include <bsec2.h>
#include "bsec_iaq.h"

BLECharacteristic *pCharacteristic;
#define BUTTON_PIN 9     // ESP32-C6 BOOT button (GPIO 9)
// Standard Bluetooth SIG UUID for Environmental Sensing
#define SERVICE_UUID           "0000181a-0000-1000-8000-00805f9b34fb" 
#define CHARACTERISTIC_UUID    "00002a6e-0000-1000-8000-00805f9b34fb"

Bsec2 bsec;
bool isButtonPressed = false;
String log_prefix = "bme688_runtime_logs";
String BLE_Name = "Meso Nose";
// ==========================================================
// Global Shared Variables for BSEC2 Callback
// ==========================================================
volatile bool newGasDataAvailable = false;
volatile float latestGasResistance = 0.0f;
volatile float latestIaq = 0.0f;
volatile uint8_t iaqAccuracy = 0;

float latestBreathScore = 0.0;
unsigned long buttonPressStart = 0;
bool isCheckingBreath = false;

// --- Function Prototypes ---
void logMessage(const String& msg);
void checkBsecStatus(Bsec2& bsec);
void initBLE();

String getCurrentDateTime() {
  unsigned long allSeconds = millis() / 1000;
  int runSeconds = allSeconds % 60;
  int runMinutes = (allSeconds / 60) % 60;
  int runHours = (allSeconds / 3600);

  char buffer[16];
  sprintf(buffer, "%02d:%02d:%02d", runHours, runMinutes, runSeconds);
  return String(buffer);
}

void logMessage(const String &message) {
    const String log_message = getCurrentDateTime() + " " + message;
    Serial.println(log_message);
    
    String file_path = "/" + log_prefix + ".txt";

    File file = SD.open(file_path, FILE_APPEND);
    if (file) {
      file.println(log_message);
      file.close();
    } else {
      Serial.println("Error opening: " + file_path);
    }
}

void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  

  // Wait up to 3 seconds for Serial Monitor to open (Requires USB CDC Enabled)
  while (!Serial && millis() < 3000);
  logMessage("starting " + BLE_Name);

  Wire.begin(6, 7); 

  // 1. Initialize BSEC2
  if (!bsec.begin(BME68X_I2C_ADDR_HIGH, Wire)) {
    logMessage("Could not find a valid sensor, check wiring!");
    while (1);
  }
  checkBsecStatus(bsec); 

  // 2. Load the stock IAQ config (from bsec_iaq.c)
  if (!bsec.setConfig(bsec_config_iaq)) {
    logMessage("Failed to set BSEC IAQ configuration!");
  }
  checkBsecStatus(bsec);

  // 3. Subscribe to valid outputs supported by the IAQ config
  bsec_virtual_sensor_t sensorList[] = {
    BSEC_OUTPUT_RAW_GAS,
    BSEC_OUTPUT_IAQ,
    BSEC_OUTPUT_BREATH_VOC_EQUIVALENT,
    BSEC_OUTPUT_RAW_TEMPERATURE,
    BSEC_OUTPUT_RAW_HUMIDITY
  };
  bsec.updateSubscription(sensorList, 5, BSEC_SAMPLE_RATE_LP);
  bsec.attachCallback(newDataCallback);
  checkBsecStatus(bsec);

  // Initialize BLE on the ESP32-C6
  initBLE();

  runBreathTest();
  goToSleep();
}

void loop() {
  // Empty! Execution reboots through setup() on every button press wakeup.
}

// --- Helper Function for BLE Setup ---
void sendBleMessage(const char* message) {
  pCharacteristic->setValue(message); 
  pCharacteristic->notify();          
}
void initBLE() {
  BLEDevice::init(BLE_Name);
  
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ | 
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
  
  logMessage("BLE initialized and advertising as " + BLE_Name);
}

// Helper function to inspect and print BSEC status or warnings
void checkBsecStatus(Bsec2& bsec) {
    if (bsec.status < BSEC_OK) {
        logMessage("BSEC Error Code: " + String(bsec.status));
    } else if (bsec.status > BSEC_OK) {
        logMessage("BSEC Warning Code: " + String(bsec.status));
    }
}

void runBreathTest() {
  // ==========================================
  // STAGE 1: AMBIENT SAMPLING
  // ==========================================
  sendBleMessage("STATE:SAMPLING");

  float ambientSum = 0;
  int validSamples = 0;
  uint32_t stageStart = millis();

  // Collect 3 LP ambient samples (~9s)
  while (validSamples < 3 && (millis() - stageStart < 12000)) {
    if (bsec.run()) {
      if (newGasDataAvailable) {
        ambientSum += latestGasResistance;
        validSamples++;
        newGasDataAvailable = false;
      }
    }
    delay(10);
  }

  if (validSamples == 0) {
    sendBleMessage("ERROR:SAMPLING_TIMEOUT");
    goToSleep();
  }

  float r_ambient = ambientSum / validSamples;

  // ==========================================
  // STAGE 2: READY TO BLOW (Notify App!)
  // ==========================================
  sendBleMessage("STATE:READY");  // <-- App triggers prompt/sound here

  uint32_t readyStart = millis();
  bool userStartedBlowing = false;

  // Wait up to 10s for button hold
  while (millis() - readyStart < 10000) {
    bsec.run(); 

    if (digitalRead(BUTTON_PIN) == LOW) {
      delay(200); // Debounce
      if (digitalRead(BUTTON_PIN) == LOW) {
        userStartedBlowing = true;
        break; 
      }
    }
    delay(20);
  }

  if (!userStartedBlowing) {
    sendBleMessage("STATE:TIMEOUT");
    return;
  }

  // ==========================================
  // STAGE 3: BREATH MEASUREMENT
  // ==========================================
  sendBleMessage("STATE:TESTING");

  float r_breath_min = r_ambient; 
  uint32_t blowStart = millis();

  // Measure for 3s during blow
  while (millis() - blowStart < 3000) {
    if (bsec.run()) {
      if (newGasDataAvailable) {
        if (latestGasResistance < r_breath_min) {
          r_breath_min = latestGasResistance; 
        }
        newGasDataAvailable = false;
      }
    }
    delay(10);
  }

  // ==========================================
  // FINAL RESULT TRANSMISSION
  // ==========================================
  float deltaDrop = (1.0 - (r_breath_min / r_ambient)) * 100.0;

  char bleBuffer[64];
  snprintf(bleBuffer, sizeof(bleBuffer), "DROP:%.1f,AMB:%.0f,BREATH:%.0f", 
           deltaDrop, r_ambient, r_breath_min);

  sendBleMessage(bleBuffer);

  delay(1000); // Allow BLE packet to flush before sleep
}

void goToSleep() {
  esp_sleep_enable_ext1_wakeup(1ULL << BUTTON_PIN, ESP_EXT1_WAKEUP_ALL_LOW);
  esp_deep_sleep_start();
}

void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsec) {
  if (!outputs.nOutputs) return;

  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    const bsecData output = outputs.output[i];
    
    if (output.sensor_id == BSEC_OUTPUT_RAW_GAS) {
      latestGasResistance = output.signal;
      newGasDataAvailable = true;
    }
    else if (output.sensor_id == BSEC_OUTPUT_IAQ) {
      latestIaq = output.signal; // Capture IAQ score
      iaqAccuracy = output.accuracy; // 0 = Uncalibrated, 1-3 = Calibrated
    }
  }
}