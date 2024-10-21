// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

// This setup connects a GPIO slice to the 316 MC board to provide a semi-automated curve

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "qadc.h"
#include "i2c.h"
#include "xassert.h"

#define NUM_ADC             1
#define LUT_SIZE            1024
#define FILTER_DEPTH        4
#define HYSTERESIS          1
#define CONVERT_MS          1
#define POT_OHMS_NOMINAL    10500
#define PERCENT_POT         0 // Set to 0 for perfect R = model
// Note opposite tolerance value because we are simulating the physical pot changing not model
#define POT_OHMS (unsigned) (float)(100 - PERCENT_POT) * POT_OHMS_NOMINAL / 100.0

const unsigned capacitor_pf = 8800;
const unsigned potentiometer_ohms = POT_OHMS;
const unsigned resistor_series_ohms = 220;

const float v_rail = 3.3;
const float v_thresh = 1.15;
const char auto_scale = 0;
const uint16_t zero_offset_ticks = 36;

const unsigned convert_interval_ticks = (CONVERT_MS * XS1_TIMER_KHZ);

// on tile[1]: port p_adc[] = {XS1_PORT_1K, XS1_PORT_1L}; // Sets which pins are to be used (channels 0..n)
on tile[1]: port p_adc[] = {XS1_PORT_1L};
on tile[0]: port p_scl = XS1_PORT_1L;
on tile[0]: port p_sda = XS1_PORT_1M;
on tile[0]: out port p_ctrl = XS1_PORT_8D;              /* p_ctrl:
                                                         * [0:3] - Unused
                                                         * [4]   - EN_3v3_N    (1v0 hardware only)
                                                         * [5]   - EN_3v3A
                                                         * [6]   - EXT_PLL_SEL (CS2100:0, SI: 1)
                                                         * [7]   - MCLK_DIR    (Out:0, In: 1)
                                                         */

on tile[0]: in port p_margin = XS1_PORT_1G;  /* CORE_POWER_MARGIN:   Driven 0:   0.925v
                                              *                      Pull down:  0.922v
                                              *                      High-z:     0.9v
                                              *                      Pull-up:    0.854v
                                              *                      Driven 1:   0.85v
                                              */

/* Board setup for XU316 MC Audio (1v1) */
#define EXT_PLL_SEL__MCLK_DIR    (0x80)
void board_setup()
{
    /* "Drive high mode" - drive high for 1, non-driving for 0 */
    set_port_drive_high(p_ctrl);

    /* Ensure high-z for 0.9v */
    p_margin :> void;

    /* Drive control port to turn on 3V3 and mclk direction appropriately.
     * Bits set to low will be high-z, pulled down */
    p_ctrl <: EXT_PLL_SEL__MCLK_DIR | 0x20;

    /* Wait for power supplies to be up and stable */
    delay_milliseconds(10);
}

// PCA9540B (2-channel I2C-bus mux) I2C Slave Address
#define PCA9540B_I2C_DEVICE_ADDR    (0x70)
// PCA9540B (2-channel I2C-bus mux) Control Register Values
#define PCA9540B_CTRL_CHAN_0        (0x04) // Set Control Register to select channel 0
#define PCA9540B_CTRL_CHAN_1        (0x05) // Set Control Register to select channel 1
#define PCA9540B_CTRL_CHAN_NONE     (0x00) // Set Control Register to select neither channel

void SetI2CMux(int ch, client interface i2c_master_if i2c)
{
    i2c_regop_res_t result;

    // I2C mux takes the last byte written as the data for the control register.
    // We can't send only one byte so we send two with the data in the last byte.
    // We set "address" to 0 below as it's discarded by device.
    unsafe
    {
        result = i2c.write_reg(PCA9540B_I2C_DEVICE_ADDR, 0, ch);
    }

    xassert(result == I2C_REGOP_SUCCESS && msg("I2C Mux I2C write reg failed"));
}

void control_task(chanend c_adc, client interface i2c_master_if i2c){

    delay_milliseconds(100);

    uint16_t cal_table[1024] = {0};

    SetI2CMux(PCA9540B_CTRL_CHAN_0, i2c);
    
    const uint8_t addr = 0x28;
    uint8_t config[] = {0x23}; // Convert on V1
    size_t num_sent;
    i2c_res_t r = i2c.write(addr, config, 1, num_sent, 1); //Write configuration information to ADC for calib

    int running = 1;

    while(running){
        uint8_t i2c_data[2] = {0};
        
        uint32_t adc[NUM_ADC];

        delay_ticks(convert_interval_ticks * FILTER_DEPTH * 2);

        int ch = 0;
        c_adc <: (uint32_t)QADC_CMD_READ | ch;
        c_adc :> adc[ch];

        c_adc <: (uint32_t)QADC_CMD_STOP_CONV;
        delay_milliseconds(5); // Time to read the actual pot voltage
        r = i2c.read(addr, i2c_data, 2, 1);
        if(r != I2C_ACK){
            printf("Ext ADC read error...\n");
        }
        uint16_t ref_val = (((i2c_data[0] & 0xf) << 8) | i2c_data[1]) >> 2;
        printf("ref_val: %u conv_val: %u \n", ref_val, adc[ch]);
        c_adc <: (uint32_t)QADC_CMD_STOP_CONV;

        cal_table[ref_val] = adc[ch];
        delay_milliseconds(1);

        if (ref_val == 1023){
            running = 0;
        }
    }

    printf("Exiting ADC and writing table.. Model pot ohms: %u\n", potentiometer_ohms);

    FILE * movable ct;
    ct = fopen("cal_table.bin", "wb");
    fwrite(cal_table, 2, 1024, ct);
    fclose(move(ct));

    FILE * movable pf;
    pf = fopen("params.txt", "wt");
    char string[1024];
    sprintf(string, "%d_%d_%d_%.2f_%d", capacitor_pf, POT_OHMS_NOMINAL, resistor_series_ohms, v_thresh, PERCENT_POT);
    fprintf(pf, "%s\n", string);
    fclose(move(pf));

    // Close peripherals
    i2c.shutdown();
    c_adc <: (uint32_t) QADC_CMD_EXIT;
}

int main() {
    interface i2c_master_if i2c[1];

    par{
        on tile[0]:{
            board_setup();
            i2c_master(i2c, 1, p_scl, p_sda, 10);
        }
        on tile[1]:{
            chan c_adc;
            
            const qadc_config_t adc_config = {capacitor_pf,
                                                potentiometer_ohms,
                                                resistor_series_ohms,
                                                v_rail,
                                                v_thresh,
                                                auto_scale,
                                                convert_interval_ticks,
                                                zero_offset_ticks};
            qadc_pot_state_t adc_pot_state;

            uint16_t state_buffer[QADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];
            qadc_pot_init(p_adc, NUM_ADC, LUT_SIZE, FILTER_DEPTH, HYSTERESIS, state_buffer, adc_config, adc_pot_state);

            par
            {
                qadc_pot_task(c_adc, p_adc, adc_pot_state);
                control_task(c_adc, i2c[0]);
            }
            printf("FINISHED!!\n");
        }
    }

    return 0;
}
