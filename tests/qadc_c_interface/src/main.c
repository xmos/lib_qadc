// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <xcore/hwtimer.h>

#include "qadc.h"

#define NUM_ADC         2
#define LUT_SIZE        64
#define FILTER_DEPTH    4
#define HYSTERESIS      1


port_t p_adc_pot[] = {XS1_PORT_1A, XS1_PORT_1B};
port_t p_adc_rheo[] = {XS1_PORT_1C, XS1_PORT_1D};

DECLARE_JOB(client, (chanend_t, chanend_t));
void client(chanend_t c_adc_pot, chanend_t c_adc_rheo){
    printstr("Client 0\n");
    chan_out_word(c_adc_pot, (uint32_t)QADC_CMD_EXIT);
    printstr("Client 1\n");
    chan_out_word(c_adc_rheo, (uint32_t)QADC_CMD_EXIT);
    printstr("Client 2\n");
}

DECLARE_JOB(qadc_pot_task_wrapper, (chanend_t, port_t *, qadc_config_t));
void qadc_pot_task_wrapper(chanend_t c_adc_pot, port_t *p_adc, qadc_config_t adc_config){
    hwtimer_realloc_xc_timer();
    qadc_pot_state_t adc_pot_state;
    uint16_t state_buffer_pot[QADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];

    for(int i = 0; i < NUM_ADC; i++){
        port_enable(p_adc[i]);
    }

    qadc_pot_init(p_adc_pot, NUM_ADC, LUT_SIZE, FILTER_DEPTH, HYSTERESIS, state_buffer_pot, adc_config, &adc_pot_state);
    printstr("Init 2\n");

    qadc_pot_task(c_adc_pot, p_adc, &adc_pot_state);
}

DECLARE_JOB(qadc_rheo_task_wrapper, (chanend_t, port_t *, qadc_config_t));
void qadc_rheo_task_wrapper(chanend_t c_adc_rheo, port_t *p_adc,  qadc_config_t adc_config){
    hwtimer_realloc_xc_timer();
    qadc_rheo_state_t adc_rheo_state;
    uint16_t state_buffer_rheo[QADC_RHEO_STATE_SIZE(NUM_ADC, FILTER_DEPTH)];
    
    for(int i = 0; i < NUM_ADC; i++){
        port_enable(p_adc[i]);
    }

    qadc_rheo_init(p_adc_rheo, NUM_ADC, 1024, FILTER_DEPTH, HYSTERESIS, state_buffer_rheo, adc_config, &adc_rheo_state);
    printstr("Init 1\n");

    qadc_rheo_task(c_adc_rheo, p_adc, &adc_rheo_state);
}

int main(void){
    const qadc_config_t adc_config = {  2000,
                                        47000,
                                        470,
                                        3.3,
                                        1.15,
                                        1 * XS1_TIMER_KHZ,
                                        1};

    channel_t c_adc_pot = chan_alloc();
    channel_t c_adc_rheo = chan_alloc();

    printstr("Init 0\n");

    PAR_JOBS(
        // PJOB(qadc_pot_task, (c_adc_pot.end_a, p_adc_pot, &adc_pot_state)),
        PJOB(qadc_pot_task_wrapper, (c_adc_pot.end_a, p_adc_pot, adc_config)),
        // PJOB(qadc_rheo_task, (c_adc_rheo.end_a, p_adc_rheo, &adc_rheo_state)),
        PJOB(qadc_rheo_task_wrapper, (c_adc_rheo.end_a, p_adc_rheo, adc_config)),
        PJOB(client, (c_adc_pot.end_b, c_adc_rheo.end_b))
    );

    printstr("Success!\n");
    return 0;
}
