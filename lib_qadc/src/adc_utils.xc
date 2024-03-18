// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <stdint.h>
#include <stdio.h>

clock cl_pwm = XS1_CLKBLK_5;

// Utility to find threshold voltage on port connected with long RC constant (longer than 0.001)
// When we are around the threshold point we can find it by driving PWM to see where the transition is
// Run at 1MHz to ensure accuracy and low ripple
float find_threshold_level(float v_rail, clock cl_pwm, port p_adc){

    set_clock_xcore(cl_pwm);
    set_port_clock(p_adc, cl_pwm);
    start_clock(cl_pwm);

    uint16_t total_period = XS1_TIMER_MHZ * 6; // 600 MHz

    printf("total_period: %u\n", total_period);

    int found_thresh = 0;
    float v_thresh_up = 0.0;
    float v_thresh_down = v_rail;

    uint16_t port_time;
    p_adc <: 0;
    delay_milliseconds(500); // Wait for strong zero

    p_adc <: 1 @ port_time;

    // We know the threshold is around 1.15V so sweep 10mV either side
    uint16_t low_bound = 1.05 / 3.3 * total_period;
    uint16_t high_bound = 1.25 / 3.3 * total_period;

    for(uint16_t high_time = low_bound; high_time < high_bound; high_time++){
        for(int i = 0; i < XS1_TIMER_HZ / total_period; i++){ // 10ms per read
            port_time += high_time;
            p_adc @ port_time <: 0;
            uint16_t low_time = total_period - high_time;
            port_time += low_time;
            p_adc @ port_time <: 1;
        }
        p_adc :> int _;
        delay_microseconds(1);
        int result = peek(p_adc);
        clearbuf(p_adc);
        printf("Up read: %d\n", result);

        if(!found_thresh && result == 1){
            found_thresh = 1;
            v_thresh_up = v_rail / (float)total_period * (float)high_time;
        }
    }

    found_thresh = 0;

    for(uint16_t high_time = high_bound; high_time > low_bound; high_time--){
        for(int i = 0; i < XS1_TIMER_HZ / total_period; i++){ // 10ms per read
            port_time += high_time;
            p_adc @ port_time <: 0;
            uint16_t low_time = total_period - high_time;
            port_time += low_time;
            p_adc @ port_time <: 1;
        }
        p_adc :> int _;
        delay_microseconds(1);
        int result = peek(p_adc);
        clearbuf(p_adc);
        printf("Down read: %d\n", result);

        if(!found_thresh && result == 0){
            found_thresh = 1;
            v_thresh_down = v_rail / (float)total_period * (float)high_time;
        }
    }

    printf("v_thresh_up: %f\n", v_thresh_up);
    printf("v_thresh_down: %f\n", v_thresh_down);
    printf("v_thresh_ave: %f\n", (v_thresh_up + v_thresh_down) / 2);

    return (v_thresh_up + v_thresh_down) / 2;
}