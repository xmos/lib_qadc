// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef __ADC_UTILS__
#define __ADC_UTILS__

#define dprintf(...) printf(__VA_ARGS__) 
// #define dprintf(...) 

// Pad control defines
#define PULL_NONE       0x0
#define PULL_UP_WEAK    0x1 // BUG doesn't work. Can half set by using set_pad_properties
#define PULL_DOWN_WEAK  0x2 // BUG 
#define BUS_KEEP_WEAK   0x3 // BUG 
#define PULL_SHIFT      18
#define DRIVE_2MA       0x0
#define DRIVE_4MA       0x1
#define DRIVE_8MA       0x2
#define DRIVE_12MA      0x3
#define DRIVE_SHIFT     20
#define SLEW_SHIFT      22
#define SCHMITT_SHIFT   23
#define RECEIVER_EN_SHIFT 17 // Set this to enable the IO reveiver

#define PAD_MAKE_WORD(port, drive_strength, pull_config, slew, schmitt) ((drive_strength << DRIVE_SHIFT) | \
                                                                        (pull_config << PULL_SHIFT) | \
                                                                        ((slew ? 1 : 0) << SLEW_SHIFT) | \
                                                                        ((schmitt ? 1 : 0) << SCHMITT_SHIFT) | \
                                                                        (1 << RECEIVER_EN_SHIFT) | \
                                                                        XS1_SETC_MODE_SETPADCTRL) 

// Macro to setup the port drive characteristics
#define set_pad_properties(port, drive_strength, pull_config, slew, schmitt)  {__asm__ __volatile__ ("setc res[%0], %1": : "r" (port) , "r" PAD_MAKE_WORD(port, drive_strength, pull_config, slew, schmitt));}

// Drive control defines
#define DRIVE_BOTH                  0x0 // Default
#define DRIVE_HIGH_WEAK_PULL_DOWN   0x1 // Open source w/pulldown
#define DRIVE_LOW_WEAK_PULL_UP      0x2 // Open drain w/pullup
#define DRIVE_MODE_SHIFT            0x3

#define set_pad_drive_mode(port, drive_mode)  {__asm__ __volatile__ ("setc res[%0], %1": : "r" (port) , "r" ((drive_mode << DRIVE_MODE_SHIFT) | \
                                                                                                            XS1_SETC_DRIVE_DRIVE)) ;}

#ifdef __XC__
float find_threshold_level(float v_rail, port p_adc);
void gen_lookup_pot(uint16_t * unsafe up, uint16_t * unsafe down, unsigned num_points,
                    float r_ohms, float capacitor_f, float rs_ohms,
                    float v_rail, float v_thresh,
                    uint32_t * unsafe max_lut_ticks_up, uint32_t * unsafe max_lut_ticks_down);
#else
void gen_lookup_pot(uint16_t * up, uint16_t * down, unsigned num_points,
                    float r_ohms, float capacitor_f, float rs_ohms,
                    float v_rail, float v_thresh,
                    uint32_t *max_lut_ticks_up, uint32_t *max_lut_ticks_down);
#endif

#endif