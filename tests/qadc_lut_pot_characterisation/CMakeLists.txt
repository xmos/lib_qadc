cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(qadc_pot_characterisation)

set(APP_HW_TARGET XCORE-AI-EXPLORER)

set(APP_DEPENDENT_MODULES   lib_i2c
                            lib_qadc
                            lib_logging
                            lib_xassert
                            )

set(APP_COMPILER_FLAGS  -Os
                        -g 
                        -report
                        )


# Workaround for now until cmake xcommon supports this
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
