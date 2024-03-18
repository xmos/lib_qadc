// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <stdio.h>
#include <assert.h>
#include <math.h>
#include <stdint.h>

#include <xs1.h>
#include <platform.h>
#include <print.h>

#include "adc_pot.h"
#include "adc_utils.h"

#define debprintf(...) printf(...) 

typedef enum adc_state_t{
        ADC_IDLE = 2,
        ADC_CHARGING = 1,
        ADC_CONVERTING = 0 // Optimisation as ISA can do != 0 on select guard
}adc_state_t;

typedef enum adc_mode_t{
        ADC_CONVERT = 0,
        ADC_CALIBRATION_MANUAL,
        ADC_CALIBRATION_AUTO        // WIP
}adc_mode_t;

static inline int post_process_result(  int discharge_elapsed_time,
                                        unsigned *zero_offset_ticks,
                                        unsigned max_offsetted_conversion_time[],
                                        int *conversion_history,
                                        int *hysteris_tracker,
                                        unsigned adc_idx,
                                        unsigned num_ports,
                                        adc_mode_t adc_mode){
    const int max_result_scale = LOOKUP_SIZE - 1;

    // Apply filter. First populate filter history.
    static unsigned filter_write_idx = 0;
    static unsigned filter_stable = 0;
    unsigned offset = adc_idx * RESULT_HISTORY_DEPTH + filter_write_idx;
    *(conversion_history + offset) = discharge_elapsed_time;
    if(adc_idx == num_ports - 1){
        if(++filter_write_idx == RESULT_HISTORY_DEPTH){
            filter_write_idx = 0;
            filter_stable = 1;
        }
    }
    // Moving average filter
    int accum = 0;
    int *hist_ptr = conversion_history + adc_idx * RESULT_HISTORY_DEPTH;
    for(int i = 0; i < RESULT_HISTORY_DEPTH; i++){
        accum += *hist_ptr;
        hist_ptr++;
    }
    int filtered_elapsed_time = accum / RESULT_HISTORY_DEPTH;

    // Remove zero offset and clip
    int zero_offsetted_ticks = filtered_elapsed_time - *zero_offset_ticks;
    if(zero_offsetted_ticks < 0){
        if(filter_stable){
            // *zero_offset_ticks += (zero_offsetted_ticks / 2); // Move zero offset halfway to compensate gradually
        }
        zero_offsetted_ticks = 0;
    }

    // Clip count positive
    if(zero_offsetted_ticks > max_offsetted_conversion_time[adc_idx]){
        if(adc_mode == ADC_CALIBRATION_MANUAL){
            max_offsetted_conversion_time[adc_idx] = zero_offsetted_ticks;
        } else {
            zero_offsetted_ticks = max_offsetted_conversion_time[adc_idx];  
        }
    }

    // Calculate scaled output
    int scaled_result = 0;
    if(max_offsetted_conversion_time[adc_idx]){ // Avoid / 0 during calibrate
        scaled_result = (max_result_scale * zero_offsetted_ticks) / max_offsetted_conversion_time[adc_idx];
    }

    // // Clip positive and move max if needed
    // if(scaled_result > max_result_scale){
    //     scaled_result = max_result_scale; // Clip
    //     // Handle moving up the maximum val
    //     if(adc_mode == ADC_CALIBRATION_MANUAL){
    //         int new_max_offsetted_conversion_time = (max_result_scale * zero_offsetted_ticks) / scaled_result;
    //         max_offsetted_conversion_time[adc_idx] += (new_max_offsetted_conversion_time - max_offsetted_conversion_time[adc_idx]);
    //     }
    // }

    // Apply hysteresis
    if(scaled_result > hysteris_tracker[adc_idx] + RESULT_HYSTERESIS || scaled_result == max_result_scale){
        hysteris_tracker[adc_idx] = scaled_result;
    }
    if(scaled_result < hysteris_tracker[adc_idx] - RESULT_HYSTERESIS || scaled_result == 0){
        hysteris_tracker[adc_idx] = scaled_result;
    }

    scaled_result = hysteris_tracker[adc_idx];

    return scaled_result;
}


// TODO make weak in C
static int stored_max[ADC_MAX_NUM_CHANNELS] = {0};
int adc_save_calibration(unsigned max_offsetted_conversion_time[], unsigned num_ports)
{
    for(int i = 0; i < num_ports; i++){
        stored_max[i] = max_offsetted_conversion_time[i];
    }

    return 0; // Success
}

int adc_load_calibration(unsigned max_offsetted_conversion_time[], unsigned num_ports)
{
    for(int i = 0; i < num_ports; i++){
        max_offsetted_conversion_time[i] = stored_max[i];
    }

    return 0; // Success
}




