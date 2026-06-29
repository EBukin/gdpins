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

## See also

[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md),
[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md),
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md).

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
