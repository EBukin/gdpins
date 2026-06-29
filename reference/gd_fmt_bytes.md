# Format a byte count as a human-readable string

Converts a numeric byte count to a compact string with appropriate unit
suffix (B, KB, MB, GB). Fits within \<=80-col output.

## Usage

``` r
gd_fmt_bytes(n)
```

## Arguments

- n:

  Numeric scalar. Number of bytes.

## Value

Character scalar, e.g. `"1.2 MB"` or `"456 B"`.
