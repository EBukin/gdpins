# Format a POSIXct timestamp compactly

Produces a short ISO-8601-like string (`"YYYY-MM-DD HH:MM"`) suitable
for narrow console output. Returns `"\u2014"` (em-dash) for `NA` values.

## Usage

``` r
gd_fmt_mtime(t)
```

## Arguments

- t:

  A `POSIXct` scalar (or something coercible via
  [`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html)).

## Value

Character scalar.
