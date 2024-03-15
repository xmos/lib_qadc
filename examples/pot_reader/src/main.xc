// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "adc_pot.h"

on tile[0]: port p_adc[] = {XS1_PORT_1A, XS1_PORT_1D}; // Sets which pins are to be used (channels 0..n) and defines channel count.  // X0D00, 11;


void control_task(chanend c_adc){
    while(1){
        delay_milliseconds(1000);
        c_adc <: (uint32_t)ADC_CMD_READ | 0;
        uint32_t adc0;
        c_adc :> adc0;
        printf("%u\n", adc0);
    }
}


int main() {
    chan c_adc;

    par
    {
        adc_pot_task(c_adc, p_adc, 1);
        control_task(c_adc);
    }
    return 0;
}
