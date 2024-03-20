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

typedef int32_t q7_24_fixed_t;
#define Q_7_24_SHIFT    24


typedef struct adc_pot_state_t{
    // User config
    size_t num_adc;
    unsigned adc_idx;
    size_t lut_size;
    size_t filter_depth;
    unsigned result_hysteresis;
    uint16_t * unsafe results;
    adc_pot_config_t adc_config;

    // Internal state
    uint16_t * unsafe cal_up;
    uint16_t * unsafe cal_down;
    uint32_t max_lut_ticks_up;
    uint32_t max_lut_ticks_down;
    uint32_t max_seen_ticks_up;
    uint32_t max_seen_ticks_down;
    q7_24_fixed_t max_scale;
    uint32_t port_time_offset;
    uint16_t * unsafe conversion_history;
    uint16_t * unsafe hysteris_tracker;
}adc_pot_state_t;




#define ADC_POT_STATE_SIZE(num_adc, lut_size, filter_depth)              (( \
                             (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) * 2 * lut_size) +            \
                             (sizeof(uint16_t) * num_adc * filter_depth) +  \
                             (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) - 1)) / sizeof(uint16_t))


// ADC operation
#define ADC_READ_INTERVAL           (1 * XS1_TIMER_KHZ)   // Time in between individual conversions 1ms with 10nf / 10k is practical minimum
#define LOOKUP_SIZE                 1024                    // Max 4096 to avoid code bloat and slow post processing
#define RESULT_HISTORY_DEPTH        32                     // For filtering raw conversion values. Tradeoff between conversion speed and noise
#define RESULT_HYSTERESIS           2                      // Reduce final output noise. Applies a small "dead zone" to current setting

// Communication protocol
#define ADC_CMD_READ                0x01000000ULL         
#define ADC_CMD_CAL_MODE_START      0x02000000ULL
#define ADC_CMD_CAL_MODE_FINISH     0x03000000ULL
#define ADC_CMD_POT_GET_DIR         0x03000000ULL
#define ADC_CMD_POT_STOP_CONV       0x04000000ULL
#define ADC_CMD_POT_START_CONV      0x05000000ULL
#define ADC_CMD_MASK                0xff000000ULL

#ifdef __XC__
void adc_pot_task(chanend c_adc, port p_adc[], adc_pot_state_t &adc_pot_state);
void adc_pot_init(size_t num_adc, size_t lut_size, size_t filter_depth, unsigned result_hysteresis, uint16_t *state_buffer, adc_pot_config_t adc_config, adc_pot_state_t &adc_pot_state);
#else
DECLARE_JOB(adc_task, (chanend_t, port_t[], size_t));
void adc_pot_task(chanend_t c_adc, port_t p_adc[], size_t num_adc, adc_pot_config_t adc_config);
#endif
