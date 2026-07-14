#include <Arduino.h>
#include <vector>
#include <ArduinoJson.h> // Library for JSON serialization
#include <FS.h>
#include <SPIFFS.h>      // Or LittleFS
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h> 
#include <SparkFun_BMV080_Arduino_Library.h> 

// ==========================================
// PHYSICAL HARDWARE INSTANTIATION
// ==========================================
SparkFunBMV080 bmv; 
#define BMV080_ADDR 0x57 // Default SparkFun BMV080 I2C Address

// File storage configurations
#define FILE_PATH "/pm_data.jsonl"
const unsigned long WRITE_INTERVAL = 45 * 60 * 1000; //45 minutes (45 mins * 60 secs * 1000 ms)
unsigned long lastWriteTime = 0;

// Struct to represent a PM sample
struct pm_sample {
  unsigned long timestamp_ms;
  float pm1;
  float pm2_5;
  float pm10;
};

// Thread-safe Memory Buffer
std::vector<pm_sample> memoryBuffer;

// BLE Configuration
BLEServer* pServer = nullptr;
BLECharacteristic* pDataCharacteristic = nullptr;
bool deviceConnected = false;
bool triggerSync = false; // Flag to tell FreeRTOS task to start background transmission

// Time parameters mapped out for your outdoor walking sessions
const unsigned long ACTIVE_RUN_TIME  = 10000;  // Wake and read for 10 seconds (ms)
const unsigned long IDLE_SLEEP_TIME  = 60000;  // Power down and wait 1 minute (ms)
const unsigned long SAMPLE_PACE      = 2000;   // Snapshot interval during active mode (2 seconds)

// Setup UUIDs
#define SERVICE_UUID        "4fa8c11a-9a37-4d1a-994c-850d9841cae5"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Spinlock initialization macro for ESP32
static portMUX_TYPE myMutex = portMUX_INITIALIZER_UNLOCKED;

// BLE Server Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      triggerSync = true; // Set flag to trigger non-blocking data send in background
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      pServer->startAdvertising(); // Restart advertising
    }
};

// Helper: Serializes a pm_sample into JSON string
String serializeSample(const pm_sample& sample) {
  StaticJsonDocument<128> doc; // Keep it lightweight
  doc["t"] = sample.timestamp_ms;
  doc["pm1"] = sample.pm1;
  doc["pm25"] = sample.pm2_5;
  doc["pm10"] = sample.pm10;
  
  String output;
  serializeJson(doc, output);
  return output;
}

// Write the memory buffer to SPIFFS
void writeBufferToSPIFFS() {
  portENTER_CRITICAL(&myMutex);
  if (memoryBuffer.empty()) {
    portEXIT_CRITICAL(&myMutex);
    return;
  }
  
  File file = SPIFFS.open(FILE_PATH, FILE_APPEND);
  if (!file) {
    portEXIT_CRITICAL(&myMutex);
    return;
  }

  // Serialize each memory buffer sample to JSON Lines (one JSON per line)
  for (const auto& sample : memoryBuffer) {
    String jsonLine = serializeSample(sample);
    file.println(jsonLine);
  }
  
  file.close();
  memoryBuffer.clear(); // Empty the RAM buffer
  portEXIT_CRITICAL(&myMutex);
}

// Background task to transmit data without blocking loop()
void bleSenderTask(void* parameter) {
  while (true) {
    if (triggerSync && deviceConnected) {
      triggerSync = false; // Reset trigger flag

      // 1. Send all data residing in SPIFFS first
      if (SPIFFS.exists(FILE_PATH)) {
        File file = SPIFFS.open(FILE_PATH, FILE_READ);
        if (file) {
          while (file.available() && deviceConnected) {
            String line = file.readStringUntil('\n');
            line.trim();
            if (line.length() > 0) {
              pDataCharacteristic->setValue(line.c_str());
              pDataCharacteristic->notify(); // Send to connected phone
              vTaskDelay(pdMS_TO_TICKS(15)); // Safe: we are outside critical section
            }
          }
          file.close();
          
          // Only delete file if we successfully completed the stream without disconnecting
          if (deviceConnected) {
            SPIFFS.remove(FILE_PATH); 
          }
        }
      }

      // 2. Send current data remaining in RAM (Safely avoiding lockup)
      std::vector<pm_sample> tempBuffer;

      portENTER_CRITICAL(&myMutex);
      if (!memoryBuffer.empty()) {
        tempBuffer = memoryBuffer; // Quickly clone vector
        memoryBuffer.clear();      // Clear volatile storage immediately
      }
      portEXIT_CRITICAL(&myMutex); // Free lock immediately

      // Now we can safely iterate and send data with task delays!
      if (!tempBuffer.empty() && deviceConnected) {
        for (const auto& sample : tempBuffer) {
          if (!deviceConnected) break; // Quit if phone disconnects mid-stream
          String line = serializeSample(sample);
          pDataCharacteristic->setValue(line.c_str());
          pDataCharacteristic->notify();
          vTaskDelay(pdMS_TO_TICKS(15)); // Perfectly safe here
        }
      }
    }
    vTaskDelay(pdMS_TO_TICKS(100)); // Yield to rest of system
  }
}

