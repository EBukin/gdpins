# Board components implied by a config

The config→components mapping is fixed by
[`new_gdpins_board()`](https://ebukin.github.io/gdpins/reference/new_gdpins_board.md).
Deriving the component set from `config` rather than from
`is.null(board$drive_board)` lets
[`format.gdpins_board()`](https://ebukin.github.io/gdpins/reference/format.gdpins_board.md)
and friends describe a board without forcing a lazy one to connect.

## Usage

``` r
.config_components(config)
```

## Arguments

- config:

  Character scalar. One of `.BOARD_CONFIGS`.

## Value

Character vector of component field names.
