# Read a file from a raw connection

Reads a file from the local mirror by default. Set
`force_refresh = TRUE` to re-pull from Drive first.

## Usage

``` r
gdpins_raw_get(conn, name, force_refresh = FALSE)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- name:

  Character scalar. Relative path within the raw-root.

- force_refresh:

  Logical. `TRUE` re-pulls from Drive before reading. Default `FALSE`.

## Value

The deserialised R object.
