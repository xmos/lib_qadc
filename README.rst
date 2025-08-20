:orphan:

##############################
lib_qadc: Quasi ADC using GPIO
##############################

:vendor: XMOS
:version: 1.0.1
:scope: General Use
:description: Quasi ADC for reading variable resistors using GPIO
:category: General Purpose
:keywords: ADC
:devices: xcore.ai

*******
Summary
*******

The xcore.ai family offers an inexpensive way to read the value of a variable resistor (rheostat) or a potentiometer without the need for a dedicated ADC component. It uses known RC delay characteristics to determine the value of the resistor and only requires two additional passive components per channel.

The performance may be suitable for applications such as reading the position of an analog slider to control an audio gain setting.
Resolutions in excess of eight bits can be achieved which can be adequate for many control applications.

********
Features
********

 * Rheostat reader or Potentiometer reader
 * One channel per 1-bit port (wide ports supported for Potentiometer type)
 * Up to 3000 conversions per second
 * 8+ effective number of bits (ENOB)
 * Filtering and hysteresis functions for smoothing noise
 * Continuous conversion (using a thread) or single shot API via function call

************
Known issues
************

* Calibration mode not yet implemented for Rheostat reader.

****************
Development repo
****************

* `lib_qadc <https://www.github.com/xmos/lib_qadc>`_

**************
Required tools
**************

* XMOS XTC Tools: 15.3.1

*********************************
Required libraries (dependencies)
*********************************

* None

*************************
Related application notes
*************************

* None

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at
`www.xmos.com/support <https://www.xmos.com/support>`_

