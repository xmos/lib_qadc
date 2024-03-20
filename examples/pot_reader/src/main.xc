// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "adc_pot.h"

#define NUM_ADC 1

on tile[0]: port p_adc[] = {XS1_PORT_1A, XS1_PORT_1D}; // Sets which pins are to be used (channels 0..n)  // X0D00, 11;


void control_task(chanend c_adc){
    while(1){
        uint32_t adc[NUM_ADC];
        uint32_t adc_dir[NUM_ADC];
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            c_adc <: (uint32_t)ADC_CMD_READ | ch;
            c_adc :> adc[ch];
            c_adc <: (uint32_t)ADC_CMD_POT_GET_DIR | ch;
            c_adc :> adc_dir[ch];

            printf("Read channel %u: %u (%u)\n", ch, adc[ch], adc_dir[ch]);
            delay_milliseconds(1000);
        }
    }
}

// extern float find_threshold_level(float v_rail, port p);

int main() {
    chan c_adc;

    const unsigned capacitor_pf = 4000;
    const unsigned resistor_ohms = 47000; // nominal maximum value ned to end
    const unsigned resistor_series_ohms = 470;

    const float v_rail = 3.3;
    const float v_thresh = 1.14;
    
    const adc_pot_config_t adc_config = {capacitor_pf, resistor_ohms, resistor_series_ohms, v_rail, v_thresh};

    par
    {
        adc_pot_task(c_adc, p_adc, NUM_ADC, adc_config);
        control_task(c_adc);
    }
    return 0;
}
