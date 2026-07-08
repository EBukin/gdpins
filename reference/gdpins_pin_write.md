# Write a pin to a gdpins board

Serialises `x` and writes it to every non-NULL component of `board`
(Drive board, cache board, local board). Format auto-detection calls
[`gdpins_detect_format()`](https://ebukin.github.io/gdpins/reference/gdpins_detect_format.md)
unless `format` is supplied explicitly.

## Usage

``` r
gdpins_pin_write(board, x, name, version = NULL, format = NULL)
```

## Arguments

- board:

  A `gdpins_board` object.

- x:

  An R object to pin.

- name:

  Character scalar. Pin name (bare snake_case, e.g. `"parcels"`).

- version:

  Character scalar or `NULL`. Version label; `NULL` uses the board
  default.

- format:

  Character scalar or `NULL`. One of `"parquet"` or `"rds"`; `NULL`
  auto-detects via
  [`gdpins_detect_format()`](https://ebukin.github.io/gdpins/reference/gdpins_detect_format.md).

## Value

Invisibly `NULL`. Called for its side effect.

## Details

If `x` is an `sf` object, it is encoded with
[`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md)
before writing (type `"parquet"`).

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md),
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
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
#> Creating new version '20260708T105252Z-c0340'
#> Writing to pin 'cars'
#> Creating new version '20260708T105252Z-c0340'
#> Writing to pin 'cars'

if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
gdpins_pin_write(board, mtcars, "cars")
} # }
```
