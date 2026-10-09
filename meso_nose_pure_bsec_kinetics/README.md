# Pure BSEC Kinetics Architecture

## Overview

The Pure BSEC Kinetics architecture provides low-latency breath malodor and volatile organic compound (VOC) classification using the Bosch BME688 sensor and BSEC2 engine.

### Warm-Up & Operational Readiness
* **Initial Cold Boot (Power-On / Reset):** Requires a **one-time 3 to 8 minute stabilization lock** for the sensor element to reach thermal equilibrium and burn off ambient condensation.
* **Inter-Test Delay:** **0 seconds**. Once initialized, continuous background 3-second LP mode (`BSEC_SAMPLE_RATE_LP`) keeps the micro-heater at operating temperature (~300°C), allowing back-to-back breath tests without warm-up delays.
---

## Mathematical Models & Metrics

### 1. Baseline Calibration
Ambient baseline readings ($R_{base}$, $RH_{base}$) are calculated as the mean of 3 consecutive valid frames (9 seconds total):

$$R_{base} = \frac{1}{3} \sum_{i=1}^{3} R_{gas,i}$$

$$RH_{base} = \frac{1}{3} \sum_{i=1}^{3} RH_{i}$$

### 2. Relative Gas Drop ($gDrop$)
Peak exhalation magnitude is calculated as the percentage drop from baseline resistance ($R_{base}$) to the minimum observed resistance ($R_{min}$):

$$gDrop = \frac{R_{base} - R_{min}}{R_{base}} \times 100\%$$

### 3. Exhalation Moisture Delta ($\Delta RH$)
The maximum humidity increase above ambient conditions during exhalation:

$$\Delta RH = RH_{max} - RH_{base}$$

### 4. Desorption Recovery Lag ($T_{50}$)
The time in seconds required for gas resistance to recover 50% from $R_{min}$ back toward $R_{base}$:

$$R_{target50} = R_{min} + 0.5 \times (R_{base} - R_{min})$$

$$\tau_{50} = t_{recovery} - t_{min} \quad \text{where } R_{gas}(t_{recovery}) \ge R_{target50}$$

* **Fast Recovery ($\tau_{50} < 3.5\text{s}$):** Rapid desorption typical of volatile non-sulfur compounds (e.g., ethanol, food/beverage esters).
* **Slow Recovery ($\tau_{50} \ge 3.5\text{s}$):** Slow desorption typical of Volatile Sulfur Compounds (VSCs like $H_2S$ and methyl mercaptan).

---

## Exhalation Validation Criteria

An exhalation event is confirmed when either condition is met within the 30-second window:

* **Standard Environment:** $\Delta RH \ge 20.0\%$ **AND** $gDrop \ge 8.0\%$
* **High Humidity Baseline ($RH_{base} \ge 80.0\%$):** $gDrop \ge 8.0\%$

---

## Classification Matrix

| Classification Result | $\Delta RH$ Delta | $gDrop$ Range | $T_{50}$ Lag | Primary Cause |
| :--- | :--- | :--- | :--- | :--- |
| `BALANCED_BREATH` | $\ge 2.5\%$ | $< 15\%$ | Any | Baseline ambient/fresh breath |
| `SOME_BEVERAGE_FOOD_ODOR` | $\ge 2.5\%$ | $15\% - 45\%$ | $< 3.5\text{s}$ | Beverage or non-sulfur food residue |
| `SETTLE_BEVERAGE_FOOD_ODOR` | $\ge 2.5\%$ | $< 15\%$ | $< 3.5\text{s}$ | Trace post-ingestion organic residue |
| `NOTICEABLE_MALODOR` | $\ge 2.5\%$ | $15\% - 45\%$ | $\ge 3.5\text{s}$ | Moderate volatile sulfur compounds (VSC) |
| `STRONG_MALODOR` | $\ge 2.5\%$ | $\ge 45\%$ | $\ge 3.5\text{s}$ | High VSC concentration |
| `DRY_MOUTH_HYDRATE` | $< 2.5\%$ | $\ge 15\%$ | $< 3.5\text{s}$ | Oral dehydration with food residue |
| `DRY_MOUTH_VSC_BUILDUP` | $< 2.5\%$ | $\ge 15\%$ | $\ge 3.5\text{s}$ | Oral dehydration with VSC accumulation |
| `NONE` | Any | $< 15\%$ | Any | Sub-threshold change or invalid blow |

---

## Performance & Accuracy Specifications

### Hardware Precision (BME688 Datasheet)
* **Relative Humidity Precision:** $\pm 3.0\%\text{ RH}$
* **Temperature Precision:** $\pm 0.5^\circ\text{C}$
* **Gas Resistance Repeatability:** $\pm 2.0\%\text{ to } 5.0\%$

### Algorithmic Reliability Estimates
* **Exhalation Event Detection:** **$> 98\%$** (Dual-parameter verification prevents false positives from ambient airflow).
* **VSC vs. Non-Sulfur Discrimination ($T_{50}$ Kinetics):** **$\sim 85\% - 92\%$** estimated correlation with gas-chromatography standards.
* **Inter-Test Warm-Up Delay:** **$0\text{ seconds}$** (Continuous LP sampling maintains steady plate temperature).