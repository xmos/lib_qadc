cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(qadc_pot_lut)

set(APP_HW_TARGET           XK-EVK-XU316)
set(APP_DEPENDENT_MODULES   lib_qadc)

set(APP_COMPILER_FLAGS  -Os
                        -g 
                        -report
                        -fcmdline-buffer-bytes=2048
                        )

# Workaround for now until cmake xcommon supports this
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../../..)
XMOS_REGISTER_APP()