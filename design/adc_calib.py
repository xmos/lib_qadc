#Copyright 2024 XMOS LIMITED.
#This Software is subject to the terms of the XMOS Public Licence: Version 1.

import matplotlib.pyplot as plt
import math
import numpy as np


def plot_curve(x_values, y_values, figname="plot"):
    plt.clf()

    # Plotting the line graph
    for ys in y_values:
        plt.plot(x_values, ys)

    # Adding labels and title
    plt.xlabel('Pot position')
    plt.title(figname)

    # Displaying the plot
    # plt.show()
    plt.savefig(figname+".png")


class qadc_rheo:
    def __init__(self,
                capacitor_pf,   # nominal value of storage cap
                r_rheo_ohms,    # nominal maximum value end to end of pot
                rs_ohms,        # nominal value of series resistor
                v_rail,         # Vddio
                v_thresh,       # input threhsold
                n_lookup=1024):

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

        plot_curve(positions, [down], "ticks_versus_slider")

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
        v_thresh_noise = np.random.triangular(-v_thresh_noise_mv, 0, v_thresh_noise_mv, 1)
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

        self.n_lookup = n_lookup
        self.v_rail = v_rail
        self.v_thresh = v_thresh

        phi = 1e-10 # avoid / 0
        XS1_TIMER_HZ = 100e6
        capacitor_f = capacitor_pf * 1e-12

        up = [0] * (n_lookup)
        down = [0] * (n_lookup)
        max_ticks = 0

        positions = range(n_lookup)
        for i in positions:
            # Calculate equivalent resistance of pot
            r_low = r_pot_ohms * (i + phi) / (n_lookup - 1)
            r_high = r_pot_ohms * ((n_lookup - i) + phi) / (n_lookup - 1)
            r_parallel = 1 / (1 / r_low + 1 / r_high)

            # Calculate equivalent resistances when charging via Rs
            rp_driving_low = 1 / (1 / r_low + 1 / rs_ohms)
            rp_driving_high = 1 / (1 / r_high + 1 / rs_ohms)

            # Calculate actual charge voltage of capacitor when using series resistor
            v_charge_h = r_low / (r_low + rp_driving_high) * v_rail
            v_charge_l = rp_driving_low / (rp_driving_low + r_high) * v_rail

            # Calculate time to for cap to reach threshold from charge volatage
            v_pot = i / n_lookup * v_rail + phi
            logval_down = 1 - (v_charge_h - v_thresh) / (v_rail - v_pot)
            t_down = 0 if logval_down <= 0 else (-r_parallel) * capacitor_f * math.log(logval_down)
            logval_up = 1 - ((v_thresh - v_charge_l) / v_pot)
            t_up = 0 if logval_up <= 0 else (-r_parallel) * capacitor_f * math.log(logval_up)

            # Convert to 100MHz timer ticks
            t_down_ticks = 0 if t_down < 0 else int(t_down * XS1_TIMER_HZ)
            t_up_ticks = 0 if t_up < 0 else int(t_up * XS1_TIMER_HZ)

            # print(f"LUT idx: {i} r_parallel: {r_parallel:.1f} v_pot: {v_pot:.2f} v_charge_h: {v_charge_h:.2f} v_charge_l: {v_charge_l:.2f} t_down: {t_down_ticks} t_up: {t_up_ticks}")

            up[i] = t_up_ticks
            down[i] = t_down_ticks
            max_ticks = max(up[i], max_ticks)
            max_ticks = max(down[i], max_ticks)

            assert max_ticks < 65535, "RC constant exceeds maximum timer depth"

        self.up = up
        self.down = down
        positions = [p / (n_lookup - 1) for p in list(positions)] #normalise from 0-1

        plot_curve(positions, (up, down), "ticks_versus_slider")

    def lookup_posn_from_ticks(self, ticks, start_high, model=None):
        if model is None:
            model = (self.up, self.down, self.n_lookup)

        up = model[0]
        down = model[1]
        n_lookup = model[2]

        if start_high:
            idx = n_lookup - 1 - np.argmax(np.flip(up) >= ticks)
        else:
            idx = np.argmax(np.array(down) >= ticks)

        return idx / (n_lookup - 1)

    def get_ticks_and_dir_from_posn(self, posn, v_thresh_noise_mv=0.0001):
        idx = int(posn * (self.n_lookup - 1))
        v_thresh_noise = np.random.triangular(-v_thresh_noise_mv, 0, v_thresh_noise_mv, 1)
        start_high = True if posn * self.v_rail > (self.v_thresh + v_thresh_noise) else False

        if start_high:
            ticks = self.up[idx]
        else:
            ticks = self.down[idx]

        return ticks, start_high


def sim_sweep(model_cal, models_used, num_points=100):
    if isinstance(models_used, type(model_cal)) == 1:
        num_models = 1
        models_used =[models_used]
    else:
        num_models = len(models_used)

    positions = np.linspace(0, 1, num_points)
    est_positions = np.zeros(num_points)
    err_positions = np.zeros((num_models, num_points))

    idx = 0
    for posn in positions:
        lut = model_cal.get_ticks_and_dir_from_posn(posn, v_thresh_noise_mv=0.08)
        est_posn = model_cal.lookup_posn_from_ticks(*lut)
        est_positions[idx] = est_posn

        for m in range(num_models):
            model = models_used[m]
            err_posn = model.lookup_posn_from_ticks(*lut)
            err_positions[m][idx] = err_posn

        idx += 1
        
    err_positions = [err_positions[m] for m in range(num_models)]
    y_values = [est_positions] + err_positions      
    plot_curve(positions, y_values, figname = "Effect_of_pot_tolerance_20pc")


def qadc_rheo_test():
    r_pot_nom = 47000
    tolerance = 0.2
    cap_pf = 3000
    r_series = 470
    v_rail = 3.3
    v_thresh = 1.14

    qadc = qadc_rheo(cap_pf, r_pot_nom, r_series, 3.3, v_thresh)
    qadc_rheo_is_under = qadc_rheo(cap_pf, r_pot_nom / (1+tolerance), r_series, v_rail, v_thresh)
    qadc_rheo_is_over = qadc_rheo(cap_pf, r_pot_nom * (1+tolerance), r_series, v_rail, v_thresh)
    sim_sweep(qadc, (qadc_rheo_is_under, qadc_rheo_is_over))


def qadc_pot_test():
    r_pot_nom = 47000
    tolerance = 0.2
    cap_pf = 3000
    r_series = 470
    v_rail = 3.3
    v_thresh = 1.14

    qadc = qadc_pot(cap_pf, r_pot_nom, r_series, 3.3, v_thresh)
    qadc_pot_is_under = qadc_pot(cap_pf, r_pot_nom / (1+tolerance), r_series, v_rail, v_thresh)
    qadc_pot_is_over = qadc_pot(cap_pf, r_pot_nom * (1+tolerance), r_series, v_rail, v_thresh)
    sim_sweep(qadc, (qadc_pot_is_under, qadc_pot_is_over))



if __name__ == '__main__':
    # qadc_pot_test()
    qadc_rheo_test()