# List contents of a raw connection

Returns a compact folder tree for the raw connection, defaulting to 2
levels of depth.

## Usage

``` r
gdpins_raw_ls(conn, depth = 2)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- depth:

  Integer scalar. Maximum directory depth to display. Default `2`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with 8 columns:

- `name`:

  chr. Relative path within the raw-root.

- `is_dir`:

  lgl. `TRUE` for directories, `FALSE` for files.

- `size`:

  dbl. File size in bytes (0 for directories).

- `mtime`:

  POSIXct. Last-modified time.

- `depth`:

  int. Directory depth (1 = top-level).

- `local_path`:

  chr. Absolute local filesystem path.

- `drive_id`:

  chr. Google Drive file/folder ID, or `NA_character_` for local-only
  connections and the fake adapter.

- `drive_url`:

  chr. Browser URL for the entry
  (`https://drive.google.com/file/d/<id>/view` for files,
  `https://drive.google.com/drive/folders/<id>` for folders), or
  `NA_character_` when `drive_id` is `NA`.

## Examples

``` r
adapter <- gdpins_fake_drive()
conn <- gdpins_raw_connect(
  drive_path = "worldbank-api",
  local_path = tempfile("raw_"),
  adapter    = adapter,
  create     = TRUE
)
gdpins_raw_put_object(conn, mtcars, "cars.csv")
tbl <- gdpins_raw_ls(conn)
tbl$local_path   # absolute local path
#> [1] "/tmp/Rtmpgw0Tfn/raw_639d6de4a412/cars.csv"
tbl$drive_id     # NA for fake adapter; real Drive ID with real adapter
#> [1] NA
```
