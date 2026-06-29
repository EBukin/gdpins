# Create a fake (tempdir-backed) Drive adapter

Simulates Google Drive using the local filesystem. State (including a
trash store) is held in a mutable environment so all closures share it.
Used as the default test seam — **never hits the network**.

## Usage

``` r
gdpins_fake_drive(root = tempfile("gdpins_fake_drive_"))
```

## Arguments

- root:

  Character scalar. Root directory for the fake drive. Defaults to a
  fresh [`tempfile()`](https://rdrr.io/r/base/tempfile.html) path
  (created on first use).

## Value

An object of class `gdpins_drive_adapter`.

## Details

[`gd_trash()`](https://ebukin.github.io/gdpins/reference/gd_trash.md)
moves entries to an internal trash store (recoverable). It never calls
[`unlink()`](https://rdrr.io/r/base/unlink.html).
[`gd_md5()`](https://ebukin.github.io/gdpins/reference/gd_md5.md) uses
[`tools::md5sum()`](https://rdrr.io/r/tools/md5sum.html).
[`gd_ls()`](https://ebukin.github.io/gdpins/reference/gd_ls.md) excludes
trashed entries.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
for the live Google Drive adapter.

## Examples

``` r
adapter <- gdpins_fake_drive()
adapter$mkdir("project/data-raw")
adapter$exists("project/data-raw")
#> [1] TRUE
```
