#include "breath_kinetics_engine.h"

BreathScenario classifyScenario(float deltaDrop, float maxDeltaHumidity, float recoveryLagSec) {
    const bool isSlowRecovery = (recoveryLagSec >= SensorConstants::RECOVERY_LAG_MALODOR_THRESHOLD);
    const bool validMoisture  = (maxDeltaHumidity >= SensorConstants::DRY_MOUTH_MAX_DELTA_RH_PCT);

    // 1. Dry Mouth Branch: Low humidity accepted if gas drop confirms oral exposure
    if (!validMoisture) {
        const bool hasSecondaryMarker = (deltaDrop >= SensorConstants::BREATH_FRESH_MAX_DROP_PCT);
        if (!hasSecondaryMarker) {
            return BreathScenario::INVALID_EXHALATION;
        }
        return isSlowRecovery ? BreathScenario::DRY_MOUTH_SLOW_RECOVERY 
                              : BreathScenario::DRY_MOUTH_FAST_RECOVERY;
    }

    // 2. Gas Drop Boundaries
    if (deltaDrop < SensorConstants::BREATH_MIN_SIGNIFICANT_DROP_PCT) {
        return isSlowRecovery ? BreathScenario::NEGLIGIBLE_DROP_SLOW_RECOVERY 
                              : BreathScenario::NEGLIGIBLE_DROP_FAST_RECOVERY;
    }

    if (deltaDrop < SensorConstants::BREATH_FRESH_MAX_DROP_PCT) {
        return isSlowRecovery ? BreathScenario::SUB_THRESHOLD_SLOW_RECOVERY 
                              : BreathScenario::SUB_THRESHOLD_FAST_RECOVERY;
    }

    if (deltaDrop < SensorConstants::BREATH_SIGNIFICANT_MAX_DROP_PCT) {
        return isSlowRecovery ? BreathScenario::MODERATE_DROP_SLOW_RECOVERY 
                              : BreathScenario::MODERATE_DROP_FAST_RECOVERY;
    }

    return isSlowRecovery ? BreathScenario::SEVERE_DROP_SLOW_RECOVERY 
                          : BreathScenario::SEVERE_DROP_FAST_RECOVERY;
}

BreathResult evaluateBreathResult(float deltaDrop, float maxDeltaHumidity, float recoveryLagSec) {
    const BreathScenario scenario = classifyScenario(deltaDrop, maxDeltaHumidity, recoveryLagSec);

    switch (scenario) {
        case BreathScenario::INVALID_EXHALATION:
            return BreathResult::INVALID_EXHALATION;

        case BreathScenario::DRY_MOUTH_FAST_RECOVERY:
            return BreathResult::DRY_MOUTH_HYDRATE;

        case BreathScenario::DRY_MOUTH_SLOW_RECOVERY:
            return BreathResult::DRY_MOUTH_VSC_BUILDUP;

        case BreathScenario::NEGLIGIBLE_DROP_FAST_RECOVERY:
            return BreathResult::BALANCED_BREATH;

        case BreathScenario::NEGLIGIBLE_DROP_SLOW_RECOVERY:
            return BreathResult::SETTLE_BREATH;

        case BreathScenario::SUB_THRESHOLD_FAST_RECOVERY:
            return BreathResult::BALANCED_BREATH;

        case BreathScenario::SUB_THRESHOLD_SLOW_RECOVERY:
            return BreathResult::SETTLE_BEVERAGE_FOOD_ODOR;

        case BreathScenario::MODERATE_DROP_FAST_RECOVERY:
        case BreathScenario::SEVERE_DROP_FAST_RECOVERY:
            return BreathResult::SOME_BEVERAGE_FOOD_ODOR;

        case BreathScenario::MODERATE_DROP_SLOW_RECOVERY:
            return BreathResult::NOTICEABLE_MALODOR;

        case BreathScenario::SEVERE_DROP_SLOW_RECOVERY:
            return BreathResult::STRONG_MALODOR;
    }

    return BreathResult::INVALID_EXHALATION;
}

const char* breathResultToString(BreathResult result) {
    switch (result) {
        case BreathResult::INVALID_EXHALATION:        return "INVALID_EXHALATION";
        case BreathResult::DRY_MOUTH_HYDRATE:         return "DRY_MOUTH_HYDRATE";
        case BreathResult::DRY_MOUTH_VSC_BUILDUP:     return "DRY_MOUTH_VSC_BUILDUP";
        case BreathResult::BALANCED_BREATH:           return "BALANCED_BREATH";
        case BreathResult::SETTLE_BREATH:             return "SETTLE_BREATH";
        case BreathResult::SETTLE_BEVERAGE_FOOD_ODOR: return "SETTLE_BEVERAGE_FOOD_ODOR";
        case BreathResult::SOME_BEVERAGE_FOOD_ODOR:   return "SOME_BEVERAGE_FOOD_ODOR";
        case BreathResult::NOTICEABLE_MALODOR:        return "NOTICEABLE_MALODOR";
        case BreathResult::STRONG_MALODOR:            return "STRONG_MALODOR";
    }
    return "UNKNOWN";
}