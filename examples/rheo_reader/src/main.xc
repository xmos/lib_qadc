// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "qadc.h"

#define NUM_ADC         2
#define FILTER_DEPTH    32
#define HYSTERESIS      1
#define NUM_STEPS       1024

on tile[1]: port p_adc[] = {XS1_PORT_1M, XS1_PORT_1O}; // Sets which pins are to be used (channels 0..n) X1D36/38

void qadc_rheo_continuous_example(chanend ?c_adc, uint16_t * unsafe result_ptr){
    printf("Running QADC in continuous mode using dedicated task!\n");

    while(1){
        uint32_t adc[NUM_ADC];

        printf("Read channel ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            if(isnull(c_adc)) unsafe{
                adc[ch] = result_ptr[ch];
                printf("ch %u: %u, ", ch, adc[ch]);

            } else {
                c_adc <: (uint32_t)QADC_CMD_READ | ch;
                c_adc :> adc[ch];

                printf("ch %u: %u, ", ch, adc[ch]);
            }
        }
        putchar('\n');
        delay_milliseconds(100);
    }
}

void qadc_rheo_single_example(port p_adc[], qadc_rheo_state_t &adc_rheo_state){
    printf("Running QADC in single shot mode using function call!\n");

    int t0, t1; // For timing the ADC read
    timer tmr;

    while(1){
        uint32_t adc[NUM_ADC];

        printf("Read ADC ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            // This blocks until the conversion is complete
            tmr :> t0;
            adc[ch] = qadc_rheo_single(p_adc, ch, adc_rheo_state);
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
            const unsigned capacitor_pf = 6800;        // Set the capacitor value here
            const unsigned potentiometer_ohms = 10500; // Set the potenitiometer nominal maximum value (end to end)
            const unsigned resistor_series_ohms = 340; // Set the series resistor value here

            const float v_rail = 3.3;
            const float v_thresh = 1.15;
            const char auto_scale = 0;

            const unsigned convert_interval_ticks = (1 * XS1_TIMER_KHZ);

            const qadc_config_t adc_config = {capacitor_pf,
                                                potentiometer_ohms,
                                                resistor_series_ohms,
                                                v_rail,
                                                v_thresh,
                                                auto_scale,
                                                convert_interval_ticks};

            qadc_rheo_state_t adc_rheo_state;
            uint16_t state_buffer[QADC_RHEO_STATE_SIZE(NUM_ADC, FILTER_DEPTH)];

            // Only use moving average filter if in continuous mode
            unsigned used_filter_depth = (CONTINUOUS == 1) ? FILTER_DEPTH : 1;
            qadc_rheo_init(p_adc, NUM_ADC, NUM_STEPS, used_filter_depth, HYSTERESIS, state_buffer, adc_config, adc_rheo_state);
            
 #if (CONTINUOUS == 1)
// The continuous mode allows for a shared memory interface if the QADC is on the same tile.
#if USE_SHARED_MEMORY
            unsafe {
                uint16_t * unsafe result_ptr = adc_rheo_state.results;

                par
                {
                    qadc_rheo_task(NULL, p_adc, adc_rheo_state);
                    qadc_rheo_continuous_example(NULL, result_ptr);
                }
            }
#else
            chan c_adc;

            par
            {
                qadc_rheo_task(c_adc, p_adc, adc_rheo_state);
                qadc_rheo_continuous_example(c_adc, NULL);
            }
#endif // USE_SHARED_MEMORY
#else
            qadc_rheo_single_example(p_adc, adc_rheo_state);
#endif // (CONTINUOUS == 1)
        }
    }

    return 0;
}
