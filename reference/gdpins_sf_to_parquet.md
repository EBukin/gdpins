# Convert an sf object to a plain tibble suitable for parquet storage

Converts all `sfc` geometry columns to WKT text and encodes the
per-column CRS (EPSG integer) into the column name using the pattern
`"<name>__<epsg>__"` (double-underscore both sides). The result is a
plain tibble with no `sf` class.

## Usage

``` r
gdpins_sf_to_parquet(x)
```

## Arguments

- x:

  An `sf` data frame with one or more geometry columns.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with geometry columns replaced by WKT character columns named
`"<original_name>__<epsg>__"`.

## Details

No coordinate transformation is performed. Each geometry is converted
via
[`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
(WKT, never WKB). Per-column CRS is supported.
