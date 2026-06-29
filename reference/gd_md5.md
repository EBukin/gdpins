# Return MD5 checksum of a Drive file

Return MD5 checksum of a Drive file

## Usage

``` r
gd_md5(adapter, path)
```

## Arguments

- adapter:

  A `gdpins_drive_adapter` object.

- path:

  Character scalar. Path relative to the adapter root.

## Value

Character scalar MD5, or `NA_character_` if absent or a directory.
