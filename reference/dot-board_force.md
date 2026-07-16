# Connect an unresolved board and cache the result

Marks the board resolved **before** running the sync check, so
[`.handle_init_sync()`](https://ebukin.github.io/gdpins/reference/dot-handle_init_sync.md)
— which reads `x$drive_board` via
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
— reads the cache instead of recursing.

## Usage

``` r
.board_force(state)
```

## Arguments

- state:

  A lazy state environment.

## Value

Invisibly `NULL`. Called for its effect on `state`.
