#################
Quasi ADC Library
#################


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

The xcore offers an inexpensive way to read the value of a variable resistor (rheostat) or a potentiometer without the need for a dedicated ADC component.
It uses know RC delay characteristics to determine the value of the resistor and only requires two passive components per channel.

The performance may be suitable for applications such as reading the position of an analog slider can may then be used to control an audio gain setting.
Resolutions in excess of eight bits can be achieved which may be adequate for many control applications.

********
Features
********

 * Rheostat reader or Potentiometer reader
 * One channel per 1-bit port
 * Up to 5000 raw conversions per second
 * 8 to 9 effective number of bits (ENOB)
 * Filtering and hysteresis functions for smoothing the output noise
 * Continuous conversion (using a thread) or single shot API

**************
Resource Usage
**************

The Rheostat reader requires XX kB and either one thread (continuous operation) or XX 1 millisecond of CPU time per conversion.

The Potentiometer reader requires XX kB and either one thread (continuous operation) or XX 1 millisecond of CPU time per conversion.

Both ADC types require a one bit port per ADC input.

*************************
Related Application Notes
*************************

  * None

Two simple examples, designed to run on the ``XK-EVK-XU316`` (xcore.ai explorer) board, can be found in the ``/examples`` directory.

************
Known Issues
************

  * None

**************
Required Tools
**************

  * XMOS XTC Tools: 15.3.0

*********************************
Required Libraries (dependencies)
*********************************

  * lib_xassert (www.github.com/xmos/lib_xassert)

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at www.xmos.com/support
