# Remove a file from a raw connection

Deletes a single file from the local mirror and, when Drive is
configured, moves the Drive file to trash (recoverable). Missing files
are ignored (idempotent no-op). Folder-recursive deletion is not
supported.

## Usage

``` r
gdpins_raw_remove(conn, name)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- name:

  Character scalar. Relative file path within the raw-root.

## Value

Invisibly `NULL`.

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
and
[`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)
use the same ladder without rungs 2–3: pin names are flat, so "path" and
"basename" are the same question.

`gdpins_raw_remove()` uses **rung 1 only**. It hard-deletes the local
copy, so it never auto-resolves a near-miss onto a real file; a missing
target stays an idempotent no-op.

## Glob and listing mode

A `name` containing `*` or `?` switches
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
`gdpins_raw_remove()`,
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
and
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

[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md),
[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md).

Other raw-connection:
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md),
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md),
[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md),
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
gdpins_raw_remove(conn, "cars.csv")
```
