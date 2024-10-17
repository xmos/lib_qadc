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

#include "qadc.h"
#include "qadc_utils.h"

#define debprintf(...) printf(...) 

typedef enum adc_state_t{
        ADC_STOPPED = 3,
        ADC_IDLE = 2,
        ADC_CHARGING = 1,
        ADC_CONVERTING = 0 // Optimisation as ISA can do != 0 on select guard
}adc_state_t;

typedef enum adc_mode_t{
        ADC_CONVERT = 0,
        ADC_CALIBRATION_MANUAL,
        ADC_CALIBRATION_AUTO        // WIP
}adc_mode_t;

static inline uint16_t post_process_result( uint16_t discharge_elapsed_time,
                                            size_t adc_steps,
                                            uint16_t *zero_offset_ticks,
                                            uint16_t max_discharge_period_ticks,
                                            uint16_t * unsafe max_scale,
                                            uint16_t * unsafe max_seen_ticks,
                                            uint16_t * unsafe conversion_history,
                                            uint16_t * unsafe hysteris_tracker,
                                            size_t result_history_depth,
                                            unsigned result_hysteresis,
                                            unsigned adc_idx,
                                            unsigned num_ports,
                                            adc_mode_t adc_mode
                                            ){

    unsafe{
        // Apply filter. First populate filter history.
        static unsigned filter_write_idx = 0;
        static unsigned filter_stable = 0;
        unsigned offset = adc_idx * result_history_depth + filter_write_idx;
        *(conversion_history + offset) = discharge_elapsed_time;
        if(adc_idx == num_ports - 1){
            if(++filter_write_idx == result_history_depth){
                filter_write_idx = 0;
                filter_stable = 1;
            }
        }
        // Moving average filter
        int accum = 0;
        uint16_t * unsafe hist_ptr = conversion_history + adc_idx * result_history_depth;
        for(int i = 0; i < result_history_depth; i++){
            accum += *hist_ptr;
            hist_ptr++;
        }
        uint16_t filtered_elapsed_time = accum / result_history_depth;

        // Remove zero offset and clip negative
        int zero_offsetted_ticks = filtered_elapsed_time - *zero_offset_ticks;
        if(zero_offsetted_ticks < 0){
            if(filter_stable){
                // *zero_offset_ticks += (zero_offsetted_ticks / 2); // Move zero offset halfway to compensate gradually
            }
            zero_offsetted_ticks = 0;
        }

        // Track maximums
        if(zero_offsetted_ticks > max_seen_ticks[adc_idx]){
            max_seen_ticks[adc_idx] = zero_offsetted_ticks;
            // Scale here if using calib
            // max_scale[adc_idx] = max_seen_ticks[adc_idx] << QADC_Q_3_13_SHIFT / max_discharge_period_ticks or something
        }
        printf("max_seen: %u\n", max_seen_ticks[adc_idx]);

        // TODO scale to max or just use max seen and remove max_scale?
        // ticks = ((int64_t)max_scale_up * (int64_t)ticks) >> QADC_Q_3_13_SHIFT;

        // Clip positive
        if(zero_offsetted_ticks > max_discharge_period_ticks){
            zero_offsetted_ticks = max_discharge_period_ticks;
        }


        // Calculate scaled output
        uint16_t scaled_result = 0;
        scaled_result = ((adc_steps - 1) * zero_offsetted_ticks) / max_discharge_period_ticks;

        // Apply hysteresis
        if(scaled_result > hysteris_tracker[adc_idx] + result_hysteresis || scaled_result == (adc_steps - 1)){
            hysteris_tracker[adc_idx] = scaled_result;
        }
        if(scaled_result < hysteris_tracker[adc_idx] - result_hysteresis || scaled_result == 0){
            hysteris_tracker[adc_idx] = scaled_result;
        }

        scaled_result = hysteris_tracker[adc_idx];

        return scaled_result;
    }
}


// TODO make weak in C
// static uint16_t stored_max[ADC_MAX_NUM_CHANNELS] = {0};
// int adc_save_calibration(unsigned max_offsetted_conversion_time[], unsigned num_ports)
// {
//     for(int i = 0; i < num_ports; i++){
//         stored_max[i] = max_offsetted_conversion_time[i];
//     }

//     return 0; // Success
// }

// int adc_load_calibration(unsigned max_offsetted_conversion_time[], unsigned num_ports)
// {
//     for(int i = 0; i < num_ports; i++){
//         max_offsetted_conversion_time[i] = stored_max[i];
//     }

//     return 0; // Success
// }


