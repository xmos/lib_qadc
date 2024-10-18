// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <stdio.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>

#include <xs1.h>
#include <platform.h>
#include <print.h>

#include "qadc.h"
#include "qadc_utils.h"



typedef enum adc_state_t{
        ADC_STOPPED = 3,
        ADC_IDLE = 2,
        ADC_CHARGING = 1,
        ADC_CONVERTING = 0 // Optimisation as ISA can do != 0 on select guard
}adc_state_t;

void qadc_pot_init( port p_adc[], 
                    size_t num_adc,
                    size_t lut_size,
                    size_t filter_depth,
                    unsigned result_hysteresis,
                    uint16_t *state_buffer,
                    qadc_config_t adc_config,
                    qadc_pot_state_t &adc_pot_state) {
    unsafe{
        memset(state_buffer, 0, QADC_POT_STATE_SIZE(num_adc, lut_size, filter_depth) * sizeof(uint16_t));

        adc_pot_state.num_adc = num_adc;
        adc_pot_state.lut_size = lut_size;
        adc_pot_state.filter_depth = filter_depth;
        adc_pot_state.result_hysteresis = result_hysteresis;
        adc_pot_state.port_time_offset = 32; // Tested at 120MHz thread speed

        // Copy config to state
        adc_pot_state.adc_config.capacitor_pf = adc_config.capacitor_pf;
        adc_pot_state.adc_config.potentiometer_ohms = adc_config.potentiometer_ohms;
        adc_pot_state.adc_config.resistor_series_ohms = adc_config.resistor_series_ohms;
        adc_pot_state.adc_config.v_rail = adc_config.v_rail;
        adc_pot_state.adc_config.v_thresh = adc_config.v_thresh;
        adc_pot_state.adc_config.convert_interval_ticks = adc_config.convert_interval_ticks;
        adc_pot_state.adc_config.auto_scale = adc_config.auto_scale;


        // Initialise pointers into state buffer blob
        uint16_t * unsafe ptr = state_buffer;
        adc_pot_state.results = ptr;
        ptr += num_adc;
        adc_pot_state.init_port_val = ptr;
        ptr += num_adc;
        adc_pot_state.conversion_history = ptr;
        ptr += filter_depth * num_adc;
        adc_pot_state.hysteris_tracker = ptr;
        ptr += num_adc;
        adc_pot_state.max_seen_ticks_up = ptr;
        ptr += num_adc;
        adc_pot_state.max_seen_ticks_down = ptr;
        ptr += num_adc;
        adc_pot_state.max_scale_up = ptr;
        ptr += num_adc;
        adc_pot_state.max_scale_down = ptr;
        ptr += num_adc;
        adc_pot_state.lut_up = ptr;
        ptr += lut_size;
        adc_pot_state.lut_down = ptr;
        ptr += lut_size;
        adc_pot_state.filter_write_idx = ptr;
        ptr += num_adc;
        unsigned limit = (unsigned)state_buffer + sizeof(uint16_t) * QADC_POT_STATE_SIZE(num_adc, lut_size, filter_depth);
        assert(ptr == limit); // Check we have matching sizes

        // Set scale and clear tide marks
        for(int i = 0; i < num_adc; i++){
            adc_pot_state.max_scale_up[i] = 1 << QADC_Q_3_13_SHIFT;
            adc_pot_state.max_scale_down[i] = 1 << QADC_Q_3_13_SHIFT;
            adc_pot_state.max_seen_ticks_up[i] = 0;
            adc_pot_state.max_seen_ticks_down[i] = 0;
        }

        // Generate calibration lookup table
        gen_lookup_pot( adc_pot_state.lut_up, adc_pot_state.lut_down, adc_pot_state.lut_size,
                        (float)adc_config.potentiometer_ohms, (float)adc_config.capacitor_pf * 1e-12, (float)adc_config.resistor_series_ohms,
                        adc_config.v_rail, adc_config.v_thresh,
                        &adc_pot_state.max_lut_ticks_up, &adc_pot_state.max_lut_ticks_down);
        adc_pot_state.crossover_idx = (unsigned)(adc_config.v_thresh / adc_config.v_rail * adc_pot_state.lut_size);

        // Set all ports to input and set drive strength to low to reduce switching noise
        const int port_drive = DRIVE_2MA;
        for(int i = 0; i < adc_pot_state.num_adc; i++){
            unsigned dummy;
            p_adc[i] :> dummy;
            // Simulator doesn't like setc so only do for hardware. isSimulation() takes 100ms or so per port so do here.
            if(!isSimulation()) set_pad_properties(p_adc[i], port_drive, PULL_NONE, 1, 0);
        }
    }
}


