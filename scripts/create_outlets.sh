ogr2ogr \
  -s_srs EPSG:3005 \
  -t_srs EPSG:26910 \
  outlets_sqam.shp \
  PG:"host=localhost user=postgres dbname=postgis password=postgres"\
  -sql "WITH waterbody_inlets AS
(
SELECT DISTINCT ON (s1.waterbody_key, s1.blue_line_key)
  s1.blue_line_key as blkey,
  s1.downstream_route_measure as meas,
  ST_LineInterpolatePoint(ST_LineMerge(s1.geom), 1) AS geom
FROM whse_basemapping.fwa_stream_networks_sp s1
INNER JOIN whse_basemapping.fwa_stream_networks_sp s2
ON s1.blue_line_key = s2.blue_line_key
AND s1.downstream_route_measure < s2.downstream_route_measure
WHERE s1.watershed_group_code = 'SQAM'
AND s1.waterbody_key IS NOT NULL
AND s1.fwa_watershed_code NOT LIKE '999%'
AND s1.blue_line_key = s1.watershed_key
ORDER BY s1.waterbody_key, s1.blue_line_key, s1.downstream_route_measure desc
),

confluences AS
(SELECT
blue_line_key as blkey,
0 as meas,
ST_LineInterpolatePoint(ST_LineMerge(streams.geom), ROUND(CAST((0 - streams.downstream_route_measure) / streams.length_metre AS NUMERIC), 5)) AS geom
FROM whse_basemapping.fwa_stream_networks_sp streams
WHERE watershed_group_code = 'SQAM'
AND downstream_route_measure = 0
AND waterbody_key IS NULL
AND fwa_watershed_code NOT LIKE '999%')


SELECT row_number() over() as outlet_id, blkey, meas, geom
FROM
(SELECT * FROM waterbody_inlets
UNION ALL
SELECT * FROM confluences) as foo"

# to make sure we only use outlet points that have DEM data,
# add elevation to the output points
fio cat outlets_sqam.shp | rio pointquery -r ../dem/nv.tif | fio load temp.shp --driver Shapefile

# then dump to outlets_nv, all outlets where there is a value for elevation
ogr2ogr outlets_nv.shp temp.shp -where "value is not null"

# delete temp shapefile
../scripts/rmshp temp.shp
