# Resolve a pin to its file path(s) on disk

The path counterpart of
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md):
same board, same name, same local-first resolution, but returns where
the pin's file(s) live rather than the object inside them. Use it to
hand a pin to a reader gdpins does not know about, or to inspect the
stored bytes.

## Usage

``` r
gdpins_pin_path(board, name, version = NULL)
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. Pin name. A `name` containing `*` or `?` switches to
  listing mode; see the Glob section on
  [raw-connection](https://ebukin.github.io/gdpins/reference/raw-connection.md).

- version:

  Character scalar or `NULL`. Pin version; `NULL` = latest.

## Value

Character vector of absolute paths — length 1 for an ordinary pin,
longer for a multi-file pin written with
[`pins::pin_upload()`](https://pins.rstudio.com/reference/pin_download.html).
In listing mode, a `gdpins_pin_listing` tibble instead.

## Details

Resolution mirrors
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
exactly — local board, then cache board, then Drive — and the pin is
materialised (downloaded into the pins cache) when Drive holds the only
copy, just as
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md)
downloads on demand.

## Name resolution

[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
and
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
resolve the name you pass against what actually exists, stopping at the
first hit:

1.  Exact relative path → resolve.

2.  Exact basename, unique → resolve silently (`"cars.csv"` finds
    `"sub/cars.csv"`).

3.  Exact basename, several matches → error listing every full path.

4.  Case-insensitive exact, unique → resolve silently.

5.  Same stem, different extension → error, suggesting it (`"cars.csv"`
    when only `"cars.parquet"` exists).

6.  Close on edit distance → error, suggesting the 5 nearest.

7.  Nothing close → error naming the connection, pointing at listing
    mode.

Auto-resolve happens **only** at rungs 1, 2 and 4, where the match is
both exact and unique. Rungs 3 and 5–7 only ever suggest — they never
guess.

Rung 4 also settles a real platform difference:
[`file.exists()`](https://rdrr.io/r/base/files.html) is case-insensitive
on Windows and case-sensitive elsewhere, so gdpins does the case-folding
itself rather than letting the filesystem do it on one platform and not
the other.

[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
and `gdpins_pin_path()` use the same ladder without rungs 2–3: pin names
are flat, so "path" and "basename" are the same question.

[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md)
uses **rung 1 only**. It hard-deletes the local copy, so it never
auto-resolves a near-miss onto a real file; a missing target stays an
idempotent no-op.

## Glob and listing mode

A `name` containing `*` or `?` switches
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
and `gdpins_pin_path()` into **listing mode**: they return a listing of
what matches instead of acting on one item. Listing mode never
bulk-reads and never bulk-deletes.

- `"*"` — everything.

- `"*.csv"` — every `.csv`, at **any depth** (unlike
  [`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md),
  whose `depth = 2` default hides `sub/sub/folder/file.rds`).

Matching is case-sensitive on every platform, so `"*.csv"` does not
match `"CARS.CSV"`. Raw verbs return a `gdpins_raw_listing`; pin verbs
return a `gdpins_pin_listing`. Both are ordinary tibbles with a print
method that shows names only.

## Objects vs paths

The governing rule across gdpins: **`*_get` / `*_read` return objects,
`*_path` returns paths.** The extension never switches the mode.

[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
deserialises, so it only accepts the four formats gdpins knows how to
read — `.rds`, `.parquet`, `.geojson`, `.csv`. Anything else is an error
naming those formats and pointing at
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md).

[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md)
returns a path for **any** extension, downloading from Drive on demand.
It is the escape hatch for formats gdpins does not read: get the path,
then hand it to whatever package does.

[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md)
mirrors that asymmetry. It uploads bytes verbatim, so it accepts any
extension (`.gpkg`, `.tif`, `.xlsx`, …) and only insists that there *is*
one.

## See also

[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md).

## Examples

``` r
adapter <- gdpins_fake_drive()
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = tempfile("cache_"),
  adapter    = adapter,
  create     = TRUE
)
gdpins_pin_write(board, mtcars, "cars")
#> Creating new version '20260716T190821Z-c0340'
#> Writing to pin 'cars'
#> Creating new version '20260716T190821Z-c0340'
#> Writing to pin 'cars'
p <- gdpins_pin_path(board, "cars")
file.exists(p)
#> [1] TRUE
```
