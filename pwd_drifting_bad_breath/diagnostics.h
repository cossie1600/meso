#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#include <Arduino.h>

/**
 * @brief Executes an on-demand diagnostic self-test to verify I2C soft reset,
 *        selectivity binary loading, BSEC_SAMPLE_RATE_SCAN callbacks, and ULP recovery.
 * 
 * @return true if all 5 diagnostic steps pass; false otherwise.
 */
bool runSelectivityDiagnosticTest();

#endif // DIAGNOSTICS_H