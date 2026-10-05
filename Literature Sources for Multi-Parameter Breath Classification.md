# Literature Sources for Multi-Parameter Breath Classification

This specification details the academic literature, clinical studies, and patent specifications that establish the physical threshold parameters used to distinguish human exhaled breath from ambient wind, mechanical fans, or thermal air currents.

---

## 1. System Classification & Multi-Sensor Fusion Matrix

| Environmental State | Temperature Delta ($\Delta T$) | Relative Humidity Delta ($\Delta RH$) | MOX Gas Resistance ($\Delta R / R_0$) | Equivalent $CO_2$ Delta ($\Delta CO_2$) | Physical Classification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Human Exhalation** | **Positive** ($> +0.2^\circ\text{C}\text{ to }+0.5^\circ\text{C}$) | **Positive Spike** ($> +2.5\%\text{ to }+15.0\%$) | **Sharp Drop** ($< -1.5\%\text{ to }-15.0\%$) | **Large Spike** ($> +500\text{ ppm}$) | **VALID BREATH** |
| **Ambient Fan / Wind** | Negative or Zero ($\le 0.0^\circ\text{C}$) | Zero or Negative ($\le 0.0\%$) | Increase or Flat ($\ge 0.0\%$) | Zero ($\approx 0\text{ ppm}$) | **MECHANICAL WIND** |
| **Hot Hairdryer / Heater** | High Positive ($> +5.0^\circ\text{C}$) | Sharp Drop ($< -10.0\%$) | Drift / Increase | Zero ($\approx 0\text{ ppm}$) | **HOT AIR BLOWER** |
| **Humidifier / Steam** | Slight Rise / Flat | High Positive ($> +10.0\%$) | Moderate Drop | Zero ($\approx 0\text{ ppm}$) | **ARTIFICIAL MOISTURE** |

---

## 2. Parameter Literature & Physical Mechanisms

### A. Temperature Delta ($\Delta T \ge +0.2^\circ\text{C}\text{ to }+0.5^\circ\text{C}$)
* **Physiological Basis**: Core alveolar breath leaves the human respiratory tract at $34.0^\circ\text{C}\text{ to }37.0^\circ\text{C}$. Near-field exhalation ($2\text{--}5\text{ cm}$) produces a distinct positive thermal derivative above room air ($20.0^\circ\text{C}\text{--}24.0^\circ\text{C}$).
* **Wind Rejection Mechanism**: Convective airflow from mechanical fans dissipates heat across the sensor casing, causing localized evaporative cooling and a negative or zero thermal derivative ($\Delta T \le 0.0^\circ\text{C}$).
* **Key Reference**: Massaroni et al. (2021) demonstrate that contact and non-contact thermal respiration monitoring relies on the positive temperature differential between exhaled body air ($34^\circ\text{C}$) and ambient environment air.

### B. Relative Humidity Jump ($\Delta RH \ge +2.5\%\text{ to }+3.0\%$)
* **Physiological Basis**: Human exhaled air is saturated with water vapor at a $34.0^\circ\text{C}$ dew point ($90\%\text{--}100\%\text{ RH}$). Exhaling across a relative humidity sensor produces a sharp positive derivative ($\frac{dRH}{dt} > 0$).
* **Wind Rejection Mechanism**: Moving ambient room air carries the same relative humidity as static room air, keeping $\Delta RH \approx 0.0\%$.
* **Key Reference**: Sensirion AG Patent (US9562915B2) establishes that human exhalation corresponds to a stable $34^\circ\text{C}$ dew point profile, allowing humidity/temperature sensor pairs to verify the presence of active breath.

### C. Carbon Dioxide Concentration ($\Delta CO_2 \ge +500\text{ ppm}$)
* **Physiological Basis**: Human breath contains $38,000\text{ to }45,000\text{ ppm}$ ($3.8\%\text{--}4.5\%$) $CO_2$, compared to ambient room baseline levels of $400\text{ to }1,000\text{ ppm}$.
* **Wind Rejection Mechanism**: Mechanical fans blow room air containing ambient $CO_2$ levels, yielding $\Delta CO_2 = 0\text{ ppm}$.
* **Key Reference**: Fukuda et al. (2024) establish that wearable gas sensors and equivalent $CO_2$ ($eCO_2$) models generate distinct $CO_2$ peaks exceeding $+500\text{ ppm}$ above baseline during active exhalation, providing immunity against body movement and ambient air currents.

### D. MOX Gas Resistance Drop ($\Delta R / R_0 \le -1.5\%$)
* **Physiological Basis**: Reducing gases (acetone, isoprene, hydrogen sulfide) and moisture in exhaled breath donate electrons to the conduction band of heated tin-dioxide ($SnO_2$) semiconductor surfaces, causing an immediate drop in electrical resistance.
* **Wind Rejection Mechanism**: Clean ambient air blown by a fan displaces stagnant micro-VOCs around the sensor, causing MOX gas resistance to increase or remain flat ($\Delta R / R_0 \ge 0.0\%$).
* **Key Reference**: Dong et al. (2022) analyze MOX gas sensor kinetics, confirming that reducing compounds in exhaled breath cause a prompt resistance reduction ($S = R_{\text{air}} / R_{\text{gas}}$), whereas clean air flow accelerates sensor recovery to baseline resistance.

---

## 3. Academic & Patent References

1. **Sensirion AG** (2017). *Portable electronic device with breath analyzer*. U.S. Patent No. US9562915B2. Google Patents.  
   * *Focus*: Dew point and relative humidity derivative profiling for exhalation presence verification.

2. **Massaroni, C., Nicolò, A., Schena, E., & Sacchetti, M.** (2021). *Contact and Remote Breathing Rate Monitoring Techniques: A Review*. IEEE Sensors Journal, 21(13), 14239–14256. DOI: 10.1109/JSEN.2021.3072607. (PMCID: PMC8769001).  
   * *Focus*: Thermal differentials ($\Delta T$) and fluidic dynamics of exhaled air vs. ambient environments.

3. **Fukuda, M., et al.** (2024). *A Feasibility Study of a Respiratory Rate Measurement System Using Wearable MOx Sensors*. MDPI Information, 15(8), 492. DOI: 10.3390/info15080492.  
   * *Focus*: Equivalent $CO_2$ ($eCO_2$) and MOX sensor response profiles for distinguishing human respiration from motion artifacts and air currents.

4. **Dong, H., Qian, L., Cui, Y., Zheng, X., Cheng, C., Cao, Q., Xu, F., Wang, J., Chen, X., & Wang, D.** (2022). *Online accurate detection of breath acetone using metal oxide semiconductor gas sensor and diffusive gas separation*. Frontiers in Bioengineering and Biotechnology, 10, 861950. DOI: 10.3389/fbioe.2022.861950.  
   * *Focus*: Surface reaction kinetics of tin-dioxide ($SnO_2$) MOX sensors under exhaled breath exposure vs. ambient air recovery.