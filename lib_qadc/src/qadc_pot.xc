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
        adc_pot_state.port_width = (unsigned)p_adc[0] >> 16; // Width is 3rd byte
        adc_pot_state.lut_size = lut_size;
        adc_pot_state.filter_depth = filter_depth;
        adc_pot_state.result_hysteresis = result_hysteresis;

        // Check all ports the same width
        unsigned num_ports = (adc_pot_state.num_adc + adc_pot_state.port_width - 1) / adc_pot_state.port_width;
        unsigned total_port_width = 0;
        for(int i = 0; i < num_ports; i++){
            total_port_width += (unsigned)p_adc[i] >> 16;
        }
        assert(total_port_width == adc_pot_state.port_width * num_ports); // Ensure all ports the same type/width


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
        for(int i = 0; i < num_ports; i++){
            p_adc[i] :> int _; // Hi-z
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
        qadc_q3_13_fixed_t max_scale_up = adc_pot_state.max_scale_up[adc_idx];
        qadc_q3_13_fixed_t max_scale_down = adc_pot_state.max_scale_down[adc_idx];

        unsigned max_arg = 0;

        if(is_up){
            //Apply scaling (for best adjusting crossover smoothness)
            ticks = (uint32_t)ticks << QADC_Q_3_13_SHIFT / max_scale_up;
            
            uint16_t max = 0;
            max_arg = num_points - 1;
            for(int i = num_points - 1; i >= 0; i--){
                if(ticks > up[i]){
                    if(up[i] > max){
                        max_arg = i;
                        max = up[i];
                    } 
                }
            }
        } else {
            //Apply scaling (for best adjusting crossover smoothness)
            ticks = (uint32_t)ticks << QADC_Q_3_13_SHIFT / max_scale_down;

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


static void do_adc_timing_init(qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
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
        pot_timings.time_trigger_start_convert = pot_timings.time_trigger_charge + pot_timings.max_charge_period_ticks;

        unsigned is_up = 0;
        if(adc_pot_state.port_width == 1){
            p_adc[adc_idx] :> adc_pot_state.init_port_val[adc_idx];
            is_up = adc_pot_state.init_port_val[adc_idx];
            p_adc[adc_idx] <: is_up ^ 0x1; // Drive opposite to what we read to "charge"
        } else {
            unsigned bit_idx = adc_idx % adc_pot_state.port_width;
            unsigned port_idx = adc_idx / adc_pot_state.port_width;
            int tmp_port = 0;
            p_adc[port_idx] :> tmp_port;
            adc_pot_state.init_port_val[adc_idx] = (tmp_port >> bit_idx) & 0x01;
            is_up = adc_pot_state.init_port_val[adc_idx];
            if(is_up){
                set_pad_drive_mode(p_adc[port_idx], DRIVE_LOW_WEAK_PULL_UP)
                p_adc[port_idx] <: ~(0x01 << bit_idx);
                // printhexln(~(0x01 << bit_idx));
            } else {
                set_pad_drive_mode(p_adc[port_idx], DRIVE_HIGH_WEAK_PULL_DOWN)
                p_adc[port_idx] <: (0x01 << bit_idx);
                // printhexln((0x01 << bit_idx));

            }
        }

        pot_timings.max_ticks_expected = is_up != 0 ? 
                            ((uint32_t)adc_pot_state.max_lut_ticks_up * (uint32_t)adc_pot_state.max_scale_up[adc_idx]) >> QADC_Q_3_13_SHIFT :
                            ((uint32_t)adc_pot_state.max_lut_ticks_down * (uint32_t)adc_pot_state.max_scale_down[adc_idx]) >> QADC_Q_3_13_SHIFT;

    }
}

static unsigned do_adc_start_convert(port p_adc[], unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    unsigned port_idx = adc_idx / adc_pot_state.port_width; // Do these calcs before the timestamp for min offset.
    unsigned post_charge_port_val = 0;
    // Set up an event to handle if port doesn't reach oppositie value. Set at double the max expected time. This is a fairly fatal 
    // event which is caused by severe mismatch of hardware vs init params.
    pot_timings.time_trigger_overshoot = pot_timings.time_trigger_start_convert + (pot_timings.max_ticks_expected * 2);

    // Do this last so min delay to the point where we see the port change
    p_adc[port_idx] :> post_charge_port_val @ pot_timings.start_time;// Make Hi Z and grab port time

    return post_charge_port_val;
}

static void do_adc_convert(unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
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


static void do_adc_handle_overshoot(unsigned adc_idx, qadc_pot_state_t &adc_pot_state, pot_timings_t &pot_timings){
    unsafe{
        unsigned is_up = adc_pot_state.init_port_val[adc_idx];
        uint16_t result = adc_pot_state.crossover_idx + (is_up != 0 ? 1 : 0);
        uint16_t post_proc_result = post_process_result(result, adc_idx, adc_pot_state);
        adc_pot_state.results[adc_idx] = post_proc_result;

        dprintf("result: %u ch: %u overshoot (ticks>%d)\n", post_proc_result, adc_idx, pot_timings.time_trigger_overshoot-pot_timings.time_trigger_start_convert);
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

    do_adc_timing_init(adc_pot_state, pot_timings);

    // Setup initial state
    adc_state_t adc_state = ADC_IDLE;

    // Set init time for charge
    tmr_charge :> pot_timings.time_trigger_charge;
    pot_timings.time_trigger_charge += pot_timings.max_charge_period_ticks; // start in one charge period

    // Used for determining the pin event conditions and auto zero offset
    unsigned post_charge_port_val = 0;
    unsigned pin_event_value = 0;

    // Used for mult-bit port
    unsigned port_idx = adc_idx / adc_pot_state.port_width;
    
    while(1) unsafe{
        select{
            case adc_state == ADC_IDLE => tmr_charge when timerafter(pot_timings.time_trigger_charge) :> int _:
                do_adc_charge(p_adc, adc_idx, adc_pot_state, pot_timings);
                adc_state = ADC_CHARGING;
            break;

            case adc_state == ADC_CHARGING => tmr_discharge when timerafter(pot_timings.time_trigger_start_convert) :> int _:
                adc_state = ADC_CONVERTING; // Put this here to minimise case execution time
                post_charge_port_val = do_adc_start_convert(p_adc, adc_idx, adc_pot_state, pot_timings);
                if(adc_pot_state.port_width == 1){
                    pin_event_value = !adc_pot_state.init_port_val[adc_idx];
                } else {
                    pin_event_value = ~post_charge_port_val; // Trigger immediately so we catch the end cases
                }
            break;

            case (adc_state == ADC_CONVERTING) => p_adc[port_idx] when pinsneq(pin_event_value) :> int port_val @ pot_timings.end_time:
                if(adc_pot_state.port_width == 1){
                    if(post_charge_port_val == adc_pot_state.init_port_val[adc_idx]){
                        pot_timings.end_time = pot_timings.start_time; // End position
                    }
                    do_adc_convert(adc_idx, adc_pot_state, pot_timings);
                } else {
                    // Work out if the pin of interest has changed
                    unsigned bit_idx = adc_idx % adc_pot_state.port_width;
                    unsigned bit_val = (port_val >> bit_idx) & 0x01;
                    if(bit_val != adc_pot_state.init_port_val[adc_idx]){
                        pin_event_value = port_val;
                        break; // Keep firing select until desired bit transiton found
                    } else {
                        unsigned post_charge_pin_val = (post_charge_port_val >> bit_idx) & 0x01;
                        if(post_charge_pin_val == adc_pot_state.init_port_val[adc_idx]){
                            pot_timings.end_time = pot_timings.start_time; // End position
                        }
                        do_adc_convert(adc_idx, adc_pot_state, pot_timings);
                    }
                }
                
                // Cycle through the ADC channels
                if(++adc_idx == adc_pot_state.num_adc){
                    adc_idx = 0;
                }
                port_idx = adc_idx / adc_pot_state.port_width;
                adc_state = ADC_IDLE;
            break;

            // This case happens if the hardware RC constant is much higher than expected
            case adc_state == ADC_CONVERTING => tmr_overshoot when timerafter(pot_timings.time_trigger_overshoot) :> int _:
                do_adc_handle_overshoot(adc_idx, adc_pot_state, pot_timings);
                // Cycle through the ADC channels
                if(++adc_idx == adc_pot_state.num_adc){
                    adc_idx = 0;
                }
                port_idx = adc_idx / adc_pot_state.port_width;
                adc_state = ADC_IDLE;
            break;

            // Handle comms
            case !isnull(c_adc) => c_adc :> uint32_t command:
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
                        unsigned num_ports = (adc_pot_state.num_adc + adc_pot_state.port_width - 1) / adc_pot_state.port_width;
                        for(int i = 0; i < num_ports; i++){
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
    unsigned port_idx = adc_idx / adc_pot_state.port_width;
    pot_timings_t pot_timings = {0};

    do_adc_timing_init(adc_pot_state, pot_timings);
    tmr_single :> pot_timings.time_trigger_charge; // Set origin time. This is the datum for the following events.
    do_adc_charge(p_adc, adc_idx, adc_pot_state, pot_timings); // Start charging
    tmr_single when timerafter(pot_timings.time_trigger_start_convert) :> int _; // Wait until fully charged
    
    unsigned post_charge_port_val = 0;
    unsigned pin_event_value = 0;

    p_adc[port_idx] :> post_charge_port_val; // Grab charged port val for wide version
    if(adc_pot_state.port_width == 1){
        unsafe{pin_event_value = !adc_pot_state.init_port_val[adc_idx];}
    } else {
        pin_event_value = ~post_charge_port_val; // Trigger immediately so we catch the end cases
    }

    do_adc_start_convert(p_adc, adc_idx, adc_pot_state, pot_timings);


    // Now wait for conversion or overshoot timeout event
    int conversion_ongoing = 1; // With mutli-bit we need to keep slecting until the known pin transition
    unsafe{
        while(conversion_ongoing){
            select{
                case p_adc[port_idx] when pinsneq(post_charge_port_val) :> int port_val @ pot_timings.end_time:
                    if(adc_pot_state.port_width == 1){
                        if(post_charge_port_val == adc_pot_state.init_port_val[adc_idx]){
                            pot_timings.end_time = pot_timings.start_time; // End position
                        }
                        do_adc_convert(adc_idx, adc_pot_state, pot_timings);
                        conversion_ongoing = 0;
                    } else {
                        // Work out if the pin of interest has changed
                        unsigned bit_idx = adc_idx % adc_pot_state.port_width;
                        unsigned bit_val = (port_val >> bit_idx) & 0x01;
                        if(bit_val != adc_pot_state.init_port_val[adc_idx]){
                            pin_event_value = port_val;
                            break; // Keep firing select until desired bit transiton found
                        } else {
                            unsigned post_charge_pin_val = (post_charge_port_val >> bit_idx) & 0x01;
                            if(post_charge_pin_val == adc_pot_state.init_port_val[adc_idx]){
                                pot_timings.end_time = pot_timings.start_time; // End position
                            }
                            do_adc_convert(adc_idx, adc_pot_state, pot_timings);
                            conversion_ongoing = 0;
                        }
                    }
                break;

                case tmr_single when timerafter(pot_timings.time_trigger_overshoot) :> int _:
                    do_adc_handle_overshoot(adc_idx, adc_pot_state, pot_timings);
                    conversion_ongoing = 0;
                break;
            }
        }
        result = adc_pot_state.results[adc_idx];
    }
    
    // The pot value has only just reached the threshold so allow some time for it to nearly reach the pot value
    // before next conversion in case it is back to back.
    tmr_single when timerafter(pot_timings.time_trigger_start_convert + pot_timings.max_ticks_expected) :> int _;


    return result;
}
