import numpy as np
import matplotlib.pyplot as plt

def plot_unsigned_short_array(array, name):
    try:
        plt.scatter(range(len(array)), array, s=1)  # s parameter controls the size of points
        plt.xlabel('Cal pos')
        plt.ylabel('QADC pos')
        plt.title(f'Calibration curve: {params}')
        plt.grid(True)
        filename = "calib_table"
        percent = name.split("_")[-1].strip()
        print(percent)
        filename += "_" + str(percent) + ".png"
        print(filename)
        plt.savefig(filename, dpi=400)
    except KeyboardInterrupt:
        print("Plot display interrupted.")

if __name__ == "__main__":
    # File path of the binary file
    file_path = "cal_table.bin"

    # Read the array from the binary file
    with open(file_path, "rb") as file:
        # Assuming array is stored as uint16 little-endian
        array = np.fromfile(file, dtype=np.uint16)

    with open("params.txt", "rt") as pf:
        params = pf.readline()

    plot_unsigned_short_array(array, params)