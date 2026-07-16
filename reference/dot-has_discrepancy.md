# Does a status tibble describe an actual discrepancy?

`TRUE` only when at least one row needs reconciling. An empty status
(nothing on either side) and rows marked `"offline"` are both "no
discrepancy": the former has nothing to compare, the latter could not be
compared at all.

## Usage

``` r
.has_discrepancy(status)
```

## Arguments

- status:

  A tibble from
  [`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md).
