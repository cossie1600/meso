#include <Arduino.h>
#include <esp_mac.h>
#include <vector>
#include <ArduinoJson.h>
#include <FS.h>
#include <LittleFS.h>
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
#define BMV080_ADDR 0x57 

// ==========================================
// THREAD-SAFE CONCURRENCY OBJECTS (MUTEXES)
// ==========================================
SemaphoreHandle_t i2cMutex = NULL; 
SemaphoreHandle_t fsMutex = NULL; 
static portMUX_TYPE ramSpinlock = portMUX_INITIALIZER_UNLOCKED; 

// ==========================================
// GLOBAL STATE & BUFFERING
// ==========================================
#define FILE_PATH "/pm_data.jsonl"
const unsigned long WRITE_INTERVAL = 45 * 60 * 1000; // 45 minutes
unsigned long lastWriteTime = 0;

struct pm_sample {
  unsigned long timestamp_ms;
  float pm1;
  float pm2_5;
  float pm10;
};

std::vector<pm_sample> memoryBuffer;

// BLE Configuration
BLEServer* pServer = nullptr;
BLECharacteristic* pDataCharacteristic = nullptr;
bool deviceConnected = false;
bool triggerSync = false; 

// Time parameters
const unsigned long ACTIVE_RUN_TIME  = 10000;  // 10 seconds active
const unsigned long IDLE_SLEEP_TIME  = 60000;  // 1 minute idle
const unsigned long SAMPLE_PACE      = 2000;   // Read every 2 seconds

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"

// ==========================================
// BLE CALLBACKS
// ==========================================
class MyServerCallbacks: public BLEServerCallbacks {
    // Core v2 connection signature
    void onConnect(BLEServer* pServer) {
      Serial.println("BLE: Mobile Device Connected! (v2 callback)");
      deviceConnected = true;
      triggerSync = true; 
    }

    // Core v3 connection signature (guarantees callback execution across compiler updates)
    void onConnect(BLEServer* pServer, esp_ble_gatts_cb_param_t *param) {
      Serial.println("BLE: Mobile Device Connected! (v3 callback)");
      deviceConnected = true;
      triggerSync = true; 
    }

    void onDisconnect(BLEServer* pServer) {
      Serial.println("BLE: Mobile Device Disconnected!");
      deviceConnected = false;
      // Restart advertising using the static, thread-safe class method
      BLEDevice::startAdvertising(); 
      Serial.println("BLE: Restarted Advertising...");
    }
};

String serializeSample(const pm_sample& sample) {
  StaticJsonDocument<128> doc; 
  doc["t"] = sample.timestamp_ms;
  doc["pm1"] = sample.pm1;
  doc["pm25"] = sample.pm2_5;
  doc["pm10"] = sample.pm10;
  
  String output;
  serializeJson(doc, output);
  return output;
}

// Write the memory buffer to LittleFS (Core 1)
void writeBufferToFilesystem() {
  Serial.println("FS: Attempting periodic RAM-to-Flash backup...");
  if (xSemaphoreTake(fsMutex, pdMS_TO_TICKS(5000)) != pdTRUE) {
    Serial.println("FS ERROR: Could not acquire Filesystem Mutex!");
    return;
  }

  File file = LittleFS.open(FILE_PATH, FILE_APPEND);
  if (!file) {
    xSemaphoreGive(fsMutex);
    Serial.println("FS ERROR: LittleFS open for append failed!");
    return;
  }

  std::vector<pm_sample> tempWriteBuffer;
  portENTER_CRITICAL(&ramSpinlock);
  if (!memoryBuffer.empty()) {
    tempWriteBuffer = memoryBuffer;
    memoryBuffer.clear();
  }
  portEXIT_CRITICAL(&ramSpinlock);

  int count = 0;
  for (const auto& sample : tempWriteBuffer) {
    String jsonLine = serializeSample(sample);
    file.println(jsonLine);
    count++;
  }
  
  file.close(); 
  xSemaphoreGive(fsMutex);
  Serial.printf("FS: Successfully backed up %d records to Flash.\n", count);
}

