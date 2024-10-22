// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xcore/hwtimer.h>
#include "qadc.h"

void qadc_pre_init_c(port p_adc[], size_t num_adc){
    hwtimer_realloc_xc_timer();

    for(int i = 0; i < num_adc; i++){
        port_enable(p_adc[i]);
    }
}