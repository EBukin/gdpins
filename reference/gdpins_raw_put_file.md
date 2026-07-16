# Upload a file verbatim to a raw connection

Copies a local file byte-for-byte to Drive and mirrors locally. No R
round-trip, no coercion — byte-faithful upload.

## Usage

``` r
gdpins_raw_put_file(conn, path, name)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- path:

  Character scalar. Path to the local source file.

- name:

  Character scalar. Relative destination path within the raw-root.

## Value

Invisibly `NULL`.

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

`gdpins_raw_put_file()` mirrors that asymmetry. It uploads bytes
verbatim, so it accepts any extension (`.gpkg`, `.tif`, `.xlsx`, …) and
only insists that there *is* one.

## See also

Other raw-connection:
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md),
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md),
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
[`gdpins_refresh_disconnect()`](https://ebukin.github.io/gdpins/reference/gdpins_refresh_disconnect.md)
