Quasi ADC Potentiometer Reader
==============================

Usage
-----

Stuff


Initialization
..............


.. _fig_qadc_pot_schem:
.. figure:: qadc_pot_schem.pdf
   :width: 100%

   QADC Potentiometer circuit


SRC Filter list
...............

A complete list of the filters supported by the SRC library, both SSRC and ASRC, is shown in :numref:`fig_src_filters`. The filters are implemented in C within the ``FilterDefs.c`` function and the coefficients can be found in the ``/FilterData`` folder. The particular combination of filters cascaded together for a given sample rate change is specified in ``ssrc.c`` and ``asrc.c``.


.. _fig_src_filters:
.. list-table:: SRC Filter Specifications
     :header-rows: 2

     * - Filter
       - Fs (norm)
       - Passband
       - Stopband
       - Ripple
       - Attenuation
       - Taps
       - Notes
     * - BL
       - 2
       - 0.454
       - 0.546
       - 0.01 dB
       - 155 dB
       - 144
       - Down-sampler by two, steep
     * - BL9644
       - 2
       - 0.417
       - 0.501
       - 0.01 dB
       - 155 dB
       - 160
       - Low-pass filter, steep for 96 to 44.1
     * - BL8848
       - 2
       - 0.494
       - 0.594
       - 0.01 dB
       - 155 dB
       - 144
       - Low-pass, steep for 88.2 to 48
     * - BLF
       - 2
       - 0.41
       - 0.546
       - 0.01 dB
       - 155 dB
       - 96
       - Low-pass at half band
     * - BL19288
       - 2
       - 0.365
       - 0.501
       - 0.01 dB
       - 155 dB
       - 96
       - Low pass, steep for 192 to 88.2
     * - BL17696
       - 2
       - 0.455
       - 0.594
       - 0.01 dB
       - 155 dB
       - 96
       - Low-pass, steep for 176.4 to 96
     * - UP
       - 2
       - 0.454
       - 0.546
       - 0.01 dB
       - 155 dB
       - 144
       - Over sample by 2, steep
     * - UP4844
       - 2
       - 0.417
       - 0.501
       - 0.01 dB
       - 155 dB
       - 160
       - Over sample by 2, steep for 48 to 44.1
     * - UPF
       - 2
       - 0.41
       - 0.546
       - 0.01 dB
       - 155 dB
       - 96
       - Over sample by 2, steep for 176.4 to 192
     * - UP192176
       - 2
       - 0.365
       - 0.501
       - 0.01 dB
       - 155 dB
       - 96
       - Over sample by 2, steep for 192 to 176.4
     * - DS
       - 4
       - 0.57
       - 1.39
       - 0.01 dB
       - 160 dB
       - 32
       - Down sample by 2, relaxed
     * - OS
       - 2
       - 0.57
       - 1.39
       - 0.01 dB
       - 160 dB
       - 32
       - Over sample by 2, relaxed
     * - HS294
       - 284
       - 0.55
       - 1.39
       - 0.01 dB
       - 155 dB
       - 2352
       - Polyphase 147/160 rate change
     * - HS320
       - 320
       - 0.55
       - 1.40
       - 0.01 dB
       - 151 dB
       - 2560
       - Polyphase 160/147 rate change
     * - ADFIR
       - 256
       - 0.45
       - 1.45
       - 0.012 dB
       - 170 dB
       - 1920
       - Adaptive polyphase prototype filter




QADC Potentiometer API
----------------------

.. doxygengroup:: qadc_pot
   :content-only:

