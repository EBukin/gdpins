# Compute relative file name from a drive ls path entry

Handles both real adapters (which return relative names from Drive API)
and fake adapters (which return absolute filesystem paths due to the
tempdir-backed simulation).

## Usage

``` r
.drive_rel(adapter, drive_path, path)
```
