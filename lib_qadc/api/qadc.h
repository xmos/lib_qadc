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
 * \addtogroup lib_qadc_common
 *
 * The public API for using the QADC.
 * @{
 */

/** @brief Read an ADC channel, arg: channel number in LSB. Please OR the cmd with the operand. */
#define QADC_CMD_READ                0x01000000ULL
/** @brief Start calibration mode. Move the potentiometer end to end to determine limits. */
#define QADC_CMD_CAL_MODE_START      0x02000000ULL
/** @brief Stop calibration mode and use new observed limits. */
#define QADC_CMD_CAL_MODE_FINISH     0x03000000ULL
/** @brief Read the conversion direction. Potentiometer QADC only. (1 = High to low, 0 = Low to high) of an ADC channel, arg: channel number in LSB.  Please OR the cmd with the operand.*/
#define QADC_CMD_POT_GET_DIR         0x04000000ULL
/** @brief Temporarily stop conversion. */
#define QADC_CMD_STOP_CONV           0x05000000ULL
/** @brief Restart conversion. */
#define QADC_CMD_START_CONV          0x06000000ULL
/** @brief Exit the qadc_pot_task(). */
#define QADC_CMD_EXIT                0x07000000ULL
/** @brief Mask word used for building commands */
#define QADC_CMD_MASK                0xff000000ULL


/** 
 * @brief   Fixed point type used internally by QADC.
 */
typedef uint16_t         qadc_q3_13_fixed_t;

/** 
 * @brief   Fixed point type used internally by QADC.
 */
#define QADC_Q_3_13_SHIFT    13

/**
 * Perform xcore resource setup if QADC is to be used from C with lib_xcore PAR_JOBS().
 * Because QADC is written in XC it expects ports to be enabled and an XC timer to
 * be available. This pre-init function meets those needs if using from a lib_core 
 * based project
 *
 * \param p_adc          An array of 1 bit ports used for conversion.
 * \param num_adc        The number of QADC channels (ports) used
 */ 
void qadc_pre_init_c(port p_adc[], size_t num_adc);


/**@}*/ // END: addtogroup lib_qadc_common


#include "qadc_pot.h"
#include "qadc_rheo.h"