cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(lib_qadc_tests)
add_subdirectory(qadc_c_interface)
add_subdirectory(qadc_lut_pot_characterisation)
# add_subdirectory(qadc_lut_pot) # THIS IS INTENTIONALLY LEFT OUT BECAUSE WE NEED TO AUTOGEN THE HEADER FIRST IN THE TEST
