# Write an R object to a raw connection

Serialises `x` to a temp file using the appropriate writer for the
extension in `name`, then deposits it to Drive and mirrors locally.

## Usage

``` r
gdpins_raw_put_object(conn, x, name, wkt_engine = NULL)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- x:

  An R object.

- name:

  Character scalar. Relative path within the raw-root, including
  extension (e.g. `"worldbank-api/gdp_2024.parquet"`).

- wkt_engine:

  Character scalar or `NULL`. WKT engine used to encode `sf` geometry
  when writing `.parquet`: `"wk"` (default) or `"sf"`. `NULL` uses the
  `gdpins.wkt_engine` option. See
  [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md).

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

[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md)
mirrors that asymmetry. It uploads bytes verbatim, so it accepts any
extension (`.gpkg`, `.tif`, `.xlsx`, …) and only insists that there *is*
one.

## See also

Other raw-connection:
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
[`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md),
[`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md),
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
[`gdpins_refresh_disconnect()`](https://ebukin.github.io/gdpins/reference/gdpins_refresh_disconnect.md)
