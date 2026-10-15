### The $T_{50}$ Equation

The $T_{50}$ metric ($\tau_{50}$) represents the **50% Desorption Recovery Lag**—the time in seconds it takes for the gas sensor's resistance to recover halfway back to ambient baseline ($R_{base}$) after reaching its maximum drop / minimum resistance ($R_{min}$) during an exhalation.

#### Step 1: Calculate the 50% Target Resistance ($R_{target50}$)

$$R_{target50} = R_{min} + 0.5 \times (R_{base} - R_{min})$$

#### Step 2: Compute Recovery Lag Time ($T_{50}$)

$$T_{50} = t(R_{target50}) - t(R_{min})$$

* $t(R_{min})$: The timestamp when minimum resistance occurs at the peak of the blow.
* $t(R_{target50})$: The timestamp when gas resistance climbs back up to reach $R_{target50}$ during clean air purging.

---

### Physical Mechanism & Research Foundation

The research underlying $T_{50}$ stems from **adsorption and desorption reaction kinetics** on Metal-Oxide Semiconductor (MOX) sensing films (such as tin dioxide, $\text{SnO}_2$, used in the Bosch BME688).

#### 1. Surface Binding Affinity & Activation Energy

* **Fast Recovery ($T_{50} < 3.5\text{s}$):** Non-sulfur volatile organic compounds (esters, alcohols, and aliphatic hydrocarbons from recent food, beverages, or mouthwashes) undergo weak physisorption or mild chemisorption on the heated sensor plate (~300°C). When exhalation stops and fresh air flows over the plate, these weakly bound molecules desorb rapidly.
* **Slow Recovery ($T_{50} \ge 3.5\text{s}$):** Volatile Sulfur Compounds (VSCs—primarily Hydrogen Sulfide $H_2S$ and Methyl Mercaptan $\text{CH}_3\text{SH}$ responsible for oral malodor) form strong chemical bonds with oxygen vacancy sites on metal oxides. These compounds require higher activation energy and significantly longer relaxation windows to break surface bonds and desorb.

#### 2. Recovery Time Metrics in Sensor Literature

In chemical sensor characterization and international standards (such as **ISO 16000-29** for VOC detectors), dynamic sensor behavior is defined by response time ($\tau_{63}$ / $\tau_{90}$) and **recovery time ($\tau_{50}$ / $\tau_{90}$)**. Recovery time $\tau_{50}$ is the standard physical benchmark measuring how quickly a sensing layer returns 50% toward baseline after removal of a target gas plume.

---

### Literature & Reference Resources

* **Bosch BME688 Datasheet & Gas Scanner Profile Manual:** Details the physical operation of the $\text{SnO}_2$ micro-heater plate and the gas scanner response kinetics across temperature steps.
* [Bosch Sensortec BME688 Datasheet (PDF)](https://www.bosch-sensortec.com/media/boschsensortec/downloads/datasheets/bst-bme688-ds000.pdf)


* **MOX Sensor Recovery Dynamics Research:** Academic literature examining the long desorption recovery times of metal oxide sensors and software algorithms used to evaluate recovery tails.
* [Overcoming Long Recovery Time of Metal-Oxide Gas Sensors (ResearchGate)](https://www.researchgate.net/publication/339283630_Overcoming_Long_Recovery_Time_of_Metal-Oxide_Gas_Sensor_With_Certainty_Factor_Sensing_Algorithm)


* **Standard Test Methods for VOC Detectors (ISO 16000-29):** Standard governing the evaluation of response and recovery kinetics ($\tau_{50}$) in indoor air and breath testing gas sensors.
* [ISO 16000-29 Test Methods for VOC Detectors (Bosch BME680 Technical Specification)](https://www.bosch-sensortec.com/media/boschsensortec/downloads/datasheets/bst-bme680-ds001.pdf)