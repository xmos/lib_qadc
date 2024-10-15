cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(qadc_pot_example)

set(APP_HW_TARGET XCORE-AI-EXPLORER)
set(APP_DEPENDENT_MODULES   lib_qadc)

set(COMMON_COMPILER_FLAGS           -Os
                                    -g 
                                    -report
                        )

set(APP_COMPILER_FLAGS_CONTINUOUS   ${COMMON_COMPILER_FLAGS}
                                    -DCONTINUOUS=1)

set(APP_COMPILER_FLAGS_SINGLE       ${COMMON_COMPILER_FLAGS}
                                    -DCONTINUOUS=0)


# Workaround for now until cmake xcommon supports this
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../../..)
XMOS_REGISTER_APP()