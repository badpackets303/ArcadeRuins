//  Storage behind AKSettings.
//
//  AKSettings' rich API is Swift (BufferLength and friends), but the Obj-C++ DSP
//  layer needs three of its scalars — AKAudioUnit and S1AudioUnit both read
//  sampleRate, channelCount and rampDuration. Rather than expose a Swift class to
//  Obj-C across a static-library boundary (fragile) or promote S1Support to a
//  framework (an extra binary to embed and sign, which ADR-008 avoids), the
//  storage lives here in C and both languages front it. One source of truth.
//
//  See ADR-010.

#ifndef AK_SETTINGS_BRIDGE_H
#define AK_SETTINGS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

double   ak_settings_sample_rate(void);
void     ak_settings_set_sample_rate(double value);

uint32_t ak_settings_channel_count(void);
void     ak_settings_set_channel_count(uint32_t value);

double   ak_settings_ramp_duration(void);
void     ak_settings_set_ramp_duration(double value);

#ifdef __cplusplus
}
#endif

#endif /* AK_SETTINGS_BRIDGE_H */
