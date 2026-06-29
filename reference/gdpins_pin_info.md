# Retrieve detailed metadata for a single pin

Returns a structured list with format, sf/CRS details (if applicable),
version count, and the pin's lineage name. The print form is compact
(≤80 cols) and uses `cli` styling.

## Usage

``` r
gdpins_pin_info(board, name)
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. Pin name.

## Value

An S3 object of class `gdpins_pin_info` — a named list with elements:
`name` (chr), `type` (chr), `n_versions` (int), `size` (dbl, bytes),
`modified` (POSIXct), `is_sf` (lgl), `crs_epsg` (int or NA),
`lineage_name` (chr), `versions` (tibble from
[`pins::pin_versions()`](https://pins.rstudio.com/reference/pin_versions.html)).
