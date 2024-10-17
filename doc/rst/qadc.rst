Quasi ADC Potentiometer Reader
==============================

Introduction
------------

The xcore offers an inexpensive way to read the value of a variable resistor (rheostat) or a potentiometer without the need for a dedicated ADC component. The performance may be suitable for applications such as reading the position of an analog slider can may then be converted in to a gain control. Resolutions in excess of eight bits can be achieved which is adequate for many control applications.

The Quasi ADC (QADC) relies on the fact that the input threshold for the xcore IO is very constant at around 1.16 V for a Vddio of 3.3 V. By charging a capacitor to the full rail and discharging it through a resistor, the RC time constant can be determined. If you know C, then you can read R by timing the transition. As long as VDDIO remains constant between the charge and discharge cycles then the voltage component will cancel out. The xcore offers precise timing of transitions of IO using port logic (in this case 10 ns resolution) so a reasonable accuracy ADC can be implemented using just a couple of additional passive components.


Two schemes are offered which have different pros and cons depending on the application. The table below summarises the approaches.


.. _fig_src_filters:
.. list-table:: QADC Comparison
     :header-rows: 1

     * - Item
       - Rheostat reader
       - Potential reader
     * - Minimum scale
       - 0% + small dead zone
       - 0% + small dead zone
     * - Maximum scale
       - Dependent on end to end track tolerance
       - 100% + small dead zone
     * - Possible discontinuity or dead zone midway
       - No
       - Yes at 35% if tolerance of components poor
     * - Typical max counts
       - ~10000
       - ~10000
     * - Required VDDIO tolerance
       - 5%
       - 5%
     * - Typical minimum conversion time per channel
       - ~1 ms
       - ~1 ms
     * - Number of channels
       - Limited by 1 bit port count only
       - Limited by 1 bit port count only
     * - Typical ENOBs post filtering 
       - 8 / 9
       - 8 / 9
     * - Requires 5 % capacitor (eg C0G)
       - Yes
       - Yes
     * - Requires calibration
       - Ideally if passive components worse than 10 % tolerance. Will improve full scale estimated position.
       - Normally OK up to around 20 % passive tolerance. Will improved 35% transition and linearity.
     * - Linearity
       - Good
       - Reasonable, depending on passive tolerance
     * - Monotonicity
       - Yes
       - Yes
     * - Resource usage
       - XXX kB
       - XXX kB

Noise is always a concern in the analog domain and the QADC is no different. In particular power supply stability and coupled signals (such as running the QADC input close to a digital IO) should be considered when designing the circuitry. Since the QADC relies on continuously charging and discharging a capacitor it is also recommended that any analog supplies on the board are separated from the xcore digital supply to avoid any noise from the QADC conversion process being coupled to places where it would unwelcome.


Rheostat Reader
---------------

The rheostat reader uses just two terminals of a potentiometer which treats it as variable resistor. The scheme works as follows:

- Charge capacitor via IO by driving a `one` and waiting for at least 5 maximum RC charge periods.
- Make IO open circuit which initiates the discharge. Take the port timer at this point. Setup a `pinseq(0)` event on the port to capture the transition to zero.
- Wait for transition to 'zero` and take the stop timestamp.
- Set the port to high impedance because there is no point in fully discharging the capacitor.
- Calculate difference the difference in time.
- Post process value to reduce noise and improve linearity.



.. _fig_qadc_rheo_schem:
.. figure:: images/qadc_rheo_schem.pdf
   :width: 80%

   QADC Rehostat Circuit


The rheostat reader offers excellent linearity however it suffers from full scale setting accuracy if the passive components have large tolerances. This may result, for example with 20% tolerances, in full scale being read at 80% (and beyond) of the travel or only 80% being registered at the end of the travel.


.. _fig_qadc_rheo_ticks:
.. figure:: images/qadc_rheo_ticks.png
   :width: 80%

   QADC Rehostat Timer Ticks vs Position


Potential Reader
----------------

