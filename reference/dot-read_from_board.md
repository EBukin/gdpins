# Read from a single pins board

Parquet pins are read through the configured parquet engine
([`.gdpins_parquet_engine()`](https://ebukin.github.io/gdpins/reference/dot-gdpins_parquet_engine.md),
default arrow) instead of
[`pins::pin_read()`](https://pins.rstudio.com/reference/pin_read.html),
which is hardwired to nanoparquet and can exhaust memory on large-string
columns. This covers both native `"parquet"` pins (legacy, nanoparquet-
authored) and the `"file"` pins gdpins now writes (an arrow-authored
`.parquet` uploaded with
[`pins::pin_upload()`](https://pins.rstudio.com/reference/pin_download.html)).
All other pin types keep the pins-native reader.

## Usage

``` r
.read_from_board(pins_board, name, version)
```

## Arguments

- pins_board:

  A pins board object.

- name:

  Pin name.

- version:

  Character scalar or `NULL`.
