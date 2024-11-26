cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(qadc_rheo_example)

set(APP_HW_TARGET XK-EVK-XU316)
set(APP_DEPENDENT_MODULES               lib_qadc)

set(COMMON_COMPILER_FLAGS               -Os
                                        -g 
                                        -report)

set(APP_COMPILER_FLAGS_CONTINUOUS_CHAN  ${COMMON_COMPILER_FLAGS}
                                        -DCONTINUOUS=1)

set(APP_COMPILER_FLAGS_CONTINUOUS_MEM   ${COMMON_COMPILER_FLAGS}
                                        -DCONTINUOUS=1
                                        -DUSE_SHARED_MEMORY=1)


set(APP_COMPILER_FLAGS_SINGLE           ${COMMON_COMPILER_FLAGS}
                                        -DCONTINUOUS=0)

set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../../..)
XMOS_REGISTER_APP()