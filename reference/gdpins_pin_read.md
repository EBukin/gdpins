# Read a pin from a gdpins board

Reads from the local-first source: local board if present, else cache
board, else Drive board. Hits the network only if the pin is absent
locally.

## Usage

``` r
gdpins_pin_read(board, name, version = NULL, wkt_engine = NULL)
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. Pin name.

- version:

  Character scalar or `NULL`. Pin version; `NULL` = latest.

- wkt_engine:

  Character scalar or `NULL`. Controls how WKT-encoded `sf` geometry is
  restored: `"wk"` (default) or `"sf"` decode to an `sf` object (reads
  are engine-agnostic; the choice only affects parse speed), while
  `"none"` skips restoration and returns the geometry columns as raw WKT
  text (names keep their `__<epsg>__` suffix, so the result can be fed
  to
  [`gdpins_as_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_as_sf.md)
  later). `NULL` uses the `gdpins.wkt_engine` option (never `"none"`).
  See
  [`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md).

## Value

The pinned R object.

## Details

If the stored object contains `__<epsg>__`-suffixed geometry columns
(WKT encoding), the geometry is automatically restored via
[`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md).

## Name resolution

[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
and `gdpins_pin_read()` resolve the name you pass against what actually
exists, stopping at the first hit:

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

`gdpins_pin_read()` and
[`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)
use the same ladder without rungs 2–3: pin names are flat, so "path" and
"basename" are the same question.

[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md)
uses **rung 1 only**. It hard-deletes the local copy, so it never
auto-resolves a near-miss onto a real file; a missing target stays an
idempotent no-op.

## Glob and listing mode

A `name` containing `*` or `?` switches
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
`gdpins_pin_read()` and
[`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)
into **listing mode**: they return a listing of what matches instead of
acting on one item. Listing mode never bulk-reads and never
bulk-deletes.

- `"*"` — everything.

- `"*.csv"` — every `.csv`, at **any depth** (unlike
  [`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md),
  whose `depth = 2` default hides `sub/sub/folder/file.rds`).

Matching is case-sensitive on every platform, so `"*.csv"` does not
match `"CARS.CSV"`. Raw verbs return a `gdpins_raw_listing`; pin verbs
return a `gdpins_pin_listing`. Both are ordinary tibbles with a print
method that shows names only.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md),
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
[`gdpins_pin_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_remove.md).

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
gdpins_pin_read(board, "cars")
#> # A tibble: 32 × 11
#>      mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>    <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#>  1  21       6  160    110  3.9   2.62  16.5     0     1     4     4
#>  2  21       6  160    110  3.9   2.88  17.0     0     1     4     4
#>  3  22.8     4  108     93  3.85  2.32  18.6     1     1     4     1
#>  4  21.4     6  258    110  3.08  3.22  19.4     1     0     3     1
#>  5  18.7     8  360    175  3.15  3.44  17.0     0     0     3     2
#>  6  18.1     6  225    105  2.76  3.46  20.2     1     0     3     1
#>  7  14.3     8  360    245  3.21  3.57  15.8     0     0     3     4
#>  8  24.4     4  147.    62  3.69  3.19  20       1     0     4     2
#>  9  22.8     4  141.    95  3.92  3.15  22.9     1     0     4     2
#> 10  19.2     6  168.   123  3.92  3.44  18.3     1     0     4     4
#> # ℹ 22 more rows

if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
gdpins_pin_read(board, "cars")
} # }
```
