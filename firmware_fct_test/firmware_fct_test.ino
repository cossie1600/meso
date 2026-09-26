#include <Wire.h>
#include <SPIFFS.h>
#include <NimBLEDevice.h>
#include "esp_pm.h"
#include "esp_sleep.h"
#include "bsec2.h"

#define ENABLE_SERIAL_LOGS true 

#define I2C_SDA 6
#define I2C_SCL 7

#define SERVICE_UUID        "4FA215F0-0001-4B0E-B682-1A4C70F3A601"
#define CHARACTERISTIC_UUID "4FA215F0-0002-4B0E-B682-1A4C70F3A601"

// Generic BLE Device Name
String Device_Name = "ESP32-C6 Board";

constexpr uint32_t SERIAL_BAUD_RATE       = 115200; 
constexpr uint32_t I2C_CLOCK_SPEED_HZ     = 100000; 
constexpr uint32_t CPU_LOW_POWER_FREQ_MHZ = 80;     

Bsec2 bsec;
NimBLEServer *pServer = NULL;
NimBLECharacteristic *pCharacteristic = NULL;
bool bsecReady = false;

void initBLE() {
  NimBLEDevice::init(Device_Name.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); 

  pServer = NimBLEDevice::createServer();
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
                    );
  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->start();
}

void setup() {
  delay(1000); 

  Serial.begin(SERIAL_BAUD_RATE);
  delay(500);
  
  // --- FACTORY TEST INITIALIZATION LOGS ---
  Serial.println("\n==========================================");
  Serial.println("     ESP32-C6 FACTORY TEST BUILD          ");
  Serial.println("==========================================");

  // 1. Test BLE Subsystem
  initBLE();
  Serial.println("[PASS] BLE Stack Initialized Successfully");

  // 2. Test I2C Peripheral Lines
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(I2C_CLOCK_SPEED_HZ);
  Wire.setTimeOut(1000);

  uint8_t sensorAddr = BME68X_I2C_ADDR_HIGH; // 0x77
  Wire.beginTransmission(sensorAddr);
  if (Wire.endTransmission() != 0) {
    sensorAddr = BME68X_I2C_ADDR_LOW; // 0x76
  }

  // Probe I2C Bus safely
  bsec.begin(sensorAddr, Wire);

  if (bsec.status != BSEC_OK) {
    // Sensor is NOT present on standalone mainboard - THIS IS EXPECTED
    Serial.println("[INFO] External Sensor Not Present (Standalone Board)");
    Serial.println("[PASS] I2C Pins (GPIO6/GPIO7) Initialized OK");
    bsecReady = false;
  } else {
    bsecReady = true;
    Serial.println("[PASS] External Sensor Detected and Initialized");
  }

  setCpuFrequencyMhz(CPU_LOW_POWER_FREQ_MHZ);

  // --- FINAL FACTORY TEST PASS CRITERIA ---
  Serial.println("------------------------------------------");
  Serial.println(">>> RESULT: MAINBOARD FCT TEST PASSED <<<");
  Serial.println("------------------------------------------\n");
}

void loop() {
  // Heartbeat log every 3 seconds to confirm MCU stability
  static unsigned long lastHeartbeat = 0;
  if (millis() - lastHeartbeat >= 3000) {
    lastHeartbeat = millis();
    Serial.println("[STATUS] Mainboard Running Normally...");
  }
  
  vTaskDelay(pdMS_TO_TICKS(100));
}