#include <Wire.h>
#include <SparkFun_BMV080_Arduino_Library.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

SparkFunBMV080 bmv;

#define SERVICE_UUID           "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a9"

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

// Time parameters mapped out for your outdoor walking sessions
const unsigned long ACTIVE_RUN_TIME  = 10000;  // Wake and read for 10 seconds (ms)
const unsigned long IDLE_SLEEP_TIME  = 15000;  // Power down and wait 15 seconds (ms)
const unsigned long SAMPLE_PACE      = 2000;   // Snapshot interval during active mode (2 seconds)

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) { 
    deviceConnected = true; 
  }
  void onDisconnect(BLEServer* pServer) { 
    deviceConnected = false; 
    pServer->getAdvertising()->start(); 
  }
};

void setup() {
  Serial.begin(115200);
  Wire.begin(); // Your Qwiic bus boots up immediately here

  if (bmv.begin() == false) {
    Serial.println("CRITICAL: BMV080 missing on Qwiic bus.");
    while(1);
  }
  
  // Explicitly close the laser initially to guarantee a clean start state
  bmv.close(); 

  // Initialize BLE Stack
  BLEDevice::init("Qwiic Meso-Node");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->getAdvertising()->start();

  Serial.println("Qwiic Continuous-Loop Firmware Initialized.");
}

void loop() {
  // ==========================================
  // PHASE 1: WAKE UP & STABILIZE SENSOR
  // ==========================================
  Serial.println("Waking up sensor engine...");
  bmv.init(); 
  bmv.setMode(SF_BMV080_MODE_CONTINUOUS);
  
  // Give the internal fanless laser a 1-second breather 
  // to spin up its registers before we begin taking data.
  delay(1000); 

  unsigned long startSampleTime = millis();
  long pm1Sum = 0, pm25Sum = 0, pm10Sum = 0;
  int totalSamplesTaken = 0;

  // Gather fast snapshot readings for the designated active window duration
  while (millis() - startSampleTime < ACTIVE_RUN_TIME) {
    if (bmv.readSensor() && !bmv.isObstructed()) {
      pm1Sum  += (int)bmv.PM1(); 
      pm25Sum += (int)bmv.PM25();
      pm10Sum += (int)bmv.PM10(); 
      totalSamplesTaken++;
    }
    // High-frequency polling step inside the active window
    delay(SAMPLE_PACE); 
  }

  // ==========================================
  // PHASE 2: CALCULATE, AGGREGATE, & BLE PUSH
  // ==========================================
  if (totalSamplesTaken > 0) {
    int avgPM1  = pm1Sum / totalSamplesTaken;
    int avgPM25 = pm25Sum / totalSamplesTaken;
    int avgPM10 = pm10Sum / totalSamplesTaken;

    String dataPacket = String(avgPM1) + "," + String(avgPM25) + "," + String(avgPM10);
    Serial.println("Aggregated Walking Packet: " + dataPacket);

    // Push straight to your iPhone app if connected
    if (deviceConnected) {
      pCharacteristic->setValue(dataPacket.c_str());
      pCharacteristic->notify();
      Serial.println("Packet successfully dispatched over BLE.");
    } else {
      Serial.println("No active app connection found. Skipping BLE transmission.");
    }
  } else {
    Serial.println("Warning: Active window timed out without capturing valid data.");
  }

  // ==========================================
  // PHASE 3: HARDWARE POWER DOWN (THRIFT MODE)
  // ==========================================
  Serial.println("Closing laser diode to preserve battery...");
  bmv.close(); // Shut down the internal laser entirely 

  Serial.println("Entering background idle step...");
  Serial.flush();

  // Use FreeRTOS delay to yield CPU cycles cleanly during the idle state
  vTaskDelay(pdMS_TO_TICKS(IDLE_SLEEP_TIME)); 
}