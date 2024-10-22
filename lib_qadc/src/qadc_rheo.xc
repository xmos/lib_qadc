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

        // Copy config
        adc_rheo_state.adc_config.capacitor_pf = adc_config.capacitor_pf;
        adc_rheo_state.adc_config.potentiometer_ohms = adc_config.potentiometer_ohms;
        adc_rheo_state.adc_config.resistor_series_ohms = adc_config.resistor_series_ohms;
        adc_rheo_state.adc_config.v_rail = adc_config.v_rail;
        adc_rheo_state.adc_config.v_thresh = adc_config.v_thresh;
        adc_rheo_state.adc_config.convert_interval_ticks = adc_config.convert_interval_ticks;
        adc_rheo_state.adc_config.auto_scale = adc_config.auto_scale;

        // Grab vars and scale
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
        adc_rheo_state.filter_write_idx = ptr;
        ptr += num_adc;

        unsigned limit = (unsigned)state_buffer + sizeof(uint16_t) * QADC_RHEO_STATE_SIZE(num_adc, filter_depth);
        assert(ptr == limit);

        // Set scale and clear tide marks
        for(int i = 0; i < num_adc; i++){
            adc_rheo_state.max_scale[i] = 1 << QADC_Q_3_13_SHIFT;
            adc_rheo_state.max_seen_ticks[i] = 0;
        }

        // Set all ports to input and set drive strength to low to reduce switching noise
        const int port_drive = DRIVE_2MA;
        for(int i = 0; i < num_adc; i++){
            unsigned dummy;
            p_adc[i] :> dummy;
            // Simulator doesn't like setc so only do for hardware. isSimulation() takes 100ms or so per port so do here.
            if(!isSimulation()) set_pad_properties(p_adc[i], port_drive, PULL_NONE, 1, 0);
        }
    }
}

