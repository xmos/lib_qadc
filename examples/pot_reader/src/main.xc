// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "adc_pot.h"

#define NUM_ADC         2
#define LUT_SIZE        1024
#define FILTER_DEPTH    8
#define HYSTERESIS      1

on tile[1]: port p_adc[] = {XS1_PORT_1M, XS1_PORT_1O}; // Sets which pins are to be used (channels 0..n) X1D36/38


void control_task(chanend c_adc){
    unsigned counter = 0;

    while(1){
        uint32_t adc[NUM_ADC];
        uint32_t adc_dir[NUM_ADC];

        printf("Read channel ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            c_adc <: (uint32_t)ADC_CMD_READ | ch;
            c_adc :> adc[ch];
            c_adc <: (uint32_t)ADC_CMD_POT_GET_DIR | ch;
            c_adc :> adc_dir[ch];

            printf("%u: %u (%u), ", ch, adc[ch], adc_dir[ch]);
        }
        putchar('\n');
        delay_milliseconds(100);

        // Optionally pause so we can read pot voltage for testing
        if(counter == 10){
            printf("Restarting ADC...\n");
            c_adc <: (uint32_t)ADC_CMD_POT_STOP_CONV;
            delay_milliseconds(1000); // Time to read the actual pot voltage
            c_adc <: (uint32_t)ADC_CMD_POT_START_CONV;
            counter = 0;
            delay_milliseconds(100);
        }
    }
}

void adc_pot_single_example(port p_adc[], adc_pot_state_t &adc_pot_state){
    printf("Hello!\n");

    int t0, t1; // For timing the ADC read
    timer tmr;

    while(1){
        uint32_t adc[NUM_ADC];

        printf("Read ADC ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            // This blocks until the conversion is complete
            tmr :> t0;
            adc[ch] = adc_pot_single(p_adc, ch, adc_pot_state);
            tmr :> t1;
            printf("%u: %u (milliseconds: %d), ", ch, adc[ch], (t1 - t0) / XS1_TIMER_KHZ);
        }
        putchar('\n');
    }

}


int main() {
    par{
        on tile[1]:{
            printf("Running QADC Pot reader. API = %s\n", CONTINUOUS == 1 ? "CONTINUOUS" : "SINGLE");


            const unsigned capacitor_pf = 8800;
            const unsigned potentiometer_ohms = 10000; // nominal maximum value ned to end
            const unsigned resistor_series_ohms = 220;

            const float v_rail = 3.3;
            const float v_thresh = 1.15;
            const char auto_scale = 1;

            const unsigned convert_interval_ticks = (1 * XS1_TIMER_KHZ);
            
            const adc_pot_config_t adc_config = {capacitor_pf,
                                                potentiometer_ohms,
                                                resistor_series_ohms,
                                                v_rail,
                                                v_thresh,
                                                convert_interval_ticks,
                                                auto_scale};
            adc_pot_state_t adc_pot_state;

            uint16_t state_buffer[ADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];
            unsigned used_filter_depth = CONTINUOUS == 1 ? FILTER_DEPTH : 1;
            adc_pot_init(NUM_ADC, LUT_SIZE, used_filter_depth, HYSTERESIS, state_buffer, adc_config, adc_pot_state);

#if (CONTINUOUS == 1)
            chan c_adc;

            par
            {
                adc_pot_task(c_adc, p_adc, adc_pot_state);
                control_task(c_adc);
            }
#else
            adc_pot_single_example(p_adc, adc_pot_state);
#endif
        }
    }

    return 0;
}
