# Trash one version directory from Drive via the adapter

Constructs the adapter-relative path `<drive_path>/<name>/<version>` and
calls
[`gd_trash()`](https://ebukin.github.io/gdpins/reference/gd_trash.md).

## Usage

``` r
.trash_drive_version(adapter, drive_path, name, version)
```

## Arguments

- adapter:

  A `gdpins_drive_adapter`.

- drive_path:

  Character. Board drive path (relative to adapter root).

- name:

  Pin name.

- version:

  Version label.
