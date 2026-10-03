# Resolve the authoritative sub-board for a given config

For Drive boards (`drive_cache`, `drive_only`): Drive board is
authoritative for reporting the removed version labels. For
`local_only`: the local copy is the only board.

## Usage

``` r
.prune_primary_board(board)
```

## Arguments

- board:

  A `gdpins_board` object.

## Value

A `pins` board object.
