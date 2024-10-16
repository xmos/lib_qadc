// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#pragma once

#include <stdint.h>
#include <stddef.h>
#include <xccompat.h>
#ifndef __XC__
#include <xcore/parallel.h>
#include <xcore/channel.h>
#include <xcore/port.h>
#define UNSAFE
#else
#define UNSAFE unsafe
#endif

/**
 * \addtogroup lib_qadc_pot_reader
 *
 * The public API for using the QADC.
 * @{
 */

  /** @struct adc_pot_config_t
   *  This is a struct
   *
   *  @var adc_pot_config_t::capacitor_pf
   *    A foo.
   *  @var adc_pot_config_t::potentiometer_ohms
   *    Also a Foo.
   *  @var adc_pot_config_t::resistor_series_ohms
   *    (unused field)
   */
typedef struct adc_pot_config_t{
    unsigned capacitor_pf;
    unsigned potentiometer_ohms; // nominal maximum value end to end
    unsigned resistor_series_ohms;
    float v_rail;
    float v_thresh;
    unsigned convert_interval_ticks;
    char auto_scale;
}adc_pot_config_t;

typedef uint16_t         q3_13_fixed_t;

#define Q_3_13_SHIFT    13


typedef struct adc_pot_state_t{
    // User config
    size_t num_adc;
    unsigned adc_idx;
    size_t lut_size;
    size_t filter_depth;
    unsigned result_hysteresis;
    uint16_t * UNSAFE results;
    adc_pot_config_t adc_config;

    // Internal state
    uint16_t * UNSAFE cal_up;
    uint16_t * UNSAFE cal_down;
    uint32_t max_lut_ticks_up;
    uint32_t max_lut_ticks_down;
    uint16_t * UNSAFE max_seen_ticks_up;
    uint16_t * UNSAFE max_seen_ticks_down;
    q3_13_fixed_t * UNSAFE max_scale_up;
    q3_13_fixed_t * UNSAFE max_scale_down;
    unsigned crossover_idx;
    uint32_t port_time_offset;
    uint16_t * UNSAFE conversion_history;
    uint16_t * UNSAFE hysteris_tracker;
    uint16_t * UNSAFE init_port_val;
    uint16_t * UNSAFE filter_write_idx;
}adc_pot_state_t;



#define ADC_POT_STATE_SIZE(num_adc, lut_size, filter_depth)              (( \
    /* results */            (sizeof(uint16_t) * num_adc) +                 \
    /* init_port_val */      (sizeof(uint16_t) * num_adc) +                 \
    /* conversion_history */ (sizeof(uint16_t) * num_adc * filter_depth) +  \
    /* hysteris_tracker */   (sizeof(uint16_t) * num_adc) +                 \
    /* max_seen_ticks u/d */ (sizeof(uint16_t) * num_adc * 2) +             \
    /* max_scale u/d */      (sizeof(uint16_t) * num_adc * 2) +             \
    /* cal up + cal down */  (sizeof(uint16_t) * 2 * lut_size) +            \
    /* filter_write_idx */   (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) - 1)) / sizeof(uint16_t))


// Communication protocol
#define ADC_CMD_READ                0x01000000ULL         
#define ADC_CMD_CAL_MODE_START      0x02000000ULL
#define ADC_CMD_CAL_MODE_FINISH     0x03000000ULL
#define ADC_CMD_POT_GET_DIR         0x04000000ULL
#define ADC_CMD_POT_STOP_CONV       0x05000000ULL
#define ADC_CMD_POT_START_CONV      0x06000000ULL
#define ADC_CMD_POT_EXIT            0x07000000ULL
#define ADC_CMD_MASK                0xff000000ULL

/**
 * Initialise a QADC potentiometer reader instance and initialise the adc_pot_state structure. 
 * This generates the look up table, initialises the state and sets up the ports used by the QADC.
 * Must be called before either adc_pot_single() or adc_pot_task().
 *
 * \param p_adc         An array of 1 bit ports used for conversion.
 * \param num_adc       The number of 1 bit ports (QADC channels) used.
 * \param lut_size      The size of the look up table. Also sets the output result full scale value to lut_size - 1.
 * \param filter_depth  The size of the moving average filter used to average each conversion result.   
 * \param state_buffer  pointer to the state buffer used of type uint16_t. Please use the ADC_POT_STATE_SIZE
 *                      macro to size the declaration of the state buffer.
 * \param adc_config    A struct of type adc_pot_config_t containing the parameters of the QADC external components
 *                      and conversion rate / mode. This must be initialised before passing to adc_pot_init().
 * \param adc_pot_state Reference to the adc_pot_state_t struct which contains internal state for the QADC. This
 *                      does not need to be initialised before hand since this function does that.
 */ 
void adc_pot_init(  port p_adc[],
                    size_t num_adc,
                    size_t lut_size,
                    size_t filter_depth,
                    unsigned result_hysteresis,
                    uint16_t *state_buffer,
                    adc_pot_config_t adc_config,
                    REFERENCE_PARAM(adc_pot_state_t, adc_pot_state));

/**
 * Perform a single ADC conversion on a specific channel. In this mode the QADC does not require a dedicated
 * task (hardware thread) to perform conversion. Note that that this is a blocking call which will
 * return only when the conversion is complete. Typically it may take a few hundred microseconds (depending
 * on the RC contsants chosen) but it's execution time is variable. It will take longest when the potentiometer
 * is set to roughly 1/3 and shorest as the end positions. Use this API when infrequent readings are needed
 * and the callee can accept a blocking call.
 * adc_pot_init() must be called before this function.
 *
 * \param p_adc         An array of 1 bit ports used for conversion.
 * \param adc_idx       The QADC channel to read.
 * \param adc_pot_state Reference to the adc_pot_state_t struct which contains internal state for the QADC. 
 */ 
uint16_t adc_pot_single(port p_adc[], unsigned adc_idx, REFERENCE_PARAM(adc_pot_state_t, adc_pot_state));

#if defined(__XC__) || defined(__DOXYGEN__)
void adc_pot_task(NULLABLE_RESOURCE(chanend, c_adc), port p_adc[], REFERENCE_PARAM(adc_pot_state_t, adc_pot_state));
#else
DECLARE_JOB(adc_pot_task, (chanend_t, port_t*, adc_pot_state_t*));
/**
 * Starts a task that will continuously cycle through all QADC inputs and convert each in turn. It will assert if
 * the time taken to convert is longer than convert_interval_ticks set in adc_config.
 * The task will apply post processing to the raw result including filtering and hysteresis.
 * 
 * The task may be placed on a different tile from the client if channel communication is used.
 * Optionally, a NULL parameter can be passed to the channel and the results in no channel being required.
 * In the channel-less case the results may be read directly out of the first N entries of ``state_buffer``
 * which contain the uint16_t conversion results.
 * It is essential that the client reading the results be on the same tile as the QADC in this case because
 * the QADC and the client need to share the same memory space.
 *
 * adc_pot_init() must be called before this task is started.
 * 
 * \param c_adc         Channel for collecting results and controlling the QADC.
 * \param p_adc         An array of 1 bit ports used for conversion.
 * \param adc_config    A struct of type adc_pot_config_t containing the parameters of the QADC external components
 *                      and conversion rate / mode. This must be initialised before by adc_pot_init() before-calling this task.
 */
void adc_pot_task(chanend_t c_adc, port_t p_adc[], adc_pot_state_t *adc_pot_state);
#endif

/**@}*/ // END: addtogroup lib_qadc_pot_reader

