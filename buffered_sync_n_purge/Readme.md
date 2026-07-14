---

# Buffered Sync-and-Purge (BSP) Algorithm for ESP32

An ultra-efficient, battery-saving, and hardware-preserving firmware architecture designed for ESP32 air quality tracking nodes communicating with iOS client applications.

---

## Overview

Typically, Bluetooth Low Energy (BLE) peripherals broadcast telemetry data in real-time. For mobile-connected IoT devices, this causes massive battery drain on both the phone and the microcontroller, risking app suspension by iOS background restrictions.

The **Buffered Sync-and-Purge (BSP)** algorithm solves this by decoupling the active sensor polling loop from the wireless transmission layer. It operates locally on the ESP32, buffering structured sensor readings securely, committing them to flash storage in 45-minute batches, and executing an asynchronous "Sync-and-Purge" routine only when a BLE connection is actively requested by the phone.

---

## Core Features

* 🔋 **Vastly Improved iOS/ESP32 Battery Life:** No continuous BLE broadcasting or active connection requirements while in background states.
* 💾 **Flash Memory Wear Protection:** Saves readings to physical SPIFFS flash only in **45-minute batches** (extending the ESP32's built-in flash lifespan to over 8.5 years of continuous use).
* ⚡ **Non-Blocking Dual-Core Execution:** Uses FreeRTOS task pinning (`xTaskCreatePinnedToCore`) to isolate heavy flash reading and BLE streaming to **Core 0**, keeping the timing-sensitive sensor sampling loop on **Core 1** perfectly uninterrupted.
* 🔒 **Thread-Safe Memory Sharing:** Uses hardware-level spinlocks (`portENTER_CRITICAL`) and an "Extract and Release" clone pattern to avoid memory corruption during concurrent RAM access.
* 📡 **Lossless "Sync-and-Purge" BLE Stream:** Streams stored historical data using line-delimited JSON (`.jsonl`) and automatically purges the local database only upon a validated, uninterrupted transfer.

---

## Timing Parameters (Walk/Run Calibration)

This build is calibrated specifically for outdoor walking or running tracking sessions, maintaining a highly optimized duty cycle:

* **Active Run Time:** 10 seconds (high-frequency polling at a 2-second pace).
* **Idle Sleep Time:** **1 minute** (60,000 ms).
* **Total Session Duty Cycle:** ~1 minute and 10 seconds.
* **Buffering Interval (SPIFFS Write):** **45 minutes**.

### Mapping Resolution At 1-Minute Intervals:

* **Walking the dog ($\approx 3\text{ mph}$):** Captures a data point roughly every **80 meters** (approx. 1 city block). High-resolution mapping tracking exact turns.
* **Running ($\approx 6\text{ mph}$):** Captures a data point roughly every **160 meters** (approx. 1.5 to 2 city blocks). A beautifully detailed route map without database bloat.

---

## Architectural Workflow

```
             CORE 1: Sensor Collection Loop           │       CORE 0: Background BLE Engine
                                                      │
     ┌──────────────────────────────────────────┐     │
     │ Wake & Stabilize BMV080 Sensor (1 sec)   │     │
     └────────────────────┬─────────────────────┘     │
                          ▼                           │
     ┌──────────────────────────────────────────┐     │
     │ Gather Snapshot Reads (10 sec / 2s pace)  │     │
     └────────────────────┬─────────────────────┘     │
                          ▼                           │
     ┌──────────────────────────────────────────┐     │
     │ Compute Mean & Push to RAM Memory Buffer │     │
     └────────────────────┬─────────────────────┘     │
                          ▼                           │
     ┌──────────────────────────────────────────┐     │     ┌───────────────────────────────────┐
     │ Shut Down Sensor Laser to Save Power     │     │ ───►│ BLE Client Connected (iOS App)    │
     └────────────────────┬─────────────────────┘     │     └─────────────────┬─────────────────┘
                          ▼                           │                       ▼
     ┌──────────────────────────────────────────┐     │     ┌───────────────────────────────────┐
     │ Timer: 45 Mins Elapsed?                  │     │     │ Copy RAM Buffer & Reset           │
     │ YES -> Flush Buffer to SPIFFS File       │     │     └─────────────────┬─────────────────┘
     └────────────────────┬─────────────────────┘     │                       ▼
                          ▼                           │     ┌───────────────────────────────────┐
     ┌──────────────────────────────────────────┐     │     │ Read SPIFFS & Stream JSON over BLE│
     │ Enter Deep Yield State (1 minute)        │     │     └─────────────────┬─────────────────┘
     └──────────────────────────────────────────┘     │                       ▼
                                                      │     ┌───────────────────────────────────┐
                                                      │     │ Success? -> Delete SPIFFS Log File│
                                                      │     └───────────────────────────────────┘

```

---

## The Core Math: Floating-Point Means

Instead of recording raw values directly, the algorithm acts as a low-pass filter to smooth out sudden transient spikes (such as a single dust particle flying through the optical chamber).

It calculates a true mathematical mean ($\bar{x}$) over $N$ samples:

$$\bar{x} = \frac{1}{N} \sum_{i=1}^{N} x_i$$

Because the ESP32 contains a dedicated hardware **Floating-Point Unit (FPU)**, this mathematical mean is computed using 32-bit floating-point precision, ensuring sub-integer trends are captured flawlessly without incurring a performance penalty.

---

## Data Structures

### Volatile Memory Object

To minimize RAM usage, data points are held in the memory buffer as a highly optimized, custom C++ struct ($16\text{ bytes}$ per sample). At a 45-minute buffering interval, the maximum footprint in RAM is only **~38 samples (608 bytes)**.

```cpp
struct pm_sample {
  unsigned long timestamp_ms; // 4 bytes
  float pm1;                  // 4 bytes
  float pm2_5;                // 4 bytes
  float pm10;                 // 4 bytes
};

```

### Persistent JSON Lines (`.jsonl`) Format

When flushed to SPIFFS, each struct is serialized into a single, compact JSON string and appended with a newline character. This format keeps parsing memory requirements on both the ESP32 and iOS client incredibly low:

```json
{"t":329480,"pm1":1.20,"pm25":4.50,"pm10":8.10}
{"t":354480,"pm1":1.10,"pm25":4.30,"pm10":7.90}

```

---

## BLE Sync Protocol (Handshake & Safety)

To guarantee that no data is lost if the wireless connection drops mid-transfer, BSP enforces a strict synchronization workflow:

1. **Connection Trigger:** A background FreeRTOS task on Core 0 sleeps until `deviceConnected` is asserted by the BLE Server callbacks.
2. **Flash Drain:** If a stored log file exists, the task opens `/pm_data.jsonl` as read-only. It reads line by line, publishing each JSON string to the target characteristic using BLE notifications.
3. **RAM Drain (Extract & Release):** To prevent race conditions during memory access:
* A spinlock mutex is acquired.
* The volatile `memoryBuffer` vector is cloned to a local `tempBuffer`.
* The `memoryBuffer` is immediately cleared.
* The spinlock is released.
* `tempBuffer` is then streamed safely over BLE notifications.


4. **The Safe Wipe:** The log file `/pm_data.jsonl` is **only deleted** if `deviceConnected` remains true through the entire file-streaming cycle. If a disconnect occurs, the file remains intact, ready to be fully resent upon the next handshake.
