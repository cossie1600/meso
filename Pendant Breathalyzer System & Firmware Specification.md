# Pendant Breathalyzer System & Firmware Specification

---

## 1. Physical Architecture & Enclosure Parameters

* **Form Factor**: Wearable pendant enclosure with a downward-facing intake port.
* **Sensing Chamber**: Micro-cavity ($0.8\text{ cm}^3$) isolated from PCB thermal radiation using silicone gasket seals.
* **Sensor Recess**: BME688 sensor positioned $5\text{ mm}$ recessed behind an outer wall intake aperture.
* **Filter Specification**: Acoustic/dust mesh or hydrophobic PTFE membrane (blocks liquid droplets while allowing 100% VOC/VSC gas permeation).

---

## 2. Multi-Sensor Heuristic Thresholds & Derivations

The physical detection logic relies on multi-sensor fusion across four parallel streams to reliably detect exhaled human breath ($2\text{--}5\text{ cm}$ distance) while rejecting ambient drafts and room fans.

| Metric | Threshold | Physical Target | Enclosure Adaptation ($5\text{ mm}$ Recess + Filter) |
| --- | --- | --- | --- |
| **Relative Humidity Jump** | $\Delta RH \ge +2.5\%$ | Exhaled moisture plume | Moisture permeates filter instantly; cavity traps vapor from ambient drift. |
| **Temperature Rise** | $\Delta T \ge +0.10^\circ\text{C}$ | Human body heat ($35^\circ\text{C}$) | Attenuated from $+0.20^\circ\text{C}$ due to wall thermal buffering; fan air causes active cooling ($\Delta T \le 0.0^\circ\text{C}$). |
| **$eCO_2$ Spike** | $\Delta eCO_2 \ge +250\text{ ppm}$ | Exhaled metabolic gas | Lowered from $+300\text{ ppm}$ to offset minor pneumatic flow restriction across the filter. |
| **MOX Resistance Drop** | $\text{gDrop} \ge 1.5\%$ | VOC / VSC gas absorption | VOCs permeate filter with a $\sim 300\text{--}500\text{ ms}$ diffusion lag. |

### Physics Derivations

* **Relative Humidity Jump ($\Delta RH \ge +2.5\%$)**: Normal indoor room air humidity floats within a tight $\pm 0.5\%$ window over a 10-second window. Water vapor ($H_2O$) passes through porous mesh or hydrophobic PTFE filters almost instantaneously. The $5\text{ mm}$ recessed cavity acts as a micro-trap that isolates moisture from ambient room drafts, making a $2.5\%$ relative humidity jump sharp and sustained inside the enclosure.
* **Temperature Rise ($\Delta T \ge +0.10^\circ\text{C}$)**: Warm exhaled breath counteracts the BME688 hotplate cooling effect. As warm air passes through the filter and down the $5\text{ mm}$ channel, thermal transfer to the outer wall attenuates the thermal spike from the open-air baseline of $+0.20^\circ\text{C}$ down to a $+0.10^\circ\text{C}\text{ to }+0.40^\circ\text{C}$ bump. Ambient fans blowing room air cause net cooling ($\Delta T \le 0.0^\circ\text{C}$).
* **Equivalent $CO_2$ Spike ($\Delta eCO_2 \ge +250\text{ ppm}$)**: Exhaled human breath contains high metabolic $CO_2$ concentration ($\sim 40,000\text{ ppm}$). When passing through the filter, this creates a distinct local $eCO_2$ jump ($\ge +250\text{ ppm}$), whereas ambient room wind or fans move background air ($\Delta eCO_2 \approx 0\text{ ppm}$).
* **MOX Resistance Drop ($\text{gDrop} \ge 1.5\%$)**: Volatile Organic Compounds (VOCs) and Volatile Sulfur Compounds (VSCs) permeate dust/PTFE filters, but experience a $\sim 300\text{--}500\text{ ms}$ diffusion delay reaching the BME688 hotplate. Requiring a $\ge 1.5\%$ resistance drop remains safely above the sensor's $\sim 0.5\%$ internal noise floor while capturing true gas absorption during a 3-second blow window.

---

## 3. Firmware Architecture

### A. BSEC Subscription List

```cpp
bsecSensor sensorList[] = {
  BSEC_OUTPUT_RAW_GAS,
  BSEC_OUTPUT_RAW_TEMPERATURE,
  BSEC_OUTPUT_RAW_HUMIDITY,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
  BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
  BSEC_OUTPUT_RAW_PRESSURE,
  BSEC_OUTPUT_CO2_EQUIVALENT,
  BSEC_OUTPUT_IAQ
};

const uint8_t numSensors = sizeof(sensorList) / sizeof(bsecSensor);

```

### B. BSEC2 Data Processing Callback

