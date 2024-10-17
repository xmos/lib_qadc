// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <stdlib.h>


#include "qadc.h"
#include "filter_settings.h"


on tile[0]: port p_adc[] = {XS1_PORT_1A, XS1_PORT_1D}; // Sets which pins are to be used (channels 0..n)  // X0D00, 11;


void parse_cmd_line(qadc_config_t &adc_config, unsigned argc, char * unsafe argv[argc])
{
    for(int i = 1; i < argc; i++){
        printf("Arg %u: %s\n", i, argv[i]);
        if(i == 1){
            adc_config.capacitor_pf = (unsigned)(atoi((char *)argv[i]));
        }
        if(i == 2){
            adc_config.potentiometer_ohms = (unsigned)(atoi((char *)argv[i]));
        }
        if(i == 3){
            adc_config.resistor_series_ohms = (unsigned)(atoi((char *)argv[i]));
        }
        if(i == 4){
            adc_config.v_rail = (float)(atof((char *)argv[i]));
        }
        if(i == 5){
            adc_config.v_thresh = (float)(atof((char *)argv[i]));
        }
        if(i > 5){
            exit(-1);
        }
    }
}



int main(unsigned argc, char * unsafe argv[argc]){

    qadc_config_t adc_config;
    parse_cmd_line(adc_config, argc, argv);
    adc_config.convert_interval_ticks = (1 * XS1_TIMER_KHZ);
    adc_config.auto_scale = 0;

    chan c_adc;

    qadc_pot_state_t adc_pot_state;

    uint16_t state_buffer[QADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];
    qadc_pot_init(p_adc, NUM_ADC, LUT_SIZE, FILTER_DEPTH, HYSTERESIS, state_buffer, adc_config, adc_pot_state);

    par
    {
        qadc_pot_task(c_adc, p_adc, adc_pot_state);
        {
            c_adc <: (uint32_t)ADC_CMD_POT_EXIT;
        }
    }

    FILE * movable fptr = fopen("pot_lut.bin","wb");
    fwrite(state_buffer, sizeof(state_buffer), 1, fptr);
    fclose(move(fptr));

    return 0;
}
