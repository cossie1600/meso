### The Three-Phase Power Thrifting Algorithm

#### Phase 1: Sensor Wakeup & Aggressive Sampling

1. **Initialize & Ignite:** The ESP32 calls `bmv.init()` over the Qwiic bus to supply power and activate the internal fanless laser diode.
2. **Set Stream Mode:** The sensor configuration is explicitly locked into Continuous Mode (`SF_BMV080_MODE_CONTINUOUS`).
3. **Register Stabilization:** The microprocessor executes a strict `delay(1000);`. This 1-second pause gives the laser engine time to spin up and stabilize its internal data registers, preventing corrupt data drops.
4. **The 10-Second High-Frequency Window:** A localized `while` loop runs for exactly 10,000 milliseconds.
* Every 2 seconds (`SAMPLE_PACE`), the ESP32 queries the sensor over $I^2C$ using `bmv.readSensor()`.
* If valid data is ready, it extracts $PM_{1.0}$, $PM_{2.5}$, and $PM_{10}$ metrics and adds them to a running mathematical total, incrementing the `totalSamplesTaken` counter.



#### Phase 2: Math Aggregation & Conditional BLE Push

1. **Calculate the True Mean:** Once the 10-second active window closes, the algorithm divides the accumulated particle sums by `totalSamplesTaken` to produce a single noise-filtered average for each particle size.
2. **String Packet Serialization:** The integers are formatted into a single lightweight text string separated by commas (e.g., `"3,11,45"`).
3. **Connection Check & Dispatch:** The code checks the status of the `deviceConnected` boolean flag managed by the Bluetooth server callbacks.
* **IF TRUE:** The ESP32 pushes the string text directly to your iPhone app via `pCharacteristic->notify()`.
* **IF FALSE:** The transmission is entirely skipped, saving the radio transmission engine from wasting precious milliamp-hours of battery power trying to stream data into an empty void.



#### Phase 3: Hardware Power Down (Thrift Mode)

1. **Laser Kill Command:** The ESP32 calls `bmv.close()`. This forcefully shuts down the physical laser diode on the BMV080 board, plummets the sensor's current draw down to $0\text{ mA}$, and prevents long-term hardware wear.
2. **Yield CPU Cycles:** The main thread executes `vTaskDelay(pdMS_TO_TICKS(15000));`. Instead of a blocking delay that locks up the processor, this tells the chip's internal real-time operating system (FreeRTOS) to pause your program for 15 seconds.
3. **Memory & Radio Maintenance:** During this 15-second idle pause, the ESP32 core steps down its processing speed, allows background garbage collection to clear out dynamic string fragments (preventing the 45-minute lockup crash), and lets the BLE radio manage minimal background keep-alive signals.
4. **Loop Reset:** Once the 15-second rest timer expires, the loop completely restarts from Phase 1, repeating a flawless **~26.5-second total cycle time** indefinitely.