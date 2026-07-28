[DEEP SLEEP / OFF] 
       │ 
       ▼ (User single-clicks button)
[STAGE 1: AMBIENT SAMPLING] ──> LED Flashes YELLOW (9s total)
       │                        • Heats BME688 micro-hotplate (~3s)
       │                        • Takes 3x 3-second samples to average R_ambient
       │                        
       ▼
[STAGE 2: READY TO BLOW]   ──> LED Flashes BLUE (Up to 10s timeout)
       │                        • Indicates sensor is prepped and waiting
       │                        • User holds button and exhales 2 inches away
       │
       ▼ (Button held down + Breath detected)
[STAGE 3: BREATH ANALYSIS]  ──> LED Turns SOLID BLUE (Sensing peak gas drop)
       │                        • Reads minimum gas resistance (R_breath)
       │                        • Computes Delta Drop %
       │
       ▼
[STAGE 4: Sends result to BLE]  ──> 
       │                        • (<30% drop): Fresh
       │                        • (30–50% drop): Moderate Odor
       │                        • (>50% drop): High VSCs / Severe Odor
       │
       ▼
[POWER DOWN]                ──> Enters Deep Sleep (<10µA draw)


OR


ESP32-C6 STATE                      BLE NOTIFICATION PAYLOAD
======================================================================
1. Ambient Sampling   ───────>   "STATE:SAMPLING"
2. Ready for Breath   ───────>   "STATE:READY"     <-- App shows "BLOW NOW!" UI
3. Breath In Progress ───────>   "STATE:TESTING"
4. Test Finished      ───────>   "DROP:42.5,AMB:150000,BREATH:87000"