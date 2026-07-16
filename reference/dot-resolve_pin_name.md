# Resolve a user-supplied pin name

The
[raw-connection](https://ebukin.github.io/gdpins/reference/raw-connection.md)
name-resolution ladder, minus the basename rungs: pin names are flat, so
"exact path" and "exact basename" are the same question. Auto-resolve
still happens only on an exact, unique match.

## Usage

``` r
.resolve_pin_name(board, name, verb = "gdpins_pin_read")
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. The name as the user typed it.

- verb:

  Character scalar. Calling verb, used in error text.

## Value

Character scalar. A pin name known to the board.
