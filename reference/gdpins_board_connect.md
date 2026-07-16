# Connect a lazy board now

Forces a board created with `lazy = TRUE` (the default) to do its
deferred init: resolve the Drive folder, build the `pins` boards, and
run the `on_discrepancy` sync check. This is exactly the work
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
used to do at init.

## Usage

``` r
gdpins_board_connect(board, on_discrepancy = NULL)
```

## Arguments

- board:

  A `gdpins_board` object.

- on_discrepancy:

  Character scalar or `NULL`. Overrides the value given at
  [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
  for this connection only. See
  [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
  for the legal values.

## Value

Invisibly `board`, now connected.

## Details

Use it to control *when* you pay: call it right after init to restore
eager-style timing and surface a bad `drive_path` immediately, or call
it at a natural pause before a long stretch of reads.

Already-connected boards and eager boards are a no-op, so it is safe to
call repeatedly. To only run the sync check on a board that may already
be connected, use
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
— it connects too, and returns the per-pin comparison rather than
applying a policy.

## See also

[lazy-boards](https://ebukin.github.io/gdpins/reference/lazy-boards.md)
for what else forces a connection,
[`gdpins_board_is_connected()`](https://ebukin.github.io/gdpins/reference/gdpins_board_is_connected.md),
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md),
[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md).

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
gdpins_board_is_connected(board)
#> [1] FALSE

gdpins_board_connect(board, on_discrepancy = "ignore")
gdpins_board_is_connected(board)
#> [1] TRUE
```
