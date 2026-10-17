#pragma once

#include <cstdint>

namespace SensorConstants {
    // Moisture & Dry Mouth Boundaries (%)
    constexpr float DRY_MOUTH_MAX_DELTA_RH_PCT      = 8.0f;

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
    DRY_MOUTH_HYDRATE,
    DRY_MOUTH_VSC_BUILDUP,
    BALANCED_BREATH,
    SETTLE_BREATH,
    SETTLE_BEVERAGE_FOOD_ODOR,
    SOME_BEVERAGE_FOOD_ODOR,
    NOTICEABLE_MALODOR,
    STRONG_MALODOR
};

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