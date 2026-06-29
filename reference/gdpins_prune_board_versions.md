# Prune old versions of all pins in a board

Applies
[`gdpins_prune_pin_versions()`](https://ebukin.github.io/gdpins/reference/gdpins_prune_pin_versions.md)
to every pin in `board`. Defaults to `dry_run = TRUE`.

## Usage

``` r
gdpins_prune_board_versions(
  board,
  keep = 1,
  dry_run = TRUE,
  threshold = 10,
  force = FALSE
)
```

## Arguments

- board:

  A `gdpins_board` object.

- keep:

  Integer scalar. Versions to keep per pin. Default `1`.

- dry_run:

  Logical. Show plan without removing. Default `TRUE`.

- threshold:

  Integer scalar. Threshold before requiring confirmation. Default `10`.

- force:

  Logical. Skip interactive confirmation. Default `FALSE`.

## Value

Invisibly, a named list of character vectors (one per pin) of removed
(or would-be-removed) version labels.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md),
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
gdpins_prune_board_versions(board, keep = 2L, dry_run = TRUE)
#> ℹ No pins found in board "data_raw".
```
