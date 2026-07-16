# Restore an sf object from a parquet-encoded tibble

Inverse of
[`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md).
Detects columns whose names match the pattern `^.*__\\d{4,5}__$` and
attempts to parse them as WKT geometry. Only columns where the WKT
actually parses are converted; others are left as plain strings (column
name is NOT changed).

## Usage

``` r
gdpins_parquet_to_sf(x, engine = NULL)
```

## Arguments

- x:

  A
  [`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
  previously produced by
  [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md).

- engine:

  Character scalar, the WKT engine: `"wk"` (default) or `"sf"`. `NULL`
  uses the `gdpins.wkt_engine` option (default `"wk"`). Reads are
  engine-agnostic — WKT written by either engine parses with either — so
  this only affects parsing speed. See the
  [io-formats](https://ebukin.github.io/gdpins/reference/io-formats.md)
  "WKT engine" section.

## Value

An `sf` object. Column names are restored to their original form (suffix
stripped). CRS is set from the EPSG code embedded in the name.

## See also

[`gdpins_as_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_as_sf.md)
for a single-column decoder that autodetects the geometry column and
infers the CRS from messier column names.

## Examples

``` r
library(sf)
pts <- st_sf(
  id = 1:2,
  geometry = st_sfc(st_point(c(71, 51)), st_point(c(76, 43)), crs = 4326)
)
encoded <- gdpins_sf_to_parquet(pts)
gdpins_parquet_to_sf(encoded)                 # default "wk" engine
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
gdpins_parquet_to_sf(encoded, engine = "sf")  # sf fallback
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
```
