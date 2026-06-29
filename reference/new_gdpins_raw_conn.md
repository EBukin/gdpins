# Construct a `gdpins_raw_conn` object (internal)

Field layout is FROZEN. WS4 calls this constructor and relies on exact
field names in exactly this order.

## Usage

``` r
new_gdpins_raw_conn(config, drive_path = NULL, local_path, adapter = NULL)
```

## Arguments

- config:

  Character scalar. One of `"drive_local"`, `"local_only"`.

- drive_path:

  Character scalar Drive raw-root (relative to the adapter root), or
  `NULL` for `"local_only"`.

- local_path:

  Character scalar local mirror directory.

- adapter:

  A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.

## Value

An object of S3 class `"gdpins_raw_conn"`.

## Details

Raw paths in verbs are **relative to `drive_path`/`local_path`** (e.g.
`"worldbank-api/x.parquet"`).
