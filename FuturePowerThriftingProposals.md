### Plan 2: Pure Qwiic + Dynamic Software Underclocking

**Hardware Required:** Standard 4-Pin Qwiic Cable Only (No extra wires).

**How it saves power:** It dynamically changes the ESP32’s clock speed. During the 10-second active window, it runs at full throttle (**240 MHz**) to process data and drive the BLE radio. The second it enters the 15-second rest state, it drops the engine speed down to **80 MHz**, instantly cutting the microcontroller's idle power draw by more than half.

```cpp
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

const unsigned long ACTIVE_RUN_TIME  = 10000;  
const unsigned long IDLE_SLEEP_TIME  = 15000;  
const unsigned long SAMPLE_PACE      = 2000;   

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) { deviceConnected = true; }
  void onDisconnect(BLEServer* pServer) { 
    deviceConnected = false; 
    pServer->getAdvertising()->start(); 
  }
};

void setup() {
  Serial.begin(115200);
  Wire.begin(); 
  bmv.begin();
  bmv.close(); 

  BLEDevice::init("Qwiic Underclock-Node");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->getAdvertising()->start();
}

void loop() {
  // ==========================================
  // PHASE 1 & 2: ACTIVE MODE (MAX PERFORMANCE)
  // ==========================================
  setCpuFrequencyMhz(240); // Crank CPU speed to 240MHz for processing & BLE
  
  bmv.init(); 
  bmv.setMode(SF_BMV080_MODE_CONTINUOUS);
  delay(1000); 

  unsigned long startSampleTime = millis();
  long pm1Sum = 0, pm25Sum = 0, pm10Sum = 0;
  int totalSamplesTaken = 0;

  while (millis() - startSampleTime < ACTIVE_RUN_TIME) {
    if (bmv.readSensor() && !bmv.isObstructed()) {
      pm1Sum  += (int)bmv.PM1(); 
      pm25Sum += (int)bmv.PM25();
      pm10Sum += (int)bmv.PM10(); 
      totalSamplesTaken++;
    }
    delay(SAMPLE_PACE); 
  }

  if (totalSamplesTaken > 0 && deviceConnected) {
    String dataPacket = String(pm1Sum/totalSamplesTaken) + "," + String(pm25Sum/totalSamplesTaken) + "," + String(pm10Sum/totalSamplesTaken);
    pCharacteristic->setValue(dataPacket.c_str());
    pCharacteristic->notify();
  }

  // ==========================================
  // PHASE 3: THRIFT MODE (UNDERCLOCK)
  // ==========================================
  bmv.close(); // Laser completely OFF
  Serial.println("Throttling clock down to 80MHz...");
  Serial.flush();
  
  setCpuFrequencyMhz(80); // Drop CPU clock speed to save raw power
  vTaskDelay(pdMS_TO_TICKS(IDLE_SLEEP_TIME)); 
}

```

---

### Plan 3: Hardware Interrupt + True Light Sleep

**Hardware Required:** 4-Pin Qwiic Cable + **One extra jumper wire** running from BMV080 **`IRQ`** pin to ESP32 **`GPIO 4`**.

**How it saves power:** This scales the system for **long sleep windows (e.g., 5 minutes)**. Instead of using code timers, it forces the ESP32 into a frozen state called **Light Sleep** where current drops to a tiny **2.5 mA**. The sensor manages the timing internally. When the 5 minutes are up, it wakes itself, samples, and shoots an electrical pulse down the wire to wake up the ESP32.

```cpp
#include <Wire.h>
#include <SparkFun_BMV080_Arduino_Library.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

SparkFunBMV080 bmv;

#define SERVICE_UUID           "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define INTERRUPT_PIN          4 // Hardware Wakeup Signal Wire

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;
volatile bool dataReadyEvent = false;

void IRAM_ATTR onDataReady() {
  dataReadyEvent = true; 
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) { deviceConnected = true; }
  void onDisconnect(BLEServer* pServer) { 
    deviceConnected = false; 
    pServer->getAdvertising()->start(); 
  }
};

void setup() {
  Serial.begin(115200);
  Wire.begin();

  pinMode(INTERRUPT_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(INTERRUPT_PIN), onDataReady, FALLING);

  bmv.begin();
  bmv.enableInterrupt(); 
  
  // Set the hardware sleep window significantly longer (e.g., 5 Minutes = 300,000 ms)
  bmv.setMeasuringInterval(300000); 
  bmv.setMode(SF_BMV080_MODE_DUTY_CYCLE); // Lock sensor into autonomous timing mode

  BLEDevice::init("Hardware-Thrift-Node");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->getAdvertising()->start();

  // Configure the ESP32 to wake up the instant GPIO 4 gets pulsed LOW
  esp_sleep_enable_ext0_wakeup((gpio_num_t)INTERRUPT_PIN, 0); 
}

void loop() {
  // If no hardware flag has arrived, freeze the ESP32 completely
  if (!dataReadyEvent) {
    Serial.println("Entering 2.5mA Light Sleep. Frozen until sensor pulse...");
    Serial.flush();
    esp_light_sleep_start(); // CPU stops here. Draws almost no battery.
  }

  // Hardware wakeup routine triggers right here
  if (dataReadyEvent) {
    dataReadyEvent = false; 

    if (bmv.readSensor()) {
      String dataPacket = String((int)bmv.PM1()) + "," + String((int)bmv.PM25()) + "," + String((int)bmv.PM10());
      
      if (deviceConnected) {
        pCharacteristic->setValue(dataPacket.c_str());
        pCharacteristic->notify();
        Serial.println("Pushed to App: " + dataPacket);
      }
    }
  }
}

```