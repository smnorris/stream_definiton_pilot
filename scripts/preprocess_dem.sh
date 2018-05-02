
# shrink the DEM by rounding to cm, converting to integer
rio calc "(round (* 10 (read 1)))" test.asc test_round.tif
gdal_translate -of "GTiff" -co "COMPRESS=LZW" -ot int16 test_round.tif test_int.tif

# set flat ocean, lakes/reservoirs to nodata

# first, get the waterbodies from FWA
ogr2ogr -f GeoJSON \
  -t_srs EPSG:26910 \
  waterbodies.json \
  PG:"host=localhost user=postgres dbname=postgis password=postgres"\
  -sql "SELECT
          waterbody_poly_id,
          geom
        FROM whse_basemapping.fwa_lakes_poly
        WHERE watershed_group_code = 'SQAM'
        UNION ALL
        SELECT
          waterbody_poly_id,
          geom
        FROM whse_basemapping.fwa_manmade_waterbodies_poly
        WHERE watershed_group_code = 'SQAM'"

# rasterize the waterbody polys
rio rasterize waterbodies.tif --like test_int.tif < waterbodies.json

# set the waterbodies to nodata
python3 ../scripts/waterbodies2nodata.py