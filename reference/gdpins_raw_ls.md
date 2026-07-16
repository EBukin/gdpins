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

## Glob and listing mode

A `name` containing `*` or `?` switches
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
and
[`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)
into **listing mode**: they return a listing of what matches instead of
acting on one item. Listing mode never bulk-reads and never
bulk-deletes.

- `"*"` — everything.

- `"*.csv"` — every `.csv`, at **any depth** (unlike `gdpins_raw_ls()`,
  whose `depth = 2` default hides `sub/sub/folder/file.rds`).

Matching is case-sensitive on every platform, so `"*.csv"` does not
match `"CARS.CSV"`. Raw verbs return a `gdpins_raw_listing`; pin verbs
return a `gdpins_pin_listing`. Both are ordinary tibbles with a print
method that shows names only.

## See also

Other raw-connection:
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md),
[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md),
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
[`gdpins_refresh_disconnect()`](https://ebukin.github.io/gdpins/reference/gdpins_refresh_disconnect.md)

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
#> [1] "/tmp/RtmplHQDVx/raw_1e0c6cf2aa31/cars.csv"
tbl$drive_id     # NA for fake adapter; real Drive ID with real adapter
#> [1] NA
```
