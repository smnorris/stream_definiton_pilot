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

### Preprocess DEM

Requirements:
- gdal
- rasterio
- fiona
- Python 3

First, create `dem` folder in project folder and copy provided DEM file to `dem/test.asc`, then run the preprocessing to simplify the DEM and set waterbodies to NODATA:

```        
$ cd dem
$ ../scripts/preprocess_dem.sh
```


### Create outlets/pour points

(not needed for generating streams)

Requirements:
- gdal
- postgresql/postgis
- `fwakit` and FWA data for `SQAM` watershed group

Generate points at:
- FWA stream confluences
- intersections of FWA streams with lakes, reservoirs and ocean (at the point where the stream flows into the waterbody)

From our root project folder:

```
$ mkdir outlets
$ cd outlets
$ ../scripts/create_outlets.sh
```


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

Create a stream network from the D8 flow model and contributing area, with 1000 as the minimum contributing area:

```
mkdir taudem
cd taudem

# make a copy of the preprocessed dem in the taudem folder
cp ../dem/nv.tif nv.tif

# fill in depressions/pits
mpiexec -n 2 pitremove nv.tif 

# run d-8 flow model
mpiexec -n 2 d8flowdir -p nvp.tif -sd8 nvsd8.tif -fel nvfel.tif

# calculate the contributing area (do not check for edge contamination)
mpiexec -n 2 aread8 -p nvp.tif -ad8 nvad8.tif -nc

# create stream raster with 1000 threshold
mpiexec -n 2 threshold -ssa nvssa.tif -src nvsrc.tif -thresh 1000

# export streams to shape (along with watersheds)
mpiexec -n 2 streamnet -fel nvfel.tif -p nvp.tif -ad8 nvad8.tif -src nvsrc.tif -ord nvord3.tif -tree nvtree.dat -coord nvcoord.dat -net nvnet.shp -w nvw.tif 
```

Other available commands from quickstart:
```
# run gridnet, producing:
# (1) the longest flow path along D8 flow directions to each grid cell
# (2) the total length of all flow paths that end at each grid cell
# (3) the grid network order
mpiexec -n 2 gridnet -p nvp.tif -plen nvplen.tif -tlen nvtlen.tif -gord nvgord.tif

# run peukerdoglas, producing a skeleton of a stream network derived entirely 
# from a local filter applied to the topography
mpiexec -n 2 peukerdouglas -fel nvfel.tif -ss nvss.tif 

# run d-infinity flow model (just as a test, we don't use this)
mpiexec -n 2 dinfflowdir -ang nvang.tif -slp nvslp.tif -fel nvfel.tif
mpiexec -n 2 areadinf -ang nvang.tif -sca nvsca.tif

# run d-8 contrib area with peukderdouglas streams as a weighting factor
# - adding flag for not checking edge contamination
# - using streams from peukerdouglas as a weight
mpiexec -n 2 aread8 -p nvp.tif -ad8 nvssa.tif -wg nvss.tif -nc

# move outlets to streams
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

```

## Grass

## Other options
http://www.saga-gis.org/saga_tool_doc/6.3.0/ta_channels_0.html
https://gis.stackexchange.com/questions/109292/generate-channel-network-rainwater-run-off-which-algorithm-is-the-best