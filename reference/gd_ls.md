# List contents of a Drive directory

List contents of a Drive directory

## Usage

``` r
gd_ls(adapter, path = "", recursive = FALSE)
```

## Arguments

- adapter:

  A `gdpins_drive_adapter` object.

- path:

  Character scalar. Path relative to the adapter root. Default `""`
  lists the root.

- recursive:

  Logical. Recurse into sub-directories? Default `FALSE`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with columns `path` (chr, relative), `is_dir` (lgl), `size` (dbl,
bytes), `md5` (chr), `mtime` (POSIXct), `drive_id` (chr; `NA_character_`
for fake adapter, Drive file/folder ID for real adapter). Trashed
entries are excluded.
