# Remove a pin from a gdpins board

Deletes `name` from every non-NULL board component (Drive, cache,
local). Missing pins are ignored (idempotent no-op).

## Usage

``` r
gdpins_pin_remove(board, name)
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. Pin name.

## Value

Invisibly `NULL`.

## See also

[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md).

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
#> Warning: ! Board "data_raw": sync discrepancy detected between Drive and local. Run
#>   `gdpins_sync()` to reconcile.
gdpins_pin_write(board, mtcars, "cars")
#> Creating new version '20260629T171414Z-283de'
#> Writing to pin 'cars'
#> Creating new version '20260629T171414Z-283de'
#> Writing to pin 'cars'
gdpins_pin_remove(board, "cars")
```
