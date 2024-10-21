# Copyright 2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
#This Software is subject to the terms of the XMOS Public Licence: Version 1.

import matplotlib.pyplot as plt
import math
import numpy as np


def plot_curve(x_values, y_values, x_label="Pot position", y_label="100 MHz ticks", figname="plot"):
    plt.clf()

    # Plotting the line graph
    for ys in y_values:
        plt.plot(x_values, ys)

    # Adding labels and title
    plt.xlabel(x_label)
    plt.ylabel(y_label)
    plt.title(figname)

    # Displaying the plot
    # plt.show()
    plt.savefig(figname+".png", dpi=300)


class qadc_rheo:
    def __init__(self,
                capacitor_pf,   # nominal value of storage cap
                r_rheo_ohms,    # nominal maximum value end to end of pot
                rs_ohms,        # nominal value of series resistor
                v_rail,         # Vddio
                v_thresh,       # input threhsold
                n_lookup=1024):

        self.name = __class__.__name__
        self.max_ticks = 0
        self.v_rail = v_rail
        self.v_thresh = v_thresh
        self.n_lookup = n_lookup

        phi = 1e-10 # avoid / 0
        XS1_TIMER_HZ = 100e6
        capacitor_f = capacitor_pf * 1e-12

        max_ticks = 0

        positions = range(n_lookup)
        down = [0] * n_lookup
        for i in positions:
            # Calculate equivalent resistance of pot
            r_pot = r_rheo_ohms * i / (n_lookup - 1)

            # Calculate equivalent resistances when charging via Rs
            r_driving_low = 1 / (1 / (r_pot+phi) + 1 / rs_ohms)
            r_driving_high = rs_ohms

            # Calculate actual charge voltage of capacitor when using series resistor
            v_charge_h = r_pot / (r_pot + r_driving_high) * v_rail

            # Calculate time to for cap to reach threshold from charge volatage
            logval_down = 1 - (v_charge_h - v_thresh) / (v_charge_h + phi)
            t_down = 0 if logval_down <= 0 else (-r_pot) * capacitor_f * math.log(logval_down)
        
            # Convert to 100MHz timer ticks
            t_down_ticks = 0 if t_down < 0 else int(t_down * XS1_TIMER_HZ)

            # print(f"LUT idx: {i} v_charge_h: {v_charge_h:.2f} t_down: {t_down_ticks}")

            down[i] = t_down_ticks
            max_ticks = max(down[i], max_ticks)

            assert max_ticks < 65535, "RC constant exceeds maximum timer depth"

        self.down = down
        positions = [p / (n_lookup - 1) for p in list(positions)] #normalise from 0-1

        plot_curve(positions, [down], figname="QADC Rheo ticks_versus_slider")

    def lookup_posn_from_ticks(self, ticks, model=None):

        if model is None or model is False:
            model = (self.down, self.n_lookup)

        down = model[0]
        n_lookup = model[1]

        if max(down) < ticks:
            # Overshoot
            idx = self.n_lookup - 1
        else:
            idx = np.argmax(np.array(down) >= ticks)

        return idx / (n_lookup - 1)

    def get_ticks_and_dir_from_posn(self, posn, v_thresh_noise_mv=0.0001):
        idx = int(posn * (self.n_lookup - 1))
        
        #this is ignored for now in this class
        v_thresh_noise = np.random.triangular(-v_thresh_noise_mv/1000, 0, v_thresh_noise_mv/1000, 1)
        ticks = self.down[idx]

        return (ticks,)



