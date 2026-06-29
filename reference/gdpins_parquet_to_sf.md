# Restore an sf object from a parquet-encoded tibble

Inverse of
[`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md).
Detects columns whose names match the pattern `^.*__\\d{4,5}__$` and
attempts to parse them as WKT geometry. Only columns where the WKT
actually parses are converted; others are left as plain strings (column
name is NOT changed).

## Usage

``` r
gdpins_parquet_to_sf(x)
```

## Arguments

- x:

  A
  [`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
  previously produced by
  [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md).

## Value

An `sf` object. Column names are restored to their original form (suffix
stripped). CRS is set from the EPSG code embedded in the name.
