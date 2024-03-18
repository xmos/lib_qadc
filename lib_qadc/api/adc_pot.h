// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#pragma once

#include <stdint.h>
#include <stddef.h>
#ifndef __XC__
#include <xcore/parallel.h>
#include <xcore/channel.h>
#include <xcore/port.h>
#endif

// ADC channels count and port declaraions
#define ADC_MAX_NUM_CHANNELS        8

typedef struct adc_pot_config_t{
    unsigned capacitor_pf;
    unsigned resistor_ohms; // nominal maximum value end to end
    unsigned resistor_series_ohms;
    float v_rail;
    float v_thresh;
}adc_pot_config_t;


// ADC operation
#define ADC_READ_INTERVAL           (100 * XS1_TIMER_KHZ)   // Time in between individual conversions 1ms with 10nf / 10k is practical minimum
#define LOOKUP_SIZE                 1024                    // Max 4096 to avoid code bloat and slow post processing
#define RESULT_HISTORY_DEPTH        32                     // For filtering raw conversion values. Tradeoff between conversion speed and noise
#define RESULT_HYSTERESIS           2                      // Reduce final output noise. Applies a small "dead zone" to current setting

// Communication protocol
#define ADC_CMD_READ                0x01000000ULL         
#define ADC_CMD_CAL_MODE_START      0x02000000ULL
#define ADC_CMD_CAL_MODE_FINISH     0x03000000ULL
#define ADC_CMD_MASK                0xff000000ULL

#ifdef __XC__
void adc_pot_task(chanend c_adc, port p_adc[], size_t num_adc, adc_pot_config_t adc_config);
#else
DECLARE_JOB(adc_task, (chanend_t, port_t[], size_t));
void adc_pot_task(chanend_t c_adc, port_t p_adc[], size_t num_adc, adc_pot_config_t adc_config);
#endif
