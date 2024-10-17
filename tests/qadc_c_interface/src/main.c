// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <print.h>


#include "adc_pot.h"
// #include "adc_rheo.h"
#include "filter_settings.h"


port_t p_adc[] = {XS1_PORT_1A, XS1_PORT_1B};

DECLARE_JOB(client, (chanend_t));
void client(chanend_t c_adc){
    printstr("Client 0\n");
    chan_out_word(c_adc, (uint32_t)ADC_CMD_POT_EXIT);
    printstr("Client 1\n");
}


int main(void){
    const adc_pot_config_t adc_config = {5000,
                                        47000,
                                        330,
                                        3.3,
                                        1.15,
                                        1 * XS1_TIMER_KHZ,
                                        1};

    channel_t c_adc = chan_alloc();

    port_enable(p_adc[0]);
    port_enable(p_adc[1]);

    adc_pot_state_t adc_pot_state;

    uint16_t state_buffer[ADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];

    printstr("Init 0\n");
    adc_pot_init(p_adc, NUM_ADC, LUT_SIZE, FILTER_DEPTH, HYSTERESIS, state_buffer, adc_config, &adc_pot_state);
    printstr("Init 1\n");

    PAR_JOBS(
        PJOB(adc_pot_task, (c_adc.end_a, p_adc, &adc_pot_state)),
        PJOB(client, (c_adc.end_b))
    );

    printstr("Fin\n");
    return 0;
}
