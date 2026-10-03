# Default local-copy cache directory for a Drive board

Pure path computation — no filesystem calls. The default local copy
lives under `getOption("gdpins.cache_dir")`, namespaced by the Drive
root (so different Drive accounts/shared drives don't collide) and by a
sanitised version of `drive_path`.

## Usage

``` r
.default_cache_dir(adapter, drive_path)
```

## Arguments

- adapter:

  A `gdpins_drive_adapter`.

- drive_path:

  Character scalar Drive path relative to the adapter root.

## Value

Character scalar path.