void setup() {
  Serial.begin(115200);

  // Initialize Wire (I2C) and the BMV080 sensor
  Wire.begin();
  if (bmv.begin(BMV080_ADDR, Wire) == false) {
    Serial.println("BMV080 sensor not detected! Freezing setup execution...");
    while (1); // Halt if hardware is missing/unwired
  }

  // Initialize SPIFFS
  if (!SPIFFS.begin(true)) {
    Serial.println("SPIFFS Mount Failed");
    return;
  }

  // Initialize BLE
  BLEDevice::init("MesoSensorDashboard");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pDataCharacteristic = pService->createCharacteristic(
                          CHARACTERISTIC_UUID,
                          BLECharacteristic::PROPERTY_READ   |
                          BLECharacteristic::PROPERTY_NOTIFY |
                          BLECharacteristic::PROPERTY_INDICATE
                        );
  pDataCharacteristic->addDescriptor(new BLE2902());
  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pServer->startAdvertising();

  // Create FreeRTOS Background Task to handle BLE transmissions on Core 0
  xTaskCreatePinnedToCore(
    bleSenderTask,    
    "BLESenderTask",  
    8192,             
    NULL,             
    1,                
    NULL,             
    0                 
  );

  lastWriteTime = millis();
}

// ==========================================
// SENSOR PIPELINE HELPER METHODS
// ==========================================

// PHASE 1: Wake up the physical hardware and allow registers to stabilize
void wakeAndStabilizeSensor() {
  bmv.init(); 
  bmv.setMode(SF_BMV080_MODE_CONTINUOUS);
  delay(1000); 
}

// PHASE 2: High-frequency polling loop to collect raw data points
void gatherSensorData(float &pm1Sum, float &pm25Sum, float &pm10Sum, int &totalSamples) {
  unsigned long startSampleTime = millis();

  while (millis() - startSampleTime < ACTIVE_RUN_TIME) {
    if (bmv.readSensor() && !bmv.isObstructed()) {
      pm1Sum  += bmv.PM1(); 
      pm25Sum += bmv.PM25();
      pm10Sum += bmv.PM10(); 
      totalSamples++;
    } 
    delay(SAMPLE_PACE); 
  }
}

// PHASE 3: Compute mathematical mean and save structure to volatile memory
void calculateAndBufferMean(float pm1Sum, float pm25Sum, float pm10Sum, int totalSamples) {
  if (totalSamples > 0) {
    float avgPM1  = pm1Sum / totalSamples;
    float avgPM25 = pm25Sum / totalSamples;
    float avgPM10 = pm10Sum / totalSamples;

    pm_sample newSample;
    newSample.timestamp_ms = millis();
    newSample.pm1 = avgPM1;
    newSample.pm2_5 = avgPM25;
    newSample.pm10 = avgPM10;

    portENTER_CRITICAL(&myMutex);
    memoryBuffer.push_back(newSample);
    portEXIT_CRITICAL(&myMutex);
  }
}

// PHASE 4: Put hardware to sleep to preserve laser life & battery
void powerDownSensor() {
  bmv.close(); 
  Serial.flush();
}

// PHASE 5: Handle the periodic SPIFFS write
void handlePeriodicStorageWrite() {
  if (millis() - lastWriteTime >= WRITE_INTERVAL) {
    lastWriteTime = millis();
    writeBufferToSPIFFS(); 
  }
}

// =========================================================================
// MAIN RUN LOOP (Core 1 execution)
// =========================================================================

void loop() {
  wakeAndStabilizeSensor();

  float pm1Sum = 0, pm25Sum = 0, pm10Sum = 0;
  int totalSamples = 0;
  gatherSensorData(pm1Sum, pm25Sum, pm10Sum, totalSamples);

  calculateAndBufferMean(pm1Sum, pm25Sum, pm10Sum, totalSamples);

  powerDownSensor();

  handlePeriodicStorageWrite();

  vTaskDelay(pdMS_TO_TICKS(IDLE_SLEEP_TIME)); 
}