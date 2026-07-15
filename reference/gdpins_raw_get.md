# Read a file from a raw connection

Reads a file from the local mirror by default. Set
`force_refresh = TRUE` to re-pull from Drive first.

## Usage

``` r
gdpins_raw_get(conn, name, force_refresh = FALSE, wkt_engine = NULL)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- name:

  Character scalar. Relative path within the raw-root.

- force_refresh:

  Logical. `TRUE` re-pulls from Drive before reading. Default `FALSE`.

- wkt_engine:

  Character scalar or `NULL`. WKT engine used to decode `sf` geometry
  when reading `.parquet`: `"wk"` (default) or `"sf"`. `NULL` uses the
  `gdpins.wkt_engine` option. Reads are engine-agnostic. See
  [`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md).

## Value

The deserialised R object.
