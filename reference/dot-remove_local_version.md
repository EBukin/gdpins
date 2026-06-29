# Remove one version directory from a local board (cache or local_only)

Directly unlinks the version subdirectory under
`board_path/<name>/<version>`.

## Usage

``` r
.remove_local_version(board_path, name, version)
```

## Arguments

- board_path:

  Character. Local path to the `pins` board_folder root.

- name:

  Pin name.

- version:

  Version label.
