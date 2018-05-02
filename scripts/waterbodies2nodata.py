import numpy as np
import rasterio

with rasterio.open('test_int.tif') as src:
    Z = src.read(1)
    profile = src.profile

with rasterio.open('waterbodies.tif') as wb:
    WB = wb.read(1)

# set negative values and waterbodies to nodata
Z[Z < 0] = -9999
Z[WB == 1] = -9999

with rasterio.open('nv.tif', 'w', **profile) as dst:
    dst.write(Z.astype(rasterio.int16), 1)
