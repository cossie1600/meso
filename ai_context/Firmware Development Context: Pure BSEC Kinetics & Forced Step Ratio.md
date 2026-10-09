# Firmware Development Context: Pure BSEC Kinetics & Forced Step Ratio

Paste this entire section into any new chat session to instantly preload the complete system architecture, logic specifications, and current progress.

---

## 1. Project Overview & System Architecture

We are building professional-grade breath analysis firmware for an ESP32-based device using the **Bosch BME688** gas sensor. The device classifies oral malodor and volatile organic compounds (VOCs) based on physical sensor kinetics ($\Delta RH$, relative gas resistance drop $gDrop$, and desorption recovery lag $T_{50}$) rather than virtual BSEC indoor air quality outputs.

### Hardware & Software Stack

* **Microcontroller:** ESP32 (SDA: Pin 6, SCL: Pin 7, Baud: 115200, I2C: 100 kHz).
* **Communication & Storage:** NimBLE BLE service (`4fa215f0-0001-4b0e-b682-1a4c70f3a601`), LittleFS offline data logging (`/offline_data.json`).
* **Sensor Library:** Bosch BSEC2 (`bsec2.h`) and low-level BME68x driver (`bme68x.h`).
* **Sensor Profile:** Bosch selectivity model (`bme688_sel_33v_3s_4d` / `bsec_selectivity.txt`).

---

## 2. Shared Physical Sensing Principles & Variables

The system relies strictly on physical gas and humidity dynamics. $eCO_2$ is unsupported by the custom Bosch selectivity profile (returns `0`) and is omitted from classification decisions.

### Shared Constants & Triggers

* **Warm-Up Requirement:** Requires a **one-time 3–8 minute cold boot stabilization** on power-on. Inter-test delay during continuous mode is **0 seconds**.
* **Baseline Capture:** Captures 3 valid samples ($9\text{ seconds}$ total) from ambient air to calculate $R_{base}$ and $RH_{base}$.
* **Exhalation Trigger Thresholds:**
* **Standard Blow:** $\Delta RH \ge 20.0\%$ **AND** $gDrop \ge 5.0\%$.
* **High Humidity Ambient Override ($RH_{base} \ge 80.0\%$):** $gDrop \ge 5.0\%$.


* **Weak Blow Detection:** $0.8\% \le \Delta RH < 20.0\%$ outputs `{"state":"EXHALATION_TOO_WEAK"}`.
* **No Blow Timeout:** 30 seconds with $\Delta RH < 0.8\%$ outputs `{"state":"TIMEOUT"}`.
* **Pressure Calibration:** Pressure is read as raw Pascals from `BSEC_OUTPUT_RAW_PRESSURE` and converted to hPa (`signal / 100.0f`).

---

## 3. Pure BSEC Kinetics Architecture (Completed)

The **Pure BSEC Kinetics** sketch operates the sensor in continuous Low Power 3-second mode (`BSEC_SAMPLE_RATE_LP`) to keep the micro-heater plate continuously energized at ~300°C.

### Physical Formulas

1. **Gas Resistance Drop Percentage ($gDrop$):**

$$gDrop = \frac{R_{base} - R_{min}}{R_{base}} \times 100\%$$

2. **Moisture Delta ($\Delta RH$):**

$$\Delta RH = RH_{max} - RH_{base}$$

3. **$T_{50}$ Desorption Recovery Lag:** Time in seconds ($\tau_{50}$) for gas resistance to recover 50% from $R_{min}$ back toward $R_{base}$:

$$R_{target50} = R_{min} + 0.5 \times (R_{base} - R_{min})$$

* **Fast Recovery ($\tau_{50} < 3.5\text{s}$):** Non-sulfur organic molecules (beverage/food/alcohol esters) desorb rapidly.
* **Slow Recovery ($\tau_{50} \ge 3.5\text{s}$):** Volatile Sulfur Compounds ($H_2S$, methyl mercaptan) bind strongly to the plate.

### Refined Decision Matrix

