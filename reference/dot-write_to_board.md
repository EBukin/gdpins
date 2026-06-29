# Write x to a single pins board with appropriate type

Write x to a single pins board with appropriate type

## Usage

``` r
.write_to_board(pins_board, x, name, fmt, versioned)
```

## Arguments

- pins_board:

  A pins board object.

- x:

  The R object to write.

- name:

  Pin name.

- fmt:

  Character scalar: `"arrow"` or `"rds"`.

- versioned:

  Logical. Whether this write creates a version.
