// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xcore/hwtimer.h>
#include "qadc.h"

void qadc_rheo_init_c(  port p_adc[],
                        size_t num_adc,
                        size_t adc_steps, 
                        size_t filter_depth,
                        unsigned result_hysteresis,
                        uint16_t *state_buffer,
                        qadc_config_t adc_config,
                        qadc_rheo_state_t *adc_rheo_state) {
    
    hwtimer_realloc_xc_timer();

    for(int i = 0; i < num_adc; i++){
        port_enable(p_adc[i]);
    }

    qadc_rheo_init(p_adc, num_adc, adc_steps, filter_depth, result_hysteresis, state_buffer, adc_config, adc_rheo_state);
}

void qadc_pot_init_c(   port p_adc[], 
                        size_t num_adc,
                        size_t lut_size,
                        size_t filter_depth,
                        unsigned result_hysteresis,
                        uint16_t *state_buffer,
                        qadc_config_t adc_config,
                        qadc_pot_state_t *adc_pot_state) {
    hwtimer_realloc_xc_timer();

    for(int i = 0; i < num_adc; i++){
        port_enable(p_adc[i]);
    }

    qadc_pot_init(p_adc, num_adc, lut_size, filter_depth, result_hysteresis, state_buffer, adc_config, adc_pot_state);
}