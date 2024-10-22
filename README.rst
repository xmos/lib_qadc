:orphan:


###########################
lib_qadc: Quasi ADC Library
###########################


:vendor: XMOS
:version: 1.0.0
:scope: General Use
:description: Resistor reading library
:category: General Purpose
:keywords: ADC, potentiometer, rheostat, slider, control
:devices: xcore.ai

********
Overview
********

The xcore.ai family offers an inexpensive way to read the value of a variable resistor (rheostat) or a potentiometer without the need for a dedicated ADC component.
It uses known RC delay characteristics to determine the value of the resistor and only requires two additional passive components per channel.

The performance may be suitable for applications such as reading the position of an analog slider to control an audio gain setting.
Resolutions in excess of eight bits can be achieved which may be adequate for many control applications.

********
Features
********

 * Rheostat reader or Potentiometer reader
 * One channel per 1-bit port
 * Up to 3000 conversions per second
 * 8+ effective number of bits (ENOB)
 * Filtering and hysteresis functions for smoothing the output noise
 * Continuous conversion (using a thread) or single shot API via function call

**************
Resource Usage
**************

The Rheostat reader requires XX kB and either one thread (continuous operation) or ~300 microseconds of CPU time per conversion.

For a two channel, 8 bit (256 output levels) with a 16 entry moving average filter, the Potentiometer reader requires 5 kB and either one thread (continuous operation) and the Rheostat reader requires around 3 kB and one thread.

Both ADC types require a one bit port per ADC input.

*************************
Related Application Notes
*************************

  * None

Two simple examples, written to run on the ``XK-EVK-XU316`` (xcore.ai explorer) board, can be found in the ``/examples`` directory.

************
Known Issues
************

  * Auto calibration mode not yet implemented for Rheostat reader.

**************
Required Tools
**************

  * XMOS XTC Tools: 15.3.0

*********************************
Required Libraries (dependencies)
*********************************

  * None

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at www.xmos.com/support
