#pragma once

#include <cstdint>

namespace SensorConstants {
    // Valid Ambient Operating Envelope for Reliable Breath Kinetics
    constexpr float MIN_VALID_AMBIENT_TEMP_C        = 10.0f;      // 50 F (blocks winter outdoor condensation skew)
    constexpr float MAX_VALID_AMBIENT_TEMP_C        = 40.0f;      // 104 F (blocks extreme heat skew)
    constexpr float MIN_VALID_AMBIENT_RH_PCT        = 20.0f;      // Blocks arid/freezing outdoor air
    constexpr float MAX_VALID_AMBIENT_RH_PCT        = 85.0f;      // Blocks fog/steam saturation
    constexpr float MIN_VALID_AMBIENT_VOC_OHMS      = 5000.0f;    // Matches HW_MIN_SENSOR_GAS_RES
    constexpr float MAX_VALID_AMBIENT_VOC_OHMS      = 100000000.0f; // Matches iOS maxUnsaturatedVOC (100 MOhm)

    // Moisture & Dry Mouth Boundaries (%)
    constexpr float DRY_MOUTH_MAX_DELTA_RH_PCT      = 3.5f;

    // VOC Drop Delta Boundaries (%)
    constexpr float BREATH_MIN_SIGNIFICANT_DROP_PCT = 6.0f;
    constexpr float BREATH_FRESH_MAX_DROP_PCT       = 17.0f;
    constexpr float BREATH_SIGNIFICANT_MAX_DROP_PCT = 45.0f;

    // Desorption Kinetics Thresholds (Seconds)
    constexpr float RECOVERY_LAG_MALODOR_THRESHOLD  = 4.2f;
    constexpr float RECOVERY_LAG_TIMEOUT_SEC        = 10.0f;
}

enum class BreathResult : uint8_t {
    INVALID_EXHALATION = 0,
    ENVIRONMENT_OUT_OF_RANGE,
    DRY_MOUTH_HYDRATE,
    DRY_MOUTH_VSC_BUILDUP,
    BALANCED_BREATH,
    SETTLE_BREATH,
    SETTLE_BEVERAGE_FOOD_ODOR,
    SOME_BEVERAGE_FOOD_ODOR,
    NOTICEABLE_MALODOR,
    STRONG_MALODOR
};

bool isAmbientEnvironmentValid(float tempC, float humidityPct, float gasResOhms);

enum class BreathScenario : uint8_t {
    INVALID_EXHALATION = 0,
    DRY_MOUTH_FAST_RECOVERY,
    DRY_MOUTH_SLOW_RECOVERY,
    NEGLIGIBLE_DROP_FAST_RECOVERY,
    NEGLIGIBLE_DROP_SLOW_RECOVERY,
    SUB_THRESHOLD_FAST_RECOVERY,
    SUB_THRESHOLD_SLOW_RECOVERY,
    MODERATE_DROP_FAST_RECOVERY,
    MODERATE_DROP_SLOW_RECOVERY,
    SEVERE_DROP_FAST_RECOVERY,
    SEVERE_DROP_SLOW_RECOVERY
};

BreathScenario classifyScenario(float deltaDrop, float maxDeltaHumidity, float recoveryLagSec);
BreathResult evaluateBreathResult(float deltaDrop, float maxDeltaHumidity, float recoveryLagSec);
const char* breathResultToString(BreathResult result);