// Background task to transmit data (Core 0)
void bleSenderTask(void* parameter) {
  while (true) {
    if (triggerSync && deviceConnected) {
      triggerSync = false; 
      Serial.println("BLE Task: Sync triggered! Processing archives...");

      // 1. Send Filesystem Data First
      if (xSemaphoreTake(fsMutex, pdMS_TO_TICKS(5000)) == pdTRUE) {
        bool fileExists = LittleFS.exists(FILE_PATH);
        File file;
        if (fileExists) {
          file = LittleFS.open(FILE_PATH, FILE_READ);
          Serial.println("BLE Task: Scanning LittleFS for stored logs...");
        }
        xSemaphoreGive(fsMutex);

        if (fileExists && file) {
          int count = 0;
          while (deviceConnected) {
            String line = "";
            bool hasLine = false;

            if (xSemaphoreTake(fsMutex, pdMS_TO_TICKS(1000)) == pdTRUE) {
              if (file.available()) {
                line = file.readStringUntil('\n');
                line.trim();
                hasLine = true;
              }
              xSemaphoreGive(fsMutex);
            }

            if (!hasLine) break;

            if (line.length() > 0) {
              pDataCharacteristic->setValue(line.c_str());
              pDataCharacteristic->notify(); 
              count++;
              vTaskDelay(pdMS_TO_TICKS(15)); 
            }
          }
          
          if (xSemaphoreTake(fsMutex, pdMS_TO_TICKS(5000)) == pdTRUE) {
            file.close();
            if (deviceConnected) {
              LittleFS.remove(FILE_PATH); 
              Serial.printf("BLE Task: Dispatched %d Flash logs. Cleared storage.\n", count);
            }
            xSemaphoreGive(fsMutex);
          }
        }
      }

      // 2. Send Volatile RAM Data
      std::vector<pm_sample> tempBuffer;
      portENTER_CRITICAL(&ramSpinlock);
      if (!memoryBuffer.empty()) {
        tempBuffer = memoryBuffer;
        memoryBuffer.clear();      
      }
      portEXIT_CRITICAL(&ramSpinlock); 

      if (!tempBuffer.empty() && deviceConnected) {
        Serial.printf("BLE Task: Sending %d fresh RAM records...\n", tempBuffer.size());
        for (const auto& sample : tempBuffer) {
          if (!deviceConnected) break; 
          String line = serializeSample(sample);
          pDataCharacteristic->setValue(line.c_str());
          pDataCharacteristic->notify();
          vTaskDelay(pdMS_TO_TICKS(15)); 
        }
        Serial.println("BLE Task: Fresh RAM dispatch finished.");
      }
    }
    vTaskDelay(pdMS_TO_TICKS(100)); 
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("\n--- Starting Meso Pin... Boot Stabilizing ---");
  delay(1000); 

  i2cMutex = xSemaphoreCreateMutex();
  fsMutex = xSemaphoreCreateMutex();

  Serial.println("Setup: Probing Qwiic I2C Bus...");
  bool sensorFound = false;
  if (xSemaphoreTake(i2cMutex, portMAX_DELAY) == pdTRUE) {
    Wire.begin(); 
    sensorFound = bmv.begin(BMV080_ADDR, Wire);
    xSemaphoreGive(i2cMutex);
  }

  if (!sensorFound) {
    while (1) {
      Serial.println("ERROR: BMV080 sensor not detected over Qwiic!");
      delay(2000); 
    }
  }
  Serial.println("BMV080 Sensor Detected.");

  Serial.println("Setup: Initializing Filesystem...");
  if (xSemaphoreTake(fsMutex, portMAX_DELAY) == pdTRUE) {
    if (!LittleFS.begin(true)) {
      Serial.println("Setup ERROR: LittleFS Mount Failed!");
    } else {
      Serial.println("Setup: Filesystem mounted successfully.");
    }
    xSemaphoreGive(fsMutex);
  }

  Serial.println("Setup: Launching BLE Stack...");
  
  // Read unique chip MAC address to dynamically generate name
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char deviceName[20];
  sprintf(deviceName, "Meso Pin-%02X%02X", mac[4], mac[5]);
  
  BLEDevice::init(deviceName);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Confirmed characteristics: Read + Notify (No Indicate to prevent iOS state lock)
  pDataCharacteristic = pService->createCharacteristic(
                          CHARACTERISTIC_UUID,
                          BLECharacteristic::PROPERTY_READ   |
                          BLECharacteristic::PROPERTY_NOTIFY
                        );
  pDataCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  
  // BLEDevice::startAdvertising();
  // iOS-Compliant BLE Advertising setup
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  
  // Create advertisement data container
  BLEAdvertisementData advertisementData;
  BLEAdvertisementData scanResponseData;
  
  // Force the Service UUID into the primary advertisement packet so iOS validates it instantly
  advertisementData.setCompleteServices(BLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advertisementData);
  
  // Keep scan response active for device name transmission
  pAdvertising->setScanResponse(true);
  scanResponseData.setName(deviceName);
  pAdvertising->setScanResponseData(scanResponseData);
  
  // Suggest ideal connection timing intervals to iOS to stabilize initial handshakes
  pAdvertising->setMinPreferred(0x06); // 7.5ms minimum connection interval
  pAdvertising->setMaxPreferred(0x12); // 22.5ms maximum connection interval
  
  BLEDevice::startAdvertising();
  Serial.printf("Setup: BLE Service Started. Advertising as: %s\n", deviceName);

  Serial.println("Setup: Pinning BLE Sender Task to Core 0...");
  xTaskCreatePinnedToCore(
    bleSenderTask,    
    "BLESenderTask",  
    8192,             
    NULL,             
    1,                
    NULL,             
    0                 
  );
  Serial.println("Setup complete. Entering main loop...");

  lastWriteTime = millis();
}

// PHASE 1: Wake up the physical hardware
void wakeAndStabilizeSensor() {
  Serial.println("\nLoop: [Phase 1/4] Waking sensor engine...");
  bool success = false;

  if (xSemaphoreTake(i2cMutex, pdMS_TO_TICKS(5000)) == pdTRUE) {
    success = bmv.begin(BMV080_ADDR, Wire);
    if (success) {
      bmv.init(); 
      bmv.setMode(SF_BMV080_MODE_CONTINUOUS);
    }
    xSemaphoreGive(i2cMutex);
  }

  if (!success) {
    while (1) {
      Serial.println("ERROR: Lost communication with BMV080 mid-run!");
      vTaskDelay(pdMS_TO_TICKS(2000)); 
    }
  }
  
  Serial.println("Loop: Sensor running. Waiting 1s for stabilization...");
  vTaskDelay(pdMS_TO_TICKS(1000)); 
}

// PHASE 2: Gather raw data points
void gatherSensorData(float &pm1Sum, float &pm25Sum, float &pm10Sum, int &totalSamples) {
  Serial.println("Loop: [Phase 2/4] Starting 10-second sampling window...");
  unsigned long startSampleTime = millis();

  while (millis() - startSampleTime < ACTIVE_RUN_TIME) {
    float currentPM1 = 0, currentPM25 = 0, currentPM10 = 0;
    bool validData = false;

    if (xSemaphoreTake(i2cMutex, pdMS_TO_TICKS(1000)) == pdTRUE) {
      if (bmv.readSensor() && !bmv.isObstructed()) {
        currentPM1  = bmv.PM1(); 
        currentPM25 = bmv.PM25();
        currentPM10 = bmv.PM10(); 
        validData = true;
      } 
      xSemaphoreGive(i2cMutex); 
    }

    if (validData) {
      pm1Sum  += currentPM1;
      pm25Sum += currentPM25;
      pm10Sum += currentPM10;
      totalSamples++;
      Serial.printf("   -> Snapshot Read #%d: PM1=%.1f, PM2.5=%.1f, PM10=%.1f\n", totalSamples, currentPM1, currentPM25, currentPM10);
    } else {
      Serial.println("   -> Read skipped (sensor reading not ready or obstructed)");
    }

    delay(SAMPLE_PACE); 
  }
}

// PHASE 3: Compute mathematical mean
void calculateAndBufferMean(float pm1Sum, float pm25Sum, float pm10Sum, int totalSamples) {
  Serial.println("Loop: [Phase 3/4] Processing collected window averages...");
  if (totalSamples > 0) {
    pm_sample newSample;
    newSample.timestamp_ms = millis();
    newSample.pm1 = pm1Sum / totalSamples;
    newSample.pm2_5 = pm25Sum / totalSamples;
    newSample.pm10 = pm10Sum / totalSamples;

    portENTER_CRITICAL(&ramSpinlock);
    memoryBuffer.push_back(newSample);
    portEXIT_CRITICAL(&ramSpinlock);
    
    Serial.printf("AVERAGE: PM1=%.2f, PM2.5=%.2f, PM10=%.2f (Buffered in RAM)\n", newSample.pm1, newSample.pm2_5, newSample.pm10);
  } else {
    Serial.println("WARNING: Window finished with 0 valid samples. Skipping buffering.");
  }
}

// PHASE 4: Put hardware to sleep
void powerDownSensor() {
  Serial.println("Loop: [Phase 4/4] Powering down sensor (Preserving laser/battery)...");
  if (xSemaphoreTake(i2cMutex, pdMS_TO_TICKS(5000)) == pdTRUE) {
    bmv.close(); 
    xSemaphoreGive(i2cMutex);
  }
  Serial.flush();
}

// PHASE 5: Handle the periodic Filesystem write
void handlePeriodicStorageWrite() {
  if (millis() - lastWriteTime >= WRITE_INTERVAL) {
    lastWriteTime = millis();
    writeBufferToFilesystem(); 
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

  Serial.println("Loop: Cycle complete. Sleeping for 1 minute...");
  vTaskDelay(pdMS_TO_TICKS(IDLE_SLEEP_TIME)); 
}