The potential reader uses all three terminals of a potentiometer where the track end terminals are connected between ground and Vddio. Depending on the initial reading of the IO pin, the QADC either charges the capacitor to Vddio or discharges it ground and then times the transition through the threshold point to the potential set by the potentiometer via the equivalent resistance of the potentiometer. The equivalent resistance of the potentiometer is the parallel of the upper and lower sections between the wiper and the end terminals. Due to the reasonably complex calculation required to determine the estimated position from the transition time, which includes several precision multiplies, divides and a logarithm, a look up table (LUT) is pre-calculated and initialisation to make the conversion step more efficient.


.. _fig_qadc_pot_ticks:
.. figure:: images/qadc_pot_ticks.png
   :width: 80%

   QADC Potentiometer Timer Ticks vs Position


.. _fig_qadc_pot_par_res:
.. figure:: images/qadc_pot_par_res.pdf
   :width: 80%

   QADC Potentiometer Equivalent Resistance vs Position


The scheme works as follows:

- Read the current port value to see if voltage of the potentiometer is above or below threshold
- Set the inverse port value and wait to charge capacitor fully to the supply rail
- Set the port to high impedance and take a timestamp
- Take a timestamp when voltage crosses threshold.
- Use the lookup table to calculate the start voltage.
- Post process value to reduce noise and improve linearity.

The potential reader offers good performance and is less susceptible to component tolerances due to the mathematics of using a parallel resistor network and logarithm used. It will always achieve zero and full scale however if tolerances are too large then it may show worse non-linearity than the rheostat reader and, in particular, around the 35% setting point which corresponds the threshold voltage of the IO. It does however always remain monotonic in operation. The fact that a small amount of noise is present when taking readings close to the threshold point and a moving average filter is typically used, these non-itineraries are reduced in practice.



.. _fig_qadc_pot_schem:
.. figure:: images/qadc_pot_schem.pdf
   :width: 80%

   QADC Potentiometer Circuit



.. _fig_qadc_pot_equiv_schem:
.. figure:: images/qadc_pot_equiv_schem.pdf
   :width: 80%

   QADC Potentiometer Equivalent Circuit



Post Processing
---------------

Both QADC schemes benefit from post processing of the raw measured transition time to improve performance.


.. _fig_post_proc:
.. figure:: images/qadc_post_proc.pdf
   :width: 80%

   QADC Post Processing Steps

The included post processing steps are as follows:



Zero Offset Removal
...................

There is a minimum time the architecture can setup a transition event on the port and the circuitry discharge a capacitor. The first post processing stage is therefore to remove this offset so that the zero scale (and full scale in the case of the potentiometer scheme) can be read as correctly.

Moving Average Filter
.....................

The moving average filter (sometimes know as a Boxcar FIR) helps filter out noise from the raw signal. It uses a conversion of history and takes the average value of the conversion and effectively low-pass filters the signal. One filter if provided per channel and the depth of the filter is configurable. A typical depth of 32 has been found to provide a good performance. Due to the low pass effect very long filters will reduce the response time of the QADC.

Scaling
.......

Scaling typically means reducing the resolution of the ADC from 12 - 13 bits and quantising it to a typical bit resolution such at 8, 9 or 10 bits. This provides a signal which has a know range, for example, 0 - 511 for the 9 bit case. This step also offers the possibility of calibration where the tolerance of the passive components may affect the estimated position of the input.

Hysteresis
..........

Even after filtering it may still be possible to see some small noise signal depending on configuration. This may also be exaggerated due to the natural quantisation to a digital value by the QADC, particularly if the setting is close to a transition point. By adding a small hysteresis (say a value of one or two) additional stability can be achieved at the cost of a very small dead zone at the last position. This may desirable if the QADC output is controlling a parameter that may be noticeable if it hunts between one or more positions. The hysteresis is configurable and may be removed completely if needed.


Comparing the Effect of Passive Component Tolerance on Both Schemes
-------------------------------------------------------------------

