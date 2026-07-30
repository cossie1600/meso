#include <Wire.h>
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <FS.h>         

#include <SPIFFS.h>
#include <bsec2.h>

BLECharacteristic *pCharacteristic;
#define BUTTON_PIN 9     // ESP32-C6 BOOT button (GPIO 9) for digitalRead checks
#define WAKEUP_PIN 4     // RTC-capable GPIO for deep sleep wakeup on ESP32-C6
#define I2C_SDA 6        // Pin Definitions for ESP32-C6
#define I2C_SCL 7

// Standard Bluetooth SIG UUID for Environmental Sensing
#define SERVICE_UUID           "0000181a-0000-1000-8000-00805f9b34fb" 
#define CHARACTERISTIC_UUID    "00002a6e-0000-1000-8000-00805f9b34fb"

Bsec2 bsec;
bool isButtonPressed = false;
String log_prefix = "bme688_runtime_logs";
String Device_Name = "Meso Nose";

// Global Shared Variables for BSEC2 Callback
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
void waitForSerialWakeupNstartSPIFF();
void recoverI2C();
void runBreathTest();
void goToSleep();
void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsec);

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

    File file = SPIFFS.open(file_path, FILE_APPEND);
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
    
  waitForSerialWakeupNstartSPIFF();

  logMessage("starting " + Device_Name);

  recoverI2C();
  initBLE();

  // Configure RTC wakeup pin (GPIO 4) for ESP32-C6
  #if defined(SOC_PM_SUPPORT_EXT1_WAKEUP) || defined(CONFIG_IDF_TARGET_ESP32C6)
    esp_sleep_enable_ext1_wakeup(1ULL << WAKEUP_PIN, ESP_EXT1_WAKEUP_ANY_LOW);
  #else
    esp_sleep_enable_ext0_wakeup((gpio_num_t)WAKEUP_PIN, 0); 
  #endif

  // Explicit raw channels supported out-of-the-box by standard BSEC ROM
  bsecSensor sensorList[] = {
    BSEC_OUTPUT_RAW_GAS,
    BSEC_OUTPUT_RAW_TEMPERATURE,
    BSEC_OUTPUT_RAW_HUMIDITY,
    BSEC_OUTPUT_RAW_PRESSURE
  };
    
  uint8_t sensorAddr = BME68X_I2C_ADDR_HIGH;

  if (!bsec.begin(sensorAddr, Wire)) {
    logMessage("Could not find BME688 at 0x77, trying 0x76 fallback...");
    sensorAddr = BME68X_I2C_ADDR_LOW;
    
    if (!bsec.begin(sensorAddr, Wire)) {
      logMessage("ERROR: BME688 not found at 0x77 or 0x76!");
      checkBsecStatus(bsec);
      return;
    }
  }
  logMessage("BME688 successfully connected and initialized!");
  
  // Attach callback so bsec.run() populates latestGasResistance!
  bsec.attachCallback(newDataCallback);

  uint8_t numSensors = sizeof(sensorList) / sizeof(bsecSensor);
  if (!bsec.updateSubscription(sensorList, numSensors, BSEC_SAMPLE_RATE_LP)) {
    logMessage("ERROR: Failed to update subscription!");
    checkBsecStatus(bsec);
  } else {
    logMessage("BSEC Subscription updated successfully!");
  }  
  checkBsecStatus(bsec);

  runBreathTest();
  goToSleep();
}

void loop() {
  if (bsec.run()) {
    logMessage("Data sampled successfully!");
  } else {
    checkBsecStatus(bsec);
  }
  delay(10);
}

void sendBleMessage(const char* message) {
  logMessage(message);
  pCharacteristic->setValue(message); 
  pCharacteristic->notify();          
}

void initBLE() {
  BLEDevice::init(Device_Name);
  
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
  
  logMessage("BLE initialized and advertising as " + Device_Name);
}

void checkBsecStatus(Bsec2 &bsec) {
    if (bsec.status < BSEC_OK) {
        logMessage("BSEC Error Code: " + String(bsec.status));
    } else if (bsec.status > BSEC_OK) {
        logMessage("BSEC Warning Code: " + String(bsec.status));
    }
    if (bsec.sensor.status < BME68X_OK) {
      logMessage("BME688 Sensor Error Code: " + String(bsec.sensor.status));
    } else if (bsec.sensor.status > BME68X_OK) {
      logMessage("BME688 Sensor Warning Code: " + String(bsec.sensor.status));
    }     
}

float ambientSampling(){
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
  return r_ambient;
}

bool wait10SecForBreathBlow(){
  sendBleMessage("STATE:READY");

  uint32_t readyStart = millis();
  bool userStartedBlowing = false;

  while (millis() - readyStart < 10000) {
    bsec.run(); 

    if (digitalRead(BUTTON_PIN) == LOW) {
      delay(200);
      if (digitalRead(BUTTON_PIN) == LOW) {
        userStartedBlowing = true;
        break; 
      }
    }
    delay(20);
  }

  return userStartedBlowing;
}

float getBreathMinIndex(const float r_ambient){
  sendBleMessage("STATE:TESTING");

  float r_breath_min = r_ambient; 
  uint32_t blowStart = millis();

  while (millis() - blowStart < 7000) {
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

  return r_breath_min;
}

void runBreathTest() {
  char bleBuffer[64];

  float r_ambient = ambientSampling();

  bool userBreathTaken = wait10SecForBreathBlow();
  if (!userBreathTaken) {
    sendBleMessage("STATE:TIMEOUT");
    return;
  }

  float r_breath_min = getBreathMinIndex(r_ambient);

  float deltaDrop = (1.0 - (r_breath_min / r_ambient)) * 100.0; 
  snprintf(bleBuffer, sizeof(bleBuffer), "DROP:%.1f,AMB:%.0f,BREATH:%.0f", 
           deltaDrop, r_ambient, r_breath_min);

  sendBleMessage(bleBuffer);

  delay(1000); 
}

void goToSleep() {
  // Use WAKEUP_PIN (GPIO 4) instead of BUTTON_PIN (GPIO 9) for RTC sleep
  esp_sleep_enable_ext1_wakeup(1ULL << WAKEUP_PIN, ESP_EXT1_WAKEUP_ANY_LOW);
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
      latestIaq = output.signal;
      iaqAccuracy = output.accuracy;
    }
  }
}

void waitForSerialWakeupNstartSPIFF() {
  while (!Serial && millis() < 3000);
  
  if (!SPIFFS.begin(true)) { 
    logMessage("An Error has occurred while mounting SPIFFS");
  } else {
    logMessage("SPIFFS mounted successfully");
  }
}

void recoverI2C() {
  pinMode(I2C_SDA, OUTPUT);
  pinMode(I2C_SCL, OUTPUT);
  digitalWrite(I2C_SDA, HIGH);
  digitalWrite(I2C_SCL, HIGH);

  for (int i = 0; i < 9; i++) {
    digitalWrite(I2C_SCL, LOW);
    delayMicroseconds(5);
    digitalWrite(I2C_SCL, HIGH);
    delayMicroseconds(5);
  }

  Wire.end();
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);
  delay(100);
}