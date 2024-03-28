// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <xs1.h>
#include <stdio.h>

#include "adc_pot.h"
#include "i2c.h"
#include "xassert.h"

#define NUM_ADC         2
#define LUT_SIZE        1024
#define FILTER_DEPTH    32
#define HYSTERESIS      1

on tile[1]: port p_adc[] = {XS1_PORT_1K, XS1_PORT_1L}; // Sets which pins are to be used (channels 0..n)
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


for(int i=0; i<0x7f; i++){
    uint8_t bl[1];
    i2c_res_t r = i2c.read(i, bl, 1, 1); 
    printf("addr: 0x%x res: %d\n", i, r);
}


    SetI2CMux(PCA9540B_CTRL_CHAN_0, i2c);
    
    const uint8_t addr = 0x28;
    unsigned counter = 0;
    uint8_t config[] = {0x13}; // Convert on V1
    size_t num_sent;
    printf("pre\n");
    i2c.write(addr, config, 1, num_sent, 1); //Write configuration information to ADC
    // i2c.write_reg(addr, 0x00, config[0]); //Write configuration information to ADC
    printf("post\n");

    uint8_t data[2] = {0};


    while(1){
        uint32_t adc[NUM_ADC];
        uint32_t adc_dir[NUM_ADC];

        // while(1);

        printf("Read channel ");
        for(unsigned ch = 0; ch < NUM_ADC; ch++){
            c_adc <: (uint32_t)ADC_CMD_READ | ch;
            c_adc :> adc[ch];
            c_adc <: (uint32_t)ADC_CMD_POT_GET_DIR | ch;
            c_adc :> adc_dir[ch];

            printf("%u: %u (%u), ", ch, adc[ch], adc_dir[ch]);
        }
        putchar('\n');
        delay_milliseconds(100);

        // Optionally pause so we can read pot voltage for testing
        if(counter == 10){
            printf("Restarting ADC...\n");
            c_adc <: (uint32_t)ADC_CMD_POT_STOP_CONV;
            delay_milliseconds(1000); // Time to read the actual pot voltage
            c_adc <: (uint32_t)ADC_CMD_POT_START_CONV;
            counter = 0;
            delay_milliseconds(100);
        }
        i2c.read(addr, data, 2, 1);
        printf("data: 0x%x 0x%x\n", data[0], data[1]);
    }
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

            const unsigned capacitor_pf = 8800;
            const unsigned potentiometer_ohms = 10000; // nominal maximum value ned to end
            const unsigned resistor_series_ohms = 220;

            const float v_rail = 3.3;
            const float v_thresh = 1.15;
            const char auto_scale = 1;

            const unsigned convert_interval_ticks = (1 * XS1_TIMER_KHZ);
            
            const adc_pot_config_t adc_config = {capacitor_pf,
                                                potentiometer_ohms,
                                                resistor_series_ohms,
                                                v_rail,
                                                v_thresh,
                                                convert_interval_ticks,
                                                auto_scale};
            adc_pot_state_t adc_pot_state;

            uint16_t state_buffer[ADC_POT_STATE_SIZE(NUM_ADC, LUT_SIZE, FILTER_DEPTH)];
            adc_pot_init(NUM_ADC, LUT_SIZE, FILTER_DEPTH, HYSTERESIS, state_buffer, adc_config, adc_pot_state);
            par
            {
                adc_pot_task(c_adc, p_adc, adc_pot_state);
                control_task(c_adc, i2c[0]);
            }
        }
    }

    return 0;
}
