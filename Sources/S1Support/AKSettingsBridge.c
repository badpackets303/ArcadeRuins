#include "AKSettingsBridge.h"

// Defaults match AudioKit 4.9.2's AKSettings.
static double   s_sampleRate    = 44100.0;
static uint32_t s_channelCount  = 2;
static double   s_rampDuration  = 0.0002;

double   ak_settings_sample_rate(void)             { return s_sampleRate; }
void     ak_settings_set_sample_rate(double v)     { s_sampleRate = v; }

uint32_t ak_settings_channel_count(void)           { return s_channelCount; }
void     ak_settings_set_channel_count(uint32_t v) { s_channelCount = v; }

double   ak_settings_ramp_duration(void)           { return s_rampDuration; }
void     ak_settings_set_ramp_duration(double v)   { s_rampDuration = v; }
