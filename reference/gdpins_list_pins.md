# List all pins in a board

Returns a programmatic tibble with one row per pin. Compact output fits
≤80 columns. Reads from the board's local-first component (`local_board`
\> `cache_board` \> `drive_board`).

## Usage

``` r
gdpins_list_pins(board)
```

## Arguments

- board:

  A `gdpins_board` object.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with columns `name` (chr), `type` (chr), `n_versions` (int), `size`
(dbl, bytes), `modified` (POSIXct). Returns a zero-row tibble for an
empty board.
