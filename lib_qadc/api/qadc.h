// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#pragma once

#include <stdint.h>
#include <stddef.h>
#include <xccompat.h>
#ifdef __XC__
#define UNSAFE unsafe
#else
#include <xcore/parallel.h>
#include <xcore/channel.h>
#include <xcore/port.h>
#define UNSAFE
#endif


/**
 * \addtogroup lib_qadc_common
 *
 * The public API for using the QADC.
 * @{
 */


/** 
 * @brief   Configuration structure for initialising the QADC. This contains
 *          the passive component definition, voltages, conversion speed ( adc_xxx_task() only ) 
 *          and mode.
 */
typedef struct qadc_config_t{
    /** Capacitor size in picofarads. Should include the stray capacitance of the PCB. */
    unsigned capacitor_pf;
    /** Potentiometer value in ohms - nominal maximum value end to end. */
    unsigned potentiometer_ohms;
    /** Series resistor size in ohms. */
    unsigned resistor_series_ohms;
    /** Voltage of the IO rail used by the QADC port as a float. */
    float v_rail;
    /** Voltage of the input threshold. This is nominally 1.15 volts for a 3.3 volt rail. */
    float v_thresh;
    /** The full conversion cycle time per channel (adc_xxx_task() only). The task will assert
     *  at initialisation if this is too short. */
    unsigned convert_interval_ticks;
    /** Boolean setting which allows the end points of the QADC to be stretched if the read value
     *  exceeds the expected value. The new end point will be kept until the task is re-started. 
     *  This is ignored in single shot mode. */ 
    char auto_scale;
}qadc_config_t;

/** 
 * @brief   Fixed point type used internally by QADC.
 */
typedef uint16_t         qadc_q3_13_fixed_t;

/** 
 * @brief   Fixed point type used internally by QADC.
 */
#define QADC_Q_3_13_SHIFT    13

/**@}*/ // END: addtogroup lib_qadc_common


#include "qadc_pot.h"
#include "qadc_rheo.h"