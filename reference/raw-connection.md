# Raw-exogenous connection

Plain-file interface for data as received from external APIs or sources.
No pins metadata layer — files are stored verbatim or serialised from R
objects. Drive path is the truth; a local directory mirrors it.

## Raw connection verbs

|  |  |  |
|----|----|----|
| Verb | Takes | Returns |
| [`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md) | `drive_path`, `local_path` | a `gdpins_raw_conn` |
| [`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md) | an R object + a `name` | invisibly `NULL` |
| [`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md) | a file `path` + a `name` | invisibly `NULL` |
| [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md) | a `name` | **the object** |
| [`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md) | a `name` or Drive ID | **a path** |
| [`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md) | a `depth` | a listing tibble |
| [`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md) | a `name` | invisibly `NULL` |
| [`gdpins_refresh_disconnect()`](https://ebukin.github.io/gdpins/reference/gdpins_refresh_disconnect.md) | — | invisibly `NULL` |

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
