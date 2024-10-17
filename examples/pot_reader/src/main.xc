// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "qadc.h"

#define NUM_ADC             2
#define LUT_SIZE            1024
#define FILTER_DEPTH        16
#define HYSTERESIS          1

on tile[1]: port p_adc[] = {XS1_PORT_1M, XS1_PORT_1O}; // Sets which pins are to be used (channels 0..n) X1D36/38


void control_task(chanend ?c_adc, uint16_t * unsafe result_ptr){
    printf("Running QADC in continuous mode using dedicated task!\n");

    unsigned counter = 0;

    while(1){
        uint32_t adc[NUM_ADC];
        uint32_t adc_dir[NUM_ADC];

        printf("Read channel ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            if(isnull(c_adc)) unsafe{
                adc[ch] = result_ptr[ch];
                adc_dir[ch] = 0;

                printf("ch %u: %u, ", ch, adc[ch]);

            } else {
                c_adc <: (uint32_t)QADC_CMD_READ | ch;
                c_adc :> adc[ch];
                c_adc <: (uint32_t)QADC_CMD_POT_GET_DIR | ch; // Get the direction of conversion (from which rail it started)
                c_adc :> adc_dir[ch];

                printf("ch %u: %u (%u), ", ch, adc[ch], adc_dir[ch]);
            }

        }
        putchar('\n');
        delay_milliseconds(100);

        // If using channel comms pause so we can read pot voltage for testing
        if(!isnull(c_adc)){
            if(++counter == 10){
                printf("Restarting ADC...\n");
                c_adc <: (uint32_t)QADC_CMD_STOP_CONV;
                delay_milliseconds(1000); // Time to read the actual pot voltage
                c_adc <: (uint32_t)QADC_CMD_STOP_CONV;
                counter = 0;
                delay_milliseconds(100);
            }
        }
    }
}

void qadc_pot_single_example(port p_adc[], qadc_pot_state_t &adc_pot_state){
    printf("Running QADC in single shot mode using function call!\n");

    int t0, t1; // For timing the ADC read
    timer tmr;

    while(1){
        uint32_t adc[NUM_ADC];

        printf("Read ADC ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            // This blocks until the conversion is complete
            tmr :> t0;
            adc[ch] = qadc_pot_single(p_adc, ch, adc_pot_state);
            tmr :> t1;
            printf("ch %u: %u (microseconds: %d), ", ch, adc[ch], (t1 - t0) / XS1_TIMER_MHZ);
        }
        putchar('\n');
        delay_milliseconds(100);
    }

}


int main() {
    par{
        on tile[1]:{
            const unsigned capacitor_pf = 8800;        // Set the capacitor value here
            const unsigned potentiometer_ohms = 10000; // Set the potenitiometer nominal maximum value (end to end)
            const unsigned resistor_series_ohms = 220; // Set the series resistor value here

            const float v_rail = 3.3;
            const float v_thresh = 1.15;
            const char auto_scale = 1;

            const unsigned convert_interval_ticks = (1 * XS1_TIMER_KHZ); // 1 millisecond
            
            const qadc_config_t adc_config = {capacitor_pf,
                                                potentiometer_ohms,
                                                resistor_series_ohms,
                                                v_rail,
                                                v_thresh,
                                                convert_interval_ticks,
                                                auto_scale};
            qadc_pot_state_t adc_pot_state;

            uint16_t state_buffer[QADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];

            // Only use moving average filter if in continuous mode
            unsigned used_filter_depth = (CONTINUOUS == 1) ? FILTER_DEPTH : 1;
            qadc_pot_init(p_adc, NUM_ADC, LUT_SIZE, used_filter_depth, HYSTERESIS, state_buffer, adc_config, adc_pot_state);

#if (CONTINUOUS == 1)
// The continuous mode allows for a shared memory interface if the QADC is on the same tile.
#if USE_SHARED_MEMORY
            unsafe {
                uint16_t * unsafe result_ptr = adc_pot_state.results;

                par
                {
                    qadc_pot_task(NULL, p_adc, adc_pot_state);
                    control_task(NULL, result_ptr);
                }
            }
#else
            chan c_adc;

            par
            {
                qadc_pot_task(c_adc, p_adc, adc_pot_state);
                control_task(c_adc, NULL);
            }
#endif // USE_SHARED_MEMORY
#else
            qadc_pot_single_example(p_adc, adc_pot_state);
#endif // (CONTINUOUS == 1)
        }
    }

    return 0;
}
