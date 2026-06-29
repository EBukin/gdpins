# Resolve the authoritative sub-board for a given config

For `drive_cache` / `drive_cache_local`: Drive board is authoritative
for reporting the removed version labels. For `local_only`: local board
is the only board.

## Usage

``` r
.prune_primary_board(board)
```

## Arguments

- board:

  A `gdpins_board` object.

## Value

A `pins` board object.
