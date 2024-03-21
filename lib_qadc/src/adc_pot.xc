// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <stdio.h>
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

#include <xs1.h>
#include <platform.h>
#include <print.h>

#include "adc_pot.h"
#include "adc_utils.h"

// #define dprintf(...) printf(__VA_ARGS__) 
#define dprintf(...) 

typedef enum adc_state_t{
        ADC_STOPPED = 3,
        ADC_IDLE = 2,
        ADC_CHARGING = 1,
        ADC_CONVERTING = 0 // Optimisation as ISA can do != 0 on select guard
}adc_state_t;


static inline uint16_t post_process_result( uint16_t raw_result,
                                            uint16_t *unsafe conversion_history,
                                            uint16_t *unsafe hysteris_tracker,
                                            unsigned adc_idx,
                                            size_t num_adc,
                                            size_t result_history_depth,
                                            size_t lookup_size,
                                            unsigned result_hysteresis){
    unsafe{

    static unsigned filter_write_idx = 0;
    static unsigned filter_stable = 0;

    // Apply filter. First populate filter history.
    unsigned offset = adc_idx * result_history_depth + filter_write_idx;
    *(conversion_history + offset) = raw_result;
    if(adc_idx == num_adc - 1){
        if(++filter_write_idx == result_history_depth){
            filter_write_idx = 0;
            filter_stable = 1;
        }
    }

    // Apply moving average filter
    uint32_t accum = 0;
    uint16_t *unsafe hist_ptr = conversion_history + adc_idx * result_history_depth;
    for(int i = 0; i < result_history_depth; i++){
        accum += *hist_ptr;
        hist_ptr++;
    }
    uint16_t filtered_result = (accum / result_history_depth);

    // Apply hysteresis
    if(filtered_result > hysteris_tracker[adc_idx] + result_hysteresis || filtered_result == (lookup_size - 1)){
        hysteris_tracker[adc_idx] = filtered_result;
    }
    if(filtered_result < hysteris_tracker[adc_idx] - result_hysteresis || filtered_result == 0){
        hysteris_tracker[adc_idx] = filtered_result;
    }

    uint16_t filtered_hysteris_result = hysteris_tracker[adc_idx];

    return filtered_hysteris_result;
}
}