```cpp
void newDataCallback(const bme68xData data, const bsecOutputs outputs, Bsec2 bsec) {
  if (!outputs.nOutputs) return;
  
  sensorData.batteryPct = readBatteryPercentage();
  
  for (uint8_t i = 0; i < outputs.nOutputs; i++) {
    const bsecData output = outputs.output[i];
    switch (output.sensor_id) {
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
        if (output.signal > -40.0f && output.signal < 85.0f && output.signal != 0.0f) {
          sensorData.currentTemp = output.signal;
        }
        break;

      case BSEC_OUTPUT_RAW_HUMIDITY:
        sensorData.currentHumidity = output.signal;
        break;

      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:
        if (sensorData.currentHumidity == 0.0f) {
          sensorData.currentHumidity = output.signal;
        }
        break;

      case BSEC_OUTPUT_RAW_PRESSURE:
        sensorData.currentPressure = output.signal;
        break;

      case BSEC_OUTPUT_RAW_GAS:
        sensorData.currentGasRes = output.signal;
        newGasDataAvailable = true;
        break;

      case BSEC_OUTPUT_CO2_EQUIVALENT:
        sensorData.currentCO2 = output.signal;
        sensorData.bsecAccuracy = output.accuracy;
        break;

      case BSEC_OUTPUT_IAQ:
        sensorData.bsecAccuracy = output.accuracy;
        break;

      default:
        break;
    }
  }
}

```

### C. Baseline Capture Function

```cpp
bool prepareAndCaptureBaseline(float &outBaselineRes, float &outBaseHumidity, float &outBaseTemp, float &outBaseCO2) {
  if (!bsecReady) {
    logMessage("[ERROR]: prepareAndCaptureBaseline aborted because bsecReady is false!");
    dispatchData("{\"state\":\"TRY_AGAIN_LATER\"}");
    return false;
  }

  setBsecProfile(PROFILE_CONT_1S);
  vTaskDelay(pdMS_TO_TICKS(100));

  float sumRes = 0.0f, sumHumidity = 0.0f, sumTemp = 0.0f, sumCO2 = 0.0f;
  const uint8_t REQUIRED_SAMPLES = 3;

  uint8_t count = collectBaselineSamples(sumRes, sumHumidity, sumTemp, sumCO2, REQUIRED_SAMPLES, 3500UL);

  if (count == 0) {
    logMessage("[INFO]: BSEC warm-up delayed, extending baseline capture window...");
    count = collectBaselineSamples(sumRes, sumHumidity, sumTemp, sumCO2, 1, 2500UL);
  }

  if (count > 0) {
    outBaselineRes  = sumRes / count;
    outBaseHumidity = sumHumidity / count;
    outBaseTemp     = sumTemp / count;
    outBaseCO2      = sumCO2 / count;

    // Reject if BSEC algorithm has not converged (Accuracy == 0)
    if (sensorData.bsecAccuracy == 0) {
      logMessage("[WARNING]: Baseline aborted — BSEC hotplate algorithm still settling.");
      dispatchData("{\"state\":\"TRY_AGAIN_LATER\"}");
      return false;
    }

    // Reject if background room air is contaminated (> 1200 ppm eCO2)
    if (outBaseCO2 > 1200.0f) {
      logMessage("[WARNING]: Baseline aborted due to high background VOC/CO2 levels.");
      dispatchData("{\"state\":\"ROOM_AIR_DIRTY_VENTILATE\"}");
      return false;
    }

    return true;
  }

  logMessage("[WARNING]: BSEC stabilization timed out during profile switch.");
  dispatchData("{\"state\":\"TRY_AGAIN_LATER\"}");
  return false;
}

```

### D. Exhalation Evaluation Logic

```cpp
static bool evaluateExhalationFrame(float baseGasRes, float baseHumidity, float baseTemp, float baseCO2, float &outMinRes) {
  if (!newGasDataAvailable) return false;
  newGasDataAvailable = false;

  float deltaHumidity = sensorData.currentHumidity - baseHumidity;
  float deltaTemp     = sensorData.currentTemp - baseTemp;
  float deltaCO2      = sensorData.currentCO2 - baseCO2;
  float gasDropPct    = (baseGasRes > 0.0f && sensorData.currentGasRes > 0.0f) ?
                        ((baseGasRes - sensorData.currentGasRes) / baseGasRes) * 100.0f : 0.0f;

  if (sensorData.currentGasRes > 0.0f && sensorData.currentGasRes < outMinRes) {
    outMinRes = sensorData.currentGasRes;
  }

  dispatchData("{\"dH\":" + String(deltaHumidity, 1) + 
               ",\"dT\":" + String(deltaTemp, 1) + 
               ",\"dCO2\":" + String(deltaCO2, 0) + 
               ",\"gDrop\":" + String(gasDropPct, 1) + "}");

  bool isMoistSpike = (deltaHumidity >= 2.5f);
  bool isWarming    = (deltaTemp >= 0.10f);
  bool isCO2Spike   = (deltaCO2 >= 250.0f);
  bool isGasDrop    = (gasDropPct >= 1.5f);

  return isMoistSpike && (isWarming || isCO2Spike || isGasDrop);
}

```