# Write an R object to a raw connection

Serialises `x` to a temp file using the appropriate writer for the
extension in `name`, then deposits it to Drive and mirrors locally.

## Usage

``` r
gdpins_raw_put_object(conn, x, name)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- x:

  An R object.

- name:

  Character scalar. Relative path within the raw-root, including
  extension (e.g. `"worldbank-api/gdp_2024.parquet"`).

## Value

Invisibly `NULL`.
