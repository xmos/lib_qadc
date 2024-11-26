# Copyright 2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
#We assume that the Xscope FileIO Python library has been installed via pip beforehand and is available to import. Please see readme for instuctions.
import os
from pathlib import Path
import subprocess
import numpy as np
import sys

file_dir = Path(__file__).parent.absolute()
root_dir = Path(__file__).parent.parent.absolute()

sys.path.append(str(root_dir/"design"))
import qadc_model


def pot_lut_compare(cap_pf, res_pot, res_ser, vrail, vthresh, num_adc, filter_depth, lut_size, hysteresis):
    firmware_xe = root_dir/"tests"/"qadc_lut_pot"/"bin"/"qadc_pot_lut.xe"
    lut_file = file_dir/"pot_lut.bin"
    if os.path.exists(lut_file):
        os.remove(lut_file)


    print(f"Firmware: {firmware_xe}")

    # Create header file for filter sizing etc.
    with open(str(file_dir/"qadc_lut_pot/src/filter_settings.h"), "wt") as incl:
        text = f"#define NUM_ADC         {num_adc}\n"
        text+= f"#define LUT_SIZE        {lut_size}\n"
        text+= f"#define FILTER_DEPTH    {filter_depth}\n"
        text+= f"#define HYSTERESIS      {hysteresis}\n"
        incl.write(text)

    # Build test app
    cmd = 'cmake -G "Unix Makefiles" -B build'
    assert not subprocess.run(cmd, shell=True, cwd=str(file_dir/"qadc_lut_pot")).returncode
    cmd = 'xmake -j'
    assert not subprocess.run(cmd, shell=True, cwd=str(file_dir/"qadc_lut_pot/build")).returncode

    # Run test app
    cmd = f"xsim --args {firmware_xe} {cap_pf} {res_pot} {res_ser} {vrail} {vthresh}"
    assert not subprocess.run(cmd.split()).returncode

    # Load output
    lut_dut = np.fromfile(lut_file, dtype=np.uint16)
    
    # Extract LUT
    lut_dut_up = lut_dut[:lut_size] 
    lut_dut_down = lut_dut[lut_size:]

    # Get model LUT
    qadc = qadc_model.qadc_pot(cap_pf, res_pot, res_ser, vrail, vthresh, lut_size)

    # Extract and turn into np
    lut_model_up = np.array(qadc.up, dtype=np.uint16)
    lut_model_down = np.array(qadc.down, dtype=np.uint16)


    assert lut_dut_up.shape == lut_model_up.shape, f"ERROR: LUTs different shapes {lut_dut_up.shape} {lut_model_up.shape}"
    assert lut_dut_down.shape == lut_model_down.shape, f"ERROR: LUTs different shapes {lut_dut_down.shape} {lut_model_down.shape}"

    for i in range(lut_size):
        assert np.isclose(lut_dut_up[i], lut_model_up[i], rtol=0.001), f"ERROR: LUTs different at index {i}"
        assert np.isclose(lut_dut_down[i], lut_model_down[i], rtol=0.001), f"ERROR: LUTs different at index {i}"


    print("LUT test OK")


def test_pot_lut():
    pot_lut_compare(3000, 47000, 470, 3.3, 1.14, 1, 32, 1022, 1)

if __name__ == "__main__":
    test_pot_lut()