void qadc_rheo_init( port p_adc[],
                    size_t num_adc,
                    size_t adc_steps, 
                    size_t filter_depth,
                    unsigned result_hysteresis,
                    uint16_t *state_buffer,
                    qadc_config_t adc_config,
                    qadc_rheo_state_t &adc_rheo_state) {
    unsafe{
        memset(state_buffer, 0, QADC_RHEO_STATE_SIZE(num_adc, filter_depth) * sizeof(uint16_t));

        adc_rheo_state.num_adc = num_adc;
        adc_rheo_state.filter_depth = filter_depth;
        adc_rheo_state.adc_steps = adc_steps;
        adc_rheo_state.result_hysteresis = result_hysteresis;
        adc_rheo_state.port_time_offset = 32; // Tested at 120MHz thread speed

        // Copy config
        adc_rheo_state.adc_config.capacitor_pf = adc_config.capacitor_pf;
        adc_rheo_state.adc_config.potentiometer_ohms = adc_config.potentiometer_ohms;
        adc_rheo_state.adc_config.resistor_series_ohms = adc_config.resistor_series_ohms;
        adc_rheo_state.adc_config.v_rail = adc_config.v_rail;
        adc_rheo_state.adc_config.v_thresh = adc_config.v_thresh;
        adc_rheo_state.adc_config.convert_interval_ticks = adc_config.convert_interval_ticks;
        adc_rheo_state.adc_config.auto_scale = adc_config.auto_scale;

        // Calc

        const float v_rail = adc_config.v_rail;
        const float v_thresh = adc_config.v_thresh;
        const float r_rheo_max = adc_config.potentiometer_ohms;
        const float capacitor_f = adc_config.capacitor_pf / 1e12;

        // Calculate actual charge voltage of capacitor
        const float v_charge_h = r_rheo_max / (r_rheo_max + adc_config.resistor_series_ohms) * v_rail;
        // printf("v_charge_h: %f\n", v_charge_h);
        
        // Calc the maximum discharge time to threshold
        const float v_down_offset = v_rail - v_charge_h;
        const float t_down = (-r_rheo_max) * capacitor_f * log(1 - (v_rail - v_thresh - v_down_offset) / (v_rail - 0.0 - v_down_offset));  
        // printf("t_down: %f\n", t_down);

        const unsigned t_down_ticks = (unsigned)(t_down * XS1_TIMER_HZ);
        adc_rheo_state.max_disch_ticks = t_down_ticks;
        assert(adc_rheo_state.max_disch_ticks * 2 < 65536); // We have a 16b port timer, so if max is more than this, then we need to slow clock or lower
        // printf("max_disch_ticks: %u\n", adc_rheo_state.max_disch_ticks);

        // Initialise pointers into state buffer blob
        uint16_t * unsafe ptr = state_buffer;
        adc_rheo_state.results = ptr;
        ptr += num_adc;
        adc_rheo_state.conversion_history = ptr;
        ptr += filter_depth * num_adc;
        adc_rheo_state.hysteris_tracker = ptr;
        ptr += num_adc;
        adc_rheo_state.max_seen_ticks = ptr;
        ptr += num_adc;
        adc_rheo_state.max_scale = ptr;
        ptr += num_adc;

        unsigned limit = (unsigned)state_buffer + sizeof(uint16_t) * QADC_RHEO_STATE_SIZE(num_adc, filter_depth);
        assert(ptr == limit);

        // Set scale and clear tide marks
        for(int i = 0; i < num_adc; i++){
            adc_rheo_state.max_scale[i] = 1 << QADC_Q_3_13_SHIFT;
            adc_rheo_state.max_seen_ticks[i] = 0;
        }
    }
}


