# Do the expensive half of board init

Everything that touches the network or the filesystem: the online probe,
the Drive existence/create dance, folder-ID resolution, and `pins` board
construction. Called eagerly by
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
when `lazy = FALSE`, and on first component access when `lazy = TRUE`.

## Usage

``` r
.build_board(spec)
```

## Arguments

- spec:

  A list from
  [`.board_spec()`](https://ebukin.github.io/gdpins/reference/dot-board_spec.md).

## Value

A fully-resolved `gdpins_board`.

## Details

Deliberately does **not** run the sync check — callers own that, so a
lazy board can mark itself resolved before
[`.handle_init_sync()`](https://ebukin.github.io/gdpins/reference/dot-handle_init_sync.md)
reads it back.
