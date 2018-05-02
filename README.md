# Test generation of stream channels from LIDAR DEM

Test various tools for generating stream channel vectors from a sample DEM.

## Input data

`bc_092g035_xl1m_utm10_170713_ASC.asc` - a 1m resolution .asc grid

```
$ gdalinfo bc_092g035_xl1m_utm10_170713_ASC.asc
Driver: AAIGrid/Arc/Info ASCII Grid
Files: bc_092g035_xl1m_utm10_170713_ASC.asc
       bc_092g035_xl1m_utm10_170713_ASC.asc.ovr
       bc_092g035_xl1m_utm10_170713_ASC.asc.aux.xml
       bc_092g035_xl1m_utm10_170713_ASC.prj
Size is 14542, 11118
Coordinate System is:
PROJCS["NAD83_CSRS_UTM_zone_10N",
    GEOGCS["GCS_NORTH_AMERICAN_1983_CSRS",
        DATUM["NAD83_Canadian_Spatial_Reference_System",
            SPHEROID["GRS_1980",6378137,298.257222101]],
        PRIMEM["Greenwich",0],
        UNIT["Degree",0.017453292519943295]],
    PROJECTION["Transverse_Mercator"],
    PARAMETER["latitude_of_origin",0],
    PARAMETER["central_meridian",-123],
    PARAMETER["scale_factor",0.9996],
    PARAMETER["false_easting",500000],
    PARAMETER["false_northing",0],
    UNIT["Meter",1]]
Origin = (485459.000000000000000,5471924.000000000000000)
Pixel Size = (1.000000000000000,-1.000000000000000)
Corner Coordinates:
Upper Left  (  485459.000, 5471924.000) (123d12' 1.49"W, 49d23'59.39"N)
Lower Left  (  485459.000, 5460806.000) (123d12' 0.03"W, 49d17'59.37"N)
Upper Right (  500001.000, 5471924.000) (122d59'59.95"W, 49d24' 0.02"N)
Lower Right (  500001.000, 5460806.000) (122d59'59.95"W, 49d17'59.99"N)
Center      (  492730.000, 5466365.000) (123d 6' 0.35"W, 49d20'59.85"N)
Band 1 Block=14542x1 Type=Float32, ColorInterp=Undefined
  NoData Value=-9999
  Overviews: 7271x5559, 3636x2780, 1818x1390, 909x695, 455x348, 228x174
```

### preprocess the DEM

- create `dem` folder in project folder and copy provided DEM files to `dem/test.asc`
- round and convert to integer
    
        rio calc "(round (* 10 (read 1)))" test.asc test_round.tif
        gdal_translate -of "GTiff" -co "COMPRESS=LZW" -ot int16 test_round.tif test_int.tif

- set ocean, lakes/reservoirs to nodata:
        
        # export waterbodies to geojson
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

        # rasterize the polys
        rio rasterize waterbodies.tif --like test_int.tif < waterbodies.json

        # set these areas to nodata
        python3 ../scripts/waterbodies2nodata.py

## TauDEM

### links
http://hydrology.usu.edu/taudem/taudem5/documentation.html
http://hydrology.usu.edu/taudem/taudem5/TauDEM53CommandLineGuide.pdf

### Installation

#### macos
```
brew install taudem
```

#### linux

install openmpi 

```
wget https://www.open-mpi.org/software/ompi/v3.0/downloads/openmpi-3.0.1.tar.gz
tar -xvf openmpi-*
cd openmpi-*
./configure --prefix="/home/$USER/.openmpi"
make
sudo make install
export PATH="$PATH:/home/$USER/.openmpi/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/home/$USER/.openmpi/lib/"
```

install taudem

```
wget https://github.com/dtarb/TauDEM/archive/v5.3.8.tar.gz
tar -xvf v5.3.7.tar.gz
cd TauDEM-5.3.7/src
# edit CMakelists.txt as per https://github.com/OSGeo/homebrew-osgeo4mac/blob/master/Formula/taudem.rb
mkdir build && cd build
cmake ..
make && make install
```


### Usage


```
mkdir taudem
cd taudem

cp ../dem/nv.tif nv.tif

mpiexec -n 2 pitremove nv.tif 

# dinf flow model
mpiexec -n 2 dinfflowdir -ang nvang.tif -slp nvslp.tif -fel nvfel.tif
mpiexec -n 2 areadinf -ang nvang.tif -sca nvsca.tif

# d8 flow model
mpiexec -n 2 d8flowdir -p nvp.tif -sd8 nvsd8.tif -fel nvfel.tif
mpiexec -n 2 aread8 -p nvp.tif -ad8 nvad8.tif -nc

mpiexec -n 2 gridnet -p nvp.tif -plen nvplen.tif -tlen nvtlen.tif -gord nvgord.tif

mpiexec -n 2 peukerdouglas -fel nvfel.tif -ss nvss.tif 

# add flag for not checking edge contamination
mpiexec -n 2 aread8 -p nvp.tif -ad8 nvssa.tif -wg nvss.tif -nc

# to make sure we only use outlet points that have DEM data,
# add elevation to the output shape
# (manually filtered points with no elevation)
fio cat outlets.shp | rio pointquery -r nv.tif | fio load t_outlets.shp --driver Shapefile

# this should also work?
# ogr2ogr outlets2.shp t_outlets.shp -where "value is not null"

MoveOutletsToStrm -p nvp.tif -src nvsrc.tif -o t_outlets.shp -om outletsmoved.shp

# this command bails with segfault
dropanalysis \
  -p nvp.tif \
  -fel nvfel.tif \
  -ad8 nvad8.tif \
  -ssa nvss.tif \
  -drp nvdrp.txt \
  -o outletsmoved.shp \
  -par 5 500 10 0


mpiexec -n 2 threshold -ssa nvssa.tif -src nvsrc.tif -thresh 300

mpiexec -n 2 streamnet -fel nvfel.tif -p nvp.tif -ad8 nvad8.tif -src nvsrc.tif -ord nvord3.tif -tree nvtree.dat -coord nvcoord.dat -net nvnet.shp -w nvw.tif 

```

## Grass

## Other options
http://www.saga-gis.org/saga_tool_doc/6.3.0/ta_channels_0.html
https://gis.stackexchange.com/questions/109292/generate-channel-network-rainwater-run-off-which-algorithm-is-the-best