Both schemes offered will work very well when the overall passive component tolerances are good (e.g. 5%). However typical variable resistors/potentiometers are designed to produce good relative resistances rather than absolute resistances. The QADC relies more on absolute resistances, especially the rheostat approach.

When passive component tolerances are poor we see differing effects on the real-life transfer curves of ``actual position`` to ``estimated position`` depending on the scheme used.

For the `Rheostat` approach we see the good linearity and zero scale performance is always retained however full scale is directly affected. For example, if the resistor tolerance is 20% too low then the time constant will be smaller than expected and the maximum setting that can be achieved is 80% even at full travel. If the resistor tolerance is 20% too high then full scale will be achieved at 80% travel and the last 20% of travel will give the same reading of full scale. 

The small step close to zero is caused by the QADC not being able to charge the capacitor past the threshold voltage at low setting due to the series resistor.

If a manufacturing test is an option to calibrate the component values then this is likely the best approach to adopt. 

.. _fig_qadc_rheo_tol:
.. figure:: images/qadc_rheo_tol.png
   :width: 80%

   QADC Rehostat Effect of 20% Tolerance


The `Potentiometer` approach is more tolerant to the overall end to end resistance since it's operation also relies on the starting potential as well as the equivalent series resistance at any given setting, which itself is a function of the end-end track resistance. Even when tolerance is 20% out the end positions will always achieve zero and full scale however linearity is slightly degraded and a small flat spot or inflection point may be seen at around 1/3 of the travel. 

The curve will always remain monotonic increasing however the effect of noise (present in all ADCs) and the use of post processing (filtering and hysteresis)  reduces the real life affect to a couple of percent of the travel, too a point where it may be unnoticeable.

Where the potentiometer end to end resistance is higher than set in the model, flat spot effect will be seen due to a higher than expected RC constant when the potentiometer is near to the GPIO input threshold voltage. Where the potentiometer end to end resistance is lower than set in the model, the inflection effect will be see due to the RC time constant being shorter than expected.

The small steps close to zero and full scale settings are caused by the QADC not being able to charge the capacitor past the threshold voltage due to the potenial divider effect of the series resistor and the potentiometer equivalent series resistance.


Overall, it is recommended to use the `Potentiometer` approach in cases where the potentiometer tolerance is up to 20% and a manufacturing test is not practical.


.. _fig_qadc_pot_tol:
.. figure:: images/qadc_pot_tol.png
   :width: 80%

   QADC Potentiometer Effect of 20% Tolerance

Passive Component Selection
---------------------------

There are three components to consider when building one channel of QADC.

The variable resistor should be typically in the order of 20 - 50 kOhms. A lower value such as 10k Ohms may be used but it will either reduce the accuracy of the QADC slightly due to the increasing effect of the (required) series resistor and a reduced count or require the inclusion a larger capacitor to compensate which will increase power consumption due to greater charge/discharge amounts. The practical effect of this will also to be to increase the step sizes seen at the end positions of the transfer curves.

Choosing a value significantly of 100 k Ohms or above may also decrease performance due to PCB parasitics or IO input leakage affecting the accuracy.

The capacitor value should by typically around 2 - 5 nF typically with the same tradeoffs being seen as that of the variable resistor. A larger value is acceptable but it will increase the conversion time.

The series resistor value is a compromise. Ideally it would set to a low value to reduce the small step effects however this increases the current draw on the IO pin when the slider is close to end settings, which is undesirable. Typically a value of 1% of the variable resistor value is applicable with a minimum being around 330 ohms.

Typical values recommened are:

.. list-table:: Recommended values of QADC
   :widths: 25 25 25 25
   :header-rows: 1

   * - Capacitor nF
     - Potentiometer Ohms
     - Series resistor Ohms
     - Conversion cycle time
   * - 3300 5%
     - 10 k 10%
     - 470 1%
     - 


QADC Potentiometer API
----------------------

.. doxygenstruct:: adc_pot_config_t
    :members:

.. doxygenstruct:: adc_pot_state_t

.. doxygengroup:: lib_qadc_pot_reader
   :content-only:

