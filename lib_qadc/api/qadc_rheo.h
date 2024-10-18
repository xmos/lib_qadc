// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#pragma once
#include "qadc.h"

/** 
 * @brief   Internal state for each QADC instance. These should not be accessed directly and instead
 *          be initialised by a call to adc_pot_init().
 */
typedef struct qadc_rheo_state_t{
    size_t num_adc;
    unsigned adc_idx;
    size_t filter_depth;
    size_t adc_steps;
    unsigned result_hysteresis;
    uint16_t * UNSAFE results;
    qadc_config_t adc_config;
    uint16_t max_disch_ticks;
    uint16_t * UNSAFE max_seen_ticks;
    qadc_q3_13_fixed_t * UNSAFE max_scale;
    unsigned crossover_idx;
    uint16_t port_time_offset;
    uint16_t * UNSAFE conversion_history;
    uint16_t * UNSAFE hysteris_tracker;
    uint16_t * UNSAFE filter_write_idx;
}qadc_rheo_state_t;





/**
 * \addtogroup lib_qadc_rheo_reader
 *
 * The public API for using the QADC.
 * @{
 */

#define QADC_RHEO_STATE_SIZE( num_adc, filter_depth)                     (( \
    /* results */            (sizeof(uint16_t) * num_adc) +                 \
    /* conversion_history */ (sizeof(uint16_t) * num_adc * filter_depth) +  \
    /* hysteris_tracker */   (sizeof(uint16_t) * num_adc) +                 \
    /* max_seen_ticks*/      (sizeof(uint16_t) * num_adc) +                 \
    /* max_scale */          (sizeof(uint16_t) * num_adc) +                 \
    /* filter_write_idx */   (sizeof(uint16_t) * num_adc) +                 \
                             (sizeof(uint16_t) - 1)) / sizeof(uint16_t))

/**
 * Initialise a QADC rheostate reader instance and initialise the qadc_rheo_state structure. 
 * This generates the look up table, initialises the state and sets up the ports used by the QADC.
 * Must be called before either qadc_rheo_single() or qadc_rheo_task().
 * 
 * IF CALLING FROM C WITH lib_xcore's PAR_JOBS() TO START THE THREADS, PLEASE CALL qadc_c_pre_init() FIRST.
 *
 * \param p_adc             An array of 1 bit ports used for conversion.
 * \param num_adc           The number of 1 bit ports (QADC channels) used.
 * \param adc_steps         The number of discrete conversion possible values. Also sets the output result full scale value to lut_size - 1.
 * \param filter_depth      The size of the moving average filter used to average each conversion result.   
 * \param state_buffer      pointer to the state buffer used of type uint16_t. Please use the ADC_POT_STATE_SIZE
 *                          macro to size the declaration of the state buffer.
 * \param adc_config        A struct of type qadc_config_t containing the parameters of the QADC external components
 *                          and conversion rate / mode. This must be initialised before passing to qadc_rheo_init().
 * \param adc_rheo_state    Reference to the qadc_rheo_state_t struct which contains internal state for the QADC. This
 *                          does not need to be initialised before hand since this function does that.
 */ 
void qadc_rheo_init(port p_adc[],
                    size_t num_adc,
                    size_t adc_steps,
                    size_t filter_depth,
                    unsigned result_hysteresis,
                    uint16_t *state_buffer,
                    qadc_config_t adc_config,
                    REFERENCE_PARAM(qadc_rheo_state_t, adc_rheo_state));

/**
 * Perform a single ADC conversion on a specific channel. In this mode the QADC does not require a dedicated
 * task (hardware thread) to perform conversion. Note that that this is a blocking call which will
 * return only when the conversion is complete. Typically it may take a few hundred microseconds (depending
 * on the RC constants chosen) but it's execution time is variable. It will take longest when the rheostate
 * is set to maximum and shortest at zero. Use this API when infrequent readings are needed
 * and the callee can accept a blocking call.
 * qadc_rheo_init() must be called before this function.
 *
 * \param p_adc             An array of 1 bit ports used for conversion.
 * \param adc_idx           The QADC channel to read.
 * \param adc_rheo_state    Reference to the adc_rheo_state_t struct which contains internal state for the QADC. 
 */
uint16_t qadc_rheo_single(port p_adc[], unsigned adc_idx, REFERENCE_PARAM(qadc_rheo_state_t, adc_rheo_state));

#if defined(__XC__) || defined(__DOXYGEN__)
void qadc_rheo_task(NULLABLE_RESOURCE(chanend, c_adc), port p_adc[], REFERENCE_PARAM(qadc_rheo_state_t, adc_rheo_state));
#else
DECLARE_JOB(qadc_rheo_task, (chanend_t, port_t*, qadc_rheo_state_t*));
/**
 * Starts a task that will continuously cycle through all QADC inputs and convert each in turn. It will assert if
 * the time taken to convert is longer than convert_interval_ticks set in qadc_config.
 * The task will apply post processing to the raw result including filtering and hysteresis.
 * 
 * The task may be placed on a different tile from the client if channel communication is used.
 * Optionally, a NULL parameter can be passed to the channel and the results in no channel being required.
 * In the channel-less case the results may be read directly out of the first N entries of ``state_buffer``
 * which contain the uint16_t conversion results.
 * It is essential that the client reading the results be on the same tile as the QADC in this case because
 * the QADC and the client need to share the same memory space.
 *
 * qadc_rheo_init() must be called before this task is started.
 * 
 * \param c_adc         Channel for collecting results and controlling the QADC.
 * \param p_adc         An array of 1 bit ports used for conversion.
 * \param adc_config    A reference to struct of type qadc_rheo_state_t containing the parameters of the QADC external components
 *                      and conversion rate / mode. This must be initialised before by qadc_rheo_init() before-calling this task.
 */
void qadc_rheo_task(chanend_t c_adc, port_t *p_adc, qadc_rheo_state_t *adc_rheo_state);
#endif

/**@}*/ // END: addtogroup lib_qadc_rheo_reader