| Result Code | $\Delta RH$ Condition | $gDrop$ Range | $T_{50}$ Recovery Lag | Physical Interpretation |
| --- | --- | --- | --- | --- |
| `BALANCED_BREATH` | $\ge 2.5\%$ | $< 15\%$ | **$< 3.5\text{s}$** | Fresh baseline breath clearing rapidly |
| `SETTLE_BEVERAGE_FOOD_ODOR` | $\ge 2.5\%$ | $< 15\%$ | **$\ge 3.5\text{s}$** | Trace organic residue settling post-ingestion |
| `SOME_BEVERAGE_FOOD_ODOR` | $\ge 2.5\%$ | $\ge 15\%$ | $< 3.5\text{s}$ | Moderate/heavy non-sulfur organic residue (food/beverage) |
| `NOTICEABLE_MALODOR` | $\ge 2.5\%$ | $15\% - 45\%$ | $\ge 3.5\text{s}$ | Moderate volatile sulfur compounds (VSC) present |
| `STRONG_MALODOR` | $\ge 2.5\%$ | $\ge 45\%$ | $\ge 3.5\text{s}$ | High VSC concentration |
| `DRY_MOUTH_HYDRATE` | $< 2.5\%$ | $\ge 15\%$ | $< 3.5\text{s}$ | Oral dehydration with food residue |
| `DRY_MOUTH_VSC_BUILDUP` | $< 2.5\%$ | $\ge 15\%$ | $\ge 3.5\text{s}$ | Oral dehydration with active VSC accumulation |
| `NONE` | Any | $< 15\%$ | Any | Sub-threshold change or invalid blow |

### Code Structure & Diagnostics

* `sensor_data.h`: Defines the `SensorData` struct and JSON formatting (`toJsonString()`).
* `diagnostics.h` / `diagnostics.cpp`: Houses the `runSelectivityDiagnosticTest()` self-test suite (triggered by command `99`).
* `newDataCallback()` Handling: Updated to explicitly handle `BSEC_OUTPUT_RAW_PRESSURE` (`output.signal / 100.0f`), fixing previous `press: 0.0` output anomalies.
* **Code Hygene Note:** Removed unused architecture stub functions (`configureLowLevelParallelScan()` and `readLowLevelScanFrame()`) to ensure zero dead code in the Pure BSEC implementation.

---

## 4. Forced Step Ratio Architecture (Next Implementation Phase)

The **Forced Step Ratio** sketch replaces continuous single-temperature LP heating with low-level heater matrix profile stepping using the raw `bme68x` driver API.

### Core Differences Between Architectures

| Feature / Metric | Pure BSEC Kinetics Architecture | Forced Step Ratio Architecture |
| --- | --- | --- |
| **Engine / Driver** | BSEC2 C++ Library (`bsec2.h`) | Low-level BME68x Driver (`bme68x.h`) |
| **Heater Operation** | Continuous 3s LP single temperature (~300°C) | Multi-step heater profile array (e.g., 10 temperature steps from 200°C to 400°C) |
| **Data Output per Frame** | Single raw gas resistance value per 3s frame | Multi-point resistance array ($R_{step1}, R_{step2}, \dots, R_{step10}$) per scan loop |
| **Selectivity Metric** | Desorption recovery lag time ($T_{50}$) over a 15-second post-exhalation window | Differential gas resistance ratios across heater steps ($R_{step\_i} / R_{step\_j}$) |
| **Exhalation Detection** | Physical $\Delta RH \ge 20\%$ AND $gDrop \ge 5\%$ | Physical $\Delta RH \ge 20\%$ AND $gDrop \ge 5\%$ (identical trigger) |
| **Dry Mouth Detection** | $\Delta RH < 2.5\%$ AND $gDrop \ge 15\%$ | $\Delta RH < 2.5\%$ AND $gDrop \ge 15\%$ (identical trigger) |
| **$eCO_2$ Availability** | None (`0`) | None (BSEC is bypassed entirely) |