static inline unsigned ticks_to_position(int is_up, uint16_t ticks, unsigned adc_idx, qadc_pot_state_t &adc_pot_state){
    unsafe{

        // Extract vars for readibility
        uint16_t * unsafe up = adc_pot_state.lut_up;
        uint16_t * unsafe down = adc_pot_state.lut_down;
        unsigned num_points = adc_pot_state.lut_size;
        unsigned port_time_offset = adc_pot_state.port_time_offset;
        qadc_q3_13_fixed_t max_scale_up = adc_pot_state.max_scale_up[adc_idx];
        qadc_q3_13_fixed_t max_scale_down = adc_pot_state.max_scale_down[adc_idx];

        unsigned max_arg = 0;

        // Remove fixed proc time overhead (nulls end positions)
        if(ticks > port_time_offset){
            ticks -= port_time_offset;
        } else{
            ticks = 0;
        }

        if(is_up){
            //Apply scaling (for best adjusting crossover smoothness)
            ticks = (uint32_t)ticks << QADC_Q_3_13_SHIFT / max_scale_up;
            // ticks = ((int64_t)max_scale_up * (int64_t)ticks) >> QADC_Q_3_13_SHIFT;
            
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
        } else {
            //Apply scaling (for best adjusting crossover smoothness)
            ticks = (uint32_t)ticks << QADC_Q_3_13_SHIFT / max_scale_down;
            // ticks = ((int64_t)max_scale_down * (int64_t)ticks) >> QADC_Q_3_13_SHIFT;

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
}


static inline uint16_t post_process_result( uint16_t raw_result, unsigned adc_idx, qadc_pot_state_t &adc_pot_state){
    unsafe{
        // Extract vars for readibility
        uint16_t *unsafe conversion_history = adc_pot_state.conversion_history;
        uint16_t *unsafe hysteris_tracker = adc_pot_state.hysteris_tracker;
        size_t num_adc = adc_pot_state.num_adc;
        size_t result_history_depth = adc_pot_state.filter_depth;
        size_t lookup_size = adc_pot_state.lut_size;
        unsigned result_hysteresis = adc_pot_state.result_hysteresis;
        uint16_t *unsafe filter_write_idx = adc_pot_state.filter_write_idx;

        // Apply filter. First populate filter history.
        unsigned offset = adc_idx * result_history_depth + filter_write_idx[adc_idx];
        *(conversion_history + offset) = raw_result;

        if(++filter_write_idx[adc_idx] == result_history_depth){
            filter_write_idx[adc_idx] = 0;
        }

        // Calculate moving average filter
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

        // Store hysteresis output for next time
        uint16_t filtered_hysteris_result = hysteris_tracker[adc_idx];

        return filtered_hysteris_result;
    }
}


// Struct which contains the various timings and event triggers for the conversion
typedef struct pot_timings_t{
    int32_t time_trigger_charge;
    int32_t time_trigger_start_convert;
    int32_t time_trigger_overshoot;
    int32_t max_ticks_expected;
    uint32_t max_charge_period_ticks;
    uint32_t max_discharge_period_ticks;
    int16_t start_time;
    int16_t end_time;
}pot_timings_t;


static void do_adc_timing_init(port p_adc[], qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    // Work out timing limits
    const unsigned capacitor_pf = adc_pot_state.adc_config.capacitor_pf;
    const unsigned potentiometer_ohms = adc_pot_state.adc_config.potentiometer_ohms;
    const int rc_times_to_charge_fully = 5; // 5 RC times should be sufficient to reach rail
    pot_timings.max_charge_period_ticks = ((uint64_t)rc_times_to_charge_fully * capacitor_pf * potentiometer_ohms / 4) / 10000;

    pot_timings.max_discharge_period_ticks = (adc_pot_state.max_lut_ticks_up > adc_pot_state.max_lut_ticks_down ?
                                                adc_pot_state.max_lut_ticks_up : adc_pot_state.max_lut_ticks_down);

    dprintf("convert_interval_ticks: %d max charge/discharge_period: %lu\n", adc_pot_state.adc_config.convert_interval_ticks, pot_timings.max_charge_period_ticks + pot_timings.max_discharge_period_ticks);
    dprintf("max_charge_period_ticks: %lu max_dis_period_ticks (up/down): (%lu,%lu), crossover_idx: %u\n",
            pot_timings.max_charge_period_ticks, adc_pot_state.max_lut_ticks_up, adc_pot_state.max_lut_ticks_down, adc_pot_state.crossover_idx);
    assert(adc_pot_state.adc_config.convert_interval_ticks > pot_timings.max_charge_period_ticks + pot_timings.max_discharge_period_ticks * 2); // Ensure conversion rate is low enough. *2 to allow post processing time
}


static void do_adc_charge(port p_adc[], unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    unsafe{
        p_adc[adc_idx] :> adc_pot_state.init_port_val[adc_idx];
        unsigned is_up = adc_pot_state.init_port_val[adc_idx];

        pot_timings.time_trigger_start_convert = pot_timings.time_trigger_charge + pot_timings.max_charge_period_ticks;

        p_adc[adc_idx] <: is_up ^ 0x1; // Drive opposite to what we read to "charge"
        pot_timings.max_ticks_expected = is_up != 0 ? 
                            ((uint32_t)adc_pot_state.max_lut_ticks_up * (uint32_t)adc_pot_state.max_scale_up[adc_idx]) >> QADC_Q_3_13_SHIFT :
                            ((uint32_t)adc_pot_state.max_lut_ticks_down * (uint32_t)adc_pot_state.max_scale_down[adc_idx]) >> QADC_Q_3_13_SHIFT;

    }
}

static void do_adc_start_convert(port p_adc[], unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    p_adc[adc_idx] :> int _ @ pot_timings.start_time; // Make Hi Z and grab port time
    // Set up an event to handle if port doesn't reach oppositie value. Set at double the max expected time. This is a fairly fatal 
    // event which is caused by severe mismatch of hardware vs init params
    pot_timings.time_trigger_overshoot = pot_timings.time_trigger_start_convert + (pot_timings.max_ticks_expected * 2);
}

static void do_adc_convert(port p_adc[], unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    unsafe{
        int32_t conversion_time = (pot_timings.end_time - pot_timings.start_time);
        if(conversion_time < 0){
            conversion_time += 0x10000; // Account for port timer wrapping
        }

        // Update max seen values. Can help tracking if actual RC constant is less than expected.
        unsigned is_up = adc_pot_state.init_port_val[adc_idx];
        if(is_up) unsafe{
            if(conversion_time > adc_pot_state.max_seen_ticks_up[adc_idx]){
                adc_pot_state.max_seen_ticks_up[adc_idx] = conversion_time;
            }
        } else unsafe{
            if(conversion_time > adc_pot_state.max_seen_ticks_down[adc_idx]){
                adc_pot_state.max_seen_ticks_down[adc_idx] = conversion_time;
            }
        }

        // Check for soft overshoot. This is when the actual RC constant is greater than expected and is expected.
        if(conversion_time > pot_timings.max_ticks_expected){
            dprintf("soft overshoot: %d (%d)\n", conversion_time, pot_timings.max_ticks_expected);
            if(adc_pot_state.adc_config.auto_scale){
                if(is_up){ // is up
                    qadc_q3_13_fixed_t new_scale = ((uint32_t)adc_pot_state.max_scale_up[adc_idx] * (uint32_t)conversion_time) / (uint32_t)pot_timings.max_ticks_expected;
                    dprintf("up scale: %d (%d)\n", adc_pot_state.max_scale_up[adc_idx], new_scale);
                    adc_pot_state.max_scale_up[adc_idx] = new_scale;
                } else {
                    qadc_q3_13_fixed_t new_scale = ((uint32_t)adc_pot_state.max_scale_down[adc_idx] * (uint32_t)conversion_time) / (uint32_t)pot_timings.max_ticks_expected;
                    dprintf("down scale: %d (%d)\n", adc_pot_state.max_scale_down[adc_idx], new_scale);
                    adc_pot_state.max_scale_down[adc_idx] = new_scale;
                }                             
            }
        }

        // Check for minimum setting being smaller than port time offset (sets zero and full scale). Minimum time to trigger port select. 
        if(conversion_time < adc_pot_state.port_time_offset){
            dprintf("Port offset: %lu %lu\n", conversion_time, adc_pot_state.port_time_offset);
            if(adc_pot_state.adc_config.auto_scale){
                adc_pot_state.port_time_offset = conversion_time;
            }
        }

        // Turn time and direction into ADC reading
        uint16_t result = ticks_to_position(is_up, conversion_time, adc_idx, adc_pot_state);
        uint16_t post_proc_result = post_process_result(result, adc_idx, adc_pot_state);
        adc_pot_state.results[adc_idx] = post_proc_result;
        dprintf("result: %u post_proc: %u ticks: %u is_up: %d mu: %lu md: %lu\n",
            result, post_proc_result, conversion_time, is_up, adc_pot_state.max_seen_ticks_up[adc_idx], adc_pot_state.max_seen_ticks_down[adc_idx]);


        pot_timings.time_trigger_charge += adc_pot_state.adc_config.convert_interval_ticks;
        int32_t time_now;
        timer tmr;
        tmr :> time_now;
        if(timeafter(time_now, pot_timings.time_trigger_charge)){
            dprintf("Error - Conversion period exceeded\n");
        }
    }
}


static void do_adc_handle_overshoot(port p_adc[], unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    unsigned overshoot_port_val = 0;
    p_adc[adc_idx] :> overshoot_port_val; // For debug only.

    unsafe{
        unsigned is_up = adc_pot_state.init_port_val[adc_idx];
        uint16_t result = adc_pot_state.crossover_idx + (is_up != 0 ? 1 : 0);
        uint16_t post_proc_result = post_process_result(result, adc_idx, adc_pot_state);
        adc_pot_state.results[adc_idx] = post_proc_result;

        dprintf("result: %u ch: %u overshoot (ticks>%d) val:%u\n", post_proc_result, adc_idx, pot_timings.time_trigger_overshoot-pot_timings.time_trigger_start_convert, overshoot_port_val);
    }

    pot_timings.time_trigger_charge += adc_pot_state.adc_config.convert_interval_ticks;

    int32_t time_now;
    timer tmr;
    tmr :> time_now;
    if(timeafter(time_now, pot_timings.time_trigger_charge)){
        dprintf("Error - Conversion period exceeded\n");
    }
}


void qadc_pot_task(chanend ?c_adc, port p_adc[], qadc_pot_state_t &adc_pot_state){
    dprintf("adc_pot_task\n");
  
    // Current conversion index
    unsigned adc_idx = 0;

    // State timers
    timer tmr_charge;
    timer tmr_discharge;
    timer tmr_overshoot;

    // Timing struct
    pot_timings_t pot_timings = {0};

    do_adc_timing_init(p_adc, adc_pot_state, pot_timings);

    // Setup initial state
    adc_state_t adc_state = ADC_IDLE;

    // Set init time for charge
    tmr_charge :> pot_timings.time_trigger_charge;
    pot_timings.time_trigger_charge += pot_timings.max_charge_period_ticks; // start in one charge period
    
    while(1) unsafe{
        select{
            case adc_state == ADC_IDLE => tmr_charge when timerafter(pot_timings.time_trigger_charge) :> int _:
                do_adc_charge(p_adc, adc_idx, adc_pot_state, pot_timings);
                adc_state = ADC_CHARGING;
            break;

            case adc_state == ADC_CHARGING => tmr_discharge when timerafter(pot_timings.time_trigger_start_convert) :> int _:
                do_adc_start_convert(p_adc, adc_idx, adc_pot_state, pot_timings);
                adc_state = ADC_CONVERTING;
            break;

            case adc_state == ADC_CONVERTING => p_adc[adc_idx] when pinseq(adc_pot_state.init_port_val[adc_idx]) :> int _ @ pot_timings.end_time:
                do_adc_convert(p_adc, adc_idx, adc_pot_state, pot_timings);
                
                // Cycle through the ADC channels
                if(++adc_idx == adc_pot_state.num_adc){
                    adc_idx = 0;
                }
                adc_state = ADC_IDLE;
            break;

            // This case happens if the hardware RC constant is much higher than expected
            case adc_state == ADC_CONVERTING => tmr_overshoot when timerafter(pot_timings.time_trigger_overshoot) :> int _:
                do_adc_handle_overshoot(p_adc, adc_idx, adc_pot_state, pot_timings);
                
                // Cycle through the ADC channels
                if(++adc_idx == adc_pot_state.num_adc){
                    adc_idx = 0;
                }
                adc_state = ADC_IDLE;
            break;

            // Handle comms. Only do in charging phase which is quite a long period and non critical if stretched
            case ((adc_state == ADC_CHARGING || adc_state == ADC_STOPPED) && !isnull(c_adc)) => c_adc :> uint32_t command:
                switch(command & QADC_CMD_MASK){
                    case QADC_CMD_READ:
                        uint32_t ch = command & (~QADC_CMD_MASK);
                        unsafe{c_adc <: (uint32_t)adc_pot_state.results[ch];}
                    break;
                    case QADC_CMD_POT_GET_DIR:
                        uint32_t ch = command & (~QADC_CMD_MASK);
                        c_adc <: (uint32_t)adc_pot_state.init_port_val[ch];
                    break;
                    case QADC_CMD_STOP_CONV:
                        for(int i = 0; i < adc_pot_state.num_adc; i++){
                            p_adc[i] :> int _;
                        }
                        adc_state = ADC_STOPPED;
                    break;
                    case QADC_CMD_START_CONV:
                        tmr_charge :> pot_timings.time_trigger_charge;
                        pot_timings.time_trigger_charge += pot_timings.max_charge_period_ticks; // start in one charge period
                        // Clear all history apart from scaling
                        memset(adc_pot_state.results, 0, adc_pot_state.max_seen_ticks_up - adc_pot_state.results);
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


uint16_t qadc_pot_single(port p_adc[], unsigned adc_idx, qadc_pot_state_t &adc_pot_state){
    int16_t result = 0;

    timer tmr_single;

    pot_timings_t pot_timings = {0};
    do_adc_timing_init(p_adc, adc_pot_state, pot_timings);
    tmr_single :> pot_timings.time_trigger_charge; // Set origin time. This is the datum for the following events.
    do_adc_charge(p_adc, adc_idx, adc_pot_state, pot_timings); // Start charging
    tmr_single when timerafter(pot_timings.time_trigger_start_convert) :> int _; // Wait until fully charged
    do_adc_start_convert(p_adc, adc_idx, adc_pot_state, pot_timings);

    // Now wait for conversion or overshoot timeout event
    unsafe{
        select{
            case p_adc[adc_idx] when pinseq(adc_pot_state.init_port_val[adc_idx]) :> int _ @ pot_timings.end_time:
                do_adc_convert(p_adc, adc_idx, adc_pot_state, pot_timings);
            break;
            case tmr_single when timerafter(pot_timings.time_trigger_overshoot) :> int _:
                do_adc_handle_overshoot(p_adc, adc_idx, adc_pot_state, pot_timings);
            break;
        }
        result = adc_pot_state.results[adc_idx];
    }
    
    return result;
}