void gen_lookup(uint16_t * unsafe up, uint16_t * unsafe down, unsigned num_points,
                float r_ohms, float capacitor_f, float rs_ohms,
                float v_rail, float v_thresh,
                uint32_t *max_lut_ticks_up, uint32_t *max_lut_ticks_down){
    dprintf("gen_lookup\n");
    
    // memset(up, 0, num_points * sizeof(up[0]));
    // memset(down, 0, num_points * sizeof(down[0]));

    *max_lut_ticks_down = 0;
    *max_lut_ticks_up = 0;

    //TODO rs_ohms
    dprintf("r_ohms: %f capacitor_f: %f v_rail: %f v_thresh: %f\n", r_ohms, capacitor_f * 1e12, v_rail, v_thresh);
    const float phi = 1e-10;

    int cross_vref_idx = 0;
    for(unsigned i = 0; i < num_points; i++) unsafe{
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
        float v_pot = (float)i / (num_points - 1) * v_rail + phi;
        float t_down = (-r_parallel) * capacitor_f * log(1 - (v_charge_h - v_thresh) / (v_rail - v_pot));  
        float t_up = (-r_parallel) * capacitor_f * log(1 - ((v_thresh - v_charge_l) / v_pot));

        // Convert to 100MHz timer ticks
        unsigned t_down_ticks = (unsigned)(t_down * XS1_TIMER_HZ);
        unsigned t_up_ticks = (unsigned)(t_up * XS1_TIMER_HZ);

        if(v_pot > v_thresh){
            up[i] = t_up_ticks;
            *max_lut_ticks_up = up[i] > *max_lut_ticks_up ? up[i] : *max_lut_ticks_up;
            if(cross_vref_idx == 0){
                cross_vref_idx = i;
                printf("cross_vref_idx: %u\n", i);
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

static inline unsigned lookup(int is_up, uint16_t ticks, uint16_t * unsafe up, uint16_t * unsafe down, unsigned num_points, unsigned port_time_offset){
    unsigned max_arg = 0;

    if(ticks > port_time_offset){
        ticks -= port_time_offset;
    } else{
        ticks = 0;
    }

    if(is_up) unsafe{
        uint16_t max = 0;
        max_arg = num_points - 1;
        for(int i = num_points - 1; i >= 0; i--){
            if(ticks > up[i]){
                if(up[i] > max){
                    max_arg = i - 1;
                    max = up[i];
                } 
            }
        }
    } else unsafe{
        int16_t max = 0;
        for(int i = 0; i < num_points; i++){
            if(ticks > down[i]){
                if(down[i] > max){
                    max_arg = i;
                    max = up[i];
                }
            }
        }
    }

    return max_arg;
}





void adc_pot_init(size_t num_adc, size_t lut_size, size_t filter_depth, unsigned result_hysteresis, uint16_t *state_buffer, adc_pot_config_t adc_config, adc_pot_state_t &adc_pot_state) {
    unsafe{
    memset(state_buffer, 0, sizeof(uint16_t) * ADC_POT_STATE_SIZE(num_adc, lut_size, filter_depth));

    adc_pot_state.num_adc = num_adc;
    adc_pot_state.lut_size = lut_size;
    adc_pot_state.filter_depth = filter_depth;
    adc_pot_state.result_hysteresis = result_hysteresis;
    adc_pot_state.port_time_offset = 32;

    adc_pot_state.adc_config.capacitor_pf = adc_config.capacitor_pf;
    adc_pot_state.adc_config.resistor_ohms = adc_config.resistor_ohms;
    adc_pot_state.adc_config.resistor_series_ohms = adc_config.resistor_series_ohms;
    adc_pot_state.adc_config.v_rail = adc_config.v_rail;
    adc_pot_state.adc_config.v_thresh = adc_config.v_thresh;

    adc_pot_state.max_scale = 1 << Q_7_24_SHIFT;

    uint16_t * unsafe ptr = state_buffer;
    adc_pot_state.results = ptr;
    ptr += num_adc;
    adc_pot_state.conversion_history = ptr;
    ptr += filter_depth * num_adc;
    adc_pot_state.hysteris_tracker = ptr;
    ptr += num_adc;
    adc_pot_state.cal_up = ptr;
    ptr += lut_size;
    adc_pot_state.cal_down = ptr;
    ptr += lut_size;
    unsigned limit = (unsigned)state_buffer + sizeof(uint16_t) * ADC_POT_STATE_SIZE(num_adc, lut_size, filter_depth);
    assert(ptr == limit);
}
}

unsigned int isSimulation();


void adc_pot_task(chanend c_adc, port p_adc[], adc_pot_state_t &adc_pot_state){
    dprintf("adc_pot_task\n");
  
    // Current conversion index
    unsigned adc_idx = 0;

    timer tmr_charge;
    timer tmr_discharge;
    timer tmr_overshoot;

    // Set all ports to input and set drive strength
    const int port_drive = DRIVE_4MA;
    for(int i = 0; i < adc_pot_state.num_adc; i++){
        unsigned dummy;
        p_adc[i] :> dummy;
        if(!isSimulation()) set_pad_properties(p_adc[i], port_drive, PULL_NONE, 0, 0);

    }

    const unsigned capacitor_pf = adc_pot_state.adc_config.capacitor_pf;
    const unsigned resistor_ohms = adc_pot_state.adc_config.resistor_ohms;
    const unsigned resistor_series_ohms = adc_pot_state.adc_config.resistor_series_ohms;

    const float v_rail = adc_pot_state.adc_config.v_rail;
    const float v_thresh = adc_pot_state.adc_config.v_thresh;

    const int rc_times_to_charge_fully = 5; // 5 RC times should be sufficient to reach rail
    const uint32_t max_charge_period_ticks = ((uint64_t)rc_times_to_charge_fully * capacitor_pf * resistor_ohms / 2) / 10000;

    // assert(ADC_READ_INTERVAL > max_charge_period_ticks + max_discharge_period_ticks * 2); // Ensure conversion rate is low enough. *2 to allow post processing time
    // printintln(ADC_READ_INTERVAL); printintln(max_charge_period_ticks +max_discharge_period_ticks);


    // Generate calibration table
    uint32_t max_lut_ticks_up = 0, max_lut_ticks_down = 0;
    gen_lookup(adc_pot_state.cal_up, adc_pot_state.cal_down, adc_pot_state.lut_size,
                (float)resistor_ohms, (float)capacitor_pf * 1e-12, (float)resistor_series_ohms,
                v_rail, v_thresh,
                &max_lut_ticks_up, &max_lut_ticks_down);
    unsigned overshoot_idx = (unsigned)(v_thresh / v_rail * adc_pot_state.lut_size);
    dprintf("max_charge_period_ticks: %lu max_dis_period_ticks (up/down): (%lu,%lu), overshoot_idx: %u\n", max_charge_period_ticks, max_lut_ticks_up, max_lut_ticks_down, overshoot_idx);

    // For auto-calibrate. TODO
    uint32_t max_seen_ticks_up = 0;
    uint32_t max_seen_ticks_down = 0;

    // Setup initial state
    adc_state_t adc_state = ADC_IDLE;

    // Set init time for charge
    int time_trigger_charge = 0;
    tmr_charge :> time_trigger_charge;
    time_trigger_charge += max_charge_period_ticks; // start in one conversion period
    
    int time_trigger_discharge = 0;
    int time_trigger_overshoot = 0;

    int16_t start_time, end_time;
    unsigned init_port_val[ADC_MAX_NUM_CHANNELS] = {0};

    int32_t max_ticks_expected = 0;

    while(1){
        select{
            case adc_state == ADC_IDLE => tmr_charge when timerafter(time_trigger_charge) :> int _:
                p_adc[adc_idx] :> init_port_val[adc_idx];
                time_trigger_discharge = time_trigger_charge + max_charge_period_ticks;

                p_adc[adc_idx] <: init_port_val[adc_idx] ^ 0x1; // Drive opposite to what we read to "charge"
                max_ticks_expected = init_port_val[adc_idx] != 0 ? (int32_t)max_lut_ticks_up : (int32_t)max_lut_ticks_down;

                adc_state = ADC_CHARGING;
            break;

            case adc_state == ADC_CHARGING => tmr_discharge when timerafter(time_trigger_discharge) :> int _:
                p_adc[adc_idx] :> int _ @ start_time; // Make Hi Z and grab port time
                // Set up an event to handle if port doesn't reach oppositie value. Set at double the max expected time. This is a fairly fatal 
                // event which is caused by mismatch of hardware vs init params
                time_trigger_overshoot = time_trigger_discharge + (max_ticks_expected * 2);

                adc_state = ADC_CONVERTING;
            break;

            case adc_state == ADC_CONVERTING => p_adc[adc_idx] when pinseq(init_port_val[adc_idx]) :> int _ @ end_time:
                int32_t conversion_time = (end_time - start_time);
                if(conversion_time < 0){
                    conversion_time += 0x10000; // Account for port timer wrapping
                }


                // Check for soft overshoot. This is when the actual RC constant is greater than expected.
                if(conversion_time > max_ticks_expected){
                    dprintf("soft overshoot: %d (%d)\n", conversion_time, max_ticks_expected);
                }

                // Update max seen values. Can help track if actual RC constant is less than expected.
                if(init_port_val[adc_idx]){
                    if(conversion_time > max_seen_ticks_up){
                        max_seen_ticks_up = conversion_time;
                    }
                } else {
                    if(conversion_time > max_seen_ticks_down){
                        max_seen_ticks_down = conversion_time;
                    }
                }

                // Check for minimum setting being smaller than port time offset (sets zero and full scale). Minimum time to trigger port select. 
                if(conversion_time < adc_pot_state.port_time_offset){
                    dprintf("Port offset: %lu %lu\n", conversion_time, adc_pot_state.port_time_offset);
                }
                
                int t0, t1;
                tmr_charge :> t0; 

                // Turn time into ADC setting
                uint16_t result = lookup(init_port_val[adc_idx], conversion_time, adc_pot_state.cal_up, adc_pot_state.cal_down, adc_pot_state.lut_size, adc_pot_state.port_time_offset);
                uint16_t post_proc_result = post_process_result(result, adc_pot_state.conversion_history, adc_pot_state.hysteris_tracker, adc_idx, adc_pot_state.num_adc, adc_pot_state.filter_depth, adc_pot_state.lut_size, adc_pot_state.result_hysteresis);
                unsafe{adc_pot_state.results[adc_idx] = post_proc_result;}
                tmr_charge :> t1; 
                dprintf("result: %u post_proc: %u ticks: %u is_up: %d proc_ticks: %d mu: %lu md: %lu\n", result, post_proc_result, conversion_time, init_port_val[adc_idx], t1-t0, max_seen_ticks_up, max_seen_ticks_down);


                if(++adc_idx == adc_pot_state.num_adc){
                    adc_idx = 0;
                }
                time_trigger_charge += ADC_READ_INTERVAL;
                int32_t time_now;
                tmr_charge :> time_now;
                if(timeafter(time_now, time_trigger_charge)){
                    dprintf("Error - Conversion time to short\n");
                }

                adc_state = ADC_IDLE;
            break;

            // This case happens if the hardware RC constant is much higher than expected
            case adc_state == ADC_CONVERTING => tmr_overshoot when timerafter(time_trigger_overshoot) :> int _:
                unsigned overshoot_port_val = 0;
                p_adc[adc_idx] :> overshoot_port_val; // For debug. TODO remove

                uint16_t result = overshoot_idx + (init_port_val[adc_idx] != 0 ? 1 : 0);
                uint16_t post_proc_result = post_process_result(result, adc_pot_state.conversion_history, adc_pot_state.hysteris_tracker, adc_idx, adc_pot_state.num_adc, adc_pot_state.filter_depth, adc_pot_state.lut_size, adc_pot_state.result_hysteresis);
                unsafe{adc_pot_state.results[adc_idx] = post_proc_result;}

                dprintf("result: %u overshoot (ticks>%d) val:%u\n", result, time_trigger_overshoot-time_trigger_discharge, overshoot_port_val);

                if(++adc_idx == adc_pot_state.num_adc){
                    adc_idx = 0;
                }
                time_trigger_charge += ADC_READ_INTERVAL;

                int32_t time_now;
                tmr_charge :> time_now;
                if(timeafter(time_now, time_trigger_charge)){
                    printstr("Error - ADC Conversion time to short\n");
                }

                adc_state = ADC_IDLE;
            break;

            // Handle comms. Only do in charging phase which is quite a long period and non critical
            case adc_state == ADC_CHARGING  || adc_state == ADC_STOPPED => c_adc :> uint32_t command:
                switch(command & ADC_CMD_MASK){
                    case ADC_CMD_READ:
                        uint32_t ch = command & (~ADC_CMD_MASK);
                        unsafe{c_adc <: (uint32_t)adc_pot_state.results[adc_idx];}
                    break;
                    case ADC_CMD_POT_GET_DIR:
                        uint32_t ch = command & (~ADC_CMD_MASK);
                        c_adc <: (uint32_t)init_port_val[ch];
                    break;
                    case ADC_CMD_POT_STOP_CONV:
                        for(int i = 0; i < adc_pot_state.num_adc; i++){
                            p_adc[adc_idx] :> int _;
                        }
                        adc_state = ADC_STOPPED;
                    break;
                    case ADC_CMD_POT_START_CONV:
                        tmr_charge :> time_trigger_charge;
                        time_trigger_charge += max_charge_period_ticks; // start in one conversion period
                        // Clear all history
                        memset(adc_pot_state.results, 0, adc_pot_state.cal_up - adc_pot_state.results);
                        printstrln("restart");
                        adc_state = ADC_IDLE;
                    break;
                    case ADC_CMD_POT_EXIT:
                        return;
                    break;
                    default:
                        assert(0);
                    break;
                }
            break;
        }
    } // while 1
}