# Write an R object to a raw connection

Serialises `x` to a temp file using the appropriate writer for the
extension in `name`, then deposits it to Drive and mirrors locally.

## Usage

``` r
gdpins_raw_put_object(conn, x, name, wkt_engine = NULL)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- x:

  An R object.

- name:

  Character scalar. Relative path within the raw-root, including
  extension (e.g. `"worldbank-api/gdp_2024.parquet"`).

- wkt_engine:

  Character scalar or `NULL`. WKT engine used to encode `sf` geometry
  when writing `.parquet`: `"wk"` (default) or `"sf"`. `NULL` uses the
  `gdpins.wkt_engine` option. See
  [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md).

## Value

Invisibly `NULL`.
