# Force-refresh a raw connection and disconnect

Pulls all files from Drive to the local mirror, then invalidates the
connection object.

## Usage

``` r
gdpins_refresh_disconnect(conn)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

## Value

Invisibly `NULL`.
