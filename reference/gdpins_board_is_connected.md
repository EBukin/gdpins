# Has a board connected yet?

Reports whether `board` has done its deferred init. Eager boards
(`lazy = FALSE`) are connected by construction and always return `TRUE`.
Never forces a connection itself.

## Usage

``` r
gdpins_board_is_connected(board)
```

## Arguments

- board:

  A `gdpins_board` object.

## Value

`TRUE` if the board has connected, `FALSE` if it is still lazy.

## See also

[`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md),
[lazy-boards](https://ebukin.github.io/gdpins/reference/lazy-boards.md).

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
gdpins_board_is_connected(board)   # FALSE — nothing has touched it
#> [1] FALSE

gdpins_pin_write(board, mtcars, "cars")
#> Creating new version '20260716T190819Z-c0340'
#> Writing to pin 'cars'
#> Creating new version '20260716T190819Z-c0340'
#> Writing to pin 'cars'
gdpins_board_is_connected(board)   # TRUE — the write connected it
#> [1] TRUE
```
