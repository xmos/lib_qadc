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


typedef struct adc_rheo_config_t{
    unsigned capacitor_pf;
    unsigned potentiometer_ohms; // nominal maximum value end to end
    unsigned resistor_series_ohms;
    float v_rail;
    float v_thresh;
    unsigned convert_interval_ticks;
    char auto_scale;
}adc_rheo_config_t;

typedef uint16_t         q3_13_fixed_t;
#define Q_3_13_SHIFT    13

typedef struct adc_rheo_state_t{
    // User config
    size_t num_adc;
    unsigned adc_idx;
    size_t filter_depth;
    size_t adc_steps;
    unsigned result_hysteresis;
    uint16_t * unsafe results;
    adc_rheo_config_t adc_config;

    // Internal state
    uint16_t max_disch_ticks;
    uint16_t * unsafe max_seen_ticks;
    q3_13_fixed_t * unsafe max_scale;
    unsigned crossover_idx;
    uint16_t port_time_offset;
    uint16_t * unsafe conversion_history;
    uint16_t * unsafe hysteris_tracker;
}adc_rheo_state_t;



// results, filter, hysteresis, max_ticks, scale
#define ADC_RHEO_STATE_SIZE( num_adc, filter_depth)                      (( \
                             (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) * num_adc * filter_depth) +  \
                             (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) - 1)) / sizeof(uint16_t))

// Communication protocol
#define ADC_CMD_READ                0x01000000ULL         
#define ADC_CMD_CAL_MODE_START      0x02000000ULL
#define ADC_CMD_CAL_MODE_FINISH     0x03000000ULL
#define ADC_CMD_STOP_CONV           0x05000000ULL
#define ADC_CMD_START_CONV          0x06000000ULL
#define ADC_CMD_EXIT                0x07000000ULL
#define ADC_CMD_MASK                0xff000000ULL


void adc_rheo_init(size_t num_adc, size_t adc_steps, size_t filter_depth, unsigned result_hysteresis, uint16_t *state_buffer, adc_rheo_config_t adc_config, adc_rheo_state_t &adc_rheo_state);
// uint32_t adc_rheo_single()
#ifdef __XC__
void adc_rheo_task(chanend c_adc, port p_adc[], adc_rheo_state_t &adc_rheo_state);
#else
DECLARE_JOB(adc_task, (chanend_t, port_t[], size_t));
void adc_rheo_task(chanend_t c_adc, port_t p_adc[], size_t num_adc, adc_rheo_state_t adc_rheo_state);
#endif
