# Copyright 2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
#We assume that the Xscope FileIO Python library has been installed via pip beforehand and is available to import. Please see readme for instuctions.
import os
from pathlib import Path
import subprocess
import sys

root_dir = Path(__file__).parent.parent.absolute()

def test_c_api():
    # expects xe to be pre-built
    firmware_xe = root_dir/"tests/qadc_c_interface/bin/qadc_c_test.xe"
    cmd = f"xsim --args {firmware_xe}"
    subprocess.run(cmd.split())
