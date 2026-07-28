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
const unsigned long pressdown_milisec = 2000;

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
    BSEC_OUTPUT_IAQ
  };
  bsec.updateSubscription(sensorList, 2, BSEC_SAMPLE_RATE_LP);
  checkBsecStatus(bsec);

  // Initialize BLE on the ESP32-C6
  initBLE();
}

void loop() {
  // 1. Let BSEC process background sensor & AI steps
  if (bsec.run()) {
    // Get the AI classification estimate (0.0 to 500.0 or class IDs)
    // Treat any spike >200.0 as bad breath.
    latestBreathScore = bsec.getData(BSEC_OUTPUT_IAQ).signal;
  }

  // 2. Check BOOT button state (Active LOW)
  if (digitalRead(BUTTON_PIN) == LOW){
    if (buttonPressStart == 0) {
      buttonPressStart = millis(); // Record when pressed started
    } else if (millis() - buttonPressStart >= pressdown_milisec && !isCheckingBreath) {
      // Button held for > 2 seconds
      isCheckingBreath = true;
      String scoreStr = String(latestBreathScore);
      logMessage("AI Breath Score: " + scoreStr);

      if (pCharacteristic != nullptr) {        
        pCharacteristic->setValue(scoreStr.c_str());
        pCharacteristic->notify(); 
        logMessage("BLE Notification Sent: " + scoreStr);
      }
    }    
  } else {
    buttonPressStart = 0; // Reset timer on release
    isCheckingBreath = false;
  }
}

// --- Helper Function for BLE Setup ---
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