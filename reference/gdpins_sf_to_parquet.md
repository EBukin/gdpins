# Convert an sf object to a plain tibble suitable for parquet storage

Converts all `sfc` geometry columns to WKT text and encodes the
per-column CRS (EPSG integer) into the column name using the pattern
`"<name>__<epsg>__"` (double-underscore both sides). The result is a
plain tibble with no `sf` class.

## Usage

``` r
gdpins_sf_to_parquet(x, engine = NULL)
```

## Arguments

- x:

  An `sf` data frame with one or more geometry columns.

- engine:

  Character scalar, the WKT engine: `"wk"` (default) or `"sf"`. `NULL`
  uses the `gdpins.wkt_engine` option (default `"wk"`). See the
  [io-formats](https://ebukin.github.io/gdpins/reference/io-formats.md)
  "WKT engine" section.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with geometry columns replaced by WKT character columns named
`"<original_name>__<epsg>__"`.

## Details

No coordinate transformation is performed. Each geometry is converted to
WKT text (never WKB) by the selected `engine` (see
[io-formats](https://ebukin.github.io/gdpins/reference/io-formats.md)).
Per-column CRS is supported.

## Examples

``` r
library(sf)
pts <- st_sf(
  id = 1:2,
  geometry = st_sfc(st_point(c(71, 51)), st_point(c(76, 43)), crs = 4326)
)
gdpins_sf_to_parquet(pts)                 # default "wk" engine
#> # A tibble: 2 × 2
#>      id geometry__4326__
#>   <int> <chr>           
#> 1     1 POINT (71 51)   
#> 2     2 POINT (76 43)   
gdpins_sf_to_parquet(pts, engine = "sf")  # sf fallback (full precision)
#> # A tibble: 2 × 2
#>      id geometry__4326__
#>   <int> <chr>           
#> 1     1 POINT (71 51)   
#> 2     2 POINT (76 43)   
```
