# Read a pin from a gdpins board

Reads from the local-first source: local board if present, else cache
board, else Drive board. Hits the network only if the pin is absent
locally.

## Usage

``` r
gdpins_pin_read(board, name, version = NULL)
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. Pin name.

- version:

  Character scalar or `NULL`. Pin version; `NULL` = latest.

## Value

The pinned R object.

## Details

If the stored object contains `__<epsg>__`-suffixed geometry columns
(WKT encoding), the geometry is automatically restored via
[`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md).

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md),
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
[`gdpins_pin_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_remove.md).

## Examples

``` r
adapter <- gdpins_fake_drive()
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = tempfile("cache_"),
  adapter    = adapter,
  create     = TRUE
)
#> Warning: ! "data_raw": sync discrepancy detected between Drive and local. Run
#>   `gdpins_sync()` to reconcile.
gdpins_pin_write(board, mtcars, "cars")
#> Creating new version '20260708T105251Z-c0340'
#> Writing to pin 'cars'
#> Creating new version '20260708T105251Z-c0340'
#> Writing to pin 'cars'
gdpins_pin_read(board, "cars")
#> # A tibble: 32 × 11
#>      mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>    <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#>  1  21       6  160    110  3.9   2.62  16.5     0     1     4     4
#>  2  21       6  160    110  3.9   2.88  17.0     0     1     4     4
#>  3  22.8     4  108     93  3.85  2.32  18.6     1     1     4     1
#>  4  21.4     6  258    110  3.08  3.22  19.4     1     0     3     1
#>  5  18.7     8  360    175  3.15  3.44  17.0     0     0     3     2
#>  6  18.1     6  225    105  2.76  3.46  20.2     1     0     3     1
#>  7  14.3     8  360    245  3.21  3.57  15.8     0     0     3     4
#>  8  24.4     4  147.    62  3.69  3.19  20       1     0     4     2
#>  9  22.8     4  141.    95  3.92  3.15  22.9     1     0     4     2
#> 10  19.2     6  168.   123  3.92  3.44  18.3     1     0     4     4
#> # ℹ 22 more rows

if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
gdpins_pin_read(board, "cars")
} # }
```
