#include <Arduino.h>
#include <vector>
#include <ArduinoJson.h> // Library for JSON serialization
#include <FS.h>
#include <SPIFFS.h>      // Or LittleFS
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// File storage configurations
#define FILE_PATH "/pm_data.jsonl"
const unsigned long WRITE_INTERVAL = 15 * 60 * 1000; // 15 minutes in milliseconds
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
    Serial.println("Failed to open file for appending");
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
  
  Serial.println("Memory buffer flushed to SPIFFS successfully.");
}

// Background task to transmit data without blocking loop()
void bleSenderTask(void* parameter) {
  while (true) {
    if (triggerSync && deviceConnected) {
      triggerSync = false; // Reset trigger flag
      Serial.println("Starting non-blocking BLE data sync...");

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
              vTaskDelay(pdMS_TO_TICKS(15)); // Short delay to prevent congestion
            }
          }
          file.close();
          SPIFFS.remove(FILE_PATH); // Wipe SPIFFS data once successfully sent
        }
      }

      // 2. Send current data remaining in RAM
      portENTER_CRITICAL(&myMutex);
      if (!memoryBuffer.empty() && deviceConnected) {
        for (const auto& sample : memoryBuffer) {
          String line = serializeSample(sample);
          pDataCharacteristic->setValue(line.c_str());
          pDataCharacteristic->notify();
          vTaskDelay(pdMS_TO_TICKS(15));
        }
        memoryBuffer.clear(); // Wipe active RAM once sent
      }
      portENTER_CRITICAL(&myMutex);

      Serial.println("BLE data sync completed. Memory & Storage Cleared.");
    }
    vTaskDelay(pdMS_TO_TICKS(100)); // Yield to rest of system
  }
}

void setup() {
  Serial.begin(115200);

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

  // Create FreeRTOS Background Task to handle BLE transmissions
  // Task is assigned to Core 0 to leave loop() running unobstructed on Core 1
  xTaskCreatePinnedToCore(
    bleSenderTask,    // Function name
    "BLESenderTask",  // Task name
    8192,             // Stack size (bytes)
    NULL,             // Task inputs
    1,                // Low priority to not block system operations
    NULL,             // Task handle
    0                 // Core 0
  );

  lastWriteTime = millis();
}

// Simulated function to show where mean values are acquired
void addNewPMSample(float mean_pm1, float mean_pm2_5, float mean_pm10) {
  pm_sample newSample;
  newSample.timestamp_ms = millis();
  newSample.pm1 = mean_pm1;
  newSample.pm2_5 = mean_pm2_5;
  newSample.pm10 = mean_pm10;

  portENTER_CRITICAL(&myMutex);
  memoryBuffer.push_back(newSample);
  portEXIT_CRITICAL(&myMutex);
}

void loop() {
  // Your sensor read loop remains completely uninterrupted!
  // Example mock mean generation logic:
  static unsigned long lastReading = 0;
  if (millis() - lastReading > 5000) { // Take reading every 5 seconds
    lastReading = millis();
    
    float mock_pm1 = random(5, 15);
    float mock_pm2_5 = random(12, 35);
    float mock_pm10 = random(20, 50);

    addNewPMSample(mock_pm1, mock_pm2_5, mock_pm10);
    Serial.println("Sensor mean calculated and sample added to buffer.");
  }

  // 15-minute write interval checker
  if (millis() - lastWriteTime >= WRITE_INTERVAL) {
    lastWriteTime = millis();
    writeBufferToSPIFFS();
  }
}