static inline uint16_t post_process_result( uint16_t raw_result, unsigned adc_idx, qadc_rheo_state_t &adc_rheo_state, adc_mode_t adc_mode){
  unsafe{
        // Extract vars for readibility
        uint16_t *unsafe conversion_history = adc_rheo_state.conversion_history;
        uint16_t *unsafe hysteris_tracker = adc_rheo_state.hysteris_tracker;
        size_t num_adc = adc_rheo_state.num_adc;
        size_t result_history_depth = adc_rheo_state.filter_depth;
        size_t adc_steps = adc_rheo_state.adc_steps;
        unsigned result_hysteresis = adc_rheo_state.result_hysteresis;
        uint16_t *unsafe filter_write_idx = adc_rheo_state.filter_write_idx;
        uint16_t max_discharge_period_ticks = adc_rheo_state.max_disch_ticks;
        uint16_t * unsafe max_scale = adc_rheo_state.max_scale;
        uint16_t * unsafe max_seen_ticks = adc_rheo_state.max_seen_ticks;

        // Apply filter. First populate filter history.
        unsigned offset = adc_idx * result_history_depth + filter_write_idx[adc_idx];
        *(conversion_history + offset) = raw_result;

        if(++filter_write_idx[adc_idx] == result_history_depth){
            filter_write_idx[adc_idx] = 0;
        }

        // Moving average filter
        int accum = 0;
        uint16_t * unsafe hist_ptr = conversion_history + adc_idx * result_history_depth;
        for(int i = 0; i < result_history_depth; i++){
            accum += *hist_ptr;
            hist_ptr++;
        }
        uint16_t filtered_elapsed_time = accum / result_history_depth;

        // Track maximums
        if(adc_rheo_state.adc_config.auto_scale && (filtered_elapsed_time > max_seen_ticks[adc_idx])){
            max_seen_ticks[adc_idx] = filtered_elapsed_time;
            // Scale here if using calib
            // max_scale[adc_idx] = max_seen_ticks[adc_idx] << QADC_Q_3_13_SHIFT / max_discharge_period_ticks or something
        }
        dprintf("max_seen: %u\n", max_seen_ticks[adc_idx]);

        // TODO scale to max or just use max seen and remove max_scale?
        // ticks = ((int64_t)max_scale_up * (int64_t)ticks) >> QADC_Q_3_13_SHIFT;

        // Clip positive
        if(filtered_elapsed_time > max_discharge_period_ticks){
            filtered_elapsed_time = max_discharge_period_ticks;
        }

        // Calculate scaled output
        uint16_t scaled_result = 0;
        scaled_result = ((adc_steps - 1) * filtered_elapsed_time) / max_discharge_period_ticks;

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


// Struct which contains the various timings and event triggers for the conversion
typedef struct rheo_timings_t{
    int32_t time_trigger_charge;
    int32_t time_trigger_discharge;
    int32_t time_trigger_overshoot;
    int32_t max_ticks_expected;
    uint32_t max_charge_period_ticks;
    uint32_t max_discharge_period_ticks;
    int16_t start_time;
    int16_t end_time;
}rheo_timings_t;


static void do_adc_timing_init(port p_adc[], qadc_rheo_state_t &adc_rheo_state, rheo_timings_t &rheo_timings){

    const uint32_t convert_interval_ticks = adc_rheo_state.adc_config.convert_interval_ticks;
    const unsigned capacitor_pf = adc_rheo_state.adc_config.capacitor_pf;
    const unsigned resistor_series_ohms = adc_rheo_state.adc_config.resistor_series_ohms;
    const int rc_times_to_charge_fully = 5; // 5 RC times should be sufficient but use double for best scaling
    rheo_timings.max_charge_period_ticks = ((uint64_t)rc_times_to_charge_fully * capacitor_pf * resistor_series_ohms) / 10000;

    assert(convert_interval_ticks > rheo_timings.max_charge_period_ticks + adc_rheo_state.max_disch_ticks * 2); // Ensure conversion rate is low enough. *2 to allow post processing time
    dprintf("max_charge_period_ticks: %lu max_discharge_period_ticks: %lu\n", rheo_timings.max_charge_period_ticks, adc_rheo_state.max_disch_ticks);
}


static void do_adc_charge(port p_adc[], unsigned adc_idx, qadc_rheo_state_t &adc_rheo_state, rheo_timings_t &rheo_timings){
    unsafe{
        rheo_timings.time_trigger_discharge = rheo_timings.time_trigger_charge + rheo_timings.max_charge_period_ticks;
        p_adc[adc_idx] <: 0x1;
    }
}


static unsigned do_adc_start_convert(port p_adc[], unsigned adc_idx, qadc_rheo_state_t &adc_rheo_state, rheo_timings_t &rheo_timings){
    unsigned post_charge_port_val = 0;
    rheo_timings.time_trigger_overshoot = rheo_timings.time_trigger_discharge + adc_rheo_state.max_disch_ticks * 2;
    p_adc[adc_idx] :> post_charge_port_val @ rheo_timings.start_time; // Make Hi Z and grab time and value
    // Setup overshoot event

    return post_charge_port_val;
}


static void do_adc_convert(port p_adc[], unsigned adc_idx, qadc_rheo_state_t &adc_rheo_state, rheo_timings_t &rheo_timings, adc_mode_t adc_mode){
    unsafe{
        int32_t conversion_time = (rheo_timings.end_time - rheo_timings.start_time);
        if(conversion_time < 0){
            conversion_time += 0x10000; // Account for port timer wrapping
        }
        int t0, t1;
        timer debug_tmr;
        debug_tmr :> t0; 
        uint16_t post_proc_result = post_process_result(conversion_time,
                                                        adc_idx,
                                                        adc_rheo_state,
                                                        adc_mode);

        unsafe{adc_rheo_state.results[adc_idx] = post_proc_result;}
        debug_tmr :> t1; 
        dprintf("ticks: %u post_proc: %u: proc_ticks: %d\n", conversion_time, post_proc_result, t1-t0);

        const uint32_t convert_interval_ticks = adc_rheo_state.adc_config.convert_interval_ticks;
        rheo_timings.time_trigger_charge += convert_interval_ticks;
    }
}

static void do_adc_handle_overshoot(port p_adc[], unsigned adc_idx, qadc_rheo_state_t &adc_rheo_state, rheo_timings_t &rheo_timings){
    unsafe{
        p_adc[adc_idx] :> int _ @ rheo_timings.end_time;
        unsafe{adc_rheo_state.results[adc_idx] = adc_rheo_state.adc_steps - 1;}
        dprintf("ticks: %u overshoot \n", rheo_timings.end_time - rheo_timings.start_time);

        const uint32_t convert_interval_ticks = adc_rheo_state.adc_config.convert_interval_ticks;
        rheo_timings.time_trigger_charge += convert_interval_ticks;
    }
}


void qadc_rheo_task(chanend ?c_adc, port p_adc[], qadc_rheo_state_t &adc_rheo_state){
    // Current conversion index
    unsigned adc_idx = 0;
    // Mode
    adc_mode_t adc_mode = ADC_CONVERT;

    // Timers for state machine
    timer tmr_charge;
    timer tmr_discharge;
    timer tmr_overshoot;

    // Timing struct
    rheo_timings_t rheo_timings = {0};

    do_adc_timing_init(p_adc, adc_rheo_state, rheo_timings);

    // Setup initial state
    adc_state_t adc_state = ADC_IDLE;

    // Set init time for charge
    tmr_charge :> rheo_timings.time_trigger_charge;
    rheo_timings.time_trigger_charge += rheo_timings.max_charge_period_ticks; // start in one charge period

    // Used for determining the zero offset
    unsigned post_charge_port_val = 0;

    while(1){
        select{
            case adc_state == ADC_IDLE => tmr_charge when timerafter(rheo_timings.time_trigger_charge) :> int _:
                do_adc_charge(p_adc, adc_idx, adc_rheo_state, rheo_timings);

                adc_state = ADC_CHARGING;
            break;

            case adc_state == ADC_CHARGING => tmr_discharge when timerafter(rheo_timings.time_trigger_discharge) :> int _:
                post_charge_port_val = do_adc_start_convert(p_adc, adc_idx, adc_rheo_state, rheo_timings);

                adc_state = ADC_CONVERTING;
            break;

            case adc_state == ADC_CONVERTING => p_adc[adc_idx] when pinseq(0x0) :> int _ @ rheo_timings.end_time:
                if(post_charge_port_val == 0){
                    rheo_timings.end_time = rheo_timings.start_time; // Zero position
                }
                do_adc_convert(p_adc, adc_idx, adc_rheo_state, rheo_timings, adc_mode);
                
                // Cycle through the ADC channels
                if(++adc_idx == adc_rheo_state.num_adc){
                    adc_idx = 0;
                }

                adc_state = ADC_IDLE;
            break;

            case (adc_state == ADC_CONVERTING) => tmr_overshoot when timerafter(rheo_timings.time_trigger_overshoot) :> int _:
                do_adc_handle_overshoot(p_adc, adc_idx, adc_rheo_state, rheo_timings);
                // Cycle through the ADC channels
                if(++adc_idx == adc_rheo_state.num_adc){
                    adc_idx = 0;
                }

                adc_state = ADC_IDLE;
            break;

            case !isnull(c_adc) => c_adc :> uint32_t command:
                switch(command & QADC_CMD_MASK){
                    case QADC_CMD_READ:
                        uint32_t ch = command & (~QADC_CMD_MASK);
                        unsafe{c_adc <: (uint32_t)adc_rheo_state.results[ch];}
                    break;
                    case QADC_CMD_STOP_CONV:
                        for(int i = 0; i < adc_rheo_state.num_adc; i++){
                            p_adc[i] :> int _;
                        }
                        adc_state = ADC_STOPPED;
                    break;
                    case QADC_CMD_START_CONV:
                        tmr_charge :> rheo_timings.time_trigger_charge;
                        rheo_timings.time_trigger_charge += rheo_timings.max_charge_period_ticks; // start in one conversion period's
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

uint16_t qadc_rheo_single(port p_adc[], unsigned adc_idx, qadc_rheo_state_t &adc_rheo_state){
    int16_t result = 0;

    timer tmr_single;

    rheo_timings_t rheo_timings = {0};
    adc_mode_t adc_mode = ADC_CONVERT;

    do_adc_timing_init(p_adc, adc_rheo_state, rheo_timings);
    tmr_single :> rheo_timings.time_trigger_charge; // Set origin time. This is the datum for the following events.
    do_adc_charge(p_adc, adc_idx, adc_rheo_state, rheo_timings); // Start charging
    tmr_single when timerafter(rheo_timings.time_trigger_discharge) :> int _; // Wait until fully charged
    do_adc_start_convert(p_adc, adc_idx, adc_rheo_state, rheo_timings);

    // Now wait for conversion or overshoot timeout event
    unsafe{
        select{
            case p_adc[adc_idx] when pinseq(0x0) :> int _ @ rheo_timings.end_time:
                do_adc_convert(p_adc, adc_idx, adc_rheo_state, rheo_timings, adc_mode);
            break;
            case tmr_single when timerafter(rheo_timings.time_trigger_overshoot) :> int _:
                do_adc_handle_overshoot(p_adc, adc_idx, adc_rheo_state, rheo_timings);
            break;
        }
        result = adc_rheo_state.results[adc_idx];
    }

    // The pot value has only just reached the threshold so allow some time for it to nearly reach the pot value
    // before next conversion in case it is back to back.
    tmr_single when timerafter(rheo_timings.time_trigger_discharge + adc_rheo_state.max_disch_ticks) :> int _;
     
    return result;
}

