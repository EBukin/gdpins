# Detect the appropriate storage format for an R object

Returns `"arrow"` for data frames, tibbles (including `sf` objects), and
other tabular objects. Returns `"rds"` for lists, nested tibbles with
list-columns, and any non-tabular object.

## Usage

``` r
gdpins_detect_format(x)
```

## Arguments

- x:

  An R object.

## Value

Character scalar: `"arrow"` or `"rds"`.

## Details

Decision rules (in order):

1.  Not a data frame -\> `"rds"`.

2.  Data frame with any non-`sfc` list-column -\> `"rds"`.

3.  Plain df/tibble or `sf` (all list-cols are `sfc`) -\> `"arrow"`.
