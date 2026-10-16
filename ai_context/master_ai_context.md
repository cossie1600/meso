================================================================================
MASTER PROJECT ARCHITECTURE & AI CONTEXT SPECIFICATION
Project: Meso Nose & Votre Air Ecosystem
Updated: October 2026
================================================================================

1. UNIVERSAL CODING RULES:
   - Zero Emojis across all firmware, iOS code, logs, comments, and headers.
   - Zero Magic Numbers & Strings: Centralize constants in typed structs (UIConstants, BMConstants).
   - Strict Isolation & Minimal Scope Edits.

2. FIRMWARE SKETCH & DECISION MATRIX CONFIGURATION:
   - Primary Firmware Sketch Name: meso_nose_pure_bsec_kinetics.ino
   - Configured Gas Drop Thresholds: BREATH_MIN_SIGNIFICANT_DROP_PCT = 6.0f, BREATH_FRESH_MAX_DROP_PCT = 17.0f, BREATH_SIGNIFICANT_MAX_DROP_PCT = 45.0f.
   - Configured T50 Recovery Lag Threshold: RECOVERY_LAG_MALODOR_THRESHOLD = 4.2f (4.2s T50 desorption threshold).

3. iOS TAB NAVIGATION, WATCHDOG ALIGNMENT & METHOD SIGNATURES (`MesoSensorDashboard`):
   - Teardown Signature Parity: handleBreathTestCompletion(didSucceed: Bool, failureReason: String? = nil) supports optional failure strings for TIMEOUT / EXHALATION_TOO_WEAK logs.
   - BreathTestState Alignment: Checks .warmingUp (matching BluetoothManager+Types.swift enum) and evaluates bleManager.isConnected directly.
   - Blow Window Timeout Alignment: BMConstants.blowWindowTimeoutSeconds = 32.0s (30s firmware timeout + 2s BLE buffer).
   - Sequence Guarding: processFirmwareStateTransition() rejects late state transition packets (.TESTING_SENSING_BREATH / .RECOVERING_CALCULATING_T50) if breathTestState is no longer active.
   - 3-Second Result Card Highlight Animation: Upon test completion (.completed), VotreAirDashboardView scales top card (+3%) with a green glow overlay for 3 seconds before smoothly fading out.

4. SENSOR STABILIZING & TELEMETRY INGESTION:
   - BME688 Resistance Threshold: transientWarmupVocFloor = 1000 Ohms. Valid ambient readings (> 1000 Ohms) auto-transition breathTestState to .idle.
   - Ambient Freshness Window: maxAmbientSampleAgeSeconds = 300.0s (5 minutes).

5. DESORPTION RECOVERY KINETICS (T50):
   - Formula: R_target50 = R_min + 0.5 * (R_base - R_min).
   - Classification: Fast Recovery (T50 < 4.2s) vs. Slow Recovery (T50 >= 4.2s) for Volatile Sulfur Compounds.
================================================================================