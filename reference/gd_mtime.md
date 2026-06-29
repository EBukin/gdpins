# Return modification time of a Drive path

Return modification time of a Drive path

## Usage

``` r
gd_mtime(adapter, path)
```

## Arguments

- adapter:

  A `gdpins_drive_adapter` object.

- path:

  Character scalar. Path relative to the adapter root.

## Value

`POSIXct` scalar, or `NA` if absent.
