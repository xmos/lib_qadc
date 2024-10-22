// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <xcore/hwtimer.h>

#include "qadc.h"

#define NUM_ADC         2
#define LUT_SIZE        64
#define NUM_STEPS       64
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

DECLARE_JOB(qadc_rheo_task_wrapper, (chanend_t, port_t *, qadc_config_t));
void qadc_rheo_task_wrapper(chanend_t c_adc_rheo, port_t *p_adc,  qadc_config_t adc_config){
    qadc_rheo_state_t adc_rheo_state;
    uint16_t state_buffer_rheo[QADC_RHEO_STATE_SIZE(NUM_ADC, FILTER_DEPTH)];
    qadc_pre_init_c(p_adc_rheo, NUM_ADC);
    qadc_rheo_init(p_adc_rheo, NUM_ADC, NUM_STEPS, FILTER_DEPTH, HYSTERESIS, state_buffer_rheo, adc_config, &adc_rheo_state);
    printstr("Init 1\n");

    qadc_rheo_task(c_adc_rheo, p_adc, &adc_rheo_state);
}

DECLARE_JOB(qadc_pot_task_wrapper, (chanend_t, port_t *, qadc_config_t));
void qadc_pot_task_wrapper(chanend_t c_adc_pot, port_t *p_adc, qadc_config_t adc_config){
    qadc_pot_state_t adc_pot_state;
    uint16_t state_buffer_pot[QADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];

    qadc_pre_init_c(p_adc_pot, NUM_ADC);
    qadc_pot_init(p_adc_pot, NUM_ADC, LUT_SIZE, FILTER_DEPTH, HYSTERESIS, state_buffer_pot, adc_config, &adc_pot_state);
    printstr("Init 2\n");

    qadc_pot_task(c_adc_pot, p_adc, &adc_pot_state);
}


int main(void){
    // Note this struct init is parsed in the rst docs
    const qadc_config_t adc_config = {  .capacitor_pf = 2000,
                                        .potentiometer_ohms = 47000,
                                        .resistor_series_ohms = 470,
                                        .v_rail = 3.3,
                                        .v_thresh = 1.15,
                                        .auto_scale = 0,
                                        .convert_interval_ticks = 1 * XS1_TIMER_KHZ};

    channel_t c_adc_pot = chan_alloc();
    channel_t c_adc_rheo = chan_alloc();

    printstr("Init 0\n");

    PAR_JOBS(
        PJOB(qadc_pot_task_wrapper, (c_adc_pot.end_a, p_adc_pot, adc_config)),
        PJOB(qadc_rheo_task_wrapper, (c_adc_rheo.end_a, p_adc_rheo, adc_config)),
        PJOB(client, (c_adc_pot.end_b, c_adc_rheo.end_b))
    );

    printstr("Success!\n");
    return 0;
}
