+-------------------------+
                        |    START LOOP() CYCLE   |
                        +------------+------------+
                                     |
                                     v
           ================= PHASE 1: SENSOR WAKEUP =================
                    |
                                     v
                        +-------------------------+
                        |    bmv.init() Bootup    | <--- Laser powers ON
                        +------------+------------+
                                     |
                                     v
                        +-------------------------+
                        |  delay(1000) Warmup     | <--- Eliminates register lag
                        +------------+------------+
                                     |
                                     v
           ============== ACTIVE SAMPLING WINDOW (10s) ==============
                                     |
                                     v
                        +-------------------------+
           +----------->|  Read PM1, PM2.5, PM10  | ----+
           |            +------------+------------+     |
           |                         |                  | Adds values to
    Every 2 seconds                  v                  | running totals
    (SAMPLE_PACE)       +-------------------------+     |
           |            |   totalSamplesTaken++   | <---+
           |            +------------+------------+
           |                         |
           |   NO                    v
           +-----+ Is 10-second Active Window Finished?
                                     | YES
                                     v
           ================== PHASE 2: BLE PUSH =====================
                                     |
                                     v
                        +-------------------------+
                        | Calculate Math Average  | ----> (pmSum / totalSamples)
                        +------------+------------+
                                     |
                                     v
                                 /---------\
                               /    Is BLE   \
                              <  Connected?   >
                               \             /
                                 \---------/
                                 /         \
                               YES          NO
                               /              \
                              v                v
                +------------------------+   +------------------------+
                | pCharacteristic->      |   | Skip BLE Transmission  |
                |   notify(dataPacket);  |   |  (Drop to save radio)  |
                +------------+-----------+   +-----------+------------+
                             |                           |
                             +-------------+-------------+
                                           |
                                           v
           ================= PHASE 3: THRIFT SLEEP ==================
                          |
                                           v
                        +-------------------------+
                        |    bmv.close() Sleep    | <--- Laser powers OFF (0mA)
                        +------------+------------+
                                     |
                                     v
                        +-------------------------+
                        |  vTaskDelay (15000ms)   | <--- ESP32 yields CPU cycles
                        +------------+------------+
                                     |
                                     v
                        +-------------------------+
                        |   LOOP REPEATS (~26.5s) |
                        +-------------------------+