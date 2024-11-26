# Copyright 2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
#We assume that the Xscope FileIO Python library has been installed via pip beforehand and is available to import. Please see readme for instuctions.
import os
from pathlib import Path
import subprocess
import numpy as np
import sys
import matplotlib.pyplot as plt


root_dir = Path(__file__).parent.parent.absolute()
sys.path.append(str(root_dir/"design"))
from qadc_model import qadc_rheo, qadc_pot, plot_curve


def sim_sweep(model_cal, models_used, tolernace, num_points=1024):
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
        lut = model_cal.get_ticks_and_dir_from_posn(posn)
        est_posn = model_cal.lookup_posn_from_ticks(*lut)
        est_positions[idx] = est_posn

        for m in range(num_models):
            model = models_used[m]
            err_posn = model.lookup_posn_from_ticks(*lut)
            err_positions[m][idx] = err_posn

        idx += 1
        
    err_positions = [err_positions[m] for m in range(num_models)]
    y_values = [est_positions] + err_positions      
    plot_curve(positions, y_values, figname = f"Effect_of_pot_tolerance_{tolernace}%_{model.name}", y_label='Estimated position')



def qadc_rheo_test(tolerance_pc):
    r_rheo_nom = 47000
    cap_pf = 2200
    r_series = 470
    v_rail = 3.3
    v_thresh = 1.14

    qadc = qadc_rheo(cap_pf, r_rheo_nom, r_series, 3.3, v_thresh)
    qadc_rheo_is_under = qadc_rheo(cap_pf, r_rheo_nom * (1-(tolerance_pc/100)), r_series, v_rail, v_thresh)
    qadc_rheo_is_over = qadc_rheo(cap_pf, r_rheo_nom * (1+(tolerance_pc/100)), r_series, v_rail, v_thresh)
    sim_sweep(qadc, (qadc_rheo_is_under, qadc_rheo_is_over), tolerance_pc)


def qadc_pot_test(tolerance_pc):
    r_pot_nom = 47000
    cap_pf = 2200
    r_series = 470
    v_rail = 3.3
    v_thresh = 1.14

    qadc = qadc_pot(cap_pf, r_pot_nom, r_series, 3.3, v_thresh)
    qadc_pot_is_under = qadc_pot(cap_pf, r_pot_nom * (1-(tolerance_pc/100)), r_series, v_rail, v_thresh)
    qadc_pot_is_over = qadc_pot(cap_pf, r_pot_nom * (1+(tolerance_pc/100)), r_series, v_rail, v_thresh)
    sim_sweep(qadc, (qadc_pot_is_under, qadc_pot_is_over), tolerance_pc)

def test_tolernace_pot():
    qadc_pot_test(20)

def test_tolernace_rheo():
    qadc_rheo_test(20)

if __name__ == "__main__":
    test_tolernace_pot()
    test_tolernace_rheo()
