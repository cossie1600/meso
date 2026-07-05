#include <Wire.h>
#include <SparkFun_BMV080_Arduino_Library.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <FS.h>
#include <SD.h>
#include <SPI.h>

SparkFunBMV080 bmv;

// Global Hardcoded UUIDs for Bluetooth matching
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

// SAFE HARDCODED DEFAULTS (Used if SD card config fails to load)
unsigned long runDuration = 60000;          // 1 minute active run (ms)
unsigned long idleDuration = 120000;        // 2 minutes software idle (ms)
unsigned long readInterval = 3000;          // 3 second polling interval (ms)

unsigned long startTime = 0;
bool isIdling = false;                      // State machine tracker

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) { deviceConnected = true; };
    void onDisconnect(BLEServer* pServer) { 
      deviceConnected = false; 
      pServer->getAdvertising()->start(); // Force restart advertising!
    }
};

// Unified Logging Engine: Outputs to screen and records directly to SD Card
void logMessage(const String &message) {
    Serial.println(message);
    
    File file = SD.open("/serial_output_log.txt", FILE_APPEND);
    if (file) {
        file.println(message);
        file.close();
    }
}

// Simple Parser to extract key-value configurations from the SD card text file
void loadConfiguration() {
    File configFile = SD.open("/config.txt");
    if (!configFile) {
        logMessage("Config file missing or unreadable. Deploying safety defaults.");
        return;
    }

    logMessage("Parsing config.txt variables...");
    while (configFile.available()) {
        String line = configFile.readStringUntil('\n');
        line.trim();
        if (line.length() == 0 || line.startsWith("#")) continue; // Skip empty lines/comments

        int separatorIdx = line.indexOf('=');
        if (separatorIdx != -1) {
            String key = line.substring(0, separatorIdx);
            String val = line.substring(separatorIdx + 1);
            key.trim();
            val.trim();

            if (key == "RUN_DURATION") {
                runDuration = val.toInt();
            } else if (key == "IDLE_DURATION") {
                idleDuration = val.toInt();
            } else if (key == "READ_INTERVAL") {
                readInterval = val.toInt();
            }
        }
    }
    configFile.close();
    
    // Print out the loaded specs to confirm assignment accuracy
    logMessage("Configuration Loaded Dynamic States:");
    logMessage(" -> Active Window: " + String(runDuration) + " ms");
    logMessage(" -> Idle Duration: " + String(idleDuration) + " ms");
    logMessage(" -> Sample Pace: " + String(readInterval) + " ms");
}

void setup() {
  Serial.begin(115200);
  Wire.begin();
  
  // Initialize SD Card Module (CS Pin 5)
  if(!SD.begin(5)){
    Serial.println("SD Card Module Failure! Locking onto core safety defaults.");
  } else {
    logMessage("\n--- SYSTEM BOOT VECTOR INITIALIZED ---");
    logMessage("Storage framework mounted successfully.");
    loadConfiguration(); 
  }

  // Wake and start the BMV080 Laser Scanner engine
  if (bmv.begin() == false) {
    logMessage("CRITICAL: BMV080 not detected on I2C bus! System freezing.");
    while(1);
  }
  bmv.init();
  bmv.setMode(SF_BMV080_MODE_CONTINUOUS);
  logMessage("BMV080 initialized into Continuous Mode.");

  // Build the Bluetooth Stack
  BLEDevice::init("BMV080 Air Tracker");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
                    );
                    
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("0"); 
  pService->start();
  pServer->getAdvertising()->start();
  
  logMessage("BLE RF Stack online. Continuous advertising active.");
  startTime = millis(); 
}

void loop() {
  unsigned long currentMillis = millis();

  // STATE 1: If active, transition to idle if the run duration window has elapsed
  if (!isIdling && (currentMillis - startTime >= runDuration)) {
    logMessage("1 minute active window reached. Pausing sensor stream...");
    logMessage("--- SENSOR STREAM IDLING (BLUETOOTH KEEP-ALIVE ACTIVE) ---");
    
    isIdling = true;
    startTime = currentMillis; // Reset state timer bound
  }

  // STATE 2: If idling, switch back to active once the idle duration has finished
  if (isIdling && (currentMillis - startTime >= idleDuration)) {
    logMessage("2 minutes idle finished. Resuming active sensor tracking...");
    
    isIdling = false;
    startTime = currentMillis; // Reset state timer bound
  }

  // ACTIVE SAMPLING TRACK: Only parse data if the state machine is active
  if (!isIdling) {
    if (bmv.readSensor()) {
      if (!bmv.isObstructed()) {
        int intPM25 = (int)bmv.PM25();
        
        char txBuffer[8];
        itoa(intPM25, txBuffer, 10); 

        pCharacteristic->setValue(txBuffer);
        pCharacteristic->notify();

        logMessage("Internal Whole PM2.5: " + String(txBuffer));
        
      } else {
        logMessage("System Status Alert: Particle intake channel obstructed.");
      }
    } else {
      logMessage("I2C state idling... awaiting data slot update window.");
    }
  }

  // This delay sets the polling cadence during active mode,
  // and keeps the CPU free during idle mode to prioritize background BLE pings.
  delay(readInterval); 
}