void adc_rheo_task(chanend c_adc, port p_adc[], size_t num_adc, adc_pot_config_t adc_config){
    printf("adc_rheo_task\n");
  
    // Current conversion index
    unsigned adc_idx = 0;
    uint16_t results[ADC_MAX_NUM_CHANNELS] = {0}; // The ADC read values
    adc_mode_t adc_mode = ADC_CONVERT;


    timer tmr_charge;
    timer tmr_discharge;
    timer tmr_overshoot;

    // Set all ports to input and set drive strength
    const int port_drive = DRIVE_4MA;
    for(int i = 0; i < num_adc; i++){
        unsigned dummy;
        p_adc[i] :> dummy;
        set_pad_properties(p_adc[i], port_drive, PULL_NONE, 0, 0);

    }

    const unsigned capacitor_pf = adc_config.capacitor_pf;
    const unsigned resistor_ohms = adc_config.resistor_ohms;
    const unsigned resistor_series_ohms = adc_config.resistor_series_ohms;

    const float v_rail = adc_config.v_rail;
    const float v_thresh = adc_config.v_thresh;

    const unsigned port_time_offset = 30; // How long approx minimum time to trigger port select. Not too critcial a parameter.

    const int rc_times_to_charge_fully = 10; // 5 RC times should be sufficient but double it for best accuracy
    const uint32_t max_charge_period_ticks = ((uint64_t)rc_times_to_charge_fully * capacitor_pf * resistor_series_ohms) / 10000;

    const int num_time_constants_disch_max = 3;
    const uint32_t max_discharge_period_ticks = ((uint64_t)capacitor_pf * num_time_constants_disch_max * resistor_ohms) / 10000;


    assert(ADC_READ_INTERVAL > max_charge_period_ticks + max_discharge_period_ticks * 2); // Ensure conversion rate is low enough. *2 to allow post processing time
    printf("max_charge_period_ticks: %lu max_discharge_period_ticks: %lu\n", max_charge_period_ticks, max_discharge_period_ticks);

    // Calaculate zero offset based on drive strength
    unsigned zero_offset_ticks = 0;
    switch(port_drive){
        case DRIVE_2MA:
            zero_offset_ticks = capacitor_pf * 0.024;
            printstrln("DRIVE_2MA\n");
        break;
        case DRIVE_4MA:
            zero_offset_ticks = capacitor_pf * 0.012;
            printstrln("DRIVE_4MA\n");
        break;
        case DRIVE_8MA:
            zero_offset_ticks = capacitor_pf * 0.008;
            printstrln("DRIVE_8MA\n");
        break;
        case DRIVE_12MA:
            zero_offset_ticks = capacitor_pf * 0.006;
            printstrln("DRIVE_12MA\n");
        break;
    }

    // Calibration for scaling to full scale
    unsigned max_offsetted_conversion_time[ADC_MAX_NUM_CHANNELS] = {0};

    // Initialise all ports and apply estimated max conversion
    for(unsigned i = 0; i < num_adc; i++){
        max_offsetted_conversion_time[i] = 0; //(resistor_ohms_min * capacitor_pf) / 103; // Calibration factor of / 10.35
        set_pad_properties(p_adc[i], port_drive, PULL_NONE, 0, 0);
    }

    // Post processing variables
    uint16_t conversion_history[ADC_MAX_NUM_CHANNELS][RESULT_HISTORY_DEPTH] = {{0}};
    uint16_t hysteris_tracker[ADC_MAX_NUM_CHANNELS] = {0};

 
    adc_state_t adc_state = ADC_IDLE;

    // Set init time for charge
    int time_trigger_charge = 0;
    tmr_charge :> time_trigger_charge;
    time_trigger_charge += max_charge_period_ticks; // start in one conversion period's
    
    int time_trigger_discharge = 0;
    int time_trigger_overshoot = 0;

    int16_t start_time, end_time;
    unsigned init_port_val = 0;

    // We read through different line than the one being discharged
    unsigned p_adc_idx_other = 0;

    printstrln("adc_task");
    while(1){
        select{
            case adc_state == ADC_IDLE => tmr_charge when timerafter(time_trigger_charge) :> int _:

                for(unsigned i = 0; i < num_adc; i++){
                    // port_out(p_adc[i], 1); // Drive a 1 to charge the capacitor via all ines
                } 
                p_adc[adc_idx] :> init_port_val;
                time_trigger_discharge = time_trigger_charge + max_charge_period_ticks;

                p_adc[adc_idx] <: init_port_val ^ 0x1; // Drive opposite to what we read to "charge"
                adc_state = ADC_CHARGING;
            break;

            case adc_state == ADC_CHARGING => tmr_discharge when timerafter(time_trigger_discharge) :> int _:
                p_adc[adc_idx] :> int _ @ start_time; // Make Hi Z and grab time
                time_trigger_overshoot = time_trigger_discharge + max_discharge_period_ticks;

                adc_state = ADC_CONVERTING;
            break;

            case adc_state == ADC_CONVERTING => p_adc[adc_idx] when pinseq(init_port_val) :> int _ @ end_time:
                int32_t conversion_time = (end_time - start_time);
                if(conversion_time < 0){
                    conversion_time += 0x10000; // Account for port timer wrapping
                }
                int t0, t1;
                tmr_charge :> t0; 
                uint16_t result = 0;
                // uint16_t post_proc_result = post_process_result(result, (uint16_t *)conversion_history, hysteris_tracker, adc_idx, num_adc);
                uint16_t post_proc_result = 0;
                results[adc_idx] = post_proc_result;
                tmr_charge :> t1; 
                printf("ticks: %u result: %u post_proc: %u ticks: %u is_up: %d proc_ticks: %d\n", conversion_time, result, post_proc_result, conversion_time, init_port_val, t1-t0);


                if(++adc_idx == num_adc){
                    adc_idx = 0;
                }
                time_trigger_charge += ADC_READ_INTERVAL;

                adc_state = ADC_IDLE;
            break;

            case adc_state == ADC_CONVERTING => tmr_overshoot when timerafter(time_trigger_overshoot) :> int _:
                p_adc[adc_idx] :> int _ @ end_time;
                // printf("result: %u overshoot\n", overshoot_idx);
                if(++adc_idx == num_adc){
                    adc_idx = 0;
                }
                time_trigger_charge += ADC_READ_INTERVAL;

                adc_state = ADC_IDLE;
            break;

            case c_adc :> uint32_t command:
                switch(command & ADC_CMD_MASK){
                    case ADC_CMD_READ:
                        uint32_t ch = command & (~ADC_CMD_MASK);
                        printf("read ch: %lu \n", ch);
                        c_adc <: (uint32_t)results[ch];
                    break;
                    default:
                        assert(0);
                    break;
                }
            break;
        }
    } // while 1
}