class qadc_pot:
    def __init__(self,
                capacitor_pf,   # nominal value of storage cap
                r_pot_ohms,  # nominal maximum value end to end of pot
                rs_ohms,
                v_rail,         # Vddio
                v_thresh,       # input threhsold
                n_lookup=1024):

        self.name = __class__.__name__
        self.n_lookup = n_lookup
        self.v_rail = v_rail
        self.v_thresh = v_thresh

        phi = 1e-10 # avoid / 0
        XS1_TIMER_HZ = 100e6
        capacitor_f = capacitor_pf * 1e-12

        up = [0] * (n_lookup)
        down = [0] * (n_lookup)
        max_ticks = 0

        print(f"capacitor_pf: {capacitor_pf} r_pot_ohms: {r_pot_ohms} rs_ohms: {rs_ohms} v_rail: {v_rail:.2f} v_thresh: {v_thresh:.2f} n_lookup: {n_lookup}")

        positions = range(n_lookup)
        for i in positions:
            # Calculate equivalent resistance of pot
            r_low = r_pot_ohms * (i + phi) / (n_lookup - 1)
            r_high = r_pot_ohms * ((n_lookup - i - 1) + phi) / (n_lookup - 1)
            r_parallel = 1 / (1 / r_low + 1 / r_high)

            # Calculate equivalent resistances when charging via Rs
            rp_driving_low = 1 / (1 / r_low + 1 / rs_ohms)
            rp_driving_high = 1 / (1 / r_high + 1 / rs_ohms)

            # Calculate actual charge voltage of capacitor when using series resistor
            v_charge_l = rp_driving_low / (rp_driving_low + r_high) * v_rail
            v_charge_h = r_low / (r_low + rp_driving_high) * v_rail

            # Calculate time to for cap to reach threshold from charge volatage
            v_pot = i / (n_lookup - 1) * v_rail + phi
            logval_up = 1 - ((v_thresh - v_charge_l) / (v_pot - v_charge_l))
            t_up = 0 if logval_up <= 0 else (-r_parallel) * capacitor_f * math.log(logval_up)
            v_down_offset = v_rail - v_charge_h;
            logval_down = 1 - (v_rail - v_thresh - v_down_offset) / (v_rail - v_pot - v_down_offset)
            t_down = 0 if logval_down <= 0 else (-r_parallel) * capacitor_f * math.log(logval_down)


            # Convert to 100MHz timer ticks
            t_down_ticks = 0 if (t_down < 0 or v_pot >= v_thresh) else int(t_down * XS1_TIMER_HZ)
            t_up_ticks = 0 if (t_up < 0 or v_pot <= v_thresh) else int(t_up * XS1_TIMER_HZ)

            # print(f"LUT idx: {i} r_parallel: {r_parallel:.1f} v_pot: {v_pot:.2f} v_charge_h: {v_charge_h:.2f} v_charge_l: {v_charge_l:.2f} t_down: {t_down_ticks} t_up: {t_up_ticks}")

            up[i] = t_up_ticks
            down[i] = t_down_ticks
            max_ticks = max(up[i], max_ticks)
            max_ticks = max(down[i], max_ticks)

            assert max_ticks < 65535, "RC constant exceeds maximum timer depth"

        self.up = up
        self.down = down
        positions = [p / (n_lookup - 1) for p in list(positions)] #normalise from 0-1

        plot_curve(positions, (up, down), figname="QADC Pot ticks_versus_slider")

    def lookup_posn_from_ticks(self, ticks, start_high, model=None):
        if model is None:
            model = (self.up, self.down, self.n_lookup)

        up = model[0]
        down = model[1]
        n_lookup = model[2]

        if start_high:
            if ticks > np.max(np.flip(up)):
                idx = n_lookup - 1 - np.argmax(np.flip(up))
            else:
                idx = n_lookup - 1 - np.argmax(np.flip(up) >= ticks)
        else:
            if ticks > np.max(np.array(down)):
                idx = np.argmax(np.array(down))
            else:
                idx = np.argmax(np.array(down) >= ticks)

        return idx / (n_lookup - 1)

    def get_ticks_and_dir_from_posn(self, posn):
        idx = int(posn * (self.n_lookup - 1))
        start_high = True if posn * self.v_rail > self.v_thresh else False

        if start_high:
            ticks = self.up[idx]
        else:
            ticks = self.down[idx]

        return ticks, start_high


# See tests/test_qadc_model_tolerance.py for an example of using this model