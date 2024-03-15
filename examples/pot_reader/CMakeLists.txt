cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(padc_pot_example)

set(APP_HW_TARGET XCORE-AI-EXPLORER)
set(APP_DEPENDENT_MODULES   lib_padc)

set(APP_COMPILER_FLAGS  -O2
                        -g 
                        -report
                        )

XMOS_REGISTER_APP()