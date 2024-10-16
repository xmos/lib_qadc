// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include <platform.h>
#include "adc_utils.h"

void gen_lookup_pot(uint16_t * up, uint16_t * down, unsigned num_points,
                    float r_ohms, float capacitor_f, float rs_ohms,
                    float v_rail, float v_thresh,
                    uint32_t *max_lut_ticks_up, uint32_t *max_lut_ticks_down){
    dprintf("gen_lookup\n");
    
    memset(up, 0, num_points * sizeof(up[0]));
    memset(down, 0, num_points * sizeof(down[0]));

    *max_lut_ticks_down = 0;
    *max_lut_ticks_up = 0;

    //TODO rs_ohms
    dprintf("r_ohms: %f capacitor_pf: %f v_rail: %f v_thresh: %f\n", r_ohms, capacitor_f * 1e12, v_rail, v_thresh);
    const float phi = 1e-10;

    int cross_vref_idx = 0;
    for(unsigned i = 0; i < num_points; i++){
        // Calculate equivalent resistance of pot
        float r_low = r_ohms * (i + phi) / (num_points - 1);  
        float r_high = r_ohms * ((num_points - i - 1) + phi) / (num_points - 1);  
        float r_parallel = 1 / (1 / r_low + 1 / r_high); // When reading the equivalent resistance of pot is this

        // Calculate equivalent resistances when charging via Rs
        float rp_low = 1 / (1 / r_low + 1 / rs_ohms);
        float rp_high = 1 / (1 / r_high + 1 / rs_ohms);

        // Calculate actual charge voltage of capacitor
        float v_charge_h = r_low / (r_low + rp_high) * v_rail;
        float v_charge_l = rp_low / (rp_low + r_high) * v_rail;

        // Calculate time to for cap to reach threshold from charge volatage
        // https://phys.libretexts.org/Bookshelves/University_Physics/University_Physics_(OpenStax)/Book%3A_University_Physics_II_-_Thermodynamics_Electricity_and_Magnetism_(OpenStax)/10%3A_Direct-Current_Circuits/10.06%3A_RC_Circuits
        float v_pot = (float)i / (num_points - 1) * v_rail + phi;
        float t_up = (-r_parallel) * capacitor_f * log(1 - ((v_thresh - v_charge_l) / (v_pot - v_charge_l)));
        float v_down_offset = v_rail - v_charge_h;
        float t_down = (-r_parallel) * capacitor_f * log(1 - (v_rail - v_thresh - v_down_offset) / (v_rail - v_pot - v_down_offset));  

        // Convert to 100MHz timer ticks
        unsigned t_down_ticks = (unsigned)(t_down * XS1_TIMER_HZ);
        unsigned t_up_ticks = (unsigned)(t_up * XS1_TIMER_HZ);

        if(v_pot > v_thresh){
            up[i] = t_up_ticks;
            *max_lut_ticks_up = up[i] > *max_lut_ticks_up ? up[i] : *max_lut_ticks_up;
            if(cross_vref_idx == 0){
                cross_vref_idx = i;
            }
        } else {
            down[i] = t_down_ticks;
            *max_lut_ticks_down = down[i] > *max_lut_ticks_down ? down[i] : *max_lut_ticks_down;
        }
        dprintf("i: %u r_parallel: %f v_pot: %f v_charge_h: %f v_charge_l: %f t_down: %u t_up: %u\n", i, r_parallel, v_pot, v_charge_h, v_charge_l, down[i] , up[i]);

    }

    dprintf("max_lut_ticks_up: %lu max_lut_ticks_down: %lu\n", *max_lut_ticks_up, *max_lut_ticks_down);

    assert(*max_lut_ticks_up < 65536); // We have a 16b port timer, so if max is more than this, then we need to slow clock or lower RC
    assert(*max_lut_ticks_down < 65536); // We have a 16b port timer, so if max is more than this, then we need to slow clock or lower RC
}
