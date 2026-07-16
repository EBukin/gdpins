# Resolve a user-supplied name to a file in a raw connection

Walks the name-resolution ladder documented on
[raw-connection](https://ebukin.github.io/gdpins/reference/raw-connection.md).
Auto-resolve happens only where the match is both exact and unique
(rungs 1, 2, 4); every looser rung only ever *suggests*, via an error.

## Usage

``` r
.resolve_raw_name(conn, name, verb = "gdpins_raw_path")
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- name:

  Character scalar. The name as the user typed it.

- verb:

  Character scalar. Calling verb, used in error text.

## Value

Character scalar. A relative path known to the connection.