void qadc_rheo_task(chanend c_adc, port p_adc[], qadc_rheo_state_t &adc_rheo_state){
    printf("adc_rheo_task\n");
  
    // Current conversion index
    unsigned adc_idx = 0;
    adc_mode_t adc_mode = ADC_CONVERT;


    timer tmr_charge;
    timer tmr_discharge;
    timer tmr_overshoot;

    // Set all ports to input and set drive strength
    const int port_drive = DRIVE_2MA;
    for(int i = 0; i < adc_rheo_state.num_adc; i++){
        unsigned dummy;
        p_adc[i] :> dummy;
        set_pad_properties(p_adc[i], port_drive, PULL_NONE, 0, 0);

    }

    const uint32_t convert_interval_ticks = adc_rheo_state.adc_config.convert_interval_ticks;


    const unsigned capacitor_pf = adc_rheo_state.adc_config.capacitor_pf;
    const unsigned resistor_series_ohms = adc_rheo_state.adc_config.resistor_series_ohms;
    const int rc_times_to_charge_fully = 10; // 5 RC times should be sufficient but use double for best scaling
    const uint32_t max_charge_period_ticks = ((uint64_t)rc_times_to_charge_fully * capacitor_pf * resistor_series_ohms) / 10000;

    assert(convert_interval_ticks > max_charge_period_ticks + adc_rheo_state.max_disch_ticks * 2); // Ensure conversion rate is low enough. *2 to allow post processing time
    printf("max_charge_period_ticks: %lu max_discharge_period_ticks: %lu\n", max_charge_period_ticks, adc_rheo_state.max_disch_ticks);


 
    adc_state_t adc_state = ADC_IDLE;

    // Set init time for charge
    int time_trigger_charge = 0;
    tmr_charge :> time_trigger_charge;
    time_trigger_charge += max_charge_period_ticks; // start in one conversion period's
    
    int time_trigger_discharge = 0;
    int time_trigger_overshoot = 0;

    int16_t start_time = 0, end_time = 0;

    while(1){
        select{
            case adc_state == ADC_IDLE => tmr_charge when timerafter(time_trigger_charge) :> int _:

                time_trigger_discharge = time_trigger_charge + max_charge_period_ticks;
                p_adc[adc_idx] <: 0x1;
                adc_state = ADC_CHARGING;
            break;

            case adc_state == ADC_CHARGING => tmr_discharge when timerafter(time_trigger_discharge) :> int _:
                p_adc[adc_idx] :> int _ @ start_time; // Make Hi Z and grab time
                time_trigger_overshoot = time_trigger_discharge + adc_rheo_state.max_disch_ticks * 2;

                adc_state = ADC_CONVERTING;
            break;

            case adc_state == ADC_CONVERTING => p_adc[adc_idx] when pinseq(0x0) :> int _ @ end_time:
                int32_t conversion_time = (end_time - start_time);
                if(conversion_time < 0){
                    conversion_time += 0x10000; // Account for port timer wrapping
                }
                int t0, t1;
                tmr_charge :> t0; 
                uint16_t post_proc_result = post_process_result(conversion_time,
                                                                adc_rheo_state.adc_steps,
                                                                &adc_rheo_state.port_time_offset,
                                                                adc_rheo_state.max_disch_ticks,
                                                                adc_rheo_state.max_scale,
                                                                adc_rheo_state.max_seen_ticks,
                                                                adc_rheo_state.conversion_history,
                                                                adc_rheo_state.hysteris_tracker,
                                                                adc_rheo_state.filter_depth,
                                                                adc_rheo_state.result_hysteresis,
                                                                adc_idx,
                                                                adc_rheo_state.num_adc,
                                                                adc_mode);
                unsafe{adc_rheo_state.results[adc_idx] = post_proc_result;}
                tmr_charge :> t1; 
                printf("ticks: %u post_proc: %u: proc_ticks: %d\n", conversion_time, post_proc_result, t1-t0);


                if(++adc_idx == adc_rheo_state.num_adc){
                    adc_idx = 0;
                }
                time_trigger_charge += convert_interval_ticks;

                adc_state = ADC_IDLE;
            break;

            case (adc_state == ADC_CONVERTING || adc_state == ADC_STOPPED)=> tmr_overshoot when timerafter(time_trigger_overshoot) :> int _:
                p_adc[adc_idx] :> int _ @ end_time;
                unsafe{adc_rheo_state.results[adc_idx] = adc_rheo_state.adc_steps - 1;}
                printf("ticks: %u overshoot \n", end_time - start_time);
                if(++adc_idx == adc_rheo_state.num_adc){
                    adc_idx = 0;
                }
                time_trigger_charge += convert_interval_ticks;

                adc_state = ADC_IDLE;
            break;

            case c_adc :> uint32_t command:
                switch(command & QADC_CMD_MASK){
                    case QADC_CMD_READ:
                        uint32_t ch = command & (~QADC_CMD_MASK);
                        printf("read ch: %lu \n", ch);
                        unsafe{c_adc <: (uint32_t)adc_rheo_state.results[ch];}
                    break;
                    case QADC_CMD_STOP_CONV:
                        for(int i = 0; i < adc_rheo_state.num_adc; i++){
                            p_adc[i] :> int _;
                        }
                        adc_state = ADC_STOPPED;
                    break;
                    case QADC_CMD_START_CONV:
                        tmr_charge :> time_trigger_charge;
                        time_trigger_charge += max_charge_period_ticks; // start in one conversion period's
                        // Clear all history apart from scaling
                        memset(adc_rheo_state.results, 0, adc_rheo_state.hysteris_tracker - adc_rheo_state.results);
                        adc_state = ADC_IDLE;
                    break;
                    case QADC_CMD_EXIT:
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


