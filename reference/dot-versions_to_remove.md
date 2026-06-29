# Compute version labels to remove for a given sub-board (oldest, keeping newest)

[`pins::pin_versions()`](https://pins.rstudio.com/reference/pin_versions.html)
returns rows sorted ascending by `created` (oldest first, newest last).
We keep the last `keep` rows and remove the rest. Each sub-board (drive,
cache, local) may have slightly different timestamp prefixes in version
labels even for the same logical version, so each board must compute its
own removal list independently.

## Usage

``` r
.versions_to_remove(sub_board, name, keep)
```

## Arguments

- sub_board:

  A `pins` board.

- name:

  Pin name.

- keep:

  Integer. Number of newest versions to keep.

## Value

Character vector of version labels to remove (may be empty).
