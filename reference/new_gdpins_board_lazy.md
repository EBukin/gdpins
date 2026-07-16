# Construct an unresolved `gdpins_board` (internal)

Mirrors
[`new_gdpins_board()`](https://ebukin.github.io/gdpins/reference/new_gdpins_board.md)'s
frozen field layout so `$` sees the same names either way. Components
are `NULL` in the underlying list and are only ever served through
`$`/`[[`, which force first.

## Usage

``` r
new_gdpins_board_lazy(spec)
```

## Arguments

- spec:

  A list from
  [`.board_spec()`](https://ebukin.github.io/gdpins/reference/dot-board_spec.md).

## Value

An unresolved `gdpins_board`.
