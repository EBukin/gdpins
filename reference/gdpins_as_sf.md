# Convert a data frame with a WKT text column to an sf object (autodetecting)

A friendly, single-column decoder for data whose geometry lives in a WKT
character column. Unlike
[`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md)
— which strictly decodes every `"<name>__<epsg>__"` column and reads the
CRS from the name — this function autodetects the geometry column and
infers the CRS, so it also handles hand-made or externally-produced
columns (`geom`, `geom_1111`, ...) whose name does not carry a clean
EPSG code.

## Usage

``` r
gdpins_as_sf(
  x,
  column = NULL,
  epsg = NULL,
  engine = NULL,
  default_epsg = 4326L
)
```

## Arguments

- x:

  A data frame with a WKT geometry column.

- column:

  Character scalar or `NULL`. Name of the WKT column. `NULL` autodetects
  (see Details).

- epsg:

  Integer scalar or `NULL`. EPSG code for the geometry CRS. `NULL`
  infers it from `column`'s name (see Details).

- engine:

  Character scalar, the WKT engine: `"wk"` (default) or `"sf"`. `NULL`
  uses the `gdpins.wkt_engine` option. See the
  [io-formats](https://ebukin.github.io/gdpins/reference/io-formats.md)
  "WKT engine" section.

- default_epsg:

  Integer scalar. CRS assumed when `epsg` is `NULL` and the column name
  carries no digits. Default `4326` (WGS 84).

## Value

An `sf` object, or — when autodetection finds no geometry column — the
input `x` unchanged (with a warning). A standard `__<epsg>__` suffix is
stripped from the converted column name; other names are kept as-is.

## Details

**Column detection.** When `column` is `NULL`, character columns whose
name matches the standard `__<epsg>__` suffix or contains
`"geom"`/`"wkt"` are candidates. Exactly one candidate is used
automatically. If none is found, `x` is returned unchanged with a
warning (so plain, non-spatial data passes through safely). If several
match, an error asks you to pass `column`. An explicitly supplied
`column` that is absent is always an error.

**CRS inference.** When `epsg` is `NULL`, the EPSG code is taken from
the column name: the standard `__<epsg>__` pattern is trusted silently;
a non-standard digit run (e.g. `geom_1111`) is used but emits a message;
a name with no digits falls back to `default_epsg` with a warning. In
the latter two cases you are firmly encouraged to pass `epsg`
explicitly. An explicit `epsg` argument always wins and silences
inference.

No coordinate transformation is performed; the EPSG code only labels the
CRS.

## See also

[`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md)
for strict multi-geometry decoding,
[`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md)
for the inverse, and
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
whose `wkt_engine = "none"` returns WKT text ready for this function.

## Examples

``` r
library(sf)
#> Linking to GEOS 3.12.1, GDAL 3.8.4, PROJ 9.4.0; sf_use_s2() is TRUE
pts <- st_sf(
  id = 1:2,
  geometry = st_sfc(st_point(c(71, 51)), st_point(c(76, 43)), crs = 4326)
)
encoded <- gdpins_sf_to_parquet(pts)   # a "geometry__4326__" WKT column
gdpins_as_sf(encoded)                  # autodetect column + EPSG, silent
#> Simple feature collection with 2 features and 1 field
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 71 ymin: 43 xmax: 76 ymax: 51
#> Geodetic CRS:  WGS 84
#> # A tibble: 2 × 2
#>      id    geometry
#>   <int> <POINT [°]>
#> 1     1     (71 51)
#> 2     2     (76 43)

# Non-standard name: EPSG inferred from the digits (with a message)
df <- data.frame(geom_3857 = "POINT (0 0)")
gdpins_as_sf(df)
#> ℹ Inferred EPSG 3857 from non-standard column name "geom_3857".
#> ℹ Pass `epsg` explicitly if this is not the intended CRS.
#> Simple feature collection with 1 feature and 0 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 0 ymin: 0 xmax: 0 ymax: 0
#> Projected CRS: WGS 84 / Pseudo-Mercator
#>     geom_3857
#> 1 POINT (0 0)

# No CRS in the name: pass epsg explicitly to avoid the default + warning
df2 <- data.frame(geom = "POINT (0 0)")
gdpins_as_sf(df2, epsg = 4326)
#> Simple feature collection with 1 feature and 0 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 0 ymin: 0 xmax: 0 ymax: 0
#> Geodetic CRS:  WGS 84
#>          geom
#> 1 POINT (0 0)
```
